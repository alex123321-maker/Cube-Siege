"""
tools/review_loop/state_manager.py - Persistent state and concurrency manager.

Manages state.json safely with:
- File-lock-guarded transactional mutations (inter-process safe)
- Atomic check-and-set acquire_lock() preventing duplicate agent runs
- Atomic writes via os.replace()
- In-flight event tracking for reliable failure recovery
- Per-PR concurrency locks with PID liveness checks
- Event deduplication and queued event coalescing
- Thread resolution tracking for reopen detection

Two processes (watcher + hook) can safely mutate state.json concurrently
because every mutation follows: acquire file lock → reload → mutate → save → release.
"""
import json
import logging
import os
import subprocess
import sys
import tempfile
import time
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Dict, Generator, List, Optional

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tools.review_loop.config import (
    DEFAULT_LOCK_LEASE_SECONDS,
    DEFAULT_STATE_FILE,
    DEFAULT_STATE_LOCK_FILE,
)

logger = logging.getLogger(__name__)

# ------------------------------------------------------------------ #
#  Cross-platform file locking
# ------------------------------------------------------------------ #

def _lock_file(fd: int) -> None:
    """Acquire an exclusive lock on fd (blocking)."""
    if sys.platform == "win32":
        import msvcrt
        # Lock a single byte at position 0 — enough for advisory locking.
        msvcrt.locking(fd, msvcrt.LK_LOCK, 1)
    else:
        import fcntl
        fcntl.flock(fd, fcntl.LOCK_EX)


def _unlock_file(fd: int) -> None:
    """Release the exclusive lock on fd."""
    if sys.platform == "win32":
        import msvcrt
        try:
            os.lseek(fd, 0, os.SEEK_SET)
            msvcrt.locking(fd, msvcrt.LK_UNLCK, 1)
        except OSError:
            pass
    else:
        import fcntl
        fcntl.flock(fd, fcntl.LOCK_UN)


def is_pid_alive(pid: int) -> bool:
    """Check if process with PID is currently running."""
    if not pid or pid <= 0:
        return False
    if sys.platform == "win32":
        try:
            res = subprocess.run(
                ["tasklist", "/FI", f"PID eq {pid}", "/FO", "CSV", "/NH"],
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
            )
            return str(pid) in res.stdout
        except Exception:
            return False
    else:
        try:
            os.kill(pid, 0)
            return True
        except OSError:
            return False


# ------------------------------------------------------------------ #
#  StateManager
# ------------------------------------------------------------------ #

class StateManager:
    """
    Inter-process-safe state manager.

    Every public mutating method follows the transactional protocol:
        acquire file lock → reload state.json → mutate → atomic save → release lock

    Read-only helpers always reload from disk first so a long-lived watcher
    process sees registrations made by short-lived hook processes.
    """

    def __init__(
        self,
        state_file: Optional[Path] = None,
        lock_file: Optional[Path] = None,
    ):
        self.state_file = Path(state_file or DEFAULT_STATE_FILE)
        self.lock_file = Path(
            lock_file or self.state_file.with_suffix(".lock")
        )
        self.state: Dict[str, Any] = {"prs": {}, "allowlist": []}
        self._load_no_lock()

    # ------------- low-level I/O (no locking) ------------- #

    def _load_no_lock(self) -> None:
        """Load state from disk without acquiring the file lock."""
        if not self.state_file.exists():
            return
        try:
            with open(self.state_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict):
                    self.state = data
                    self.state.setdefault("prs", {})
                    self.state.setdefault("allowlist", [])
        except Exception as e:
            logger.warning(
                "Failed to load state file '%s': %s. Re-initializing.",
                self.state_file,
                e,
            )

    def _save_no_lock(self) -> None:
        """Atomically persist state to disk without acquiring the file lock."""
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        tmp_fd, tmp_path = tempfile.mkstemp(
            dir=self.state_file.parent, prefix="state_", suffix=".tmp"
        )
        try:
            with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
                json.dump(self.state, f, indent=2, ensure_ascii=False)
            os.replace(tmp_path, self.state_file)
        except Exception as e:
            if os.path.exists(tmp_path):
                try:
                    os.remove(tmp_path)
                except OSError:
                    pass
            logger.error("Failed to save state to '%s': %s", self.state_file, e)
            raise

    # ------------- transactional context manager ------------- #

    @contextmanager
    def _transact(self) -> Generator[None, None, None]:
        """
        Acquire exclusive file lock, reload state from disk, yield for
        mutations, then atomically save and release.
        """
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        self.lock_file.parent.mkdir(parents=True, exist_ok=True)

        fd = os.open(str(self.lock_file), os.O_RDWR | os.O_CREAT)
        try:
            _lock_file(fd)
            self._load_no_lock()
            yield
            self._save_no_lock()
        finally:
            _unlock_file(fd)
            os.close(fd)

    # ------------- public read helpers (always reload) ------------- #

    def load(self) -> None:
        """Reload state from disk (public API for backward compatibility)."""
        self._load_no_lock()

    def save(self) -> None:
        """Persist state to disk (public API — prefer _transact for safety)."""
        self._save_no_lock()

    def get_registered_prs(self) -> Dict[str, Any]:
        """Return dict of all registered PRs (reloads from disk)."""
        self._load_no_lock()
        return dict(self.state.get("prs", {}))

    def get_pr(self, pr_number: int) -> Optional[Dict[str, Any]]:
        """Get info for specific PR (reloads from disk)."""
        self._load_no_lock()
        return self.state.get("prs", {}).get(str(pr_number))

    # ------------- PR Registration & Lifecycle ------------- #

    def register_pr(
        self, pr_number: int, conversation_id: str, branch: str
    ) -> None:
        """
        Register or update a PR mapping (transactional).
        Strictly idempotent: if PR is already registered, preserves active
        lifecycle fields (status, active_agent_pid, processing_started_at,
        in_flight_events, pending_events, retry_count) so hook calls do not
        destroy active processing state.
        """
        with self._transact():
            key = str(pr_number)
            if key in self.state["prs"]:
                self.state["prs"][key]["conversation_id"] = conversation_id
                self.state["prs"][key]["branch"] = branch
            else:
                self.state["prs"][key] = {
                    "conversation_id": conversation_id,
                    "branch": branch,
                    "status": "watching",
                    "last_head_sha": "",
                    "processed_event_ids": [],
                    "processing_started_at": 0.0,
                    "active_agent_pid": None,
                    "thread_states": {},
                    "pending_events": [],
                    "in_flight_events": [],
                    "retry_count": 0,
                }

    def unregister_pr(self, pr_number: int) -> bool:
        """Remove PR from state (transactional)."""
        with self._transact():
            key = str(pr_number)
            if key in self.state["prs"]:
                del self.state["prs"][key]
                return True
        return False

    def mark_pr_status(self, pr_number: int, status: str) -> None:
        """Set status ('watching', 'processing', 'approved', 'closed', 'error', 'awaiting_design_decision')."""
        with self._transact():
            key = str(pr_number)
            if key in self.state["prs"]:
                self.state["prs"][key]["status"] = status

    def update_pr_fields(
        self, pr_number: int, **fields: Any
    ) -> None:
        """Update arbitrary fields on a PR entry (transactional)."""
        with self._transact():
            key = str(pr_number)
            if key in self.state["prs"]:
                self.state["prs"][key].update(fields)

    def increment_retry_count(self, pr_number: int) -> int:
        """Increment and return retry count for PR (transactional)."""
        with self._transact():
            key = str(pr_number)
            if key in self.state["prs"]:
                cnt = self.state["prs"][key].get("retry_count", 0) + 1
                self.state["prs"][key]["retry_count"] = cnt
                return cnt
        return 0

    def reset_retry_count(self, pr_number: int) -> None:
        """Reset retry count for PR (transactional)."""
        with self._transact():
            key = str(pr_number)
            if key in self.state["prs"]:
                self.state["prs"][key]["retry_count"] = 0

    # ------------- Deduplication ------------- #

    def is_event_processed(self, pr_number: int, event_id: str) -> bool:
        """Check if an event has already been processed (reloads from disk)."""
        pr = self.get_pr(pr_number)
        if not pr or not event_id:
            return False
        return event_id in pr.get("processed_event_ids", [])

    def is_event_known(self, pr_number: int, event_id: str) -> bool:
        """
        Check if an event is already known (processed, currently in-flight,
        or queued in pending_events).
        Prevents in-flight events from being rediscovered and queued again.
        """
        pr = self.get_pr(pr_number)
        if not pr or not event_id:
            return False
        if event_id in pr.get("processed_event_ids", []):
            return True
        if any(e.get("id") == event_id for e in pr.get("in_flight_events", [])):
            return True
        if any(e.get("id") == event_id for e in pr.get("pending_events", [])):
            return True
        return False

    def mark_event_processed(self, pr_number: int, event_id: str) -> None:
        """Record event ID as processed (transactional)."""
        with self._transact():
            key = str(pr_number)
            if key in self.state["prs"]:
                events = self.state["prs"][key].setdefault(
                    "processed_event_ids", []
                )
                if event_id not in events:
                    events.append(event_id)

    # ------------- In-Flight Events (Delayed Failure Safety) ------------- #

    def set_in_flight_events(
        self, pr_number: int, events: List[Dict[str, Any]]
    ) -> None:
        """Record events currently being worked on by an active agent turn (transactional)."""
        with self._transact():
            key = str(pr_number)
            if key in self.state["prs"]:
                self.state["prs"][key]["in_flight_events"] = list(events)

    def get_in_flight_events(
        self, pr_number: int
    ) -> List[Dict[str, Any]]:
        """Retrieve in-flight events for a PR (reloads from disk)."""
        self._load_no_lock()
        pr = self.state.get("prs", {}).get(str(pr_number))
        if not pr:
            return []
        return list(pr.get("in_flight_events", []))

    def finalize_in_flight_events(self, pr_number: int) -> None:
        """
        Mark all in-flight events as permanently processed and clear the list.
        Called strictly after the agent has successfully pushed a new head SHA (transactional).
        """
        with self._transact():
            key = str(pr_number)
            if key in self.state["prs"]:
                in_flight = self.state["prs"][key].get("in_flight_events", [])
                processed = self.state["prs"][key].setdefault("processed_event_ids", [])
                for ev in in_flight:
                    ev_id = ev.get("id")
                    if ev_id and ev_id not in processed:
                        processed.append(ev_id)
                self.state["prs"][key]["in_flight_events"] = []

    def restore_in_flight_to_pending(self, pr_number: int) -> None:
        """
        Move in-flight events back into the pending_events queue.
        Called when an agent process exits without pushing fixes (transactional).
        """
        with self._transact():
            key = str(pr_number)
            if key in self.state["prs"]:
                in_flight = self.state["prs"][key].get("in_flight_events", [])
                pending = self.state["prs"][key].setdefault("pending_events", [])
                for ev in reversed(in_flight):
                    ev_id = ev.get("id")
                    if not any(e.get("id") == ev_id for e in pending if ev_id):
                        pending.insert(0, ev)
                self.state["prs"][key]["in_flight_events"] = []

    # ------------- Thread Resolution Tracking ------------- #

    def get_thread_is_resolved(
        self, pr_number: int, thread_id: str
    ) -> Optional[bool]:
        """Get last known isResolved state for a review thread."""
        pr = self.get_pr(pr_number)
        if not pr:
            return None
        return pr.get("thread_states", {}).get(thread_id)

    def set_thread_is_resolved(
        self, pr_number: int, thread_id: str, is_resolved: bool
    ) -> None:
        """Update isResolved state for a review thread (transactional)."""
        with self._transact():
            key = str(pr_number)
            if key in self.state["prs"]:
                threads = self.state["prs"][key].setdefault(
                    "thread_states", {}
                )
                threads[thread_id] = is_resolved

    # ------------- Concurrency Locking & Queuing ------------- #

    def is_processing(
        self,
        pr_number: int,
        lease_seconds: float = DEFAULT_LOCK_LEASE_SECONDS,
    ) -> bool:
        """
        Check if PR is currently being processed by an agent.
        Reloads from disk, checks PID liveness & lease expiry.
        """
        self._load_no_lock()
        pr = self.state.get("prs", {}).get(str(pr_number))
        if not pr:
            return False
        if pr.get("status") == "processing":
            pid = pr.get("active_agent_pid")
            if pid and is_pid_alive(pid):
                return True

            started = pr.get("processing_started_at", 0.0)
            if time.time() - started < lease_seconds:
                return True

            logger.warning(
                "Processing lease for PR #%s expired after %ss and no alive "
                "process. Clearing lock.",
                pr_number,
                lease_seconds,
            )
            self.release_lock(pr_number)
        return False

    def acquire_lock(
        self,
        pr_number: int,
        lease_seconds: float = DEFAULT_LOCK_LEASE_SECONDS,
        pid: Optional[int] = None,
    ) -> bool:
        """
        Attempt to acquire processing lock for PR (atomic & transactional).
        Both liveness/lease check AND lock acquisition are executed within
        the SAME file-locked transaction to prevent race conditions.
        """
        with self._transact():
            key = str(pr_number)
            pr = self.state["prs"].get(key)
            if not pr:
                return False

            if pr.get("status") == "processing":
                tracked_pid = pr.get("active_agent_pid")
                if tracked_pid and is_pid_alive(tracked_pid):
                    return False

                started = pr.get("processing_started_at", 0.0)
                if time.time() - started < lease_seconds:
                    return False

                logger.warning(
                    "Processing lease for PR #%s expired after %ss and no alive "
                    "process. Reclaiming lock.",
                    pr_number,
                    lease_seconds,
                )

            # Claim lock atomically within this transaction
            pr["status"] = "processing"
            pr["processing_started_at"] = time.time()
            pr["active_agent_pid"] = pid
            return True

    def release_lock(self, pr_number: int) -> None:
        """Release processing lock (transactional)."""
        with self._transact():
            key = str(pr_number)
            if key in self.state["prs"]:
                # Only reset to 'watching' if it was 'processing'; preserve terminal/approved states
                if self.state["prs"][key].get("status") == "processing":
                    self.state["prs"][key]["status"] = "watching"
                self.state["prs"][key]["processing_started_at"] = 0.0
                self.state["prs"][key]["active_agent_pid"] = None

    def queue_pending_event(
        self, pr_number: int, event: Dict[str, Any]
    ) -> None:
        """Queue event (transactional, deduplicates by event id)."""
        with self._transact():
            key = str(pr_number)
            if key in self.state["prs"]:
                pending = self.state["prs"][key].setdefault(
                    "pending_events", []
                )
                event_id = event.get("id")
                if not any(
                    e.get("id") == event_id for e in pending if event_id
                ):
                    pending.append(event)

    def restore_pending_events(
        self, pr_number: int, events: List[Dict[str, Any]]
    ) -> None:
        """Prepend events to pending queue when dispatch fails (transactional)."""
        with self._transact():
            key = str(pr_number)
            if key in self.state["prs"]:
                pending = self.state["prs"][key].setdefault(
                    "pending_events", []
                )
                for ev in reversed(events):
                    ev_id = ev.get("id")
                    if not any(
                        e.get("id") == ev_id for e in pending if ev_id
                    ):
                        pending.insert(0, ev)

    def pop_pending_events(self, pr_number: int) -> List[Dict[str, Any]]:
        """Pop all pending queued events for PR (transactional)."""
        with self._transact():
            key = str(pr_number)
            if key in self.state["prs"]:
                events = list(
                    self.state["prs"][key].get("pending_events", [])
                )
                self.state["prs"][key]["pending_events"] = []
                return events
        return []

    # ------------- Allowlist ------------- #

    def get_allowlist(self) -> List[str]:
        self._load_no_lock()
        return self.state.get("allowlist", [])

    def add_to_allowlist(self, username: str) -> None:
        with self._transact():
            if username and not any(
                u.lower() == username.lower()
                for u in self.state.get("allowlist", [])
            ):
                self.state.setdefault("allowlist", []).append(username)

    def is_user_allowed(self, username: str) -> bool:
        if not username:
            return False
        allowlist = self.get_allowlist()
        return any(u.lower() == username.lower() for u in allowlist)

"""
tools/review_loop/state_manager.py - Persistent state and concurrency manager.

Manages state.json safely with atomic writes, per-PR concurrency locks,
event deduplication, and queued event coalescing.
"""
import json
import logging
import os
import tempfile
import time
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tools.review_loop.config import DEFAULT_LOCK_LEASE_SECONDS, DEFAULT_STATE_FILE

logger = logging.getLogger(__name__)

class StateManager:
    def __init__(self, state_file: Optional[Path] = None):
        self.state_file = Path(state_file or DEFAULT_STATE_FILE)
        self.state: Dict[str, Any] = {
            "prs": {},
            "allowlist": []
        }
        self.load()

    def load(self) -> None:
        """Load state from disk. If missing or corrupted, start clean."""
        if not self.state_file.exists():
            return

        try:
            with open(self.state_file, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, dict):
                    self.state = data
                    if "prs" not in self.state:
                        self.state["prs"] = {}
                    if "allowlist" not in self.state:
                        self.state["allowlist"] = []
        except Exception as e:
            logger.warning("Failed to load state file '%s': %s. Re-initializing.", self.state_file, e)

    def save(self) -> None:
        """Atomically persist state to disk."""
        self.state_file.parent.mkdir(parents=True, exist_ok=True)
        tmp_fd, tmp_path = tempfile.mkstemp(dir=self.state_file.parent, prefix="state_", suffix=".tmp")
        try:
            with os.fdopen(tmp_fd, "w", encoding="utf-8") as f:
                json.dump(self.state, f, indent=2, ensure_ascii=False)
            # Atomic replace
            os.replace(tmp_path, self.state_file)
        except Exception as e:
            if os.path.exists(tmp_path):
                try:
                    os.remove(tmp_path)
                except OSError:
                    pass
            logger.error("Failed to save state to '%s': %s", self.state_file, e)
            raise

    # ---------------- PR Registration & Lifecycle ----------------

    def register_pr(self, pr_number: int, conversation_id: str, branch: str) -> None:
        """Register or update a PR mapping."""
        key = str(pr_number)
        existing = self.state["prs"].get(key, {})
        self.state["prs"][key] = {
            "conversation_id": conversation_id,
            "branch": branch,
            "status": "watching",
            "last_head_sha": existing.get("last_head_sha", ""),
            "processed_event_ids": existing.get("processed_event_ids", []),
            "processing_started_at": 0.0,
            "pending_events": existing.get("pending_events", [])
        }
        self.save()

    def unregister_pr(self, pr_number: int) -> bool:
        """Remove PR from state."""
        key = str(pr_number)
        if key in self.state["prs"]:
            del self.state["prs"][key]
            self.save()
            return True
        return False

    def mark_pr_status(self, pr_number: int, status: str) -> None:
        """Set status ('watching', 'processing', 'closed', 'error')."""
        key = str(pr_number)
        if key in self.state["prs"]:
            self.state["prs"][key]["status"] = status
            self.save()

    def get_registered_prs(self) -> Dict[str, Any]:
        """Return dict of all registered PRs."""
        return self.state.get("prs", {})

    def get_pr(self, pr_number: int) -> Optional[Dict[str, Any]]:
        """Get info for specific PR."""
        return self.state.get("prs", {}).get(str(pr_number))

    # ---------------- Deduplication ----------------

    def is_event_processed(self, pr_number: int, event_id: str) -> bool:
        """Check if an event (review ID, comment ID, etc.) has already been processed."""
        pr = self.get_pr(pr_number)
        if not pr:
            return False
        return event_id in pr.get("processed_event_ids", [])

    def mark_event_processed(self, pr_number: int, event_id: str) -> None:
        """Record event ID as processed."""
        key = str(pr_number)
        if key in self.state["prs"]:
            events = self.state["prs"][key].setdefault("processed_event_ids", [])
            if event_id not in events:
                events.append(event_id)
                self.save()

    # ---------------- Concurrency Locking & Queuing ----------------

    def is_processing(self, pr_number: int, lease_seconds: float = DEFAULT_LOCK_LEASE_SECONDS) -> bool:
        """Check if PR is currently being processed by an agent and lease has not expired."""
        pr = self.get_pr(pr_number)
        if not pr:
            return False
        if pr.get("status") == "processing":
            started = pr.get("processing_started_at", 0.0)
            if time.time() - started < lease_seconds:
                return True
            logger.warning("Processing lease for PR #%s expired after %ss. Clearing lock.", pr_number, lease_seconds)
            self.release_lock(pr_number)
        return False

    def acquire_lock(self, pr_number: int, lease_seconds: float = DEFAULT_LOCK_LEASE_SECONDS) -> bool:
        """
        Attempt to acquire processing lock for PR.
        Returns True if acquired, False if already locked.
        """
        if self.is_processing(pr_number, lease_seconds):
            return False

        key = str(pr_number)
        if key in self.state["prs"]:
            self.state["prs"][key]["status"] = "processing"
            self.state["prs"][key]["processing_started_at"] = time.time()
            self.save()
            return True
        return False

    def release_lock(self, pr_number: int) -> None:
        """Release processing lock and return to watching status."""
        key = str(pr_number)
        if key in self.state["prs"]:
            self.state["prs"][key]["status"] = "watching"
            self.state["prs"][key]["processing_started_at"] = 0.0
            self.save()

    def queue_pending_event(self, pr_number: int, event: Dict[str, Any]) -> None:
        """Queue an event that arrived while agent was already processing."""
        key = str(pr_number)
        if key in self.state["prs"]:
            pending = self.state["prs"][key].setdefault("pending_events", [])
            # Avoid queuing identical event multiple times
            event_id = event.get("id")
            if not any(e.get("id") == event_id for e in pending if event_id):
                pending.append(event)
                self.save()

    def pop_pending_events(self, pr_number: int) -> List[Dict[str, Any]]:
        """Pop all pending queued events for PR."""
        key = str(pr_number)
        if key in self.state["prs"]:
            events = list(self.state["prs"][key].get("pending_events", []))
            self.state["prs"][key]["pending_events"] = []
            self.save()
            return events
        return []

    # ---------------- Allowlist ----------------

    def get_allowlist(self) -> List[str]:
        return self.state.get("allowlist", [])

    def add_to_allowlist(self, username: str) -> None:
        if username not in self.state.setdefault("allowlist", []):
            self.state["allowlist"].append(username)
            self.save()

    def is_user_allowed(self, username: str) -> bool:
        if not username:
            return False
        allowlist = self.get_allowlist()
        # Case-insensitive comparison for GitHub usernames
        return any(u.lower() == username.lower() for u in allowlist)

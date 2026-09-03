"""
tools/review_loop/watcher.py - Main review loop polling daemon.

Monitors registered PRs on GitHub for review feedback, REQUEST_CHANGES,
thread reopenings, and wakes the mapped Antigravity agent context.
"""
import argparse
import logging
import os
import signal
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tools.review_loop.agent_resumer import AgentResumer
from tools.review_loop.config import (
    AGENT_COMMENT_MARKER,
    DEFAULT_BACKOFF_FACTOR,
    DEFAULT_BACKOFF_INITIAL_SECONDS,
    DEFAULT_BACKOFF_MAX_SECONDS,
    DEFAULT_LOG_FILE,
    DEFAULT_PID_FILE,
    DEFAULT_POLL_INTERVAL_SECONDS,
    DEFAULT_STATE_FILE,
    REPO_ROOT,
)
from tools.review_loop.github_client import GitHubClient, GitHubError
from tools.review_loop.state_manager import StateManager

logger = logging.getLogger("review_loop.watcher")

def is_agent_generated(body: str) -> bool:
    """Check if comment was posted by an automated agent tool to prevent loops."""
    if not body:
        return False
    return AGENT_COMMENT_MARKER in body or "<!-- agent:" in body or "<!-- antigravity:" in body

def is_bot_noise(author: str) -> bool:
    """Check if commenter is an automated bot that should be ignored by default."""
    if not author:
        return True
    author_lower = author.lower()
    return author_lower.endswith("[bot]") or "copilot" in author_lower

class ReviewWatcher:
    def __init__(
        self,
        github_client: Optional[GitHubClient] = None,
        state_manager: Optional[StateManager] = None,
        agent_resumer: Optional[AgentResumer] = None,
        poll_interval: int = DEFAULT_POLL_INTERVAL_SECONDS,
        run_once: bool = False
    ):
        self.github = github_client or GitHubClient(cwd=REPO_ROOT)
        self.state = state_manager or StateManager()
        self.resumer = agent_resumer or AgentResumer(cwd=REPO_ROOT)
        self.poll_interval = poll_interval
        self.run_once = run_once
        self._running = False

    def init_allowlist_if_empty(self) -> None:
        """If allowlist is empty, initialize it with repository owner."""
        if not self.state.get_allowlist():
            try:
                owner, _ = self.github.get_repo_owner_and_name()
                if owner:
                    logger.info("Initializing review allowlist with repo owner: %s", owner)
                    self.state.add_to_allowlist(owner)
            except Exception as e:
                logger.warning("Could not auto-detect repo owner: %s", e)

    def check_pr_events(self, pr_number: int, pr_info: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Inspect PR for new, unhandled, allowed review events.
        Accepts feedback from allowlisted reviewers even if reviewer == PR author.
        Ignores agent-marked comments and bot noise.
        """
        new_events: List[Dict[str, Any]] = []

        # 1. Inspect PR reviews
        try:
            reviews = self.github.get_pr_reviews(pr_number)
            for rev in reviews:
                rev_id = rev.get("id")
                rev_state = rev.get("state")
                rev_author = rev.get("author", {}).get("login", "")
                rev_body = rev.get("body", "")

                if not rev_id or self.state.is_event_processed(pr_number, rev_id):
                    continue

                if is_bot_noise(rev_author) or is_agent_generated(rev_body):
                    continue

                # Allowlist check: allowlisted reviewer feedback has highest priority
                if not self.state.is_user_allowed(rev_author):
                    logger.debug("Skipping review from non-allowlisted user: %s", rev_author)
                    continue

                if rev_state == "APPROVED":
                    logger.info("PR #%s received APPROVE from %s. Setting status to approved.", pr_number, rev_author)
                    self.state.mark_event_processed(pr_number, rev_id)
                    self.state.mark_pr_status(pr_number, "approved")
                    # Clear any pending events since PR is approved
                    self.state.pop_pending_events(pr_number)
                    continue

                if rev_state == "REQUEST_CHANGES":
                    logger.info("Detected REQUEST_CHANGES on PR #%s by %s", pr_number, rev_author)
                    new_events.append({
                        "id": rev_id,
                        "type": "REQUEST_CHANGES",
                        "author": rev_author,
                        "body": rev_body
                    })
                elif rev_state == "COMMENTED":
                    body = rev_body.strip()
                    if body:
                        logger.info("Detected review comment on PR #%s by %s", pr_number, rev_author)
                        new_events.append({
                            "id": rev_id,
                            "type": "REVIEW_COMMENT",
                            "author": rev_author,
                            "body": body
                        })
        except GitHubError as e:
            logger.warning("Error fetching reviews for PR #%s: %s", pr_number, e)

        # 2. Inspect top-level PR / issue comments
        try:
            comments = self.github.get_pr_comments(pr_number)
            for c in comments:
                c_id = c.get("id")
                c_author = c.get("author", {}).get("login", "")
                c_body = c.get("body", "")

                if not c_id or self.state.is_event_processed(pr_number, c_id):
                    continue

                if is_bot_noise(c_author) or is_agent_generated(c_body):
                    continue

                if not self.state.is_user_allowed(c_author):
                    continue

                body = c_body.strip()
                if body:
                    logger.info("Detected PR comment on PR #%s by %s", pr_number, c_author)
                    new_events.append({
                        "id": c_id,
                        "type": "PR_COMMENT",
                        "author": c_author,
                        "body": body
                    })
        except GitHubError as e:
            logger.warning("Error fetching comments for PR #%s: %s", pr_number, e)

        # 3. Inspect inline review comments
        try:
            inline_comments = self.github.get_pr_inline_comments(pr_number)
            for ic in inline_comments:
                ic_id = str(ic.get("id"))
                ic_author = ic.get("user", {}).get("login", "")
                ic_body = ic.get("body", "")

                if not ic_id or self.state.is_event_processed(pr_number, ic_id):
                    continue

                if is_bot_noise(ic_author) or is_agent_generated(ic_body):
                    continue

                if not self.state.is_user_allowed(ic_author):
                    continue

                body = ic_body.strip()
                if body:
                    logger.info("Detected inline review comment on PR #%s by %s", pr_number, ic_author)
                    new_events.append({
                        "id": ic_id,
                        "type": "INLINE_COMMENT",
                        "author": ic_author,
                        "body": body,
                        "path": ic.get("path"),
                        "line": ic.get("line")
                    })
        except GitHubError as e:
            logger.debug("Inline comments check for PR #%s: %s", pr_number, e)

        # 4. Inspect GraphQL review threads (including thread reopening transitions)
        try:
            threads = self.github.get_pr_review_threads(pr_number)
            for th in threads:
                th_id = th.get("id")
                is_resolved = th.get("isResolved", False)

                if th_id:
                    prev_resolved = self.state.get_thread_is_resolved(pr_number, th_id)
                    # Check for reopened transition (previously resolved -> now unresolved)
                    if prev_resolved is True and is_resolved is False:
                        reopen_id = f"reopen_{th_id}"
                        if not self.state.is_event_processed(pr_number, reopen_id):
                            logger.info("Detected reopened review thread %s on PR #%s", th_id, pr_number)
                            new_events.append({
                                "id": reopen_id,
                                "type": "THREAD_REOPENED",
                                "thread_id": th_id,
                                "body": "Review thread was reopened."
                            })
                    # Update tracked thread state
                    self.state.set_thread_is_resolved(pr_number, th_id, is_resolved)

                # Check unresolved thread's latest comment
                if not is_resolved:
                    th_comments = th.get("comments", {}).get("nodes", [])
                    if th_comments:
                        last_c = th_comments[-1]
                        th_c_id = last_c.get("id")
                        th_author = last_c.get("author", {}).get("login", "")
                        th_body = last_c.get("body", "")

                        if th_c_id and not self.state.is_event_processed(pr_number, th_c_id):
                            if not is_bot_noise(th_author) and not is_agent_generated(th_body):
                                if self.state.is_user_allowed(th_author):
                                    if not any(e.get("id") == th_c_id for e in new_events):
                                        new_events.append({
                                            "id": th_c_id,
                                            "type": "THREAD_COMMENT",
                                            "author": th_author,
                                            "body": th_body
                                        })
        except Exception as e:
            logger.debug("Review threads query for PR #%s: %s", pr_number, e)

        return new_events

    def process_registered_pr(self, pr_number: int, pr_entry: Dict[str, Any]) -> None:
        """Process a single registered PR."""
        conversation_id = pr_entry.get("conversation_id")
        if not conversation_id:
            logger.warning("PR #%s has no mapped conversation ID. Skipping.", pr_number)
            return

        try:
            pr_info = self.github.get_pr_details(pr_number)
        except GitHubError as e:
            logger.warning("Failed to fetch details for PR #%s: %s", pr_number, e)
            return

        pr_state = pr_info.get("state", "").upper()
        if pr_state in ["CLOSED", "MERGED"]:
            logger.info("PR #%s is %s. Updating status and stopping watch.", pr_number, pr_state)
            self.state.mark_pr_status(pr_number, "closed")
            return

        current_head_sha = pr_info.get("headRefOid", "")
        last_head_sha = pr_entry.get("last_head_sha", "")

        # Check if an approved PR was reactivated by a new commit
        if pr_entry.get("status") == "approved":
            if current_head_sha and last_head_sha and current_head_sha != last_head_sha:
                logger.info("Approved PR #%s received new commit (%s -> %s). Reactivating watch.", pr_number, last_head_sha, current_head_sha)
                pr_entry["last_head_sha"] = current_head_sha
                self.state.mark_pr_status(pr_number, "watching")
            else:
                # PR is approved and head SHA hasn't changed. Feedback loop is completely stopped.
                return

        # Check if agent pushed fixes while processing (head changed from baseline)
        if self.state.is_processing(pr_number):
            if current_head_sha and last_head_sha and current_head_sha != last_head_sha:
                logger.info("PR #%s head SHA changed (%s -> %s). Agent completed run.", pr_number, last_head_sha, current_head_sha)
                pr_entry["last_head_sha"] = current_head_sha
                self.state.save()
                self.state.release_lock(pr_number)

        # Detect new review events
        new_events = self.check_pr_events(pr_number, pr_info)

        # If PR became approved during event check, stop here
        if pr_entry.get("status") == "approved":
            return

        # Handle concurrency and locking
        if self.state.is_processing(pr_number):
            if new_events:
                logger.info("PR #%s is currently being processed. Queuing %d new event(s).", pr_number, len(new_events))
                for ev in new_events:
                    self.state.queue_pending_event(pr_number, ev)
            return

        # PR is idle. Collect new and pending events
        pending_events = self.state.pop_pending_events(pr_number)
        all_events = new_events + pending_events

        if not all_events:
            return

        # Acquire lock before attempting resume
        if not self.state.acquire_lock(pr_number):
            logger.warning("Failed to acquire lock for PR #%s. Skipping.", pr_number)
            # Put events back so they are not lost
            self.state.restore_pending_events(pr_number, all_events)
            return

        # Update last known head SHA
        if current_head_sha:
            pr_entry["last_head_sha"] = current_head_sha
            self.state.save()

        logger.info(
            "Waking Antigravity conversation %s for PR #%s with %d event(s)...",
            conversation_id, pr_number, len(all_events)
        )
        success, out, active_pid = self.resumer.resume_conversation(conversation_id, pr_number)

        if not success:
            logger.error("Failed to wake conversation %s: %s. Restoring events and releasing lock for retry.", conversation_id, out)
            # CRITICAL: DO NOT lose events on failure! Restore them to pending queue!
            self.state.restore_pending_events(pr_number, all_events)
            self.state.release_lock(pr_number)
        else:
            logger.info("Successfully signaled agent for PR #%s.", pr_number)
            # Only mark events as processed AFTER successful dispatch!
            for ev in all_events:
                self.state.mark_event_processed(pr_number, ev["id"])
            if active_pid:
                self.state.state["prs"][str(pr_number)]["active_agent_pid"] = active_pid
                self.state.save()

    def run_cycle(self) -> None:
        """Run a single polling cycle across all active registered PRs."""
        self.init_allowlist_if_empty()
        prs = self.state.get_registered_prs()
        if not prs:
            logger.debug("No registered PRs to watch.")
            return

        for pr_str, pr_entry in list(prs.items()):
            try:
                pr_number = int(pr_str)
            except ValueError:
                continue

            if pr_entry.get("status") == "closed":
                continue

            self.process_registered_pr(pr_number, pr_entry)

    def start(self) -> None:
        """Main polling loop with bounded backoff on GitHub failures."""
        try:
            os.chdir(REPO_ROOT)
        except Exception:
            pass

        is_auth, auth_msg = self.github.check_auth()
        if not is_auth:
            logger.error("FATAL: GitHub CLI (gh) is not authenticated!\n%s\nRun 'gh auth login' to authenticate.", auth_msg)
            sys.exit(1)

        logger.info("GitHub authentication verified.")
        self.write_pid()
        self._running = True

        backoff = DEFAULT_BACKOFF_INITIAL_SECONDS

        try:
            while self._running:
                try:
                    self.run_cycle()
                    backoff = DEFAULT_BACKOFF_INITIAL_SECONDS
                except GitHubError as e:
                    logger.warning("GitHub CLI error encountered: %s. Backing off for %ss.", e, backoff)
                    time.sleep(backoff)
                    backoff = min(backoff * DEFAULT_BACKOFF_FACTOR, DEFAULT_BACKOFF_MAX_SECONDS)
                    continue
                except Exception as e:
                    logger.exception("Unexpected error during watcher cycle: %s", e)

                if self.run_once:
                    break

                time.sleep(self.poll_interval)
        finally:
            self.remove_pid()
            logger.info("Review watcher stopped.")

    def stop(self) -> None:
        self._running = False

    def write_pid(self) -> None:
        DEFAULT_PID_FILE.parent.mkdir(parents=True, exist_ok=True)
        try:
            DEFAULT_PID_FILE.write_text(str(os.getpid()), encoding="utf-8")
        except Exception as e:
            logger.warning("Could not write PID file: %s", e)

    def remove_pid(self) -> None:
        try:
            if DEFAULT_PID_FILE.exists():
                DEFAULT_PID_FILE.unlink()
        except Exception:
            pass

def setup_logging(log_file: Optional[Path] = None, verbose: bool = False) -> None:
    path = log_file or DEFAULT_LOG_FILE
    path.parent.mkdir(parents=True, exist_ok=True)
    level = logging.DEBUG if verbose else logging.INFO

    formatter = logging.Formatter(
        fmt="%(asctime)s [%(levelname)s] [%(name)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S"
    )

    file_handler = logging.FileHandler(str(path), encoding="utf-8")
    file_handler.setFormatter(formatter)
    file_handler.setLevel(level)

    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(formatter)
    console_handler.setLevel(level)

    root = logging.getLogger()
    root.setLevel(level)
    root.addHandler(file_handler)
    root.addHandler(console_handler)

def main() -> None:
    parser = argparse.ArgumentParser(description="Autonomous PR review feedback watcher.")
    parser.add_argument("--run-once", action="store_true", help="Run a single check cycle and exit.")
    parser.add_argument("--interval", type=int, default=DEFAULT_POLL_INTERVAL_SECONDS, help="Polling interval in seconds.")
    parser.add_argument("--verbose", "-v", action="store_true", help="Enable verbose debug logging.")
    args = parser.parse_args()

    setup_logging(verbose=args.verbose)
    watcher = ReviewWatcher(poll_interval=args.interval, run_once=args.run_once)

    def handle_signal(sig, frame):
        logger.info("Received termination signal %s. Exiting gracefully...", sig)
        watcher.stop()

    signal.signal(signal.SIGINT, handle_signal)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, handle_signal)

    watcher.start()

if __name__ == "__main__":
    main()

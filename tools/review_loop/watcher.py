"""
tools/review_loop/watcher.py - Main review loop polling daemon.

Monitors registered PRs on GitHub for review comments, REQUEST_CHANGES,
and wakes the mapped Antigravity agent context.
"""
import argparse
import logging
import os
import signal
import sys
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

# Ensure repository root is in sys.path for direct script execution
_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tools.review_loop.agent_resumer import AgentResumer
from tools.review_loop.config import (
    DEFAULT_BACKOFF_FACTOR,
    DEFAULT_BACKOFF_INITIAL_SECONDS,
    DEFAULT_BACKOFF_MAX_SECONDS,
    DEFAULT_LOG_FILE,
    DEFAULT_PID_FILE,
    DEFAULT_POLL_INTERVAL_SECONDS,
    DEFAULT_STATE_FILE,
)
from tools.review_loop.github_client import GitHubClient, GitHubError
from tools.review_loop.state_manager import StateManager

logger = logging.getLogger("review_loop.watcher")

class ReviewWatcher:
    def __init__(
        self,
        github_client: Optional[GitHubClient] = None,
        state_manager: Optional[StateManager] = None,
        agent_resumer: Optional[AgentResumer] = None,
        poll_interval: int = DEFAULT_POLL_INTERVAL_SECONDS,
        run_once: bool = False
    ):
        self.github = github_client or GitHubClient()
        self.state = state_manager or StateManager()
        self.resumer = agent_resumer or AgentResumer()
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
        Returns list of new event dictionaries.
        """
        new_events: List[Dict[str, Any]] = []
        author = pr_info.get("author", {}).get("login", "")
        review_decision = pr_info.get("reviewDecision")

        # 1. Inspect PR reviews
        try:
            reviews = self.github.get_pr_reviews(pr_number)
            for rev in reviews:
                rev_id = rev.get("id")
                rev_state = rev.get("state")
                rev_author = rev.get("author", {}).get("login", "")

                if not rev_id or self.state.is_event_processed(pr_number, rev_id):
                    continue

                # Never react to comments by PR author / agent itself
                if rev_author and rev_author.lower() == author.lower():
                    continue

                # Enforce reviewer allowlist
                if not self.state.is_user_allowed(rev_author):
                    logger.debug("Skipping review from non-allowlisted user: %s", rev_author)
                    continue

                if rev_state == "APPROVED":
                    logger.info("PR #%s received APPROVE from %s. Halting loop without waking.", pr_number, rev_author)
                    self.state.mark_event_processed(pr_number, rev_id)
                    continue

                if rev_state == "REQUEST_CHANGES":
                    logger.info("Detected REQUEST_CHANGES on PR #%s by %s", pr_number, rev_author)
                    new_events.append({
                        "id": rev_id,
                        "type": "REQUEST_CHANGES",
                        "author": rev_author,
                        "body": rev.get("body", "")
                    })
                elif rev_state == "COMMENTED":
                    body = rev.get("body", "").strip()
                    if body and "copilot-pull-request-reviewer" not in rev_author.lower():
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

                if not c_id or self.state.is_event_processed(pr_number, c_id):
                    continue

                if c_author and c_author.lower() == author.lower():
                    continue

                if not self.state.is_user_allowed(c_author):
                    continue

                body = c.get("body", "").strip()
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

                if not ic_id or self.state.is_event_processed(pr_number, ic_id):
                    continue

                if ic_author and ic_author.lower() == author.lower():
                    continue

                if not self.state.is_user_allowed(ic_author):
                    continue

                body = ic.get("body", "").strip()
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

        # 4. Inspect GraphQL review threads for reopened / unresolved comments
        try:
            threads = self.github.get_pr_review_threads(pr_number)
            for th in threads:
                if not th.get("isResolved", False):
                    th_comments = th.get("comments", {}).get("nodes", [])
                    if th_comments:
                        last_c = th_comments[-1]
                        th_c_id = last_c.get("id")
                        th_author = last_c.get("author", {}).get("login", "")
                        if th_c_id and not self.state.is_event_processed(pr_number, th_c_id):
                            if th_author and th_author.lower() != author.lower() and self.state.is_user_allowed(th_author):
                                if not any(e.get("id") == th_c_id for e in new_events):
                                    new_events.append({
                                        "id": th_c_id,
                                        "type": "THREAD_COMMENT",
                                        "author": th_author,
                                        "body": last_c.get("body", "")
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

        # Check PR state
        pr_state = pr_info.get("state", "").upper()
        if pr_state in ["CLOSED", "MERGED"]:
            logger.info("PR #%s is %s. Updating status and stopping watch.", pr_number, pr_state)
            self.state.mark_pr_status(pr_number, "closed")
            return

        current_head_sha = pr_info.get("headRefOid", "")
        last_head_sha = pr_entry.get("last_head_sha", "")

        # Check if agent pushed fixes while processing (head changed from known baseline)
        if self.state.is_processing(pr_number):
            if current_head_sha and last_head_sha and current_head_sha != last_head_sha:
                logger.info("PR #%s head SHA changed (%s -> %s). Agent completed run.", pr_number, last_head_sha, current_head_sha)
                pr_entry["last_head_sha"] = current_head_sha
                self.state.save()
                self.state.release_lock(pr_number)

        # Detect new review events
        new_events = self.check_pr_events(pr_number, pr_info)

        # Handle concurrency and locking
        if self.state.is_processing(pr_number):
            if new_events:
                logger.info("PR #%s is currently being processed. Queuing %d new event(s).", pr_number, len(new_events))
                for ev in new_events:
                    self.state.queue_pending_event(pr_number, ev)
                    self.state.mark_event_processed(pr_number, ev["id"])
            return

        # PR is idle. If there are new events or pending queued events:
        pending_events = self.state.pop_pending_events(pr_number)
        all_events = new_events + pending_events

        if not all_events:
            return

        # Acquire lock
        if not self.state.acquire_lock(pr_number):
            logger.warning("Failed to acquire lock for PR #%s. Skipping.", pr_number)
            return

        # Mark all new events processed before waking to guarantee idempotency
        for ev in all_events:
            self.state.mark_event_processed(pr_number, ev["id"])

        # Update last known head SHA before waking
        if current_head_sha:
            pr_entry["last_head_sha"] = current_head_sha
            self.state.save()

        logger.info(
            "Waking Antigravity conversation %s for PR #%s with %d event(s)...",
            conversation_id, pr_number, len(all_events)
        )
        success, out = self.resumer.resume_conversation(conversation_id, pr_number)
        if not success:
            logger.error("Failed to wake conversation %s: %s. Releasing lock.", conversation_id, out)
            self.state.release_lock(pr_number)
        else:
            logger.info("Successfully signaled agent for PR #%s.", pr_number)

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
        # 1. Check auth status at startup
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
                    backoff = DEFAULT_BACKOFF_INITIAL_SECONDS  # Reset on success
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

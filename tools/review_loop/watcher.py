"""
tools/review_loop/watcher.py - Main review loop polling daemon.

Monitors registered PRs on GitHub for review feedback, REQUEST_CHANGES,
thread reopenings, and wakes the mapped Antigravity agent context.
Tracks full agent lifecycle with zero feedback loss on delayed failures.
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

from tools.review_loop.agent_resumer import AgentResumer, AgentResumerError
from tools.review_loop.config import (
    AGENT_COMMENT_MARKER,
    AGENT_STARTUP_GRACE_PERIOD_SECONDS,
    DEFAULT_BACKOFF_FACTOR,
    DEFAULT_BACKOFF_INITIAL_SECONDS,
    DEFAULT_BACKOFF_MAX_SECONDS,
    DEFAULT_LOG_FILE,
    DEFAULT_PID_FILE,
    DEFAULT_POLL_INTERVAL_SECONDS,
    DEFAULT_STATE_FILE,
    DESIGN_DECISION_MARKER,
    MAX_AGENT_RETRIES,
    REPO_ROOT,
    REVIEW_LOOP_DIR,
)
from tools.review_loop.github_client import GitHubAuthError, GitHubClient, GitHubError
from tools.review_loop.state_manager import StateManager, is_pid_alive

logger = logging.getLogger("review_loop.watcher")

READY_VERDICT_MARKERS = [
    "READY TO MERGE",
    "READY WITH NON-BLOCKING NOTES",
]

def extract_verdict_line(body: str) -> Optional[str]:
    """
    Extract the explicit verdict line from the first non-empty line of a review or comment body.
    Normalizes markdown formatting and optional 'Verdict:' or 'Вердикт:' prefix.
    Does not scan subsequent lines to prevent mentions inside quotes/history from triggering approval.
    """
    if not body:
        return None

    lines = [line.strip() for line in body.splitlines() if line.strip()]
    if not lines:
        return None

    # Derive the terminal verdict ONLY from the first non-empty line
    raw_first_line = lines[0]
    cleaned = raw_first_line.replace("*", "").replace("_", "").replace("#", "").replace("`", "").strip()
    cleaned_lower = cleaned.lower()

    if cleaned_lower.startswith("verdict:") or cleaned_lower.startswith("вердикт:"):
        _, val = cleaned.split(":", 1)
        return val.strip()
    if cleaned_lower.startswith("verdict") or cleaned_lower.startswith("вердикт"):
        parts = cleaned.split(None, 1)
        if len(parts) > 1:
            return parts[1].strip()

    return cleaned

def is_ready_verdict(body: str) -> bool:
    """
    Check if review or comment body contains an explicit project-level merge-ready verdict.
    Derives the verdict only from the first non-empty logical line, and requires the normalized
    verdict value itself to be exactly 'READY TO MERGE' or 'READY WITH NON-BLOCKING NOTES'.
    Any trailing explanatory text must be placed on following lines.
    """
    verdict_line = extract_verdict_line(body)
    if not verdict_line:
        return False

    v_upper = verdict_line.strip().upper().rstrip(".!")
    return v_upper in READY_VERDICT_MARKERS

def is_agent_generated(body: str) -> bool:
    """Check if comment was posted by an automated agent tool to prevent loops."""
    if not body:
        return False
    return AGENT_COMMENT_MARKER in body or "<!-- agent:" in body or "<!-- antigravity:" in body

def is_event_allowed(author: str, body: str, state_mgr: StateManager) -> bool:
    """
    Check if a review or comment event should be processed.
    - Agent-generated comments are always ignored to prevent infinite loops.
    - Explicitly allowlisted users (including explicitly allowed bots) are permitted.
    - Generic bot noise and unallowlisted users are ignored.
    """
    if is_agent_generated(body):
        return False
    if not author:
        return False
    return state_mgr.is_user_allowed(author)

def get_effective_review_state(
    reviews: List[Dict[str, Any]],
    allowlist: List[str],
    review_decision: Optional[str] = None,
    comments: Optional[List[Dict[str, Any]]] = None,
) -> str:
    """
    Determine the effective review state for the PR.
    Returns: 'APPROVED', 'CHANGES_REQUESTED', or 'NEUTRAL'.
    Recognizes explicit GitHub reviewDecision, explicit APPROVED state,
    or project fallback READY_VERDICT_MARKERS ('READY TO MERGE') in reviews/comments.
    """
    # 1. If GitHub reports explicit overall reviewDecision, check that first
    if review_decision:
        decision_upper = review_decision.upper()
        if decision_upper in ("CHANGES_REQUESTED", "REQUEST_CHANGES"):
            return "CHANGES_REQUESTED"
        if decision_upper == "APPROVED":
            return "APPROVED"

    # 2. Track latest interaction per allowlisted reviewer across reviews and comments
    author_states: Dict[str, Dict[str, Any]] = {}

    for rev in reviews:
        author = rev.get("author", {}).get("login", "")
        if not author or not any(u.lower() == author.lower() for u in allowlist):
            continue
        ts = rev.get("submittedAt") or rev.get("submitted_at") or rev.get("createdAt") or ""
        state = (rev.get("state") or "").upper()
        body = rev.get("body", "")
        verdict = "NEUTRAL"
        if state in ("REQUEST_CHANGES", "CHANGES_REQUESTED"):
            verdict = "CHANGES_REQUESTED"
        elif state == "APPROVED" or (state == "COMMENTED" and is_ready_verdict(body)):
            verdict = "APPROVED"
        author_states[author.lower()] = {"verdict": verdict, "ts": ts}

    if comments:
        for c in comments:
            author = c.get("author", {}).get("login", "")
            if not author or not any(u.lower() == author.lower() for u in allowlist):
                continue
            ts = c.get("createdAt") or c.get("created_at") or ""
            body = c.get("body", "")
            if is_ready_verdict(body):
                existing = author_states.get(author.lower())
                # Update to APPROVED if no review yet, or if comment is newer/equal to review
                if not existing or not ts or not existing.get("ts") or ts >= existing.get("ts", ""):
                    author_states[author.lower()] = {"verdict": "APPROVED", "ts": ts}

    if not author_states:
        return "NEUTRAL"

    has_approval = False
    for a_info in author_states.values():
        v = a_info.get("verdict")
        if v == "CHANGES_REQUESTED":
            return "CHANGES_REQUESTED"
        if v == "APPROVED":
            has_approval = True

    if has_approval:
        return "APPROVED"

    return "NEUTRAL"

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
            except GitHubAuthError:
                raise
            except Exception as e:
                logger.warning("Could not auto-detect repo owner: %s", e)

    def reconcile_registrations(self) -> None:
        """Recover open PR registrations from hook-observed branch mappings."""
        mappings = self.state.get_branch_conversations()
        if not mappings:
            return

        registered = self.state.get_registered_prs()
        registered_branches = {
            str(entry.get("branch") or "")
            for entry in registered.values()
            if isinstance(entry, dict)
        }
        unmatched_mappings = {
            branch: conversation_id
            for branch, conversation_id in mappings.items()
            if branch not in registered_branches
        }
        if not unmatched_mappings:
            return

        for pr in self.github.get_open_prs():
            pr_number = pr.get("number")
            branch = str(pr.get("headRefName") or "").strip()
            conversation_id = unmatched_mappings.get(branch)
            if not pr_number or not conversation_id or str(pr_number) in registered:
                continue
            self.state.register_pr(int(pr_number), conversation_id, branch)
            logger.info(
                "Recovered registration for PR #%s on branch '%s' from hook state.",
                pr_number,
                branch,
            )

    def check_pr_events(self, pr_number: int, pr_info: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Inspect PR for new, unhandled, allowed review events.
        Accepts feedback from allowlisted reviewers even if reviewer == PR author.
        Ignores agent-marked comments, terminal merge-ready verdicts, and unallowlisted bot noise.
        """
        new_events: List[Dict[str, Any]] = []

        # 1. Inspect PR reviews
        try:
            reviews = self.github.get_pr_reviews(pr_number)
            for rev in reviews:
                rev_id = rev.get("id")
                rev_state = (rev.get("state") or "").upper()
                rev_author = rev.get("author", {}).get("login", "")
                rev_body = rev.get("body", "")

                if not rev_id or self.state.is_event_known(pr_number, rev_id):
                    continue

                if not is_event_allowed(rev_author, rev_body, self.state):
                    continue

                if rev_state == "APPROVED":
                    # Mark review ID as seen, but DO NOT unilaterally declare PR approved here.
                    # Effective review state is evaluated holistically in process_registered_pr.
                    self.state.mark_event_processed(pr_number, rev_id)
                    continue

                if rev_state == "COMMENTED" and is_ready_verdict(rev_body):
                    logger.info("Detected merge-ready review verdict on PR #%s by %s", pr_number, rev_author)
                    self.state.mark_event_processed(pr_number, rev_id)
                    continue

                if rev_state in ("REQUEST_CHANGES", "CHANGES_REQUESTED"):
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
        except GitHubAuthError:
            raise
        except GitHubError as e:
            logger.warning("Error fetching reviews for PR #%s: %s", pr_number, e)
            raise

        # 2. Inspect top-level PR / issue comments
        try:
            comments = self.github.get_pr_comments(pr_number)
            for c in comments:
                c_id = c.get("id")
                c_author = c.get("author", {}).get("login", "")
                c_body = c.get("body", "")

                if not c_id or self.state.is_event_known(pr_number, c_id):
                    continue

                if not is_event_allowed(c_author, c_body, self.state):
                    continue

                body = c_body.strip()
                if is_ready_verdict(body):
                    logger.info("Detected merge-ready comment verdict on PR #%s by %s", pr_number, c_author)
                    self.state.mark_event_processed(pr_number, c_id)
                    continue

                if body:
                    logger.info("Detected PR comment on PR #%s by %s", pr_number, c_author)
                    new_events.append({
                        "id": c_id,
                        "type": "PR_COMMENT",
                        "author": c_author,
                        "body": body
                    })
        except GitHubAuthError:
            raise
        except GitHubError as e:
            logger.warning("Error fetching comments for PR #%s: %s", pr_number, e)
            raise

        # 3. Inspect inline review comments
        try:
            inline_comments = self.github.get_pr_inline_comments(pr_number)
            for ic in inline_comments:
                ic_id = str(ic.get("id"))
                ic_author = ic.get("user", {}).get("login", "")
                ic_body = ic.get("body", "")

                if not ic_id or self.state.is_event_known(pr_number, ic_id):
                    continue

                if not is_event_allowed(ic_author, ic_body, self.state):
                    continue

                body = ic_body.strip()
                if is_ready_verdict(body):
                    self.state.mark_event_processed(pr_number, ic_id)
                    continue

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
        except GitHubAuthError:
            raise
        except GitHubError as e:
            logger.debug("Inline comments check for PR #%s: %s", pr_number, e)

        # 4. Inspect GraphQL review threads (including thread reopening transitions)
        try:
            threads = self.github.get_pr_review_threads(pr_number)
            for th in threads:
                th_id = th.get("id")
                is_resolved = th.get("isResolved", False)

                if th_id:
                    # Atomic transition check + state update + counter increment in one file-locked transaction
                    reopen_version = self.state.observe_thread_resolution(pr_number, th_id, is_resolved)
                    if reopen_version is not None:
                        reopen_id = f"reopen_{th_id}_v{reopen_version}"
                        if not self.state.is_event_known(pr_number, reopen_id):
                            logger.info(
                                "Detected reopened review thread %s (transition #%d) on PR #%s",
                                th_id, reopen_version, pr_number
                            )
                            new_events.append({
                                "id": reopen_id,
                                "type": "THREAD_REOPENED",
                                "thread_id": th_id,
                                "reopen_transition": reopen_version,
                                "body": f"Review thread was reopened (reopen #{reopen_version})."
                            })

                # Check unresolved thread's latest comment
                if not is_resolved:
                    th_comments = th.get("comments", {}).get("nodes", [])
                    if th_comments:
                        last_c = th_comments[-1]
                        th_c_id = last_c.get("id")
                        th_author = last_c.get("author", {}).get("login", "")
                        th_body = last_c.get("body", "")

                        if th_c_id and not self.state.is_event_known(pr_number, th_c_id):
                            if is_event_allowed(th_author, th_body, self.state):
                                if is_ready_verdict(th_body):
                                    self.state.mark_event_processed(pr_number, th_c_id)
                                    continue
                                if not any(e.get("id") == th_c_id for e in new_events):
                                    new_events.append({
                                        "id": th_c_id,
                                        "type": "THREAD_COMMENT",
                                        "author": th_author,
                                        "body": th_body
                                    })
        except GitHubAuthError:
            raise
        except Exception as e:
            logger.debug("Review threads query for PR #%s: %s", pr_number, e)

        return new_events

    def process_registered_pr(self, pr_number: int, pr_entry: Optional[Dict[str, Any]] = None) -> None:
        """Process a single registered PR with full terminal completion and failure handling."""
        try:
            self._process_registered_pr_impl(pr_number, pr_entry)
        except GitHubAuthError as e:
            logger.error(
                "FATAL: GitHub authentication failure processing PR #%s: %s. "
                "Transitioning PR to 'error' status.",
                pr_number, e
            )
            self.state.mark_pr_status(pr_number, "error")
            self.state.restore_in_flight_to_pending(pr_number)
            self.state.release_lock(pr_number)
            raise

    def _process_registered_pr_impl(self, pr_number: int, pr_entry: Optional[Dict[str, Any]] = None) -> None:
        authoritative_pr = self.state.get_pr(pr_number)
        if not authoritative_pr:
            return
        pr_entry = authoritative_pr

        conversation_id = pr_entry.get("conversation_id")
        if not conversation_id:
            logger.warning("PR #%s has no mapped conversation ID. Skipping.", pr_number)
            return

        try:
            pr_info = self.github.get_pr_details(pr_number)
        except GitHubAuthError:
            raise
        except GitHubError as e:
            if "could not resolve to a pullrequest" in str(e).lower() or "not found" in str(e).lower():
                logger.warning("PR #%s not found on GitHub. Closing.", pr_number)
                self.state.mark_pr_status(pr_number, "closed")
                return
            logger.warning("Transient GitHub error fetching details for PR #%s: %s", pr_number, e)
            raise

        pr_state = pr_info.get("state", "").upper()
        if pr_state in ["CLOSED", "MERGED"]:
            logger.info("PR #%s is %s. Updating status and stopping watch.", pr_number, pr_state)
            self.state.mark_pr_status(pr_number, "closed")
            return

        current_head_sha = pr_info.get("headRefOid", "")
        last_head_sha = pr_entry.get("last_head_sha", "")

        pr_status = pr_entry.get("status", "watching")
        if pr_status in ["closed", "error", "awaiting_design_decision"]:
            # If developer pushed a new commit, reactivate the PR back to watching!
            if current_head_sha and last_head_sha and current_head_sha != last_head_sha:
                logger.info(
                    "PR #%s received new commit (%s -> %s). Reactivating from '%s' to 'watching'.",
                    pr_number, last_head_sha, current_head_sha, pr_status
                )
                self.state.reset_retry_count(pr_number)
                self.state.update_pr_fields(pr_number, last_head_sha=current_head_sha, status="watching")
                pr_entry = self.state.get_pr(pr_number) or pr_entry
            else:
                return

        # ---------------- 1. Active Processing Check & Completion ----------------
        if pr_status == "processing":
            pid = pr_entry.get("active_agent_pid")
            started_at = pr_entry.get("processing_started_at", 0.0)
            elapsed = time.time() - started_at

            if pid and is_pid_alive(pid):
                # Agent process is actively running. Queue any new incoming review events.
                new_events = self.check_pr_events(pr_number, pr_info)
                if new_events:
                    logger.info("PR #%s is currently being processed. Queuing %d new event(s).", pr_number, len(new_events))
                    for ev in new_events:
                        self.state.queue_pending_event(pr_number, ev)
                return

            # If launch is in progress (pid is None) and within startup grace period, do not intervene
            if pid is None and elapsed < AGENT_STARTUP_GRACE_PERIOD_SECONDS:
                logger.debug("PR #%s agent launch in progress (elapsed: %.1fs). Waiting.", pr_number, elapsed)
                return

            # Process has EXITED or startup timed out or lease expired. Run completion handling:
            in_flight = self.state.get_in_flight_events(pr_number)
            if current_head_sha and last_head_sha and current_head_sha != last_head_sha:
                # SUCCESS: Agent completed turn and pushed fixes to GitHub!
                logger.info(
                    "Agent run succeeded for PR #%s (new head %s -> %s). Finalizing %d in-flight event(s).",
                    pr_number, last_head_sha, current_head_sha, len(in_flight)
                )
                self.state.reset_retry_count(pr_number)
                self.state.finalize_in_flight_events(pr_number)
                self.state.update_pr_fields(pr_number, last_head_sha=current_head_sha)
                self.state.release_lock(pr_number)
                return
            else:
                # Check run-scoped agy log output for DESIGN DECISION REQUIRED
                run_id = self.state.get_current_run_id(pr_number)
                log_path = REVIEW_LOOP_DIR / f"agy_pr_{pr_number}_run_{run_id}.log"
                log_text = ""
                if log_path.exists():
                    try:
                        log_text = log_path.read_text(encoding="utf-8", errors="replace")
                    except Exception:
                        pass

                if DESIGN_DECISION_MARKER in log_text:
                    logger.warning(
                        "PR #%s halted: agent reported %s. Awaiting human design decision.",
                        pr_number, DESIGN_DECISION_MARKER
                    )
                    self.state.mark_pr_status(pr_number, "awaiting_design_decision")
                    self.state.restore_in_flight_to_pending(pr_number)
                    self.state.release_lock(pr_number)
                    return

                # Unrecoverable error / soft-deny / crash / lease expiry without commit: check retry count
                retry_cnt = self.state.increment_retry_count(pr_number)
                if retry_cnt >= MAX_AGENT_RETRIES:
                    logger.error(
                        "PR #%s reached maximum retries (%d). Transitioning to 'error' state.",
                        pr_number, MAX_AGENT_RETRIES
                    )
                    self.state.mark_pr_status(pr_number, "error")
                    self.state.restore_in_flight_to_pending(pr_number)
                    self.state.release_lock(pr_number)
                    return

                logger.warning(
                    "Agent process for PR #%s exited without pushing new commits (retry %d/%d). "
                    "Restoring %d in-flight event(s) to pending queue for retry.",
                    pr_number, retry_cnt, MAX_AGENT_RETRIES, len(in_flight)
                )
                self.state.restore_in_flight_to_pending(pr_number)
                self.state.release_lock(pr_number)
                return

        # ---------------- 2. Approved PR Handling ----------------
        if pr_entry.get("status") == "approved":
            # If developer pushed new commit, approval baseline is invalidated: reactivate!
            if current_head_sha and last_head_sha and current_head_sha != last_head_sha:
                logger.info("Approved PR #%s received new commit (%s -> %s). Reactivating watch.", pr_number, last_head_sha, current_head_sha)
                self.state.reset_retry_count(pr_number)
                self.state.update_pr_fields(pr_number, last_head_sha=current_head_sha, status="watching")
                pr_entry = self.state.get_pr(pr_number) or pr_entry
            else:
                # Check if reviewDecision or latest review changed back to CHANGES_REQUESTED
                try:
                    reviews = self.github.get_pr_reviews(pr_number)
                    comments = self.github.get_pr_comments(pr_number)
                    effective_state = get_effective_review_state(
                        reviews,
                        self.state.get_allowlist(),
                        pr_info.get("reviewDecision"),
                        comments=comments
                    )
                except GitHubAuthError:
                    raise
                except Exception:
                    effective_state = "NEUTRAL"

                if effective_state == "CHANGES_REQUESTED":
                    logger.info("Approved PR #%s received new CHANGES_REQUESTED. Reactivating watch.", pr_number)
                    self.state.reset_retry_count(pr_number)
                    self.state.update_pr_fields(pr_number, status="watching")
                    pr_entry = self.state.get_pr(pr_number) or pr_entry
                else:
                    # Still approved: comments or neutral events on approved PR do NOT wake agent!
                    return

        # ---------------- 3. Collect Actionable Events ----------------
        new_events = self.check_pr_events(pr_number, pr_info)
        pending_events = self.state.pop_pending_events(pr_number)
        raw_events = new_events + pending_events
        # Filter out any event already finalized as processed
        all_events = [ev for ev in raw_events if not self.state.is_event_processed(pr_number, ev.get("id"))]

        # ---------------- 4. Effective Review State Evaluation & Dominance ----------------
        try:
            reviews = self.github.get_pr_reviews(pr_number)
            comments = self.github.get_pr_comments(pr_number)
            effective_state = get_effective_review_state(
                reviews,
                self.state.get_allowlist(),
                pr_info.get("reviewDecision"),
                comments=comments
            )
        except GitHubAuthError:
            raise
        except Exception as e:
            logger.debug("Error checking effective review state for PR #%s: %s", pr_number, e)
            effective_state = "NEUTRAL"

        if effective_state == "APPROVED":
            logger.info(
                "PR #%s effective review state is APPROVED. Setting status to approved and ignoring stale events.",
                pr_number
            )
            self.state.mark_pr_status(pr_number, "approved")
            # Clear/mark any stale or same-cycle events as processed so they never wake the agent
            for ev in raw_events:
                ev_id = ev.get("id")
                if ev_id:
                    self.state.mark_event_processed(pr_number, ev_id)
            return

        if not all_events:
            return

        # ---------------- 5. Acquire Lock & Dispatch ----------------
        if not self.state.acquire_lock(pr_number):
            logger.warning("Failed to acquire lock for PR #%s. Restoring events to pending.", pr_number)
            self.state.restore_pending_events(pr_number, all_events)
            return

        if current_head_sha:
            self.state.update_pr_fields(pr_number, last_head_sha=current_head_sha)

        # Record events as in-flight BEFORE launch. They are NOT marked processed yet!
        self.state.set_in_flight_events(pr_number, all_events)

        run_id = self.state.start_new_run(pr_number)
        logger.info(
            "Waking Antigravity conversation %s for PR #%s (run %d) with %d in-flight event(s)...",
            conversation_id, pr_number, run_id, len(all_events)
        )
        try:
            success, out, active_pid = self.resumer.resume_conversation(
                conversation_id, pr_number, run_id=run_id
            )
        except AgentResumerError as e:
            success = False
            out = f"Missing resume capability: {e}"
            active_pid = None

        if not success:
            if "Missing resume capability" in out or "AgentResumerError" in out:
                logger.error(
                    "Missing Antigravity resume capability for PR #%s: %s. Transitioning to terminal 'error' state.",
                    pr_number, out
                )
                self.state.mark_pr_status(pr_number, "error")
            else:
                retry_cnt = self.state.increment_retry_count(pr_number)
                if retry_cnt >= MAX_AGENT_RETRIES:
                    logger.error(
                        "PR #%s reached maximum retries (%d) on launch failures. Transitioning to 'error' state.",
                        pr_number, MAX_AGENT_RETRIES
                    )
                    self.state.mark_pr_status(pr_number, "error")
                else:
                    logger.warning(
                        "Failed to launch agent for conversation %s (retry %d/%d): %s. Restoring events to pending.",
                        conversation_id, retry_cnt, MAX_AGENT_RETRIES, out
                    )
            self.state.restore_in_flight_to_pending(pr_number)
            self.state.release_lock(pr_number)
        else:
            logger.info("Agent successfully initiated for PR #%s (run %d, PID: %s).", pr_number, run_id, active_pid)
            if active_pid:
                self.state.update_pr_fields(pr_number, active_agent_pid=active_pid)

    def run_cycle(self) -> None:
        """Run a single polling cycle across all active registered PRs."""
        self.init_allowlist_if_empty()
        self.reconcile_registrations()
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
                except GitHubAuthError as e:
                    logger.error(
                        "FATAL: GitHub authentication expired or invalid during polling: %s. "
                        "Halting review watcher.", e
                    )
                    prs = self.state.get_registered_prs()
                    for pr_str in prs:
                        try:
                            num = int(pr_str)
                            if self.state.get_pr_status(num) != "closed":
                                self.state.mark_pr_status(num, "error")
                                self.state.restore_in_flight_to_pending(num)
                                self.state.release_lock(num)
                        except Exception:
                            pass
                    self._running = False
                    break
                except GitHubError as e:
                    logger.warning("GitHub CLI error encountered: %s. Backing off for %ss.", e, backoff)
                    if self.run_once:
                        break
                    time.sleep(backoff)
                    backoff = min(backoff * DEFAULT_BACKOFF_FACTOR, DEFAULT_BACKOFF_MAX_SECONDS)
                    continue
                except Exception as e:
                    logger.exception("Unexpected error during watcher cycle: %s", e)

                if self.run_once:
                    break

                time.sleep(self.poll_interval)
        finally:
            self._running = False
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

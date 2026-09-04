"""
tests/unit/test_review_loop.py - Comprehensive unit, regression, and integration
tests for the autonomous PR review feedback loop.

Tests cover:
  - StateManager: persistence, deduplication, atomic lock acquisition, in-flight events,
    thread states, idempotent hook registration, inter-process safety
  - AgentResumer: backend detection (PureWindowsPath portability), prompt contract, retry,
    Popen output logging
  - ReviewWatcher: identity model, bot allowlist precedence, effective review state (APPROVE),
    delayed agy failure recovery, event deduplication across cycles, terminal failure states
    (max retries and DESIGN DECISION REQUIRED)
  - Hook Registration: PostToolUse and Stop hook contracts
  - Full Lifecycle Integration: hook → watcher visibility → review → failed dispatch →
    retry → successful dispatch → delayed failure handling → new head → APPROVE → silence
"""
import io
import json
import os
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from tools.review_loop.agent_resumer import (
    BACKEND_AGY,
    AgentResumer,
    AgentResumerError,
    detect_backend_from_path,
)
from tools.review_loop.config import AGENT_COMMENT_MARKER, DESIGN_DECISION_MARKER, REVIEW_LOOP_DIR
from tools.review_loop.github_client import GitHubAuthError, GitHubClient, GitHubError, is_auth_error_message
from tools.review_loop.install import install_linux
from tools.review_loop.register import register_from_hook
from tools.review_loop.state_manager import StateManager
from tools.review_loop.watcher import (
    READY_VERDICT_MARKERS,
    ReviewWatcher,
    get_effective_review_state,
    is_event_allowed,
    is_ready_verdict,
)


# ===================================================================
#  StateManager
# ===================================================================

class TestStateManager(unittest.TestCase):
    def setUp(self):
        self.test_dir = Path(tempfile.mkdtemp())
        self.state_file = self.test_dir / "state.json"
        self.state_mgr = StateManager(state_file=self.state_file)

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_register_and_persistence(self):
        """Verify PR registration survives reload / watcher restart."""
        self.state_mgr.register_pr(pr_number=42, conversation_id="conv-123", branch="feat/test")
        self.state_mgr.add_to_allowlist("alex123321-maker")

        reloaded = StateManager(state_file=self.state_file)
        pr = reloaded.get_pr(42)
        self.assertIsNotNone(pr)
        self.assertEqual(pr["conversation_id"], "conv-123")
        self.assertEqual(pr["branch"], "feat/test")
        self.assertEqual(pr["status"], "watching")
        self.assertTrue(reloaded.is_user_allowed("alex123321-maker"))

    def test_register_pr_is_idempotent(self):
        """
        BLOCKER 1 Regression: PostToolUse fires during an active agent run.
        register_pr() MUST preserve status, active_agent_pid, processing_started_at,
        and in_flight_events for an already registered PR.
        """
        self.state_mgr.register_pr(pr_number=88, conversation_id="conv-initial", branch="feat/88")
        self.state_mgr.update_pr_fields(
            88,
            status="processing",
            active_agent_pid=6789,
            processing_started_at=100.0,
            in_flight_events=[{"id": "ev1"}],
        )

        # Re-register with the same or updated conversation/branch
        self.state_mgr.register_pr(pr_number=88, conversation_id="conv-new", branch="feat/88")

        pr = self.state_mgr.get_pr(88)
        self.assertEqual(pr["conversation_id"], "conv-new")
        self.assertEqual(pr["status"], "processing")
        self.assertEqual(pr["active_agent_pid"], 6789)
        self.assertEqual(pr["processing_started_at"], 100.0)
        self.assertEqual(len(pr["in_flight_events"]), 1)

    def test_event_deduplication(self):
        """Verify events are marked as processed and duplicates detected."""
        self.state_mgr.register_pr(pr_number=10, conversation_id="c1", branch="b1")
        self.assertFalse(self.state_mgr.is_event_processed(10, "rev_1"))

        self.state_mgr.mark_event_processed(10, "rev_1")
        self.assertTrue(self.state_mgr.is_event_processed(10, "rev_1"))

        # Second mark should not duplicate
        self.state_mgr.mark_event_processed(10, "rev_1")
        pr = self.state_mgr.get_pr(10)
        self.assertEqual(pr["processed_event_ids"].count("rev_1"), 1)

    def test_is_event_known(self):
        """Verify is_event_known checks processed, in-flight, and pending events."""
        self.state_mgr.register_pr(pr_number=12, conversation_id="c12", branch="b12")
        self.assertFalse(self.state_mgr.is_event_known(12, "ev_any"))

        # In-flight
        self.state_mgr.set_in_flight_events(12, [{"id": "ev_inflight"}])
        self.assertTrue(self.state_mgr.is_event_known(12, "ev_inflight"))

        # Pending
        self.state_mgr.queue_pending_event(12, {"id": "ev_pending"})
        self.assertTrue(self.state_mgr.is_event_known(12, "ev_pending"))

        # Processed
        self.state_mgr.mark_event_processed(12, "ev_processed")
        self.assertTrue(self.state_mgr.is_event_known(12, "ev_processed"))

    def test_allowlist_case_insensitive(self):
        """Verify allowlist enforcement is case-insensitive."""
        self.state_mgr.add_to_allowlist("Alex123321-Maker")
        self.assertTrue(self.state_mgr.is_user_allowed("alex123321-maker"))
        self.assertFalse(self.state_mgr.is_user_allowed("UntrustedUser"))
        self.assertFalse(self.state_mgr.is_user_allowed(""))

    def test_concurrency_lock_and_lease(self):
        """Verify lock prevents parallel runs; lease timeout reclaims expired lock."""
        self.state_mgr.register_pr(pr_number=5, conversation_id="c", branch="b")
        self.assertFalse(self.state_mgr.is_processing(5))

        self.assertTrue(self.state_mgr.acquire_lock(5, lease_seconds=10.0))
        self.assertTrue(self.state_mgr.is_processing(5))
        self.assertFalse(self.state_mgr.acquire_lock(5, lease_seconds=10.0))

        # Simulate expired lease without alive process — directly mutate for test
        with self.state_mgr._transact():
            self.state_mgr.state["prs"]["5"]["processing_started_at"] -= 20.0

        self.assertFalse(self.state_mgr.is_processing(5, lease_seconds=10.0))
        self.assertTrue(self.state_mgr.acquire_lock(5, lease_seconds=10.0))

        self.state_mgr.release_lock(5)
        self.assertFalse(self.state_mgr.is_processing(5))

    def test_atomic_acquire_lock_concurrency(self):
        """
        Two independent StateManager instances simulate
        two watcher processes racing to acquire the lock on an idle PR.
        Exactly one must succeed; the second must return False.
        """
        mgr1 = StateManager(state_file=self.state_file)
        mgr2 = StateManager(state_file=self.state_file)

        mgr1.register_pr(pr_number=100, conversation_id="c100", branch="b100")

        res1 = mgr1.acquire_lock(100)
        res2 = mgr2.acquire_lock(100)

        self.assertTrue(res1)
        self.assertFalse(res2)

        # After releasing lock, second manager can acquire it
        mgr1.release_lock(100)
        self.assertTrue(mgr2.acquire_lock(100))
        self.assertFalse(mgr1.acquire_lock(100))

    def test_in_flight_events_lifecycle(self):
        """Verify in-flight events are saved, finalized on success, or restored on failure."""
        self.state_mgr.register_pr(pr_number=200, conversation_id="c200", branch="b200")
        evs = [{"id": "ev1", "type": "comment"}, {"id": "ev2", "type": "review"}]

        self.state_mgr.set_in_flight_events(200, evs)
        self.assertEqual(len(self.state_mgr.get_in_flight_events(200)), 2)

        # Failure: restore to pending
        self.state_mgr.restore_in_flight_to_pending(200)
        self.assertEqual(len(self.state_mgr.get_in_flight_events(200)), 0)
        pending = self.state_mgr.pop_pending_events(200)
        self.assertEqual(len(pending), 2)
        self.assertEqual(pending[0]["id"], "ev1")

        # Success: finalize to processed
        self.state_mgr.set_in_flight_events(200, evs)
        self.state_mgr.finalize_in_flight_events(200)
        self.assertEqual(len(self.state_mgr.get_in_flight_events(200)), 0)
        self.assertTrue(self.state_mgr.is_event_processed(200, "ev1"))
        self.assertTrue(self.state_mgr.is_event_processed(200, "ev2"))

    def test_retry_count_helpers(self):
        """Verify retry count increment and reset."""
        self.state_mgr.register_pr(pr_number=300, conversation_id="c300", branch="b300")
        self.assertEqual(self.state_mgr.increment_retry_count(300), 1)
        self.assertEqual(self.state_mgr.increment_retry_count(300), 2)
        self.state_mgr.reset_retry_count(300)
        pr = self.state_mgr.get_pr(300)
        self.assertEqual(pr["retry_count"], 0)


# ===================================================================
#  AgentResumer
# ===================================================================

class TestAgentResumer(unittest.TestCase):
    def test_build_prompt_contains_marker(self):
        """Resume prompt MUST contain AGENT_COMMENT_MARKER verbatim."""
        resumer = AgentResumer(agentapi_cmd=["agy"], backend_type=BACKEND_AGY)
        prompt = resumer.build_prompt(pr_number=123)
        self.assertIn(AGENT_COMMENT_MARKER, prompt)
        self.assertIn("PR #123", prompt)
        self.assertIn("DESIGN DECISION REQUIRED", prompt)
        self.assertIn("Do not merge the PR", prompt)

    def test_detect_backend_windows_path_on_any_os(self):
        """Windows-style paths must be correctly identified on any host OS."""
        self.assertEqual(
            detect_backend_from_path(r"D:\Tools\agy\bin\agy.exe"),
            BACKEND_AGY,
        )
        self.assertEqual(
            detect_backend_from_path(r"C:\Users\user\AppData\Local\agy\bin\agy.exe"),
            BACKEND_AGY,
        )
        self.assertEqual(
            detect_backend_from_path("/usr/local/bin/agy"),
            BACKEND_AGY,
        )

    @patch("subprocess.Popen")
    @patch("time.sleep")
    def test_agy_backend_uses_popen_and_returns_pid(self, mock_sleep, mock_popen):
        """agy backend must use Popen and return the launched PID."""
        mock_proc = MagicMock()
        mock_proc.pid = 12345
        mock_proc.poll.return_value = None  # still running
        mock_popen.return_value = mock_proc

        resumer = AgentResumer(
            agentapi_cmd=[r"D:\Tools\agy\bin\agy.exe"],
            backend_type=BACKEND_AGY,
        )
        success, out, pid = resumer.resume_conversation("test-conv", pr_number=4)

        self.assertTrue(success)
        self.assertEqual(pid, 12345)
        self.assertIn("PID", out)

        call_args = mock_popen.call_args
        cmd = call_args[0][0]
        self.assertIn("--conversation", cmd)
        self.assertIn("test-conv", cmd)
        self.assertIn("--print-timeout", cmd)

    @patch("subprocess.Popen")
    @patch("time.sleep")
    def test_agy_instant_crash_triggers_retry(self, mock_sleep, mock_popen):
        """agy process that exits immediately should trigger retry."""
        mock_proc = MagicMock()
        mock_proc.pid = 111
        mock_proc.poll.return_value = 1  # exited immediately
        mock_popen.return_value = mock_proc

        resumer = AgentResumer(
            agentapi_cmd=["agy"], backend_type=BACKEND_AGY
        )
        success, out, pid = resumer.resume_conversation(
            "conv", pr_number=1, max_retries=2
        )
        self.assertFalse(success)
        self.assertIsNone(pid)
        self.assertEqual(mock_popen.call_count, 2)

    def test_resume_conversation_missing_capability_returns_clean_error(self):
        """When _discover_command raises AgentResumerError, resume_conversation returns (False, msg, None)."""
        resumer = AgentResumer()
        with patch.object(resumer, "_discover_command", side_effect=AgentResumerError("No CLI found")):
            success, out, pid = resumer.resume_conversation("conv-x", 123)
            self.assertFalse(success)
            self.assertIn("Missing resume capability", out)
            self.assertIsNone(pid)


# ===================================================================
#  ReviewWatcher
# ===================================================================

class TestReviewWatcher(unittest.TestCase):
    def setUp(self):
        self.test_dir = Path(tempfile.mkdtemp())
        self.state_file = self.test_dir / "state.json"
        self.state_mgr = StateManager(state_file=self.state_file)
        self.state_mgr.add_to_allowlist("alex123321-maker")

        self.mock_github = MagicMock(spec=GitHubClient)
        self.mock_resumer = MagicMock(spec=AgentResumer)
        self.mock_resumer.resume_conversation.return_value = (True, "Dispatched", 1234)

        self.watcher = ReviewWatcher(
            github_client=self.mock_github,
            state_manager=self.state_mgr,
            agent_resumer=self.mock_resumer,
            run_once=True,
        )

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def _setup_pr_mocks(self, pr_number, reviews=None, comments=None, inline=None, threads=None, head="sha_x", review_decision=None):
        self.mock_github.get_pr_details.return_value = {
            "number": pr_number,
            "state": "OPEN",
            "headRefOid": head,
            "author": {"login": "alex123321-maker"},
            "reviewDecision": review_decision,
        }
        self.mock_github.get_pr_reviews.return_value = reviews or []
        self.mock_github.get_pr_comments.return_value = comments or []
        self.mock_github.get_pr_inline_comments.return_value = inline or []
        self.mock_github.get_pr_review_threads.return_value = threads or []

    def test_in_flight_event_not_rediscovered_during_active_processing(self):
        """
        BLOCKER 2 Regression: Original review remains visible on GitHub throughout
        the entire agent run. It MUST NOT be re-queued in pending_events,
        and exactly one agent wake must occur.
        """
        self.state_mgr.register_pr(pr_number=70, conversation_id="c70", branch="b70")
        self.state_mgr.update_pr_fields(70, last_head_sha="sha_base")

        review_req = {
            "id": "rev_must_not_duplicate",
            "state": "REQUEST_CHANGES",
            "author": {"login": "alex123321-maker"},
            "body": "Fix this bug once",
        }

        # Cycle 1: Review discovered, agent launched with PID 8888
        self._setup_pr_mocks(70, reviews=[review_req], head="sha_base")
        self.mock_resumer.resume_conversation.return_value = (True, "launched", 8888)

        self.watcher.run_cycle()

        self.assertEqual(self.mock_resumer.resume_conversation.call_count, 1)
        pr = self.state_mgr.get_pr(70)
        self.assertEqual(len(pr["in_flight_events"]), 1)
        self.assertEqual(len(pr["pending_events"]), 0)

        # Cycle 2: Agent is actively running (PID 8888 alive). GitHub review is STILL returned.
        with patch("tools.review_loop.watcher.is_pid_alive", return_value=True):
            self.watcher.run_cycle()

        # Event must NOT be re-added to pending!
        pr = self.state_mgr.get_pr(70)
        self.assertEqual(len(pr["pending_events"]), 0)
        self.assertEqual(self.mock_resumer.resume_conversation.call_count, 1)

        # Cycle 3: Agent completes and pushes new head SHA (sha_new)
        self.mock_github.get_pr_details.return_value["headRefOid"] = "sha_new"

        with patch("tools.review_loop.watcher.is_pid_alive", return_value=False):
            self.watcher.run_cycle()

        pr = self.state_mgr.get_pr(70)
        self.assertTrue(self.state_mgr.is_event_processed(70, "rev_must_not_duplicate"))
        self.assertEqual(len(pr["pending_events"]), 0)
        self.assertEqual(len(pr["in_flight_events"]), 0)

        # Cycle 4: Idle cycle — review is already finalized, no new wake occurs!
        self.watcher.run_cycle()
        self.assertEqual(self.mock_resumer.resume_conversation.call_count, 1)

    def test_max_retries_exceeded_transitions_to_error(self):
        """
        BLOCKER 3 Regression: 3 repeated failures transition PR to 'error' state
        and halt the feedback loop without infinite retry.
        """
        self.state_mgr.register_pr(pr_number=80, conversation_id="c80", branch="b80")
        self.state_mgr.update_pr_fields(80, last_head_sha="sha_constant")

        self._setup_pr_mocks(80, reviews=[
            {
                "id": "rev_unrecoverable",
                "state": "REQUEST_CHANGES",
                "author": {"login": "alex123321-maker"},
                "body": "Persistent issue",
            }
        ], head="sha_constant")

        # Attempt 1
        self.mock_resumer.resume_conversation.return_value = (True, "launched", 101)
        self.watcher.run_cycle()
        with patch("tools.review_loop.watcher.is_pid_alive", return_value=False):
            self.watcher.run_cycle()  # Failure 1

        # Attempt 2
        self.mock_resumer.resume_conversation.return_value = (True, "launched", 102)
        self.watcher.run_cycle()
        with patch("tools.review_loop.watcher.is_pid_alive", return_value=False):
            self.watcher.run_cycle()  # Failure 2

        # Attempt 3
        self.mock_resumer.resume_conversation.return_value = (True, "launched", 103)
        self.watcher.run_cycle()
        with patch("tools.review_loop.watcher.is_pid_alive", return_value=False):
            self.watcher.run_cycle()  # Failure 3 -> should hit MAX_AGENT_RETRIES

        pr = self.state_mgr.get_pr(80)
        self.assertEqual(pr["status"], "error")
        self.assertEqual(pr["retry_count"], 3)
        # Work is preserved in pending queue
        self.assertEqual(len(pr["pending_events"]), 1)

        # Cycle after error: must NOT dispatch again!
        self.mock_resumer.reset_mock()
        self.watcher.run_cycle()
        self.assertFalse(self.mock_resumer.resume_conversation.called)

    def test_repeated_launch_failures_transition_to_error(self):
        """
        BLOCKER 2: If resume_conversation fails repeatedly (returns False),
        watcher must increment retry_count and stop at MAX_AGENT_RETRIES.
        """
        self.state_mgr.register_pr(pr_number=85, conversation_id="c85", branch="b85")
        self._setup_pr_mocks(85, reviews=[
            {
                "id": "rev_bad_launch",
                "state": "REQUEST_CHANGES",
                "author": {"login": "alex123321-maker"},
                "body": "Launch will fail",
            }
        ], head="sha_85")

        self.mock_resumer.resume_conversation.return_value = (False, "CLI crashed", None)

        # Attempt 1
        self.watcher.run_cycle()
        pr = self.state_mgr.get_pr(85)
        self.assertEqual(pr["retry_count"], 1)

        # Attempt 2
        self.watcher.run_cycle()
        pr = self.state_mgr.get_pr(85)
        self.assertEqual(pr["retry_count"], 2)

        # Attempt 3 -> transitions to error
        self.watcher.run_cycle()
        pr = self.state_mgr.get_pr(85)
        self.assertEqual(pr["status"], "error")
        self.assertEqual(pr["retry_count"], 3)
        self.assertEqual(len(pr["pending_events"]), 1)

        # Subsequent cycle: does not launch again
        self.mock_resumer.reset_mock()
        self.watcher.run_cycle()
        self.assertFalse(self.mock_resumer.resume_conversation.called)

    def test_pr_closed_or_merged_transitions_to_closed_status(self):
        """
        BLOCKER 1: When an actively watched PR becomes CLOSED or MERGED,
        watcher immediately sets status to 'closed' and halts processing.
        """
        self.state_mgr.register_pr(pr_number=86, conversation_id="c86", branch="b86")
        self._setup_pr_mocks(86, head="sha_86")
        self.mock_github.get_pr_details.return_value["state"] = "CLOSED"

        self.watcher.run_cycle()

        pr = self.state_mgr.get_pr(86)
        self.assertEqual(pr["status"], "closed")
        self.assertFalse(self.mock_resumer.resume_conversation.called)

        # Same for MERGED
        self.state_mgr.register_pr(pr_number=87, conversation_id="c87", branch="b87")
        self._setup_pr_mocks(87, head="sha_87")
        self.mock_github.get_pr_details.return_value["state"] = "MERGED"

        self.watcher.run_cycle()

        pr2 = self.state_mgr.get_pr(87)
        self.assertEqual(pr2["status"], "closed")
        self.assertFalse(self.mock_resumer.resume_conversation.called)

    def test_design_decision_required_halts_loop(self):
        """
        BLOCKER 3 Regression: If agent log contains DESIGN DECISION REQUIRED,
        PR transitions to 'awaiting_design_decision' and stops without retrying.
        """
        self.state_mgr.register_pr(pr_number=90, conversation_id="c90", branch="b90")
        self.state_mgr.update_pr_fields(90, last_head_sha="sha_90")

        self._setup_pr_mocks(90, reviews=[
            {
                "id": "rev_design",
                "state": "REQUEST_CHANGES",
                "author": {"login": "alex123321-maker"},
                "body": "How should health regen scale?",
            }
        ], head="sha_90")

        self.mock_resumer.resume_conversation.return_value = (True, "launched", 404)
        self.watcher.run_cycle()

        # Simulate agent writing DESIGN DECISION REQUIRED to run-scoped log file
        run_id = self.state_mgr.get_current_run_id(90)
        log_file = REVIEW_LOOP_DIR / f"agy_pr_90_run_{run_id}.log"
        log_file.parent.mkdir(parents=True, exist_ok=True)
        log_file.write_text(f"Analyzed request.\n{DESIGN_DECISION_MARKER}: Missing formula.\n", encoding="utf-8")

        # Agent exits without pushing
        with patch("tools.review_loop.watcher.is_pid_alive", return_value=False):
            self.watcher.run_cycle()

        pr = self.state_mgr.get_pr(90)
        self.assertEqual(pr["status"], "awaiting_design_decision")
        # Work is preserved in pending_events
        self.assertEqual(len(pr["pending_events"]), 1)

        # Subsequent cycle: must NOT retry!
        self.mock_resumer.reset_mock()
        self.watcher.run_cycle()
        self.assertFalse(self.mock_resumer.resume_conversation.called)

        if log_file.exists():
            log_file.unlink()

    def test_design_decision_run_scope_isolation(self):
        """
        BLOCKER 3: Run A contains design marker -> reactivate -> Run B fails without
        marker -> Run B must follow failure/retry semantics, NOT awaiting_design_decision.
        """
        self.state_mgr.register_pr(pr_number=95, conversation_id="c95", branch="b95")
        self.state_mgr.update_pr_fields(95, last_head_sha="sha_95")

        self._setup_pr_mocks(95, reviews=[
            {
                "id": "rev_run_scope",
                "state": "REQUEST_CHANGES",
                "author": {"login": "alex123321-maker"},
                "body": "Need design decision then normal bug",
            }
        ], head="sha_95")

        # Run 1 dispatches
        self.mock_resumer.resume_conversation.return_value = (True, "launched", 501)
        self.watcher.run_cycle()

        # Run 1 writes DESIGN DECISION REQUIRED
        run_1_id = self.state_mgr.get_current_run_id(95)
        log_file_1 = REVIEW_LOOP_DIR / f"agy_pr_95_run_{run_1_id}.log"
        log_file_1.parent.mkdir(parents=True, exist_ok=True)
        log_file_1.write_text(f"{DESIGN_DECISION_MARKER}: Which color?\n", encoding="utf-8")

        with patch("tools.review_loop.watcher.is_pid_alive", return_value=False):
            self.watcher.run_cycle()

        pr = self.state_mgr.get_pr(95)
        self.assertEqual(pr["status"], "awaiting_design_decision")

        # User provides decision and reactivates PR
        self.state_mgr.reactivate_pr(95)
        self.assertEqual(self.state_mgr.get_pr(95)["status"], "watching")

        # Run 2 dispatches (new run_id generated!)
        self.mock_resumer.resume_conversation.return_value = (True, "launched", 502)
        self.watcher.run_cycle()

        run_2_id = self.state_mgr.get_current_run_id(95)
        self.assertNotEqual(run_1_id, run_2_id)

        # Run 2 log does NOT have design decision marker (it crashes cleanly)
        log_file_2 = REVIEW_LOOP_DIR / f"agy_pr_95_run_{run_2_id}.log"
        log_file_2.write_text("Fatal error: syntax error in script.\n", encoding="utf-8")

        with patch("tools.review_loop.watcher.is_pid_alive", return_value=False):
            self.watcher.run_cycle()

        # Run 2 MUST be classified as failure/retry (status watching, retry 1), NOT awaiting_design_decision!
        pr2 = self.state_mgr.get_pr(95)
        self.assertEqual(pr2["status"], "watching")
        self.assertEqual(pr2["retry_count"], 1)

        # Cleanup
        for lf in (log_file_1, log_file_2):
            if lf.exists():
                lf.unlink()

    def test_error_state_preserves_work_and_reactivates_cleanly(self):
        """
        IMPORTANT: When PR reaches 'error', work items are preserved in pending_events,
        and reactivate_pr allows immediate retry on the next cycle.
        """
        self.state_mgr.register_pr(pr_number=98, conversation_id="c98", branch="b98")
        self.state_mgr.set_in_flight_events(98, [{"id": "ev_important"}])
        self.state_mgr.mark_pr_status(98, "error")
        self.state_mgr.restore_in_flight_to_pending(98)

        pr = self.state_mgr.get_pr(98)
        self.assertEqual(len(pr["pending_events"]), 1)
        self.assertEqual(pr["status"], "error")

        # Reactivate
        self.state_mgr.reactivate_pr(98)
        pr = self.state_mgr.get_pr(98)
        self.assertEqual(pr["status"], "watching")
        self.assertEqual(pr["retry_count"], 0)
        self.assertEqual(len(pr["pending_events"]), 1)

    def test_approved_then_request_changes_wakes_agent(self):
        """Older APPROVED followed by newer REQUEST_CHANGES MUST wake the agent."""
        self.state_mgr.register_pr(pr_number=15, conversation_id="c15", branch="b15")
        self._setup_pr_mocks(15, reviews=[
            {
                "id": "rev_old_app",
                "state": "APPROVED",
                "author": {"login": "alex123321-maker"},
                "body": "Looked good earlier",
            },
            {
                "id": "rev_new_req",
                "state": "REQUEST_CHANGES",
                "author": {"login": "alex123321-maker"},
                "body": "Found a critical bug, please fix!",
            },
        ], head="sha15", review_decision="CHANGES_REQUESTED")

        self.watcher.run_cycle()

        self.assertTrue(self.mock_resumer.resume_conversation.called)
        pr = self.state_mgr.get_pr(15)
        self.assertNotEqual(pr["status"], "approved")
        self.assertEqual(len(pr["in_flight_events"]), 1)
        self.assertEqual(pr["in_flight_events"][0]["id"], "rev_new_req")

    def test_allowlisted_bot_is_accepted(self):
        """An explicitly allowlisted bot account MUST be processed."""
        self.state_mgr.add_to_allowlist("code-review-bot[bot]")

        allowed = is_event_allowed("code-review-bot[bot]", "Please fix indentation", self.state_mgr)
        self.assertTrue(allowed)

        ignored = is_event_allowed("unauthorized-bot[bot]", "Noise", self.state_mgr)
        self.assertFalse(ignored)

        agent_marker = is_event_allowed("code-review-bot[bot]", f"Done {AGENT_COMMENT_MARKER}", self.state_mgr)
        self.assertFalse(agent_marker)

    def test_two_watchers_interleaving_during_startup(self):
        """
        BLOCKER 1: When Watcher 1 is starting an agent (status=processing, pid=None,
        elapsed < grace period), Watcher 2 must NOT treat it as exited, must NOT
        clear lock, and must NOT restore in-flight events.
        """
        self.state_mgr.register_pr(pr_number=101, conversation_id="c101", branch="b101")
        self._setup_pr_mocks(101, head="sha101")
        # Watcher 1 acquires lock and sets in-flight
        self.state_mgr.acquire_lock(101)
        self.state_mgr.set_in_flight_events(101, [{"id": "ev_startup"}])

        # Watcher 2 simulates running process_registered_pr
        watcher2 = ReviewWatcher(
            state_manager=self.state_mgr,
            github_client=self.mock_github,
            agent_resumer=self.mock_resumer,
        )
        watcher2.process_registered_pr(101)

        pr = self.state_mgr.get_pr(101)
        # Lock must be intact and in processing status
        self.assertEqual(pr["status"], "processing")
        self.assertEqual(len(pr["in_flight_events"]), 1)
        self.assertEqual(len(pr["pending_events"]), 0)
        self.assertFalse(self.mock_resumer.resume_conversation.called)

    def test_process_exit_after_lease_expiry_with_changed_head(self):
        """
        BLOCKER 1: When process exits after lock lease expiry and head HAS changed,
        watcher must finalize in-flight events and release lock cleanly without stranding work.
        """
        import time
        self.state_mgr.register_pr(pr_number=102, conversation_id="c102", branch="b102")
        self.state_mgr.update_pr_fields(
            102,
            status="processing",
            processing_started_at=time.time() - 2500.0,  # Expired lease (> 1800s)
            active_agent_pid=99999,
            last_head_sha="sha_old",
            in_flight_events=[{"id": "ev_lease_change"}],
        )
        self._setup_pr_mocks(102, head="sha_new")

        with patch("tools.review_loop.watcher.is_pid_alive", return_value=False):
            self.watcher.process_registered_pr(102)

        pr = self.state_mgr.get_pr(102)
        self.assertEqual(pr["status"], "watching")
        self.assertIn("ev_lease_change", pr["processed_event_ids"])
        self.assertEqual(len(pr["in_flight_events"]), 0)
        self.assertEqual(pr["last_head_sha"], "sha_new")

    def test_process_exit_after_lease_expiry_with_unchanged_head(self):
        """
        BLOCKER 1: When process exits after lock lease expiry and head is UNCHANGED,
        watcher must restore in-flight events to pending and release lock cleanly without stranding work.
        """
        import time
        self.state_mgr.register_pr(pr_number=103, conversation_id="c103", branch="b103")
        self.state_mgr.update_pr_fields(
            103,
            status="processing",
            processing_started_at=time.time() - 2500.0,  # Expired lease (> 1800s)
            active_agent_pid=99999,
            last_head_sha="sha_same",
            in_flight_events=[{"id": "ev_lease_no_change"}],
        )
        self._setup_pr_mocks(103, head="sha_same")

        with patch("tools.review_loop.watcher.is_pid_alive", return_value=False):
            self.watcher.process_registered_pr(103)

        pr = self.state_mgr.get_pr(103)
        self.assertEqual(pr["status"], "watching")
        self.assertEqual(len(pr["in_flight_events"]), 0)
        self.assertEqual(len(pr["pending_events"]), 1)
        self.assertEqual(pr["pending_events"][0]["id"], "ev_lease_no_change")
        self.assertEqual(pr["retry_count"], 1)

    def test_missing_agy_capability_transitions_to_terminal_error(self):
        """
        BLOCKER 2: When Antigravity resume capability is missing (AgentResumerError),
        watcher must catch/classify it as an unrecoverable infrastructure failure,
        immediately transition PR to 'error', restore events to pending, and halt retries.
        """
        self.state_mgr.register_pr(pr_number=104, conversation_id="c104", branch="b104")
        self._setup_pr_mocks(104, reviews=[
            {
                "id": "rev_missing_agy",
                "state": "REQUEST_CHANGES",
                "author": {"login": "alex123321-maker"},
                "body": "Need changes",
            }
        ], head="sha104")

        self.mock_resumer.resume_conversation.side_effect = AgentResumerError(
            "Neither agy CLI nor agentapi found. Please install agy or configure --agy-path."
        )

        # Run cycle
        self.watcher.run_cycle()

        pr = self.state_mgr.get_pr(104)
        self.assertEqual(pr["status"], "error")
        # Work is preserved in pending_events
        self.assertEqual(len(pr["pending_events"]), 1)
        self.assertEqual(pr["pending_events"][0]["id"], "rev_missing_agy")
        self.assertEqual(len(pr["in_flight_events"]), 0)

        # Subsequent cycle: does NOT dispatch again
        self.mock_resumer.reset_mock()
        self.watcher.run_cycle()
        self.assertFalse(self.mock_resumer.resume_conversation.called)

    def test_reopen_thread_multiple_cycles_produces_distinct_wakes(self):
        """
        BLOCKER 3: resolve -> reopen -> process -> resolve -> reopen must produce a second wake!
        Ensures each reopen transition gets a unique transition ID so is_event_known does not suppress it.
        """
        self.state_mgr.register_pr(pr_number=105, conversation_id="c105", branch="b105")
        self.state_mgr.update_pr_fields(105, last_head_sha="sha_head_1")
        self.mock_resumer.resume_conversation.return_value = (True, "launched", 601)

        # 1. Initially thread is resolved
        self._setup_pr_mocks(105, head="sha_head_1")
        self.mock_github.get_pr_review_threads.return_value = [
            {"id": "th_toggle", "isResolved": True, "comments": {"nodes": []}}
        ]
        self.watcher.run_cycle()
        self.assertEqual(self.state_mgr.get_thread_is_resolved(105, "th_toggle"), True)
        self.assertFalse(self.mock_resumer.resume_conversation.called)

        # 2. Thread reopened -> Wake #1!
        self.mock_github.get_pr_review_threads.return_value = [
            {"id": "th_toggle", "isResolved": False, "comments": {"nodes": []}}
        ]
        self.watcher.run_cycle()
        self.assertEqual(self.mock_resumer.resume_conversation.call_count, 1)

        # Agent finishes turn and pushes new commit
        self.mock_github.get_pr_details.return_value["headRefOid"] = "sha_head_2"
        with patch("tools.review_loop.watcher.is_pid_alive", return_value=False):
            self.watcher.run_cycle()

        pr = self.state_mgr.get_pr(105)
        self.assertEqual(pr["status"], "watching")
        self.assertIn("reopen_th_toggle_v1", pr["processed_event_ids"])

        # 3. Thread resolved again
        self.mock_resumer.reset_mock()
        self.mock_github.get_pr_details.return_value["headRefOid"] = "sha_head_2"
        self.mock_github.get_pr_review_threads.return_value = [
            {"id": "th_toggle", "isResolved": True, "comments": {"nodes": []}}
        ]
        self.watcher.run_cycle()
        self.assertEqual(self.state_mgr.get_thread_is_resolved(105, "th_toggle"), True)
        self.assertFalse(self.mock_resumer.resume_conversation.called)

        # 4. Thread reopened a second time -> Wake #2!
        self.mock_resumer.resume_conversation.return_value = (True, "launched", 602)
        self.mock_github.get_pr_review_threads.return_value = [
            {"id": "th_toggle", "isResolved": False, "comments": {"nodes": []}}
        ]
        self.watcher.run_cycle()
        self.assertEqual(self.mock_resumer.resume_conversation.call_count, 1)

        pr2 = self.state_mgr.get_pr(105)
        self.assertEqual(len(pr2["in_flight_events"]), 1)
        self.assertEqual(pr2["in_flight_events"][0]["id"], "reopen_th_toggle_v2")

    def test_request_changes_then_newer_approved_on_fresh_state_zero_wake(self):
        """
        BLOCKER 1: On fresh/restarted state, if an older REQUEST_CHANGES is present
        but the latest allowlisted review / reviewDecision is APPROVED,
        APPROVE must dominate, stale events are marked processed, and zero wakes occur.
        """
        self.state_mgr.register_pr(pr_number=110, conversation_id="c110", branch="b110")
        self._setup_pr_mocks(
            110,
            reviews=[
                {
                    "id": "rev_old_req",
                    "state": "REQUEST_CHANGES",
                    "author": {"login": "alex123321-maker"},
                    "body": "Old changes requested",
                },
                {
                    "id": "rev_new_app",
                    "state": "APPROVED",
                    "author": {"login": "alex123321-maker"},
                    "body": "Looks great now!",
                },
            ],
            head="sha110",
            review_decision="APPROVED",
        )

        self.watcher.run_cycle()

        self.assertFalse(self.mock_resumer.resume_conversation.called)
        pr = self.state_mgr.get_pr(110)
        self.assertEqual(pr["status"], "approved")
        self.assertEqual(len(pr["pending_events"]), 0)
        self.assertEqual(len(pr["in_flight_events"]), 0)
        self.assertTrue(self.state_mgr.is_event_processed(110, "rev_old_req"))

    def test_approved_with_same_cycle_comment_zero_wake(self):
        """
        BLOCKER 1: When reviewDecision is APPROVED and a new comment arrives in the same cycle,
        APPROVE must dominate, comment is marked processed, and zero wakes occur.
        """
        self.state_mgr.register_pr(pr_number=111, conversation_id="c111", branch="b111")
        self._setup_pr_mocks(
            111,
            reviews=[
                {
                    "id": "rev_app_only",
                    "state": "APPROVED",
                    "author": {"login": "alex123321-maker"},
                    "body": "Approved!",
                }
            ],
            comments=[
                {
                    "id": "c_same_cycle",
                    "author": {"login": "alex123321-maker"},
                    "body": "Nice work, merging soon",
                }
            ],
            head="sha111",
            review_decision="APPROVED",
        )

        self.watcher.run_cycle()

        self.assertFalse(self.mock_resumer.resume_conversation.called)
        pr = self.state_mgr.get_pr(111)
        self.assertEqual(pr["status"], "approved")
        self.assertEqual(len(pr["pending_events"]), 0)
        self.assertEqual(len(pr["in_flight_events"]), 0)
        self.assertTrue(self.state_mgr.is_event_processed(111, "c_same_cycle"))

    def test_atomic_thread_reopen_across_two_watchers_produces_single_wake(self):
        """
        BLOCKER 2: When two watcher instances / StateManager instances concurrently
        observe a resolved -> unresolved thread transition, the observe_thread_resolution
        transaction ensures exactly ONE watcher receives the reopen version,
        and exactly ONE synthetic event / wake is generated.
        """
        mgr1 = self.state_mgr
        mgr2 = StateManager(state_file=self.state_file)

        mgr1.register_pr(pr_number=112, conversation_id="c112", branch="b112")
        mgr1.set_thread_is_resolved(112, "th_atomic_1", True)

        v1 = mgr1.observe_thread_resolution(112, "th_atomic_1", False)
        v2 = mgr2.observe_thread_resolution(112, "th_atomic_1", False)

        results = [v for v in [v1, v2] if v is not None]
        self.assertEqual(len(results), 1)
        self.assertEqual(results[0], 1)

    def test_two_watchers_inspecting_reopened_thread_generate_single_event(self):
        """
        BLOCKER 2 (E2E): Two watchers checking the same reopened thread in the same cycle:
        Watcher 1 detects reopen_th_race_v1 and queues it;
        Watcher 2 sees thread already marked unresolved and emits ZERO events.
        """
        mgr1 = self.state_mgr
        mgr2 = StateManager(state_file=self.state_file)

        mgr1.register_pr(pr_number=113, conversation_id="c113", branch="b113")
        mgr1.set_thread_is_resolved(113, "th_race", True)

        mock_gh = MagicMock(spec=GitHubClient)
        mock_gh.get_pr_details.return_value = {
            "number": 113, "state": "OPEN", "headRefOid": "sha113",
            "author": {"login": "alex123321-maker"}, "reviewDecision": None,
        }
        mock_gh.get_pr_reviews.return_value = []
        mock_gh.get_pr_comments.return_value = []
        mock_gh.get_pr_inline_comments.return_value = []
        mock_gh.get_pr_review_threads.return_value = [
            {"id": "th_race", "isResolved": False, "comments": {"nodes": []}}
        ]

        w1 = ReviewWatcher(github_client=mock_gh, state_manager=mgr1, agent_resumer=self.mock_resumer)
        w2 = ReviewWatcher(github_client=mock_gh, state_manager=mgr2, agent_resumer=self.mock_resumer)

        evs1 = w1.check_pr_events(113, mock_gh.get_pr_details(113))
        evs2 = w2.check_pr_events(113, mock_gh.get_pr_details(113))

        self.assertEqual(len(evs1), 1)
        self.assertEqual(evs1[0]["id"], "reopen_th_race_v1")
        self.assertEqual(len(evs2), 0)


# ===================================================================
#  Hook Registration
# ===================================================================

class TestHookRegistration(unittest.TestCase):
    def test_from_hook_post_tool_use_output(self):
        """PostToolUse hook must output {} to stdout."""
        hook_payload = json.dumps({"conversationId": "hook-conv-999", "workspacePaths": ["/repo"]})
        stdout_capture = io.StringIO()

        with patch("sys.stdin", io.StringIO(hook_payload)), \
             patch("sys.stdout", stdout_capture), \
             patch("tools.review_loop.register.get_current_git_branch", return_value="feat/hook-test"), \
             patch("tools.review_loop.register.GitHubClient") as MockGH:
            MockGH.return_value.find_pr_for_branch.return_value = 99
            register_from_hook(is_stop=False)

        output = stdout_capture.getvalue().strip()
        self.assertEqual(output, "{}")

    def test_from_hook_stop_output_contract(self):
        """Stop hook must output {"decision": "stop"} to allow normal termination."""
        hook_payload = json.dumps({"conversationId": "conv-stop"})
        stdout_capture = io.StringIO()

        with patch("sys.stdin", io.StringIO(hook_payload)), \
             patch("sys.stdout", stdout_capture), \
             patch("tools.review_loop.register.get_current_git_branch", return_value="main"):
            register_from_hook(is_stop=True)

        output = json.loads(stdout_capture.getvalue().strip())
        self.assertEqual(output["decision"], "stop")

    def test_hook_registration_preserves_active_processing_lock(self):
        """
        BLOCKER 1: Verify PostToolUse hook call mid-flight does not destroy
        the active 'processing' lock or PID.
        """
        test_dir = Path(tempfile.mkdtemp())
        state_file = test_dir / "state.json"

        try:
            state_mgr = StateManager(state_file=state_file)
            state_mgr.register_pr(pr_number=45, conversation_id="conv-active", branch="feat/45")
            state_mgr.update_pr_fields(45, status="processing", active_agent_pid=3333, processing_started_at=200.0)

            hook_payload = json.dumps({"conversationId": "conv-active", "workspacePaths": ["/repo"]})

            with patch("sys.stdin", io.StringIO(hook_payload)), \
                 patch("sys.stdout", io.StringIO()), \
                 patch("tools.review_loop.register.get_current_git_branch", return_value="feat/45"), \
                 patch("tools.review_loop.register.GitHubClient") as MockGH, \
                 patch("tools.review_loop.register.StateManager", return_value=state_mgr):
                MockGH.return_value.find_pr_for_branch.return_value = 45
                register_from_hook(is_stop=False)

            pr = state_mgr.get_pr(45)
            self.assertEqual(pr["status"], "processing")
            self.assertEqual(pr["active_agent_pid"], 3333)
            self.assertEqual(pr["processing_started_at"], 200.0)
        finally:
            shutil.rmtree(test_dir, ignore_errors=True)


# ===================================================================
#  Installer
# ===================================================================

class TestInstaller(unittest.TestCase):
    @patch("subprocess.run")
    def test_linux_installer_failure_returns_false(self, mock_run):
        mock_run.return_value = MagicMock(returncode=1, stderr="Failed to reload", stdout="")
        res = install_linux()
        self.assertFalse(res)


# ===================================================================
#  Full Lifecycle Integration Test
# ===================================================================

class TestFullLifecycleIntegration(unittest.TestCase):
    """
    Deterministic end-to-end integration test exercising:
      hook registration → watcher visibility → owner review → delayed agy failure
      recovery → retry → successful turn with new head → APPROVE → no further wake
    """

    def test_complete_review_loop_lifecycle(self):
        test_dir = Path(tempfile.mkdtemp())
        state_file = test_dir / "state.json"

        try:
            # Step 1: Hook registers PR
            hook_state = StateManager(state_file=state_file)
            hook_state.add_to_allowlist("alex123321-maker")
            hook_state.register_pr(pr_number=50, conversation_id="conv-50", branch="feat/50")

            # Step 2: Watcher sees registration
            watcher_state = StateManager(state_file=state_file)
            prs = watcher_state.get_registered_prs()
            self.assertIn("50", prs)

            # Step 3: Setup watcher
            mock_github = MagicMock(spec=GitHubClient)
            mock_resumer = MagicMock(spec=AgentResumer)

            watcher = ReviewWatcher(
                github_client=mock_github,
                state_manager=watcher_state,
                agent_resumer=mock_resumer,
                run_once=True,
            )

            # Step 4: Owner posts REQUEST_CHANGES
            mock_github.get_pr_details.return_value = {
                "number": 50, "state": "OPEN", "headRefOid": "sha_v1",
                "author": {"login": "alex123321-maker"},
                "reviewDecision": "CHANGES_REQUESTED",
            }
            mock_github.get_pr_reviews.return_value = [
                {
                    "id": "rev_lifecycle_1",
                    "state": "REQUEST_CHANGES",
                    "author": {"login": "alex123321-maker"},
                    "body": "Fix the identity model",
                }
            ]
            mock_github.get_pr_comments.return_value = []
            mock_github.get_pr_inline_comments.return_value = []
            mock_github.get_pr_review_threads.return_value = []
            mock_github.get_repo_owner_and_name.return_value = ("alex123321-maker", "Cube-Siege")

            mock_resumer.resume_conversation.return_value = (True, "launched", 900)

            watcher.run_cycle()

            pr = watcher_state.get_pr(50)
            self.assertEqual(pr["status"], "processing")
            self.assertEqual(len(pr["in_flight_events"]), 1)

            # Step 5: Delayed failure: PID 900 exits without pushing
            with patch("tools.review_loop.watcher.is_pid_alive", return_value=False):
                watcher.run_cycle()

            pr = watcher_state.get_pr(50)
            self.assertEqual(len(pr["pending_events"]), 1)
            self.assertEqual(len(pr["in_flight_events"]), 0)
            self.assertFalse(watcher_state.is_event_processed(50, "rev_lifecycle_1"))

            # Step 6: Next cycle: retry dispatches pending event with PID 901
            mock_resumer.resume_conversation.return_value = (True, "launched", 901)
            watcher.run_cycle()

            pr = watcher_state.get_pr(50)
            self.assertEqual(pr["status"], "processing")
            self.assertEqual(len(pr["in_flight_events"]), 1)

            # Step 7: Agent pushes new head (sha_v2) and exits
            mock_github.get_pr_details.return_value["headRefOid"] = "sha_v2"

            with patch("tools.review_loop.watcher.is_pid_alive", return_value=False):
                watcher.run_cycle()

            pr = watcher_state.get_pr(50)
            self.assertTrue(watcher_state.is_event_processed(50, "rev_lifecycle_1"))
            self.assertEqual(pr["last_head_sha"], "sha_v2")
            self.assertEqual(pr["status"], "watching")

            # Step 8: APPROVE received
            mock_github.get_pr_details.return_value["reviewDecision"] = "APPROVED"
            mock_github.get_pr_reviews.return_value = [
                {
                    "id": "rev_approve_final",
                    "state": "APPROVED",
                    "author": {"login": "alex123321-maker"},
                    "body": "Ship it!",
                }
            ]
            mock_resumer.reset_mock()

            watcher.run_cycle()

            pr = watcher_state.get_pr(50)
            self.assertEqual(pr["status"], "approved")
            self.assertFalse(mock_resumer.resume_conversation.called)

            # Step 9: Subsequent comment on approved PR — NO wake
            mock_github.get_pr_reviews.return_value = []
            mock_github.get_pr_comments.return_value = [
                {
                    "id": "comment_after_approve",
                    "author": {"login": "alex123321-maker"},
                    "body": "Great work!",
                }
            ]

            watcher.run_cycle()

            self.assertFalse(mock_resumer.resume_conversation.called)

        finally:
            shutil.rmtree(test_dir, ignore_errors=True)


# ===================================================================
#  TestReadyVerdictsAndAuthFailure (Regression for Pass #8)
# ===================================================================

class TestReadyVerdictsAndAuthFailure(unittest.TestCase):
    def setUp(self):
        self.test_dir = Path(tempfile.mkdtemp())
        self.state_file = self.test_dir / "state.json"
        self.state_mgr = StateManager(state_file=self.state_file)

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_is_ready_verdict_recognition(self):
        """Verify is_ready_verdict identifies merge-ready verdicts and rejects negations."""
        self.assertTrue(is_ready_verdict("Вердикт: READY TO MERGE"))
        self.assertTrue(is_ready_verdict("READY TO MERGE"))
        self.assertTrue(is_ready_verdict("Вердикт: READY WITH NON-BLOCKING NOTES"))
        self.assertTrue(is_ready_verdict("All tests pass, ready to merge."))
        self.assertTrue(is_ready_verdict("LGTM! ready with non-blocking notes"))

        # Explicit negations must NOT match
        self.assertFalse(is_ready_verdict("Вердикт: NOT READY"))
        self.assertFalse(is_ready_verdict("NOT READY TO MERGE"))
        self.assertFalse(is_ready_verdict("This is not ready to merge yet"))
        self.assertFalse(is_ready_verdict("General comments without verdict"))
        self.assertFalse(is_ready_verdict(""))
        self.assertFalse(is_ready_verdict(None))

    def test_is_auth_error_message_recognition(self):
        """Verify is_auth_error_message detects various gh CLI auth failures."""
        self.assertTrue(is_auth_error_message("To re-authenticate, run: gh auth login"))
        self.assertTrue(is_auth_error_message("HTTP 401: Bad credentials"))
        self.assertTrue(is_auth_error_message("GraphQL: Could not authenticate (oauth)"))
        self.assertTrue(is_auth_error_message("token expired or invalid"))
        self.assertTrue(is_auth_error_message("unauthorized request"))
        self.assertTrue(is_auth_error_message("You are not authenticated with any GitHub hosts"))

        self.assertFalse(is_auth_error_message("Could not resolve to a PullRequest with number 99."))
        self.assertFalse(is_auth_error_message("ETIMEDOUT: Connection reset by peer"))
        self.assertFalse(is_auth_error_message(""))
        self.assertFalse(is_auth_error_message(None))

    def test_get_effective_review_state_ready_verdicts(self):
        """Verify get_effective_review_state recognizes ready verdicts in reviews and comments."""
        allowlist = ["alex123321-maker"]

        # 1. Review with state COMMENTED and READY TO MERGE
        reviews = [{
            "id": "r1",
            "author": {"login": "alex123321-maker"},
            "state": "COMMENTED",
            "body": "Вердикт: READY TO MERGE\nAll criteria satisfied."
        }]
        self.assertEqual(get_effective_review_state(reviews, allowlist), "APPROVED")

        # 2. Review with state COMMENTED and READY WITH NON-BLOCKING NOTES
        reviews = [{
            "id": "r2",
            "author": {"login": "alex123321-maker"},
            "state": "COMMENTED",
            "body": "Вердикт: READY WITH NON-BLOCKING NOTES\nMinor typo in comment."
        }]
        self.assertEqual(get_effective_review_state(reviews, allowlist), "APPROVED")

        # 3. Top-level comment with READY TO MERGE
        comments = [{
            "id": "c1",
            "author": {"login": "alex123321-maker"},
            "body": "Вердикт: READY TO MERGE"
        }]
        self.assertEqual(get_effective_review_state([], allowlist, comments=comments), "APPROVED")

        # 4. Review with NOT READY is NEUTRAL
        reviews = [{
            "id": "r3",
            "author": {"login": "alex123321-maker"},
            "state": "COMMENTED",
            "body": "Вердикт: NOT READY\nBLOCKER 1: Needs fix."
        }]
        self.assertEqual(get_effective_review_state(reviews, allowlist), "NEUTRAL")

        # 5. Active CHANGES_REQUESTED dominates even if older ready comment exists
        reviews = [{
            "id": "r4",
            "author": {"login": "alex123321-maker"},
            "state": "CHANGES_REQUESTED",
            "body": "Fix required."
        }]
        self.assertEqual(get_effective_review_state(reviews, allowlist), "CHANGES_REQUESTED")

    def test_comment_ready_to_merge_produces_zero_wakes_and_approves(self):
        """Regression test: Review comment with READY TO MERGE sets status to approved and wakes 0 agents."""
        mock_github = MagicMock()
        mock_github.get_pr_details.return_value = {
            "state": "OPEN",
            "headRefOid": "sha123",
            "reviewDecision": None
        }
        mock_github.get_pr_reviews.return_value = [{
            "id": "rev_ready_1",
            "author": {"login": "alex123321-maker"},
            "state": "COMMENTED",
            "body": "Вердикт: READY TO MERGE\nClean implementation, closes #2."
        }]
        mock_github.get_pr_comments.return_value = []
        mock_github.get_pr_inline_comments.return_value = []
        mock_github.get_pr_review_threads.return_value = []

        mock_resumer = MagicMock()
        watcher = ReviewWatcher(
            github_client=mock_github,
            state_manager=self.state_mgr,
            agent_resumer=mock_resumer,
            run_once=True
        )

        self.state_mgr.register_pr(pr_number=4, conversation_id="conv4", branch="feat/2")
        self.state_mgr.add_to_allowlist("alex123321-maker")

        watcher.run_cycle()

        pr = self.state_mgr.get_pr(4)
        self.assertEqual(pr["status"], "approved")
        self.assertTrue(self.state_mgr.is_event_processed(4, "rev_ready_1"))
        self.assertFalse(mock_resumer.resume_conversation.called)

    def test_comment_ready_with_non_blocking_notes_produces_zero_wakes(self):
        """Regression test: Review comment with READY WITH NON-BLOCKING NOTES sets status to approved and wakes 0 agents."""
        mock_github = MagicMock()
        mock_github.get_pr_details.return_value = {
            "state": "OPEN",
            "headRefOid": "sha456",
            "reviewDecision": None
        }
        mock_github.get_pr_reviews.return_value = [{
            "id": "rev_ready_notes",
            "author": {"login": "alex123321-maker"},
            "state": "COMMENTED",
            "body": "Вердикт: READY WITH NON-BLOCKING NOTES\nNote: could rename helper later."
        }]
        mock_github.get_pr_comments.return_value = []
        mock_github.get_pr_inline_comments.return_value = []
        mock_github.get_pr_review_threads.return_value = []

        mock_resumer = MagicMock()
        watcher = ReviewWatcher(
            github_client=mock_github,
            state_manager=self.state_mgr,
            agent_resumer=mock_resumer,
            run_once=True
        )

        self.state_mgr.register_pr(pr_number=4, conversation_id="conv4", branch="feat/2")
        self.state_mgr.add_to_allowlist("alex123321-maker")

        watcher.run_cycle()

        pr = self.state_mgr.get_pr(4)
        self.assertEqual(pr["status"], "approved")
        self.assertTrue(self.state_mgr.is_event_processed(4, "rev_ready_notes"))
        self.assertFalse(mock_resumer.resume_conversation.called)

    def test_top_level_comment_ready_to_merge_produces_zero_wakes(self):
        """Regression test: Top-level comment with READY TO MERGE sets status to approved and wakes 0 agents."""
        mock_github = MagicMock()
        mock_github.get_pr_details.return_value = {
            "state": "OPEN",
            "headRefOid": "sha789",
            "reviewDecision": None
        }
        mock_github.get_pr_reviews.return_value = []
        mock_github.get_pr_comments.return_value = [{
            "id": "comment_ready_top",
            "author": {"login": "alex123321-maker"},
            "body": "All criteria met. READY TO MERGE"
        }]
        mock_github.get_pr_inline_comments.return_value = []
        mock_github.get_pr_review_threads.return_value = []

        mock_resumer = MagicMock()
        watcher = ReviewWatcher(
            github_client=mock_github,
            state_manager=self.state_mgr,
            agent_resumer=mock_resumer,
            run_once=True
        )

        self.state_mgr.register_pr(pr_number=4, conversation_id="conv4", branch="feat/2")
        self.state_mgr.add_to_allowlist("alex123321-maker")

        watcher.run_cycle()

        pr = self.state_mgr.get_pr(4)
        self.assertEqual(pr["status"], "approved")
        self.assertTrue(self.state_mgr.is_event_processed(4, "comment_ready_top"))
        self.assertFalse(mock_resumer.resume_conversation.called)

    def test_commented_review_not_ready_dispatches_agent(self):
        """Verify COMMENTED review with NOT READY verdict triggers normal agent dispatch."""
        mock_github = MagicMock()
        mock_github.get_pr_details.return_value = {
            "state": "OPEN",
            "headRefOid": "sha999",
            "reviewDecision": None
        }
        mock_github.get_pr_reviews.return_value = [{
            "id": "rev_not_ready",
            "author": {"login": "alex123321-maker"},
            "state": "COMMENTED",
            "body": "Вердикт: NOT READY\nBLOCKER 1: Please fix the edge case."
        }]
        mock_github.get_pr_comments.return_value = []
        mock_github.get_pr_inline_comments.return_value = []
        mock_github.get_pr_review_threads.return_value = []

        mock_resumer = MagicMock()
        mock_resumer.resume_conversation.return_value = (True, "launched", 1234)

        watcher = ReviewWatcher(
            github_client=mock_github,
            state_manager=self.state_mgr,
            agent_resumer=mock_resumer,
            run_once=True
        )

        self.state_mgr.register_pr(pr_number=4, conversation_id="conv4", branch="feat/2")
        self.state_mgr.add_to_allowlist("alex123321-maker")

        watcher.run_cycle()

        pr = self.state_mgr.get_pr(4)
        self.assertEqual(pr["status"], "processing")
        self.assertTrue(mock_resumer.resume_conversation.called)

    def test_post_startup_auth_loss_transitions_pr_to_error_and_halts_watcher(self):
        """Regression test: Mid-run GitHubAuthError transitions PRs to error status and halts watcher.start()."""
        mock_github = MagicMock()
        # Initial check_auth succeeds
        mock_github.check_auth.return_value = (True, "Logged in to github.com as alex123321-maker")
        # Subsequent PR fetch encounters expired auth credentials
        mock_github.get_pr_details.side_effect = GitHubAuthError("GitHub authentication error: HTTP 401: Bad credentials")

        mock_resumer = MagicMock()
        watcher = ReviewWatcher(
            github_client=mock_github,
            state_manager=self.state_mgr,
            agent_resumer=mock_resumer
        )

        self.state_mgr.register_pr(pr_number=77, conversation_id="conv77", branch="feat/77")
        self.state_mgr.set_in_flight_events(77, [{"id": "ev_inflight", "type": "comment"}])
        self.state_mgr.acquire_lock(77)

        # Execute watcher loop
        watcher.start()

        # PR must transition to 'error'
        pr = self.state_mgr.get_pr(77)
        self.assertEqual(pr["status"], "error")
        # In-flight events restored to pending
        self.assertEqual(len(pr["in_flight_events"]), 0)
        self.assertEqual(len(pr["pending_events"]), 1)
        # Lock released
        self.assertFalse(self.state_mgr.is_processing(77))
        self.assertEqual(pr["processing_started_at"], 0.0)
        self.assertIsNone(pr["active_agent_pid"])
        # Watcher loop halted
        self.assertFalse(watcher._running)

    def test_transient_github_error_propagates_to_backoff(self):
        """Verify transient network GitHubError triggers backoff in watcher.start()."""
        mock_github = MagicMock()
        mock_github.check_auth.return_value = (True, "Logged in")
        mock_github.get_pr_details.side_effect = GitHubError("ETIMEDOUT: Connection reset")

        mock_resumer = MagicMock()
        watcher = ReviewWatcher(
            github_client=mock_github,
            state_manager=self.state_mgr,
            agent_resumer=mock_resumer,
            run_once=True
        )

        self.state_mgr.register_pr(pr_number=88, conversation_id="conv88", branch="feat/88")

        # start() with run_once=True should catch GitHubError, back off / break cleanly
        watcher.start()
        self.assertFalse(watcher._running)

    def test_github_client_raises_auth_error(self):
        """Verify GitHubClient.run_gh raises GitHubAuthError on auth failure output."""
        client = GitHubClient(cwd=self.test_dir)
        with patch("subprocess.run") as mock_run:
            mock_run.return_value = MagicMock(
                returncode=1,
                stdout="",
                stderr="HTTP 401: Bad credentials. To re-authenticate, run: gh auth login"
            )
            with self.assertRaises(GitHubAuthError):
                client.get_pr_details(123)


if __name__ == "__main__":
    unittest.main()


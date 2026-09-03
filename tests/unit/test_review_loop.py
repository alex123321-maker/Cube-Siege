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
    detect_backend_from_path,
)
from tools.review_loop.config import AGENT_COMMENT_MARKER, DESIGN_DECISION_MARKER, REVIEW_LOOP_DIR
from tools.review_loop.github_client import GitHubClient, GitHubError
from tools.review_loop.install import install_linux
from tools.review_loop.register import register_from_hook
from tools.review_loop.state_manager import StateManager
from tools.review_loop.watcher import ReviewWatcher, get_effective_review_state, is_event_allowed


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

        # Cycle after error: must NOT dispatch again!
        self.mock_resumer.reset_mock()
        self.watcher.run_cycle()
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

        # Simulate agent writing DESIGN DECISION REQUIRED to log file
        log_file = REVIEW_LOOP_DIR / "agy_pr_90.log"
        log_file.parent.mkdir(parents=True, exist_ok=True)
        log_file.write_text(f"Analyzed request.\n{DESIGN_DECISION_MARKER}: Missing formula.\n", encoding="utf-8")

        # Agent exits without pushing
        with patch("tools.review_loop.watcher.is_pid_alive", return_value=False):
            self.watcher.run_cycle()

        pr = self.state_mgr.get_pr(90)
        self.assertEqual(pr["status"], "awaiting_design_decision")

        # Subsequent cycle: must NOT retry!
        self.mock_resumer.reset_mock()
        self.watcher.run_cycle()
        self.assertFalse(self.mock_resumer.resume_conversation.called)

        # Cleanup test log
        if log_file.exists():
            log_file.unlink()

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


if __name__ == "__main__":
    unittest.main()

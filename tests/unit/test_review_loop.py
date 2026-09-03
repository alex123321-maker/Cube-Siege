"""
tests/unit/test_review_loop.py - Comprehensive unit, regression, and integration
tests for the autonomous PR review feedback loop.

Tests cover:
  - StateManager: persistence, deduplication, locking, thread states, file-lock safety
  - AgentResumer: backend detection (PureWindowsPath portability), prompt contract, retry
  - ReviewWatcher: identity model, marker filtering, failed dispatch retry, APPROVE halt,
    thread reopen detection, event coalescing
  - register_from_hook: PostToolUse and Stop hook contracts
  - Full lifecycle integration: hook → watcher visibility → review → fail → retry →
    new head → APPROVE → no further wake
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
    BACKEND_AGENTAPI,
    BACKEND_AGY,
    AgentResumer,
    detect_backend_from_path,
)
from tools.review_loop.config import AGENT_COMMENT_MARKER
from tools.review_loop.github_client import GitHubClient, GitHubError
from tools.review_loop.register import register_from_hook
from tools.review_loop.state_manager import StateManager
from tools.review_loop.watcher import ReviewWatcher


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

    def test_pending_events_queue_and_restore(self):
        """Verify pending queue ordering, deduplication, and restore on failure."""
        self.state_mgr.register_pr(pr_number=7, conversation_id="c", branch="b")
        ev1 = {"id": "e1", "type": "comment", "body": "first"}
        ev2 = {"id": "e2", "type": "comment", "body": "second"}

        self.state_mgr.queue_pending_event(7, ev1)
        self.state_mgr.queue_pending_event(7, ev2)
        self.state_mgr.queue_pending_event(7, ev1)  # duplicate

        popped = self.state_mgr.pop_pending_events(7)
        self.assertEqual(len(popped), 2)
        self.assertEqual(len(self.state_mgr.pop_pending_events(7)), 0)

        self.state_mgr.restore_pending_events(7, popped)
        restored = self.state_mgr.pop_pending_events(7)
        self.assertEqual(len(restored), 2)
        self.assertEqual(restored[0]["id"], "e1")

    def test_thread_state_tracking(self):
        """Verify tracking of review thread isResolved states."""
        self.state_mgr.register_pr(pr_number=9, conversation_id="c", branch="b")
        self.assertIsNone(self.state_mgr.get_thread_is_resolved(9, "th_1"))

        self.state_mgr.set_thread_is_resolved(9, "th_1", True)
        self.assertTrue(self.state_mgr.get_thread_is_resolved(9, "th_1"))

        self.state_mgr.set_thread_is_resolved(9, "th_1", False)
        self.assertFalse(self.state_mgr.get_thread_is_resolved(9, "th_1"))

    def test_update_pr_fields_transactional(self):
        """Verify update_pr_fields atomically updates multiple fields."""
        self.state_mgr.register_pr(pr_number=20, conversation_id="c20", branch="b20")
        self.state_mgr.update_pr_fields(20, last_head_sha="abc123", active_agent_pid=9999)

        pr = self.state_mgr.get_pr(20)
        self.assertEqual(pr["last_head_sha"], "abc123")
        self.assertEqual(pr["active_agent_pid"], 9999)

    def test_inter_process_state_visibility(self):
        """
        BLOCKER 3 regression: Two StateManager instances on the same file simulate
        watcher + hook concurrency. Hook registers a PR; watcher must see it.
        """
        watcher_state = StateManager(state_file=self.state_file)
        watcher_state.add_to_allowlist("watcher-user")

        # Simulate hook process (separate StateManager instance)
        hook_state = StateManager(state_file=self.state_file)
        hook_state.register_pr(pr_number=55, conversation_id="hook-conv", branch="feat/55")

        # Watcher's next read must see the hook's registration
        watcher_prs = watcher_state.get_registered_prs()
        self.assertIn("55", watcher_prs)
        self.assertEqual(watcher_prs["55"]["conversation_id"], "hook-conv")

        # Watcher's own mutation must not clobber hook's data
        watcher_state.add_to_allowlist("another-user")
        hook_pr = watcher_state.get_pr(55)
        self.assertIsNotNone(hook_pr)
        self.assertEqual(hook_pr["conversation_id"], "hook-conv")


# ===================================================================
#  AgentResumer
# ===================================================================

class TestAgentResumer(unittest.TestCase):
    def test_build_prompt_contains_marker(self):
        """
        BLOCKER 4 regression: Resume prompt MUST contain AGENT_COMMENT_MARKER
        verbatim so the agent knows to tag its GitHub comments.
        """
        resumer = AgentResumer(agentapi_cmd=["dummy"], backend_type=BACKEND_AGENTAPI)
        prompt = resumer.build_prompt(pr_number=123)
        self.assertIn(AGENT_COMMENT_MARKER, prompt)
        self.assertIn("PR #123", prompt)
        self.assertIn("DESIGN DECISION REQUIRED", prompt)
        self.assertIn("Do not merge the PR", prompt)

    def test_detect_backend_windows_path_on_any_os(self):
        """
        BLOCKER 1 CI regression: Windows-style paths must be correctly
        identified as agy backend regardless of host OS.
        """
        self.assertEqual(
            detect_backend_from_path(r"D:\Tools\agy\bin\agy.exe"),
            BACKEND_AGY,
        )
        self.assertEqual(
            detect_backend_from_path(r"C:\Users\user\AppData\Local\agy\bin\agy.exe"),
            BACKEND_AGY,
        )
        # POSIX paths
        self.assertEqual(
            detect_backend_from_path("/usr/local/bin/agy"),
            BACKEND_AGY,
        )
        # agentapi
        self.assertEqual(
            detect_backend_from_path("/usr/local/bin/agentapi"),
            BACKEND_AGENTAPI,
        )
        self.assertEqual(
            detect_backend_from_path(r"C:\agentapi\agentapi.exe"),
            BACKEND_AGENTAPI,
        )

    @patch("subprocess.Popen")
    @patch("time.sleep")
    def test_agy_backend_uses_popen_and_returns_pid(self, mock_sleep, mock_popen):
        """
        BLOCKER 5 regression: agy backend must use Popen (not subprocess.run)
        and return the launched PID for lifecycle tracking.
        """
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

        # Verify Popen was called with --conversation and --print-timeout
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

    @patch("time.sleep")
    @patch("subprocess.run")
    def test_agentapi_backend_uses_subprocess_run(self, mock_run, mock_sleep):
        """agentapi backend must use synchronous subprocess.run."""
        mock_run.side_effect = [
            MagicMock(returncode=1, stdout="", stderr="busy"),
            MagicMock(returncode=1, stdout="", stderr="busy"),
            MagicMock(returncode=0, stdout="Dispatched", stderr=""),
        ]
        resumer = AgentResumer(
            agentapi_cmd=["agentapi"], backend_type=BACKEND_AGENTAPI
        )
        success, out, pid = resumer.resume_conversation(
            "test-conv-id", pr_number=123, max_retries=3
        )
        self.assertTrue(success)
        self.assertIsNone(pid)  # agentapi doesn't return PID
        self.assertEqual(mock_run.call_count, 3)
        self.assertEqual(mock_sleep.call_count, 2)


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
        self.mock_resumer.resume_conversation.return_value = (True, "Dispatched", None)

        self.watcher = ReviewWatcher(
            github_client=self.mock_github,
            state_manager=self.state_mgr,
            agent_resumer=self.mock_resumer,
            run_once=True,
        )

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def _setup_pr_mocks(self, pr_number, reviews=None, comments=None, inline=None, threads=None, head="sha_x"):
        """Helper to configure mock GitHub responses."""
        self.mock_github.get_pr_details.return_value = {
            "number": pr_number,
            "state": "OPEN",
            "headRefOid": head,
            "author": {"login": "alex123321-maker"},
        }
        self.mock_github.get_pr_reviews.return_value = reviews or []
        self.mock_github.get_pr_comments.return_value = comments or []
        self.mock_github.get_pr_inline_comments.return_value = inline or []
        self.mock_github.get_pr_review_threads.return_value = threads or []

    def test_owner_equals_pr_author_review_is_accepted(self):
        """
        BLOCKER 1: PR author is repo owner (alex123321-maker).
        Review feedback from owner MUST wake agent, not be ignored.
        """
        self.state_mgr.register_pr(pr_number=4, conversation_id="conv-owner", branch="feat/4")
        self._setup_pr_mocks(4, reviews=[
            {
                "id": "rev_owner_req",
                "state": "REQUEST_CHANGES",
                "author": {"login": "alex123321-maker"},
                "body": "Fix blocker 1",
            }
        ], head="sha_4")

        self.watcher.run_cycle()

        self.assertTrue(self.mock_resumer.resume_conversation.called)
        self.assertTrue(self.state_mgr.is_event_processed(4, "rev_owner_req"))

    def test_agent_authored_comment_with_marker_ignored(self):
        """Comments with AGENT_COMMENT_MARKER must be ignored to prevent loops."""
        self.state_mgr.register_pr(pr_number=4, conversation_id="conv-owner", branch="feat/4")
        self._setup_pr_mocks(4, comments=[
            {
                "id": "comment_agent_fix",
                "author": {"login": "alex123321-maker"},
                "body": f"Fixed the issues. {AGENT_COMMENT_MARKER}",
            }
        ], head="sha_4")

        self.watcher.run_cycle()

        self.assertFalse(self.mock_resumer.resume_conversation.called)
        self.assertFalse(self.state_mgr.is_event_processed(4, "comment_agent_fix"))

    def test_failed_resume_restores_pending_events(self):
        """
        BLOCKER 3: If resume fails, events must NOT be marked processed
        and must be restored to pending_events for retry.
        """
        self.state_mgr.register_pr(pr_number=11, conversation_id="c11", branch="b11")
        self.mock_resumer.resume_conversation.return_value = (False, "Network error", None)
        self._setup_pr_mocks(11, reviews=[
            {
                "id": "rev_must_retry",
                "state": "REQUEST_CHANGES",
                "author": {"login": "alex123321-maker"},
                "body": "Critical fix needed",
            }
        ], head="sha11")

        self.watcher.run_cycle()

        self.assertFalse(self.state_mgr.is_event_processed(11, "rev_must_retry"))
        pr = self.state_mgr.get_pr(11)
        self.assertEqual(len(pr["pending_events"]), 1)
        self.assertEqual(pr["pending_events"][0]["id"], "rev_must_retry")
        self.assertFalse(self.state_mgr.is_processing(11))

        # Second cycle: resume succeeds, events drained from pending
        self.mock_resumer.resume_conversation.return_value = (True, "OK", None)
        self.mock_github.get_pr_reviews.return_value = []

        self.watcher.run_cycle()

        self.assertTrue(self.state_mgr.is_event_processed(11, "rev_must_retry"))
        self.assertEqual(len(self.state_mgr.get_pr(11)["pending_events"]), 0)

    def test_approve_stops_feedback_loop_completely(self):
        """
        BLOCKER 4: APPROVED transitions PR to 'approved' and subsequent
        comments do NOT wake the agent.
        """
        self.state_mgr.register_pr(pr_number=12, conversation_id="c12", branch="b12")
        self._setup_pr_mocks(12, reviews=[
            {
                "id": "rev_approved",
                "state": "APPROVED",
                "author": {"login": "alex123321-maker"},
                "body": "LGTM",
            }
        ], head="sha12")

        self.watcher.run_cycle()

        pr = self.state_mgr.get_pr(12)
        self.assertEqual(pr["status"], "approved")
        self.assertFalse(self.mock_resumer.resume_conversation.called)

        # Subsequent comment must NOT trigger wake
        self._setup_pr_mocks(12, comments=[
            {
                "id": "comment_post_approval",
                "author": {"login": "alex123321-maker"},
                "body": "By the way, good job",
            }
        ], head="sha12")

        self.watcher.run_cycle()
        self.assertFalse(self.mock_resumer.resume_conversation.called)

    def test_thread_reopened_transition_detected(self):
        """Reopened thread (isResolved True→False) wakes agent."""
        self.state_mgr.register_pr(pr_number=13, conversation_id="c13", branch="b13")
        self.state_mgr.set_thread_is_resolved(13, "th_reopen_test", True)
        self._setup_pr_mocks(13, threads=[
            {"id": "th_reopen_test", "isResolved": False, "comments": {"nodes": []}}
        ], head="sha13")

        self.watcher.run_cycle()

        self.assertTrue(self.mock_resumer.resume_conversation.called)
        self.assertTrue(self.state_mgr.is_event_processed(13, "reopen_th_reopen_test"))

    def test_events_queued_during_active_processing(self):
        """Events arriving while agent is processing are queued, not parallelized."""
        self.state_mgr.register_pr(pr_number=7, conversation_id="conv-7", branch="feat/7")
        self.state_mgr.update_pr_fields(7, last_head_sha="sha7")
        self.state_mgr.acquire_lock(7)

        self._setup_pr_mocks(7, reviews=[
            {
                "id": "rev_mid_flight",
                "state": "REQUEST_CHANGES",
                "author": {"login": "alex123321-maker"},
                "body": "Another quick fix",
            }
        ], head="sha7")

        self.watcher.run_cycle()

        self.assertFalse(self.mock_resumer.resume_conversation.called)
        pr = self.state_mgr.get_pr(7)
        self.assertEqual(len(pr["pending_events"]), 1)


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
        """
        BLOCKER 2: Stop hook must output {"decision": "stop"} to allow
        normal termination, NOT {}.
        """
        hook_payload = json.dumps({"conversationId": "conv-stop"})
        stdout_capture = io.StringIO()

        with patch("sys.stdin", io.StringIO(hook_payload)), \
             patch("sys.stdout", stdout_capture), \
             patch("tools.review_loop.register.get_current_git_branch", return_value="main"):
            register_from_hook(is_stop=True)

        output = json.loads(stdout_capture.getvalue().strip())
        self.assertEqual(output["decision"], "stop")

    def test_from_hook_registers_pr(self):
        """Hook registration creates PR mapping in state.json."""
        test_dir = Path(tempfile.mkdtemp())
        state_file = test_dir / "state.json"
        hook_payload = json.dumps({"conversationId": "hook-conv-77", "workspacePaths": ["/repo"]})

        try:
            with patch("sys.stdin", io.StringIO(hook_payload)), \
                 patch("sys.stdout", io.StringIO()), \
                 patch("tools.review_loop.register.get_current_git_branch", return_value="feat/hook-77"), \
                 patch("tools.review_loop.register.GitHubClient") as MockGH, \
                 patch("tools.review_loop.register.StateManager") as MockSM:
                mock_instance = MockSM.return_value
                MockGH.return_value.find_pr_for_branch.return_value = 77
                register_from_hook(is_stop=False)
                mock_instance.register_pr.assert_called_once_with(77, "hook-conv-77", "feat/hook-77")
        finally:
            shutil.rmtree(test_dir, ignore_errors=True)


# ===================================================================
#  Full Lifecycle Integration Test
# ===================================================================

class TestFullLifecycleIntegration(unittest.TestCase):
    """
    Deterministic end-to-end integration test exercising:
      hook conversationId → watcher visibility → owner review → failed dispatch →
      retry → successful dispatch → new head → APPROVE → no further wake
    """

    def test_complete_review_loop_lifecycle(self):
        test_dir = Path(tempfile.mkdtemp())
        state_file = test_dir / "state.json"

        try:
            # ---- Step 1: Hook process registers a PR ----
            hook_state = StateManager(state_file=state_file)
            hook_state.add_to_allowlist("alex123321-maker")
            hook_state.register_pr(pr_number=50, conversation_id="conv-50", branch="feat/50")

            # ---- Step 2: Watcher (separate StateManager) sees registration ----
            watcher_state = StateManager(state_file=state_file)
            prs = watcher_state.get_registered_prs()
            self.assertIn("50", prs)
            self.assertEqual(prs["50"]["conversation_id"], "conv-50")

            # ---- Step 3: Create watcher with mocked GitHub + resumer ----
            mock_github = MagicMock(spec=GitHubClient)
            mock_resumer = MagicMock(spec=AgentResumer)

            watcher = ReviewWatcher(
                github_client=mock_github,
                state_manager=watcher_state,
                agent_resumer=mock_resumer,
                run_once=True,
            )

            # ---- Step 4: Owner posts REQUEST_CHANGES ----
            mock_github.get_pr_details.return_value = {
                "number": 50, "state": "OPEN", "headRefOid": "sha_v1",
                "author": {"login": "alex123321-maker"},
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

            # ---- Step 5: First dispatch FAILS ----
            mock_resumer.resume_conversation.return_value = (False, "timeout", None)

            watcher.run_cycle()

            # Events must be preserved, not lost
            self.assertFalse(watcher_state.is_event_processed(50, "rev_lifecycle_1"))
            pr = watcher_state.get_pr(50)
            self.assertEqual(len(pr["pending_events"]), 1)
            self.assertFalse(watcher_state.is_processing(50))

            # ---- Step 6: Second cycle — dispatch SUCCEEDS ----
            mock_resumer.resume_conversation.return_value = (True, "agy launched (PID 999)", 999)
            mock_github.get_pr_reviews.return_value = []  # no new reviews

            watcher.run_cycle()

            # Events dispatched successfully
            self.assertTrue(watcher_state.is_event_processed(50, "rev_lifecycle_1"))
            pr = watcher_state.get_pr(50)
            self.assertEqual(len(pr["pending_events"]), 0)
            self.assertEqual(pr["active_agent_pid"], 999)

            # ---- Step 7: Agent pushes new head SHA ----
            mock_github.get_pr_details.return_value["headRefOid"] = "sha_v2"

            with patch("tools.review_loop.state_manager.is_pid_alive", return_value=False):
                watcher.run_cycle()

            pr = watcher_state.get_pr(50)
            self.assertEqual(pr["last_head_sha"], "sha_v2")
            self.assertEqual(pr["status"], "watching")

            # ---- Step 8: APPROVE received ----
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
            # APPROVE must NOT trigger resume
            self.assertFalse(mock_resumer.resume_conversation.called)

            # ---- Step 9: Subsequent comment on approved PR — NO wake ----
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

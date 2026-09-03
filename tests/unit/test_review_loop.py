"""
tests/unit/test_review_loop.py - Comprehensive unit, regression, and integration
tests for the autonomous PR review feedback loop.

Tests cover:
  - StateManager: persistence, deduplication, atomic lock acquisition, in-flight events,
    thread states, inter-process safety
  - AgentResumer: backend detection (PureWindowsPath portability), prompt contract, retry,
    Popen output logging
  - ReviewWatcher: identity model, bot allowlist precedence, effective review state (APPROVE),
    delayed agy failure recovery, thread reopen detection, event coalescing
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
    BACKEND_AGENTAPI,
    BACKEND_AGY,
    AgentResumer,
    detect_backend_from_path,
)
from tools.review_loop.config import AGENT_COMMENT_MARKER
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

    def test_atomic_acquire_lock_concurrency(self):
        """
        BLOCKER 1 Regression: Two independent StateManager instances simulate
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
        """
        BLOCKER 3: Verify in-flight events are saved, finalized on success,
        or restored to pending queue on failure.
        """
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
        Two StateManager instances on the same file simulate
        watcher + hook concurrency. Hook registers a PR; watcher must see it.
        """
        watcher_state = StateManager(state_file=self.state_file)
        watcher_state.add_to_allowlist("watcher-user")

        hook_state = StateManager(state_file=self.state_file)
        hook_state.register_pr(pr_number=55, conversation_id="hook-conv", branch="feat/55")

        watcher_prs = watcher_state.get_registered_prs()
        self.assertIn("55", watcher_prs)
        self.assertEqual(watcher_prs["55"]["conversation_id"], "hook-conv")


# ===================================================================
#  AgentResumer
# ===================================================================

class TestAgentResumer(unittest.TestCase):
    def test_build_prompt_contains_marker(self):
        """Resume prompt MUST contain AGENT_COMMENT_MARKER verbatim."""
        resumer = AgentResumer(agentapi_cmd=["dummy"], backend_type=BACKEND_AGENTAPI)
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

    def test_owner_equals_pr_author_review_is_accepted(self):
        """Owner review on own PR MUST wake agent, not be ignored."""
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
        # Event is in-flight, not permanently finalized yet
        pr = self.state_mgr.get_pr(4)
        self.assertEqual(len(pr["in_flight_events"]), 1)

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

    def test_approved_then_request_changes_wakes_agent(self):
        """
        BLOCKER 2 Regression: Older APPROVED followed by newer REQUEST_CHANGES
        from the same reviewer MUST wake the agent and NOT get stuck in approved!
        """
        self.state_mgr.register_pr(pr_number=15, conversation_id="c15", branch="b15")
        # Review list has historical APPROVED followed by recent REQUEST_CHANGES
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

        # Agent MUST be woken for rev_new_req!
        self.assertTrue(self.mock_resumer.resume_conversation.called)
        pr = self.state_mgr.get_pr(15)
        self.assertNotEqual(pr["status"], "approved")
        self.assertEqual(len(pr["in_flight_events"]), 1)
        self.assertEqual(pr["in_flight_events"][0]["id"], "rev_new_req")

    def test_mixed_existing_reviews_effective_decision(self):
        """
        BLOCKER 2: PR registered with mixed existing review history respects
        reviewDecision and does not treat older APPROVE as final.
        """
        reviews = [
            {"id": "r1", "state": "APPROVED", "author": {"login": "alex123321-maker"}},
            {"id": "r2", "state": "REQUEST_CHANGES", "author": {"login": "alex123321-maker"}},
        ]
        decision = get_effective_review_state(reviews, ["alex123321-maker"], review_decision="CHANGES_REQUESTED")
        self.assertEqual(decision, "CHANGES_REQUESTED")

        # When latest review is APPROVED and reviewDecision is APPROVED
        reviews_approved = [
            {"id": "r1", "state": "REQUEST_CHANGES", "author": {"login": "alex123321-maker"}},
            {"id": "r2", "state": "APPROVED", "author": {"login": "alex123321-maker"}},
        ]
        decision_app = get_effective_review_state(reviews_approved, ["alex123321-maker"], review_decision="APPROVED")
        self.assertEqual(decision_app, "APPROVED")

    def test_delayed_agy_failure_restores_events(self):
        """
        BLOCKER 3 Regression: Agent process starts (passes startup window) but
        later exits without pushing any new commits (head unchanged).
        Watcher must restore all in-flight events to pending and NOT lose them!
        """
        self.state_mgr.register_pr(pr_number=33, conversation_id="c33", branch="b33")
        self.state_mgr.update_pr_fields(33, last_head_sha="sha_initial")

        # Cycle 1: Event detected, agent launched with PID 7777
        self._setup_pr_mocks(33, reviews=[
            {
                "id": "rev_fragile",
                "state": "REQUEST_CHANGES",
                "author": {"login": "alex123321-maker"},
                "body": "Fix this bug",
            }
        ], head="sha_initial")

        self.watcher.run_cycle()

        self.assertTrue(self.mock_resumer.resume_conversation.called)
        pr = self.state_mgr.get_pr(33)
        self.assertEqual(len(pr["in_flight_events"]), 1)
        self.assertFalse(self.state_mgr.is_event_processed(33, "rev_fragile"))

        # Cycle 2: Agent died (PID 7777 is dead) and head SHA is STILL sha_initial!
        # Watcher must detect failure, restore event to pending, and clear in-flight.
        self.mock_github.get_pr_reviews.return_value = []  # No new reviews on GitHub

        with patch("tools.review_loop.watcher.is_pid_alive", return_value=False):
            self.watcher.run_cycle()

        pr = self.state_mgr.get_pr(33)
        # Events must NOT be lost!
        self.assertFalse(self.state_mgr.is_event_processed(33, "rev_fragile"))
        self.assertEqual(len(pr["pending_events"]), 1)
        self.assertEqual(pr["pending_events"][0]["id"], "rev_fragile")
        self.assertEqual(len(pr["in_flight_events"]), 0)

    def test_allowlisted_bot_is_accepted(self):
        """
        IMPORTANT 1 Regression: An explicitly allowlisted bot account MUST be
        processed, and generic unallowlisted bots MUST be ignored.
        """
        self.state_mgr.add_to_allowlist("code-review-bot[bot]")

        # Allowlisted bot comment
        allowed = is_event_allowed("code-review-bot[bot]", "Please fix indentation", self.state_mgr)
        self.assertTrue(allowed)

        # Unallowlisted bot comment
        ignored = is_event_allowed("unauthorized-bot[bot]", "Noise", self.state_mgr)
        self.assertFalse(ignored)

        # Agent comment with marker from allowlisted bot is still rejected (anti-loop)
        agent_marker = is_event_allowed("code-review-bot[bot]", f"Done {AGENT_COMMENT_MARKER}", self.state_mgr)
        self.assertFalse(agent_marker)

    def test_thread_reopened_transition_detected(self):
        """Reopened thread (isResolved True→False) wakes agent."""
        self.state_mgr.register_pr(pr_number=13, conversation_id="c13", branch="b13")
        self.state_mgr.set_thread_is_resolved(13, "th_reopen_test", True)
        self._setup_pr_mocks(13, threads=[
            {"id": "th_reopen_test", "isResolved": False, "comments": {"nodes": []}}
        ], head="sha13")

        self.watcher.run_cycle()

        self.assertTrue(self.mock_resumer.resume_conversation.called)
        pr = self.state_mgr.get_pr(13)
        self.assertEqual(len(pr["in_flight_events"]), 1)
        self.assertEqual(pr["in_flight_events"][0]["id"], "reopen_th_reopen_test")


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


# ===================================================================
#  Installer
# ===================================================================

class TestInstaller(unittest.TestCase):
    @patch("subprocess.run")
    def test_linux_installer_failure_returns_false(self, mock_run):
        """
        IMPORTANT 2 Regression: If systemctl daemon-reload or enable fails,
        install_linux() must return False instead of True.
        """
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
            # ---- Step 1: Hook process registers a PR ----
            hook_state = StateManager(state_file=state_file)
            hook_state.add_to_allowlist("alex123321-maker")
            hook_state.register_pr(pr_number=50, conversation_id="conv-50", branch="feat/50")

            # ---- Step 2: Watcher sees registration ----
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

            # First launch succeeds (PID 900)
            mock_resumer.resume_conversation.return_value = (True, "launched", 900)

            watcher.run_cycle()

            pr = watcher_state.get_pr(50)
            self.assertEqual(pr["status"], "processing")
            self.assertEqual(len(pr["in_flight_events"]), 1)

            # ---- Step 5: Delayed failure: PID 900 exits without pushing (head is still sha_v1) ----
            mock_github.get_pr_reviews.return_value = []

            with patch("tools.review_loop.watcher.is_pid_alive", return_value=False):
                watcher.run_cycle()

            # Event must be restored to pending!
            pr = watcher_state.get_pr(50)
            self.assertEqual(len(pr["pending_events"]), 1)
            self.assertEqual(len(pr["in_flight_events"]), 0)
            self.assertFalse(watcher_state.is_event_processed(50, "rev_lifecycle_1"))

            # ---- Step 6: Next cycle: retry dispatches pending event with PID 901 ----
            mock_resumer.resume_conversation.return_value = (True, "launched", 901)
            watcher.run_cycle()

            pr = watcher_state.get_pr(50)
            self.assertEqual(pr["status"], "processing")
            self.assertEqual(len(pr["in_flight_events"]), 1)

            # ---- Step 7: Agent pushes new head (sha_v2) and exits ----
            mock_github.get_pr_details.return_value["headRefOid"] = "sha_v2"

            with patch("tools.review_loop.watcher.is_pid_alive", return_value=False):
                watcher.run_cycle()

            # Event is now permanently finalized!
            pr = watcher_state.get_pr(50)
            self.assertTrue(watcher_state.is_event_processed(50, "rev_lifecycle_1"))
            self.assertEqual(pr["last_head_sha"], "sha_v2")
            self.assertEqual(pr["status"], "watching")

            # ---- Step 8: APPROVE received ----
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

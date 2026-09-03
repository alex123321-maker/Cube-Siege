"""
tests/unit/test_review_loop.py - Comprehensive unit & regression tests for review loop watcher.
"""
import io
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from tools.review_loop.agent_resumer import AgentResumer
from tools.review_loop.config import AGENT_COMMENT_MARKER
from tools.review_loop.github_client import GitHubClient, GitHubError
from tools.review_loop.register import register_from_hook
from tools.review_loop.state_manager import StateManager
from tools.review_loop.watcher import ReviewWatcher

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
        """Verify events are marked as processed and duplicate events detected."""
        self.state_mgr.register_pr(pr_number=10, conversation_id="c1", branch="b1")
        self.assertFalse(self.state_mgr.is_event_processed(10, "rev_1"))

        self.state_mgr.mark_event_processed(10, "rev_1")
        self.assertTrue(self.state_mgr.is_event_processed(10, "rev_1"))

        self.state_mgr.mark_event_processed(10, "rev_1")
        pr = self.state_mgr.get_pr(10)
        self.assertEqual(pr["processed_event_ids"].count("rev_1"), 1)

    def test_allowlist_filtering(self):
        """Verify allowlist enforcement and case-insensitivity."""
        self.state_mgr.add_to_allowlist("Alex123321-Maker")
        self.assertTrue(self.state_mgr.is_user_allowed("Alex123321-Maker"))
        self.assertTrue(self.state_mgr.is_user_allowed("alex123321-maker"))
        self.assertFalse(self.state_mgr.is_user_allowed("UntrustedUser"))
        self.assertFalse(self.state_mgr.is_user_allowed(""))

    def test_concurrency_lock_and_lease(self):
        """Verify lock prevents parallel runs and lease timeout reclaims expired lock."""
        self.state_mgr.register_pr(pr_number=5, conversation_id="c", branch="b")
        self.assertFalse(self.state_mgr.is_processing(5))

        self.assertTrue(self.state_mgr.acquire_lock(5, lease_seconds=10.0))
        self.assertTrue(self.state_mgr.is_processing(5))
        self.assertFalse(self.state_mgr.acquire_lock(5, lease_seconds=10.0))

        # Simulate expired lease without alive process
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
        self.state_mgr.queue_pending_event(7, ev1)

        popped = self.state_mgr.pop_pending_events(7)
        self.assertEqual(len(popped), 2)
        self.assertEqual(len(self.state_mgr.pop_pending_events(7)), 0)

        # Restore on failure
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

class TestAgentResumer(unittest.TestCase):
    def test_build_prompt_contract(self):
        """Verify resume prompt matches contract requirements."""
        resumer = AgentResumer(agentapi_cmd=["dummy_agentapi"])
        prompt = resumer.build_prompt(pr_number=123)
        self.assertIn("PR #123", prompt)
        self.assertIn("DESIGN DECISION REQUIRED", prompt)
        self.assertIn("Do not merge the PR", prompt)
        self.assertIn("verification", prompt)

    @patch("subprocess.run")
    def test_windows_agy_exe_command_construction(self, mock_run):
        """Verify official agy CLI execution on Windows (agy.exe)."""
        mock_run.return_value = MagicMock(returncode=0, stdout="OK", stderr="")
        resumer = AgentResumer(agentapi_cmd=[r"D:\Tools\agy\bin\agy.exe"])
        success, out, pid = resumer.resume_conversation("test-conv-id", pr_number=4)
        self.assertTrue(success)
        self.assertTrue(mock_run.called)
        cmd = mock_run.call_args[0][0]
        self.assertEqual(cmd[0], r"D:\Tools\agy\bin\agy.exe")
        self.assertEqual(cmd[1], "--conversation")
        self.assertEqual(cmd[2], "test-conv-id")
        self.assertEqual(cmd[3], "-p")

    @patch("time.sleep")
    @patch("subprocess.run")
    def test_resume_conversation_retry_and_backoff(self, mock_run, mock_sleep):
        mock_run.side_effect = [
            MagicMock(returncode=1, stdout="", stderr="busy"),
            MagicMock(returncode=1, stdout="", stderr="busy"),
            MagicMock(returncode=0, stdout="Dispatched", stderr="")
        ]
        resumer = AgentResumer(agentapi_cmd=["agentapi"])
        success, out, pid = resumer.resume_conversation("test-conv-id", pr_number=123, max_retries=3)
        self.assertTrue(success)
        self.assertEqual(mock_run.call_count, 3)
        self.assertEqual(mock_sleep.call_count, 2)

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
            run_once=True
        )

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_owner_equals_pr_author_review_is_accepted(self):
        """
        BLOCKER 1 Regression: PR author is repo owner (alex123321-maker).
        Review feedback from alex123321-maker MUST wake the agent, not be ignored!
        """
        self.state_mgr.register_pr(pr_number=4, conversation_id="conv-owner", branch="feat/4")
        self.mock_github.get_pr_details.return_value = {
            "number": 4, "state": "OPEN", "headRefOid": "sha_4",
            "author": {"login": "alex123321-maker"}  # PR author is owner!
        }
        self.mock_github.get_pr_reviews.return_value = [
            {
                "id": "rev_owner_req",
                "state": "REQUEST_CHANGES",
                "author": {"login": "alex123321-maker"},  # Reviewer is also owner!
                "body": "Fix blocker 1"
            }
        ]
        self.mock_github.get_pr_comments.return_value = []
        self.mock_github.get_pr_inline_comments.return_value = []
        self.mock_github.get_pr_review_threads.return_value = []

        self.watcher.run_cycle()

        # Resumer MUST be called!
        self.assertTrue(self.mock_resumer.resume_conversation.called)
        self.assertTrue(self.state_mgr.is_event_processed(4, "rev_owner_req"))
        self.assertTrue(self.state_mgr.is_processing(4))

    def test_agent_authored_comment_with_marker_ignored(self):
        """
        Comments posted by the agent with AGENT_COMMENT_MARKER must be ignored to prevent loops.
        """
        self.state_mgr.register_pr(pr_number=4, conversation_id="conv-owner", branch="feat/4")
        self.mock_github.get_pr_details.return_value = {
            "number": 4, "state": "OPEN", "headRefOid": "sha_4",
            "author": {"login": "alex123321-maker"}
        }
        self.mock_github.get_pr_reviews.return_value = []
        self.mock_github.get_pr_comments.return_value = [
            {
                "id": "comment_agent_fix",
                "author": {"login": "alex123321-maker"},
                "body": f"Fixed the issues. {AGENT_COMMENT_MARKER}"
            }
        ]
        self.mock_github.get_pr_inline_comments.return_value = []
        self.mock_github.get_pr_review_threads.return_value = []

        self.watcher.run_cycle()

        # Agent marker comments must NOT wake agent
        self.assertFalse(self.mock_resumer.resume_conversation.called)
        self.assertFalse(self.state_mgr.is_event_processed(4, "comment_agent_fix"))

    def test_failed_resume_restores_pending_events(self):
        """
        BLOCKER 3 Regression: If resume fails, events are NOT marked processed
        and are restored to pending_events for retry on the next cycle.
        """
        self.state_mgr.register_pr(pr_number=11, conversation_id="c11", branch="b11")
        self.mock_resumer.resume_conversation.return_value = (False, "Network error", None)

        self.mock_github.get_pr_details.return_value = {
            "number": 11, "state": "OPEN", "headRefOid": "sha11",
            "author": {"login": "alex123321-maker"}
        }
        self.mock_github.get_pr_reviews.return_value = [
            {
                "id": "rev_must_retry",
                "state": "REQUEST_CHANGES",
                "author": {"login": "alex123321-maker"},
                "body": "Critical fix needed"
            }
        ]
        self.mock_github.get_pr_comments.return_value = []
        self.mock_github.get_pr_inline_comments.return_value = []
        self.mock_github.get_pr_review_threads.return_value = []

        self.watcher.run_cycle()

        # Must NOT be marked as permanently processed
        self.assertFalse(self.state_mgr.is_event_processed(11, "rev_must_retry"))
        # Must be restored in pending_events
        pr = self.state_mgr.get_pr(11)
        self.assertEqual(len(pr["pending_events"]), 1)
        self.assertEqual(pr["pending_events"][0]["id"], "rev_must_retry")
        # Lock must be released
        self.assertFalse(self.state_mgr.is_processing(11))

        # Next cycle: resume succeeds
        self.mock_resumer.resume_conversation.return_value = (True, "Dispatched", None)
        self.mock_github.get_pr_reviews.return_value = []  # No new reviews on GitHub

        self.watcher.run_cycle()

        # Successfully dispatched from pending queue!
        self.assertTrue(self.state_mgr.is_event_processed(11, "rev_must_retry"))
        self.assertEqual(len(self.state_mgr.get_pr(11)["pending_events"]), 0)

    def test_approve_stops_feedback_loop_completely(self):
        """
        BLOCKER 4 Regression: An APPROVED review transitions PR to 'approved' state,
        and subsequent review comments or cycles do NOT wake the agent.
        """
        self.state_mgr.register_pr(pr_number=12, conversation_id="c12", branch="b12")
        self.mock_github.get_pr_details.return_value = {
            "number": 12, "state": "OPEN", "headRefOid": "sha12",
            "author": {"login": "alex123321-maker"}
        }
        self.mock_github.get_pr_reviews.return_value = [
            {
                "id": "rev_approved",
                "state": "APPROVED",
                "author": {"login": "alex123321-maker"},
                "body": "LGTM"
            }
        ]
        self.mock_github.get_pr_comments.return_value = []
        self.mock_github.get_pr_inline_comments.return_value = []
        self.mock_github.get_pr_review_threads.return_value = []

        self.watcher.run_cycle()

        # PR status becomes 'approved'
        pr = self.state_mgr.get_pr(12)
        self.assertEqual(pr["status"], "approved")
        self.assertFalse(self.mock_resumer.resume_conversation.called)

        # Subsequent comment on approved PR arrives
        self.mock_github.get_pr_reviews.return_value = []
        self.mock_github.get_pr_comments.return_value = [
            {
                "id": "comment_post_approval",
                "author": {"login": "alex123321-maker"},
                "body": "By the way, good job"
            }
        ]

        self.watcher.run_cycle()

        # Must NOT wake agent because PR is in approved state
        self.assertFalse(self.mock_resumer.resume_conversation.called)

    def test_thread_reopened_transition_detected(self):
        """
        Reopened thread without new comments is detected via isResolved transition (True -> False).
        """
        self.state_mgr.register_pr(pr_number=13, conversation_id="c13", branch="b13")
        # Pre-seed thread as resolved
        self.state_mgr.set_thread_is_resolved(13, "th_reopen_test", True)

        self.mock_github.get_pr_details.return_value = {
            "number": 13, "state": "OPEN", "headRefOid": "sha13",
            "author": {"login": "alex123321-maker"}
        }
        self.mock_github.get_pr_reviews.return_value = []
        self.mock_github.get_pr_comments.return_value = []
        self.mock_github.get_pr_inline_comments.return_value = []
        # Thread is now unresolved!
        self.mock_github.get_pr_review_threads.return_value = [
            {
                "id": "th_reopen_test",
                "isResolved": False,
                "comments": {"nodes": []}
            }
        ]

        self.watcher.run_cycle()

        self.assertTrue(self.mock_resumer.resume_conversation.called)
        self.assertTrue(self.state_mgr.is_event_processed(13, "reopen_th_reopen_test"))

    def test_two_near_simultaneous_events_coalesce_without_parallel_runs(self):
        """Events arriving while agent is already processing are queued, not parallelized."""
        self.state_mgr.register_pr(pr_number=7, conversation_id="conv-7", branch="feat/7")
        self.state_mgr.state["prs"]["7"]["last_head_sha"] = "sha7"
        self.state_mgr.acquire_lock(7)

        self.mock_github.get_pr_details.return_value = {
            "number": 7, "state": "OPEN", "headRefOid": "sha7",
            "author": {"login": "alex123321-maker"}
        }
        self.mock_github.get_pr_reviews.return_value = [
            {
                "id": "rev_mid_flight",
                "state": "REQUEST_CHANGES",
                "author": {"login": "alex123321-maker"},
                "body": "Another quick fix"
            }
        ]
        self.mock_github.get_pr_comments.return_value = []
        self.mock_github.get_pr_inline_comments.return_value = []
        self.mock_github.get_pr_review_threads.return_value = []

        self.watcher.run_cycle()

        self.assertFalse(self.mock_resumer.resume_conversation.called)
        pr = self.state_mgr.get_pr(7)
        self.assertEqual(len(pr["pending_events"]), 1)
        self.assertEqual(pr["pending_events"][0]["id"], "rev_mid_flight")

    def test_from_hook_registration(self):
        """
        BLOCKER 2: Test automatic registration from official Antigravity Hook JSON payload.
        """
        hook_payload = json.dumps({
            "conversationId": "hook-conv-999",
            "workspacePaths": ["/path/to/repo"]
        })

        with patch("sys.stdin", io.StringIO(hook_payload)), \
             patch("sys.stdout", io.StringIO()), \
             patch("tools.review_loop.register.get_current_git_branch", return_value="feat/hook-test"), \
             patch("tools.review_loop.register.GitHubClient.find_pr_for_branch", return_value=99):

            register_from_hook()

            # Verify registered in StateManager
            state = StateManager()
            pr = state.get_pr(99)
            self.assertIsNotNone(pr)
            self.assertEqual(pr["conversation_id"], "hook-conv-999")
            self.assertEqual(pr["branch"], "feat/hook-test")

            # Clean up
            state.unregister_pr(99)

if __name__ == "__main__":
    unittest.main()

"""
tests/unit/test_review_loop.py - Comprehensive unit & integration tests for review loop watcher.
"""
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from tools.review_loop.agent_resumer import AgentResumer
from tools.review_loop.github_client import GitHubClient, GitHubError
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
        self.state_mgr.add_to_allowlist("reviewer_alice")

        # Create brand new StateManager pointing to same file
        reloaded = StateManager(state_file=self.state_file)
        pr = reloaded.get_pr(42)
        self.assertIsNotNone(pr)
        self.assertEqual(pr["conversation_id"], "conv-123")
        self.assertEqual(pr["branch"], "feat/test")
        self.assertEqual(pr["status"], "watching")
        self.assertTrue(reloaded.is_user_allowed("reviewer_alice"))

    def test_event_deduplication(self):
        """Verify events are marked as processed and duplicate events detected."""
        self.state_mgr.register_pr(pr_number=10, conversation_id="c1", branch="b1")
        self.assertFalse(self.state_mgr.is_event_processed(10, "rev_1"))

        self.state_mgr.mark_event_processed(10, "rev_1")
        self.assertTrue(self.state_mgr.is_event_processed(10, "rev_1"))

        # Re-marking does not duplicate
        self.state_mgr.mark_event_processed(10, "rev_1")
        pr = self.state_mgr.get_pr(10)
        self.assertEqual(pr["processed_event_ids"].count("rev_1"), 1)

    def test_allowlist_filtering(self):
        """Verify allowlist enforcement and case-insensitivity."""
        self.state_mgr.add_to_allowlist("AliceTester")
        self.assertTrue(self.state_mgr.is_user_allowed("AliceTester"))
        self.assertTrue(self.state_mgr.is_user_allowed("alicetester"))
        self.assertFalse(self.state_mgr.is_user_allowed("UntrustedHacker"))
        self.assertFalse(self.state_mgr.is_user_allowed(""))

    def test_concurrency_lock_and_lease(self):
        """Verify lock prevents parallel runs and lease timeout reclaims expired lock."""
        self.state_mgr.register_pr(pr_number=5, conversation_id="c", branch="b")
        self.assertFalse(self.state_mgr.is_processing(5))

        # Acquire lock
        self.assertTrue(self.state_mgr.acquire_lock(5, lease_seconds=10.0))
        self.assertTrue(self.state_mgr.is_processing(5))

        # Secondary acquire must fail
        self.assertFalse(self.state_mgr.acquire_lock(5, lease_seconds=10.0))

        # Simulate expired lease
        self.state_mgr.state["prs"]["5"]["processing_started_at"] -= 20.0
        self.assertFalse(self.state_mgr.is_processing(5, lease_seconds=10.0))

        # Should be re-acquirable now
        self.assertTrue(self.state_mgr.acquire_lock(5, lease_seconds=10.0))

        # Normal release
        self.state_mgr.release_lock(5)
        self.assertFalse(self.state_mgr.is_processing(5))

    def test_pending_events_queue(self):
        """Verify events arriving while processing are queued and popped safely."""
        self.state_mgr.register_pr(pr_number=7, conversation_id="c", branch="b")
        ev1 = {"id": "e1", "type": "comment", "body": "first"}
        ev2 = {"id": "e2", "type": "comment", "body": "second"}

        self.state_mgr.queue_pending_event(7, ev1)
        self.state_mgr.queue_pending_event(7, ev2)
        # Duplicate queuing of same ID is avoided
        self.state_mgr.queue_pending_event(7, ev1)

        popped = self.state_mgr.pop_pending_events(7)
        self.assertEqual(len(popped), 2)
        self.assertEqual(popped[0]["id"], "e1")
        self.assertEqual(popped[1]["id"], "e2")

        # After pop, queue is empty
        self.assertEqual(len(self.state_mgr.pop_pending_events(7)), 0)

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
    def test_resume_conversation_success(self, mock_run):
        mock_run.return_value = MagicMock(returncode=0, stdout="OK", stderr="")
        resumer = AgentResumer(agentapi_cmd=["agentapi"])
        success, out = resumer.resume_conversation("test-conv-id", pr_number=123)
        self.assertTrue(success)
        self.assertTrue(mock_run.called)
        cmd = mock_run.call_args[0][0]
        self.assertEqual(cmd[0], "agentapi")
        self.assertEqual(cmd[1], "send-message")
        self.assertEqual(cmd[2], "test-conv-id")

    @patch("time.sleep")
    @patch("subprocess.run")
    def test_resume_conversation_retry_and_backoff(self, mock_run, mock_sleep):
        # Fail 2 times then succeed
        mock_run.side_effect = [
            MagicMock(returncode=1, stdout="", stderr="busy"),
            MagicMock(returncode=1, stdout="", stderr="busy"),
            MagicMock(returncode=0, stdout="Dispatched", stderr="")
        ]
        resumer = AgentResumer(agentapi_cmd=["agentapi"])
        success, out = resumer.resume_conversation("test-conv-id", pr_number=123, max_retries=3)
        self.assertTrue(success)
        self.assertEqual(mock_run.call_count, 3)
        self.assertEqual(mock_sleep.call_count, 2)

class TestReviewWatcher(unittest.TestCase):
    def setUp(self):
        self.test_dir = Path(tempfile.mkdtemp())
        self.state_file = self.test_dir / "state.json"
        self.state_mgr = StateManager(state_file=self.state_file)
        self.state_mgr.add_to_allowlist("alice_reviewer")

        self.mock_github = MagicMock(spec=GitHubClient)
        self.mock_resumer = MagicMock(spec=AgentResumer)
        self.mock_resumer.resume_conversation.return_value = (True, "Dispatched")

        self.watcher = ReviewWatcher(
            github_client=self.mock_github,
            state_manager=self.state_mgr,
            agent_resumer=self.mock_resumer,
            run_once=True
        )

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_request_changes_wakes_agent(self):
        """A new REQUEST_CHANGES review wakes the registered agent."""
        self.state_mgr.register_pr(pr_number=1, conversation_id="conv-1", branch="feat/1")
        self.mock_github.get_pr_details.return_value = {
            "number": 1, "state": "OPEN", "headRefOid": "sha1",
            "author": {"login": "gemini_agent"}
        }
        self.mock_github.get_pr_reviews.return_value = [
            {
                "id": "rev_req_1",
                "state": "REQUEST_CHANGES",
                "author": {"login": "alice_reviewer"},
                "body": "Fix validation logic"
            }
        ]
        self.mock_github.get_pr_comments.return_value = []
        self.mock_github.get_pr_inline_comments.return_value = []
        self.mock_github.get_pr_review_threads.return_value = []

        self.watcher.run_cycle()

        self.assertTrue(self.mock_resumer.resume_conversation.called)
        self.assertTrue(self.state_mgr.is_event_processed(1, "rev_req_1"))
        self.assertTrue(self.state_mgr.is_processing(1))

    def test_inline_comment_wakes_agent(self):
        """A new inline review comment wakes the registered agent."""
        self.state_mgr.register_pr(pr_number=2, conversation_id="conv-2", branch="feat/2")
        self.mock_github.get_pr_details.return_value = {
            "number": 2, "state": "OPEN", "headRefOid": "sha2",
            "author": {"login": "gemini_agent"}
        }
        self.mock_github.get_pr_reviews.return_value = []
        self.mock_github.get_pr_comments.return_value = []
        self.mock_github.get_pr_inline_comments.return_value = [
            {
                "id": 9991,
                "user": {"login": "alice_reviewer"},
                "body": "Null check missing here",
                "path": "main.gd",
                "line": 45
            }
        ]
        self.mock_github.get_pr_review_threads.return_value = []

        self.watcher.run_cycle()

        self.assertTrue(self.mock_resumer.resume_conversation.called)
        self.assertTrue(self.state_mgr.is_event_processed(2, "9991"))

    def test_approve_stops_feedback_loop_without_waking(self):
        """An APPROVED review halts the loop for that PR without waking agent."""
        self.state_mgr.register_pr(pr_number=3, conversation_id="conv-3", branch="feat/3")
        self.mock_github.get_pr_details.return_value = {
            "number": 3, "state": "OPEN", "headRefOid": "sha3",
            "author": {"login": "gemini_agent"}
        }
        self.mock_github.get_pr_reviews.return_value = [
            {
                "id": "rev_app_1",
                "state": "APPROVED",
                "author": {"login": "alice_reviewer"},
                "body": "Looks great!"
            }
        ]
        self.mock_github.get_pr_comments.return_value = []
        self.mock_github.get_pr_inline_comments.return_value = []
        self.mock_github.get_pr_review_threads.return_value = []

        self.watcher.run_cycle()

        self.assertFalse(self.mock_resumer.resume_conversation.called)
        self.assertFalse(self.state_mgr.is_processing(3))
        self.assertTrue(self.state_mgr.is_event_processed(3, "rev_app_1"))

    def test_agent_authored_comment_ignored(self):
        """Comments authored by the PR author (agent) do not create an infinite loop."""
        self.state_mgr.register_pr(pr_number=4, conversation_id="conv-4", branch="feat/4")
        self.mock_github.get_pr_details.return_value = {
            "number": 4, "state": "OPEN", "headRefOid": "sha4",
            "author": {"login": "gemini_agent"}
        }
        self.mock_github.get_pr_reviews.return_value = []
        self.mock_github.get_pr_comments.return_value = [
            {
                "id": "comment_self_1",
                "author": {"login": "gemini_agent"},
                "body": "I have fixed the issue."
            }
        ]
        self.mock_github.get_pr_inline_comments.return_value = []
        self.mock_github.get_pr_review_threads.return_value = []

        self.watcher.run_cycle()

        self.assertFalse(self.mock_resumer.resume_conversation.called)
        self.assertFalse(self.state_mgr.is_event_processed(4, "comment_self_1"))

    def test_non_allowlisted_comment_ignored(self):
        """Comments from users outside allowlist do not wake agent."""
        self.state_mgr.register_pr(pr_number=5, conversation_id="conv-5", branch="feat/5")
        self.mock_github.get_pr_details.return_value = {
            "number": 5, "state": "OPEN", "headRefOid": "sha5",
            "author": {"login": "gemini_agent"}
        }
        self.mock_github.get_pr_reviews.return_value = [
            {
                "id": "rev_untrusted",
                "state": "REQUEST_CHANGES",
                "author": {"login": "untrusted_user"},
                "body": "Random internet suggestion"
            }
        ]
        self.mock_github.get_pr_comments.return_value = []
        self.mock_github.get_pr_inline_comments.return_value = []
        self.mock_github.get_pr_review_threads.return_value = []

        self.watcher.run_cycle()

        self.assertFalse(self.mock_resumer.resume_conversation.called)
        self.assertFalse(self.state_mgr.is_processing(5))

    def test_already_processed_event_does_not_wake_again(self):
        """Events already recorded as processed do not trigger agent resume."""
        self.state_mgr.register_pr(pr_number=6, conversation_id="conv-6", branch="feat/6")
        self.state_mgr.mark_event_processed(6, "rev_already_done")

        self.mock_github.get_pr_details.return_value = {
            "number": 6, "state": "OPEN", "headRefOid": "sha6",
            "author": {"login": "gemini_agent"}
        }
        self.mock_github.get_pr_reviews.return_value = [
            {
                "id": "rev_already_done",
                "state": "REQUEST_CHANGES",
                "author": {"login": "alice_reviewer"},
                "body": "Fix this please"
            }
        ]
        self.mock_github.get_pr_comments.return_value = []
        self.mock_github.get_pr_inline_comments.return_value = []
        self.mock_github.get_pr_review_threads.return_value = []

        self.watcher.run_cycle()

        self.assertFalse(self.mock_resumer.resume_conversation.called)

    def test_two_near_simultaneous_events_coalesce_without_parallel_runs(self):
        """Events arriving while agent is already processing are queued, not parallelized."""
        self.state_mgr.register_pr(pr_number=7, conversation_id="conv-7", branch="feat/7")
        self.state_mgr.acquire_lock(7)  # Agent is actively running

        self.mock_github.get_pr_details.return_value = {
            "number": 7, "state": "OPEN", "headRefOid": "sha7",
            "author": {"login": "gemini_agent"}
        }
        self.mock_github.get_pr_reviews.return_value = [
            {
                "id": "rev_mid_flight",
                "state": "REQUEST_CHANGES",
                "author": {"login": "alice_reviewer"},
                "body": "Another quick fix"
            }
        ]
        self.mock_github.get_pr_comments.return_value = []
        self.mock_github.get_pr_inline_comments.return_value = []
        self.mock_github.get_pr_review_threads.return_value = []

        self.watcher.run_cycle()

        # Resumer must NOT be called because PR is already locked
        self.assertFalse(self.mock_resumer.resume_conversation.called)

        # But event MUST be safely queued in pending_events
        pr = self.state_mgr.get_pr(7)
        self.assertEqual(len(pr["pending_events"]), 1)
        self.assertEqual(pr["pending_events"][0]["id"], "rev_mid_flight")

    def test_deterministic_end_to_end_loop(self):
        """
        Deterministic integration test harness:
        1. PR registered
        2. Review event arrives (REQUEST_CHANGES)
        3. Watcher executes cycle -> agent resumed, lock acquired
        4. Review event arriving mid-flight is queued
        5. Agent pushes commit (head SHA changes) -> lock released
        6. Watcher executes next cycle -> queued event processed
        """
        self.state_mgr.register_pr(pr_number=8, conversation_id="conv-8", branch="feat/8")

        # Step 1 & 2: PR has first REQUEST_CHANGES
        self.mock_github.get_pr_details.return_value = {
            "number": 8, "state": "OPEN", "headRefOid": "sha_initial",
            "author": {"login": "gemini_agent"}
        }
        self.mock_github.get_pr_reviews.return_value = [
            {
                "id": "rev_cycle_1",
                "state": "REQUEST_CHANGES",
                "author": {"login": "alice_reviewer"},
                "body": "First feedback item"
            }
        ]
        self.mock_github.get_pr_comments.return_value = []
        self.mock_github.get_pr_inline_comments.return_value = []
        self.mock_github.get_pr_review_threads.return_value = []

        # Step 3: First watcher cycle
        self.watcher.run_cycle()
        self.assertEqual(self.mock_resumer.resume_conversation.call_count, 1)
        self.assertTrue(self.state_mgr.is_processing(8))

        # Step 4: Mid-flight review event arrives
        self.mock_github.get_pr_comments.return_value = [
            {
                "id": "comment_cycle_2",
                "author": {"login": "alice_reviewer"},
                "body": "Also don't forget this"
            }
        ]
        self.watcher.run_cycle()
        # No extra resume call while locked
        self.assertEqual(self.mock_resumer.resume_conversation.call_count, 1)
        # Event queued
        pr = self.state_mgr.get_pr(8)
        self.assertEqual(len(pr["pending_events"]), 1)

        # Step 5: Agent finishes and pushes commit (head SHA changes)
        self.mock_github.get_pr_details.return_value["headRefOid"] = "sha_updated"
        self.watcher.run_cycle()

        # Step 6: Watcher detected head SHA change, processed pending events, and triggered next cycle
        self.assertEqual(self.mock_resumer.resume_conversation.call_count, 2)
        pr_after = self.state_mgr.get_pr(8)
        self.assertEqual(len(pr_after["pending_events"]), 0)
        self.assertEqual(pr_after["last_head_sha"], "sha_updated")

if __name__ == "__main__":
    unittest.main()

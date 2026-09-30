"""Codex routing, delivery and completion regressions; no real agent or GitHub calls."""
import io
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from tools.review_loop.agent_target import resolve_agent_target
from tools.review_loop.codex_resumer import CodexResumer
from tools.review_loop.create_pr import create_and_register_pr
from tools.review_loop.github_client import GitHubClient
from tools.review_loop.state_manager import StateManager
from tools.review_loop.watcher import ReviewWatcher

THREAD = "11111111-1111-4111-8111-111111111111"


class CodexReviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.state = StateManager(state_file=self.root / ".review_loop" / "state.json")
        self.state.add_to_allowlist("reviewer")
        self.github = MagicMock(spec=GitHubClient)
        self.github.get_pr_details.return_value = {"state": "OPEN", "headRefOid": "head-a"}
        self.github.get_pr_reviews.return_value = []
        self.github.get_pr_comments.return_value = [
            {"id": "review-1", "author": {"login": "reviewer"}, "body": "Fix the defect."}
        ]
        self.github.get_pr_inline_comments.return_value = []
        self.github.get_pr_review_threads.return_value = []
        self.codex = MagicMock(spec=CodexResumer)
        self.codex.resume_conversation.return_value = (True, "queued", None)
        self.antigravity = MagicMock()
        self.watcher = ReviewWatcher(
            github_client=self.github, state_manager=self.state,
            agent_resumer=self.antigravity, codex_resumer=self.codex,
        )

    def register_codex(self):
        self.state.register_pr(42, THREAD, "codex/fix", agent_provider="codex")

    def test_persistent_provider_and_legacy_default(self):
        self.register_codex()
        reloaded = StateManager(state_file=self.state.state_file)
        self.assertEqual(reloaded.get_pr(42)["agent_provider"], "codex")
        self.assertEqual(reloaded.get_branch_target("codex/fix"), (THREAD, "codex"))
        self.state.register_pr(43, "agy-chat", "feat/43")
        self.assertEqual(self.state.get_branch_target("feat/43"), ("agy-chat", "antigravity"))

    def test_environment_resolution_and_no_cross_provider_fallback(self):
        with patch.dict(os.environ, {"CODEX_THREAD_ID": THREAD}, clear=True):
            self.assertEqual(resolve_agent_target(None, None, self.state, "codex/fix"), (THREAD, "codex"))
        self.state.remember_branch_conversation("codex/fix", "agy-chat")
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(ValueError):
                resolve_agent_target(None, "codex", self.state, "codex/fix")

    def test_ambiguous_environment_requires_provider(self):
        with patch.dict(os.environ, {"CODEX_THREAD_ID": THREAD, "ANTIGRAVITY_CONVERSATION_ID": "agy"}, clear=True):
            with self.assertRaises(ValueError):
                resolve_agent_target(None, None, self.state, "codex/fix")

    def test_codex_rejects_name_and_unknown_provider(self):
        for thread, provider in [("most-recent", "codex"), (THREAD, "unknown")]:
            with self.assertRaises(ValueError):
                self.state.register_pr(42, thread, "codex/fix", agent_provider=provider)

    def test_active_mapping_cannot_be_reassigned(self):
        self.register_codex()
        self.state.acquire_lock(42)
        with self.assertRaises(ValueError):
            self.state.register_pr(42, "agy-chat", "codex/fix")
        self.assertEqual(self.state.get_pr(42)["conversation_id"], THREAD)

    def test_antigravity_hook_does_not_steal_codex_branch(self):
        from tools.review_loop.register import register_from_hook
        self.register_codex()
        with patch("tools.review_loop.register.StateManager", return_value=self.state), patch(
            "tools.review_loop.register.get_current_git_branch", return_value="codex/fix"
        ), patch("tools.review_loop.register.GitHubClient") as client, patch(
            "sys.stdin", io.StringIO('{"conversationId":"agy-chat"}')
        ), patch("sys.stdout", io.StringIO()):
            register_from_hook()
        client.assert_not_called()
        self.assertEqual(self.state.get_branch_target("codex/fix"), (THREAD, "codex"))

    def test_hook_write_cannot_overwrite_concurrent_codex_registration(self):
        # Simulate a hook that observed the branch before Codex registered it.
        stale_hook = StateManager(state_file=self.state.state_file)
        self.assertIsNone(stale_hook.get_branch_target("codex/fix"))
        self.register_codex()
        with self.assertRaises(ValueError):
            stale_hook.remember_branch_conversation("codex/fix", "agy", preserve_provider=True)
        with self.assertRaises(ValueError):
            stale_hook.register_pr(42, "agy", "codex/fix", preserve_provider=True)
        self.assertEqual(self.state.get_pr(42)["agent_provider"], "codex")

    def test_pr_wrapper_remembers_codex_provider(self):
        self.github.find_pr_for_branch.return_value = 42
        with patch.dict(os.environ, {}, clear=True):
            ok, number = create_and_register_pr(
                [], conversation_id=THREAD, branch="codex/fix", github=self.github,
                state=self.state, ensure_watcher=False, agent_provider="codex",
            )
        self.assertTrue(ok)
        self.assertEqual(number, 42)
        self.assertEqual(self.state.get_pr(42)["agent_provider"], "codex")

    def test_reconcile_keeps_provider(self):
        self.state.remember_branch_conversation("codex/fix", THREAD, agent_provider="codex")
        self.github.get_open_prs.return_value = [{"number": 42, "headRefName": "codex/fix"}]
        self.watcher.reconcile_registrations()
        self.assertEqual(self.state.get_pr(42)["agent_provider"], "codex")

    def test_routes_codex_and_waits_without_duplicate(self):
        self.register_codex()
        self.watcher.process_registered_pr(42)
        self.assertEqual(self.state.get_pr(42)["dispatch_mode"], "codex")
        self.watcher.process_registered_pr(42)
        self.antigravity.resume_conversation.assert_not_called()
        self.codex.resume_conversation.assert_called_once()
        self.assertFalse(self.state.is_event_processed(42, "review-1"))

    def test_new_feedback_waits_for_completion(self):
        self.test_routes_codex_and_waits_without_duplicate()
        self.github.get_pr_comments.return_value.append(
            {"id": "review-2", "author": {"login": "reviewer"}, "body": "Another defect."}
        )
        self.watcher.process_registered_pr(42)
        self.assertEqual([e["id"] for e in self.state.get_pr(42)["pending_events"]], ["review-2"])
        self.codex.resume_conversation.assert_called_once()

    def test_no_change_completion_is_run_scoped(self):
        self.test_routes_codex_and_waits_without_duplicate()
        run = self.state.get_current_run_id(42)
        with self.assertRaises(ValueError):
            self.state.complete_codex_run(42, run - 1)
        self.state.complete_codex_run(42, run)
        self.watcher.process_registered_pr(42)
        self.assertTrue(self.state.is_event_processed(42, "review-1"))
        self.assertEqual(self.state.get_pr(42)["status"], "watching")

    def test_changed_head_alone_does_not_finish_queued_codex_run(self):
        self.test_routes_codex_and_waits_without_duplicate()
        self.github.get_pr_details.return_value["headRefOid"] = "head-b"
        self.watcher.process_registered_pr(42)
        self.assertEqual(self.state.get_pr(42)["status"], "processing")

    def test_uncertain_delivery_never_auto_retries(self):
        self.register_codex()
        self.codex.resume_conversation.return_value = (False, "Delivery uncertain: timeout", None)
        self.watcher.process_registered_pr(42)
        self.watcher.process_registered_pr(42)
        self.assertEqual(self.state.get_pr(42)["status"], "error")
        self.assertEqual(len(self.state.get_pr(42)["pending_events"]), 1)
        self.codex.resume_conversation.assert_called_once()

    def test_codex_timeout_preserves_feedback_without_resubmission(self):
        self.test_routes_codex_and_waits_without_duplicate()
        self.state.update_pr_fields(42, processing_started_at=time.time() - 4000)
        self.watcher.process_registered_pr(42)
        self.assertEqual(self.state.get_pr(42)["status"], "error")
        self.assertEqual(len(self.state.get_pr(42)["pending_events"]), 1)
        self.codex.resume_conversation.assert_called_once()

    def test_design_decision_completion(self):
        self.test_routes_codex_and_waits_without_duplicate()
        self.state.complete_codex_run(42, self.state.get_current_run_id(42), "awaiting_design_decision")
        self.watcher.process_registered_pr(42)
        self.assertEqual(self.state.get_pr(42)["status"], "awaiting_design_decision")
        self.assertEqual(len(self.state.get_pr(42)["pending_events"]), 1)

    def test_long_unicode_feedback_is_spooled_losslessly(self):
        body = 'Текст " & $(must_not_run) ' * 4000
        resumer = CodexResumer(cwd=self.root, command=["codex.exe"])
        with patch("tools.review_loop.codex_resumer.subprocess.run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, "Queued", "")
            ok, _, pid = resumer.resume_conversation(THREAD, 42, run_id=3, feedback_events=[{"id":"a", "body":body}])
        self.assertTrue(ok)
        self.assertIsNone(pid)
        command = run.call_args.args[0]
        self.assertEqual(command[:4], ["codex.exe", "queue", "--thread", THREAD])
        self.assertLess(len(command[-1]), 4000)
        self.assertNotIn("--dangerously-bypass-approvals-and-sandbox", command)
        self.assertNotIn("--model", command)
        self.assertFalse(run.call_args.kwargs.get("shell", False))
        payloads = list((self.root / ".review_loop" / "feedback").glob("codex_*.txt"))
        self.assertEqual(len(payloads), 1)
        content = payloads[0].read_text(encoding="utf-8")
        self.assertIn(body, content)
        self.assertIn("--run-id 3", content)
        self.assertIn("AGENTS.md", content)

    def test_transport_timeout_does_not_retry(self):
        resumer = CodexResumer(cwd=self.root, command=["codex.exe"])
        with patch("tools.review_loop.codex_resumer.subprocess.run", side_effect=subprocess.TimeoutExpired("codex", 60)) as run:
            ok, error, _ = resumer.resume_conversation(THREAD, 42)
        self.assertFalse(ok)
        self.assertIn("uncertain", error.lower())
        self.assertEqual(run.call_count, 1)

    def test_batch_shim_is_rejected_without_dispatch(self):
        resumer = CodexResumer(cwd=self.root, command=["codex.cmd"])
        with patch("tools.review_loop.codex_resumer.subprocess.run") as run:
            ok, _, _ = resumer.resume_conversation(THREAD, 42)
        self.assertFalse(ok)
        run.assert_not_called()

    def test_explicit_antigravity_id_is_not_changed_by_codex_environment(self):
        with patch.dict(os.environ, {"CODEX_THREAD_ID": THREAD}, clear=True):
            self.assertEqual(
                resolve_agent_target("agy-chat", None, self.state, "codex/fix"),
                ("agy-chat", "antigravity"),
            )

    def test_old_completion_cannot_finish_newly_acquired_run(self):
        self.test_no_change_completion_is_run_scoped()
        old_run = self.state.get_current_run_id(42)
        self.assertTrue(self.state.acquire_lock(42))
        self.state.set_in_flight_events(42, [{"id": "new-review", "body": "Fix another defect"}])
        with self.assertRaises(ValueError):
            self.state.complete_codex_run(42, old_run)
        self.assertFalse(self.state.finish_codex_run(42, old_run))
        self.watcher.process_registered_pr(42)
        self.assertEqual(self.state.get_pr(42)["status"], "processing")
        self.assertFalse(self.state.is_event_processed(42, "new-review"))

    def test_acknowledgement_wins_race_with_timeout_snapshot(self):
        self.test_routes_codex_and_waits_without_duplicate()
        run_id = self.state.get_current_run_id(42)
        self.state.complete_codex_run(42, run_id)
        self.assertTrue(self.state.finish_codex_run(42, run_id, error="stale timeout"))
        self.assertEqual(self.state.get_pr(42)["status"], "watching")
        self.assertTrue(self.state.is_event_processed(42, "review-1"))
        self.assertEqual(self.state.get_pr(42)["last_dispatch_error"], "")

    def test_expired_lease_does_not_dispatch_second_codex_turn(self):
        self.test_routes_codex_and_waits_without_duplicate()
        self.state.update_pr_fields(42, processing_started_at=time.time() - 4000)
        self.assertTrue(self.state.is_processing(42))
        self.assertFalse(self.state.acquire_lock(42))

    def test_wrong_checkout_branch_does_not_send_feedback(self):
        with patch("tools.review_loop.codex_resumer.subprocess.run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, "another-branch\n", "")
            ok, error, _ = CodexResumer(cwd=self.root, command=["codex.exe"]).resume_conversation(
                THREAD, 42, expected_branch="codex/fix"
            )
        self.assertFalse(ok)
        self.assertIn("registered branch", error)
        self.assertEqual(run.call_count, 1)
        self.assertEqual(run.call_args.args[0], ["git", "branch", "--show-current"])

    def test_codex_ensure_does_not_install_antigravity(self):
        from tools.review_loop.install import ensure_service
        with patch("tools.review_loop.persistent_service.manage", return_value=True) as start, patch(
            "tools.review_loop.install.install_service"
        ) as install:
            self.assertTrue(ensure_service(agent_provider="codex"))
        self.assertEqual(start.call_args.args[0], "ensure")
        self.assertTrue(start.call_args.args[1].endswith("Codex"))
        install.assert_not_called()

    def test_provider_workers_do_not_touch_each_others_prs(self):
        self.register_codex()
        self.watcher.agent_provider = "antigravity"
        self.watcher.process_registered_pr(42)
        self.github.get_pr_details.assert_not_called()
        self.codex.resume_conversation.assert_not_called()
        self.state.register_pr(43, "agy-chat", "feat/43")
        self.watcher.agent_provider = "codex"
        self.watcher.process_registered_pr(43)
        self.github.get_pr_details.assert_not_called()
        self.antigravity.resume_conversation.assert_not_called()

    def test_persistent_task_has_hidden_startup_and_recovery_without_shell(self):
        import xml.etree.ElementTree as ET
        from tools.review_loop.persistent_service import build_task_xml
        xml = build_task_xml(Path("C:/Python & Tools/pythonw.exe"),
                             Path("C:/Repository with spaces/service_entry.py"),
                             Path("C:/Repository with spaces/service.json"))
        root = ET.fromstring(xml)
        ns = {"t": "http://schemas.microsoft.com/windows/2004/02/mit/task"}
        def value(path):
            return root.find(path, ns).text
        self.assertEqual(value("t:Settings/t:ExecutionTimeLimit"), "PT0S")
        self.assertEqual(value("t:Settings/t:RestartOnFailure/t:Interval"), "PT1M")
        self.assertEqual(value("t:Settings/t:MultipleInstancesPolicy"), "IgnoreNew")
        self.assertEqual(value("t:Settings/t:Hidden"), "true")
        self.assertIsNotNone(root.find("t:Triggers/t:LogonTrigger", ns))
        self.assertEqual(value("t:Triggers/t:TimeTrigger/t:Repetition/t:Interval"), "PT1M")
        self.assertEqual(value("t:Actions/t:Exec/t:Command"), "C:\\Python & Tools\\pythonw.exe" if os.name == "nt" else "C:/Python & Tools/pythonw.exe")
        self.assertIn("--config", value("t:Actions/t:Exec/t:Arguments"))

    def test_service_stop_waits_for_process_exit_before_allowing_restart(self):
        from tools.review_loop.persistent_service import manage
        with patch("tools.review_loop.persistent_service.sys.platform", "win32"), patch(
            "tools.review_loop.persistent_service._task",
            return_value=subprocess.CompletedProcess([], 0, "", ""),
        ), patch("tools.review_loop.persistent_service.current_pid", side_effect=[123, 0, 0]) as pid, patch(
            "tools.review_loop.persistent_service.time.sleep"
        ) as sleep:
            self.assertTrue(manage("stop", "TestWatcher"))
        self.assertEqual(pid.call_count, 3)
        sleep.assert_called_once_with(0.25)

    def test_github_poll_has_timeout_and_no_console_window(self):
        client = GitHubClient(gh_path="gh", cwd=self.root)
        with patch("tools.review_loop.github_client.subprocess.run",
                   return_value=subprocess.CompletedProcess([], 0, "[]", "")) as run:
            client.run_gh(["pr", "list"])
        self.assertEqual(run.call_args.kwargs["timeout"], 30)
        expected = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
        self.assertEqual(run.call_args.kwargs["creationflags"], expected)

    def test_real_subprocess_delivery_and_completion_with_fake_cli(self):
        # Exercise argv quoting, Unicode paths, spooling and state transitions
        # with a real child process, without sending to a real Codex chat.
        folder = self.root / "CLI с пробелами"
        folder.mkdir()
        fake = folder / "fake_codex.py"
        fake.write_text(
            "import hashlib, json, pathlib, sys\n"
            "args = sys.argv[1:]\n"
            "assert args[0] == 'queue' and args[1] == '--thread' and args[3] == '--message'\n"
            "message = args[4]\n"
            "tail = message.split('UTF-8 task file before acting: ', 1)[1]\n"
            "path, _ = json.JSONDecoder().raw_decode(tail)\n"
            "payload = pathlib.Path(path).read_bytes()\n"
            "assert hashlib.sha256(payload).hexdigest() in message\n"
            "pathlib.Path(__file__).with_suffix('.json').write_text(json.dumps(args), encoding='utf-8')\n"
            "print('Queued by fake CLI')\n",
            encoding="utf-8",
        )
        subprocess.run(["git", "init", "-b", "codex/fix", str(self.root)], check=True, capture_output=True)
        body = 'Длинное замечание " & $(literal) \n' * 5000 + "Конец."
        self.github.get_pr_comments.return_value[0]["body"] = body
        self.watcher.codex_resumer = CodexResumer(cwd=self.root, command=[sys.executable, str(fake)])
        self.register_codex()
        self.watcher.process_registered_pr(42)
        self.assertEqual(self.state.get_pr(42)["status"], "processing")
        args = json.loads(fake.with_suffix(".json").read_text(encoding="utf-8"))
        self.assertEqual(args[2], THREAD)
        self.assertLess(len(args[-1]), 4000)
        payload = next((self.root / ".review_loop" / "feedback").glob("codex_*.txt"))
        self.assertTrue(body in payload.read_text(encoding="utf-8"), "Full Unicode review body must survive delivery")
        from tools.review_loop.complete_run import mark_run_completed
        reloaded = StateManager(state_file=self.state.state_file)
        mark_run_completed(42, state_manager=reloaded, run_id=reloaded.get_current_run_id(42))
        self.watcher.process_registered_pr(42)
        self.assertEqual(self.state.get_pr(42)["status"], "watching")
        self.assertTrue(self.state.is_event_processed(42, "review-1"))


if __name__ == "__main__":
    unittest.main()

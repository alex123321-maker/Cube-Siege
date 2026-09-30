"""Create a GitHub PR and atomically register it with the review loop.

Use this wrapper instead of calling ``gh pr create`` directly. It remembers the
agent provider and conversation before the PR exists, verifies that the watcher is
available, and registers either a newly-created or already-open PR.
"""
import argparse
import re
import sys
import time
from pathlib import Path
from typing import List, Optional, Tuple

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tools.review_loop.config import REPO_ROOT
from tools.review_loop.agent_target import AGENT_PROVIDERS, resolve_agent_target
from tools.review_loop.github_client import GitHubClient, GitHubError
from tools.review_loop.install import ensure_service
from tools.review_loop.register import get_current_git_branch
from tools.review_loop.state_manager import StateManager

_PR_URL_PATTERN = re.compile(r"/pull/(\d+)(?:\D|$)")
_DEFAULT_BRANCHES = {"", "main", "master", "develop", "HEAD"}


def _extract_pr_number(output: str) -> Optional[int]:
    match = _PR_URL_PATTERN.search(output or "")
    return int(match.group(1)) if match else None


def create_and_register_pr(
    gh_args: List[str],
    conversation_id: Optional[str] = None,
    branch: Optional[str] = None,
    github: Optional[GitHubClient] = None,
    state: Optional[StateManager] = None,
    ensure_watcher: bool = True,
    agent_provider: Optional[str] = None,
) -> Tuple[bool, Optional[int]]:
    """Create/reuse the current branch PR and persist its GUI conversation."""
    resolved_branch = branch or get_current_git_branch()
    if resolved_branch in _DEFAULT_BRANCHES:
        print("[ERROR] Create a task branch before opening a Pull Request.")
        return False, None

    state_mgr = state or StateManager()
    try:
        resolved_conversation, resolved_provider = resolve_agent_target(
            conversation_id, agent_provider, state_mgr, resolved_branch
        )
        state_mgr.remember_branch_conversation(
            resolved_branch, resolved_conversation, agent_provider=resolved_provider
        )
    except ValueError as exc:
        print(f"[ERROR] {exc}")
        return False, None

    # Persist this before touching GitHub so a hook/watcher can reconcile a PR
    # even if the CLI is interrupted immediately after creation.
    watcher_ready = not ensure_watcher or (
        ensure_service(agent_provider="codex") if resolved_provider == "codex" else ensure_service()
    )
    if not watcher_ready:
        print("[ERROR] Review watcher is unavailable; the PR was not created.")
        return False, None

    client = github or GitHubClient(cwd=REPO_ROOT)
    try:
        pr_number = client.find_pr_for_branch(resolved_branch)
        if pr_number is None:
            args = ["pr", "create"] + list(gh_args)
            rc, stdout, stderr = client.run_gh(args, timeout=120)
            output = "\n".join(part for part in (stdout, stderr) if part)
            if rc != 0:
                print(f"[ERROR] gh pr create failed: {output}")
                return False, None
            if stdout:
                print(stdout)
            pr_number = _extract_pr_number(output)
            if pr_number is None:
                # GitHub may return localized/non-URL output; allow a short
                # eventual-consistency window before giving up.
                for _ in range(5):
                    time.sleep(1)
                    pr_number = client.find_pr_for_branch(resolved_branch)
                    if pr_number is not None:
                        break
        else:
            print(f"[INFO] Reusing open PR #{pr_number} for '{resolved_branch}'.")
    except GitHubError as exc:
        print(f"[ERROR] Could not create or locate Pull Request: {exc}")
        return False, None

    if pr_number is None:
        print("[ERROR] Pull Request was created but its number could not be resolved.")
        return False, None

    state_mgr.register_pr(pr_number, resolved_conversation, resolved_branch, agent_provider=resolved_provider)
    print(
        f"[SUCCESS] PR #{pr_number} is attached to {resolved_provider} conversation "
        f"'{resolved_conversation}' and will be watched automatically."
    )
    return True, pr_number


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create a PR and attach it to the autonomous review loop."
    )
    parser.add_argument("--conversation-id", "--thread-id", help="Exact conversation ID (Codex: thread UUID).")
    parser.add_argument("--agent", choices=AGENT_PROVIDERS, help="Agent provider; otherwise inferred from its environment or branch mapping.")
    parser.add_argument("--branch", help="Current task branch (normally auto-detected).")
    parser.add_argument(
        "gh_args", nargs=argparse.REMAINDER,
        help="Arguments passed to gh pr create; place them after --.",
    )
    args = parser.parse_args()
    gh_args = args.gh_args[1:] if args.gh_args[:1] == ["--"] else args.gh_args
    success, _ = create_and_register_pr(
        gh_args, conversation_id=args.conversation_id, branch=args.branch, agent_provider=args.agent
    )
    raise SystemExit(0 if success else 1)


if __name__ == "__main__":
    main()

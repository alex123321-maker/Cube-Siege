"""
Create (or reuse) the current branch's Pull Request and register it with the
autonomous review loop before reporting success.

Usage:
    python tools/review_loop/create_pr.py -- --title "..." --body "..."

Wrapper options such as --conversation-id and --branch must appear before the
separator. Everything after ``--`` is forwarded to ``gh pr create``.
"""
import argparse
import os
import re
import sys
import time
from pathlib import Path
from typing import Callable, List, Optional

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tools.review_loop.github_client import GitHubClient, GitHubError
from tools.review_loop.install import ensure_service
from tools.review_loop.register import get_current_git_branch
from tools.review_loop.state_manager import StateManager


def _pr_number_from_output(output: str) -> Optional[int]:
    match = re.search(r"/pull/(\d+)(?:\s|$)", str(output or ""))
    return int(match.group(1)) if match else None


def create_and_register_pr(
    gh_args: List[str],
    conversation_id: Optional[str] = None,
    branch: Optional[str] = None,
    github: Optional[GitHubClient] = None,
    state_manager: Optional[StateManager] = None,
    ensure_watcher: Callable[[], bool] = ensure_service,
) -> bool:
    """Create/reuse a PR, register it, and ensure the watcher is healthy."""
    state = state_manager or StateManager()
    client = github or GitHubClient(cwd=_REPO_ROOT)
    resolved_branch = (branch or get_current_git_branch()).strip()
    if not resolved_branch or resolved_branch in (
        "main", "master", "develop", "HEAD"
    ):
        print("[ERROR] Create PR from a non-default feature branch.")
        return False

    resolved_conversation = (
        conversation_id
        or os.environ.get("ANTIGRAVITY_CONVERSATION_ID")
        or state.get_branch_conversation(resolved_branch)
    )
    resolved_conversation = str(resolved_conversation or "").strip()
    if not resolved_conversation:
        print(
            "[ERROR] No agent conversation is known for branch "
            f"'{resolved_branch}'. Run this command from the active Antigravity "
            "conversation or pass --conversation-id explicitly."
        )
        return False

    if not ensure_watcher():
        print(
            "[ERROR] The review watcher could not be installed or started. "
            "The Pull Request was not created."
        )
        return False

    try:
        pr_number = client.find_pr_for_branch(resolved_branch)
        create_output = ""
        if pr_number is None:
            forwarded = list(gh_args)
            if forwarded and forwarded[0] == "--":
                forwarded = forwarded[1:]
            rc, stdout, stderr = client.run_gh(
                ["pr", "create", *forwarded], timeout=120
            )
            create_output = stdout
            if rc != 0:
                print(f"[ERROR] gh pr create failed: {stderr or stdout}")
                return False

            pr_number = _pr_number_from_output(stdout)
            for _ in range(5):
                if pr_number is not None:
                    break
                pr_number = client.find_pr_for_branch(resolved_branch)
                if pr_number is None:
                    time.sleep(1)

        if pr_number is None:
            print(
                "[ERROR] GitHub accepted the command, but the new PR number "
                "could not be resolved. Registration did not complete."
            )
            return False

        state.remember_branch_conversation(
            resolved_branch, resolved_conversation
        )
        state.register_pr(
            pr_number, resolved_conversation, resolved_branch
        )
        if create_output:
            print(create_output)
        print(
            f"[SUCCESS] PR #{pr_number} is registered to conversation "
            f"'{resolved_conversation}', and the watcher is running."
        )
        return True
    except GitHubError as exc:
        print(f"[ERROR] GitHub operation failed: {exc}")
        return False
    except Exception as exc:
        print(f"[ERROR] PR registration failed: {exc}")
        return False


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create a PR and require successful review-loop registration."
    )
    parser.add_argument(
        "--conversation-id",
        help="Agent conversation ID (normally learned automatically by the hook).",
    )
    parser.add_argument(
        "--branch", help="Branch override (default: current branch)."
    )
    parser.add_argument(
        "gh_args",
        nargs=argparse.REMAINDER,
        help="Arguments forwarded to gh pr create after --.",
    )
    args = parser.parse_args()
    success = create_and_register_pr(
        args.gh_args,
        conversation_id=args.conversation_id,
        branch=args.branch,
    )
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()

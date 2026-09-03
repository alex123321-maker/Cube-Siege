"""
tools/review_loop/register.py - Automatic PR ↔ Antigravity conversation registration CLI.

Associates an open Pull Request with the current Antigravity conversation/session ID.
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path
from typing import Optional

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tools.review_loop.github_client import GitHubClient, GitHubError
from tools.review_loop.state_manager import StateManager

def get_current_git_branch() -> str:
    """Get current active git branch name."""
    res = subprocess.run(
        ["git", "branch", "--show-current"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace"
    )
    if res.returncode == 0 and res.stdout.strip():
        return res.stdout.strip()

    # Fallback to rev-parse
    res = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace"
    )
    if res.returncode == 0 and res.stdout.strip():
        return res.stdout.strip()
    return ""

def get_current_conversation_id() -> Optional[str]:
    """Retrieve active Antigravity conversation ID from environment."""
    return os.environ.get("ANTIGRAVITY_CONVERSATION_ID")

def register(
    pr_number: Optional[int] = None,
    conversation_id: Optional[str] = None,
    branch: Optional[str] = None
) -> bool:
    state_mgr = StateManager()
    github = GitHubClient()

    # 1. Resolve branch
    resolved_branch = branch or get_current_git_branch()
    if not resolved_branch:
        print("[ERROR] Could not determine current git branch.")
        return False

    # 2. Resolve PR number
    resolved_pr = pr_number
    if resolved_pr is None:
        try:
            resolved_pr = github.find_pr_for_branch(resolved_branch)
        except GitHubError as e:
            print(f"[ERROR] Failed to query GitHub for open PR on branch '{resolved_branch}': {e}")
            return False

    if resolved_pr is None:
        print(f"[ERROR] No open Pull Request found for branch '{resolved_branch}'. Create a PR first or specify --pr <number>.")
        return False

    # 3. Resolve conversation ID
    resolved_conv = conversation_id or get_current_conversation_id()
    if not resolved_conv:
        print("[ERROR] No Antigravity conversation ID found in environment (ANTIGRAVITY_CONVERSATION_ID).")
        print("Please provide --conversation-id explicitly.")
        return False

    # 4. Save registration
    state_mgr.register_pr(resolved_pr, resolved_conv, resolved_branch)
    print(f"[SUCCESS] Registered PR #{resolved_pr} (branch: '{resolved_branch}') to Antigravity conversation '{resolved_conv}'.")
    return True

def list_registered() -> None:
    state_mgr = StateManager()
    prs = state_mgr.get_registered_prs()
    allowlist = state_mgr.get_allowlist()

    print("\n--- Review Loop Allowlist ---")
    if allowlist:
        print(", ".join(allowlist))
    else:
        print("(empty - will auto-populate with repository owner)")

    print("\n--- Registered Pull Requests ---")
    if not prs:
        print("No PRs currently registered.")
        return

    for pr_num, entry in prs.items():
        status = entry.get("status", "unknown")
        conv = entry.get("conversation_id", "")
        branch = entry.get("branch", "")
        events_cnt = len(entry.get("processed_event_ids", []))
        pending_cnt = len(entry.get("pending_events", []))
        print(f"PR #{pr_num:4s} | status: {status:<10s} | branch: {branch:<30s} | conversation: {conv} | processed: {events_cnt} | pending: {pending_cnt}")

def main() -> None:
    parser = argparse.ArgumentParser(description="Register a PR with Antigravity review feedback loop.")
    parser.add_argument("--pr", type=int, help="Pull Request number (default: auto-detect from current branch).")
    parser.add_argument("--conversation-id", help="Antigravity conversation ID (default: $ANTIGRAVITY_CONVERSATION_ID).")
    parser.add_argument("--branch", help="Git branch name (default: current git branch).")
    parser.add_argument("--list", action="store_true", help="List all registered PRs and allowlist.")
    parser.add_argument("--unregister", type=int, help="Unregister a PR from review loop.")
    parser.add_argument("--allow-user", help="Add a username to reviewer allowlist.")
    args = parser.parse_args()

    state_mgr = StateManager()

    if args.allow_user:
        state_mgr.add_to_allowlist(args.allow_user)
        print(f"[SUCCESS] Added '{args.allow_user}' to review allowlist.")
        return

    if args.unregister:
        if state_mgr.unregister_pr(args.unregister):
            print(f"[SUCCESS] Unregistered PR #{args.unregister}.")
        else:
            print(f"[WARN] PR #{args.unregister} was not registered.")
        return

    if args.list:
        list_registered()
        return

    success = register(args.pr, args.conversation_id, args.branch)
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()

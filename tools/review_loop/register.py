"""
tools/review_loop/register.py - Automatic PR ↔ Antigravity conversation registration CLI.

Associates an open Pull Request with the Antigravity conversation/session ID.
Supports official Antigravity Hook payload via stdin (`--from-hook`).
Correctly handles PostToolUse (output: {}) and Stop (output: {"decision":"stop"}) contracts.
"""
import argparse
import json
import os
import subprocess
import sys
import time
import traceback
from pathlib import Path
from typing import Optional

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tools.review_loop.config import DEFAULT_HOOK_LOG_FILE, REPO_ROOT
from tools.review_loop.github_client import GitHubClient, GitHubError
from tools.review_loop.state_manager import StateManager


def get_current_git_branch() -> str:
    """Get current active git branch name."""
    res = subprocess.run(
        ["git", "branch", "--show-current"],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if res.returncode == 0 and res.stdout.strip():
        return res.stdout.strip()

    res = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if res.returncode == 0 and res.stdout.strip():
        return res.stdout.strip()
    return ""


def get_current_conversation_id() -> Optional[str]:
    """Retrieve active Antigravity conversation ID from environment if set."""
    return os.environ.get("ANTIGRAVITY_CONVERSATION_ID")


def log_hook_event(message: str) -> None:
    """Persist hook diagnostics without changing the hook output contract."""
    try:
        DEFAULT_HOOK_LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(DEFAULT_HOOK_LOG_FILE, "a", encoding="utf-8") as log_file:
            log_file.write(
                f"{time.strftime('%Y-%m-%d %H:%M:%S')} {message.rstrip()}\n"
            )
    except Exception:
        pass


def register_from_hook(is_stop: bool = False) -> None:
    """
    Handle official Antigravity Hook invocation.

    Reads JSON payload from stdin, extracts conversationId, resolves PR,
    and saves mapping to state.json.

    Output contract:
        PostToolUse: {} (empty JSON object)
        Stop: {"decision": "stop"} to allow normal termination
    """
    try:
        payload_text = sys.stdin.read()
        if not payload_text.strip():
            log_hook_event("Hook received an empty payload; registration skipped.")
        else:
            data = json.loads(payload_text)
            conv_id = str(data.get("conversationId") or "").strip()
            if not conv_id:
                log_hook_event(
                    "Hook payload has no conversationId; registration skipped."
                )
            else:
                branch = get_current_git_branch()
                if branch and branch not in (
                    "main", "master", "develop", "HEAD"
                ):
                    state_mgr = StateManager()
                    state_mgr.remember_branch_conversation(branch, conv_id)
                    github = GitHubClient(cwd=REPO_ROOT)
                    pr_number = github.find_pr_for_branch(branch)
                    if pr_number:
                        state_mgr.register_pr(pr_number, conv_id, branch)
                        log_hook_event(
                            f"Registered PR #{pr_number} on branch '{branch}' "
                            f"to conversation '{conv_id}'."
                        )
                    else:
                        log_hook_event(
                            f"Remembered conversation '{conv_id}' for branch "
                            f"'{branch}'; no open PR exists yet."
                        )
                else:
                    log_hook_event(
                        f"Branch '{branch or '<unknown>'}' is not eligible for "
                        "review-loop registration."
                    )
    except Exception as exc:
        log_hook_event(
            f"Hook registration failed: {exc}\n{traceback.format_exc().rstrip()}"
        )
    finally:
        # Output the correct contract response
        if is_stop:
            sys.stdout.write('{"decision": "stop"}\n')
        else:
            sys.stdout.write("{}\n")
        sys.stdout.flush()


def register(
    pr_number: Optional[int] = None,
    conversation_id: Optional[str] = None,
    branch: Optional[str] = None,
) -> bool:
    state_mgr = StateManager()
    github = GitHubClient(cwd=REPO_ROOT)

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
            print(
                f"[ERROR] Failed to query GitHub for open PR on branch "
                f"'{resolved_branch}': {e}"
            )
            return False

    if resolved_pr is None:
        print(
            f"[ERROR] No open Pull Request found for branch "
            f"'{resolved_branch}'. Create a PR first or specify --pr <number>."
        )
        return False

    # 3. Resolve conversation ID
    resolved_conv = (
        conversation_id
        or get_current_conversation_id()
        or state_mgr.get_branch_conversation(resolved_branch)
    )
    if not resolved_conv:
        print(
            "[ERROR] No Antigravity conversation ID was provided, found in "
            "the environment, or remembered by the hook for this branch."
        )
        print(
            "Please provide --conversation-id explicitly, or trigger via "
            "Antigravity Hook (--from-hook)."
        )
        return False

    # 4. Save registration
    state_mgr.register_pr(resolved_pr, resolved_conv, resolved_branch)
    print(
        f"[SUCCESS] Registered PR #{resolved_pr} (branch: "
        f"'{resolved_branch}') to Antigravity conversation '{resolved_conv}'."
    )
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
        print(
            f"PR #{pr_num:4s} | status: {status:<10s} | branch: "
            f"{branch:<30s} | conversation: {conv} | processed: "
            f"{events_cnt} | pending: {pending_cnt}"
        )


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Register a PR with Antigravity review feedback loop."
    )
    parser.add_argument(
        "--from-hook",
        action="store_true",
        help="Process official Antigravity Hook payload from stdin.",
    )
    parser.add_argument(
        "--stop",
        action="store_true",
        help="Indicate this is a Stop hook invocation (output contract differs).",
    )
    parser.add_argument(
        "--pr", type=int, help="Pull Request number (default: auto-detect)."
    )
    parser.add_argument(
        "--conversation-id",
        help="Antigravity conversation ID (default: $ANTIGRAVITY_CONVERSATION_ID).",
    )
    parser.add_argument(
        "--branch", help="Git branch name (default: current git branch)."
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List all registered PRs and allowlist.",
    )
    parser.add_argument(
        "--unregister", type=int, help="Unregister a PR from review loop."
    )
    parser.add_argument(
        "--reactivate",
        type=int,
        help="Reactivate an approved/closed PR back to watching status.",
    )
    parser.add_argument(
        "--allow-user", help="Add a username to reviewer allowlist."
    )
    args = parser.parse_args()

    if args.from_hook:
        register_from_hook(is_stop=args.stop)
        sys.exit(0)

    state_mgr = StateManager()

    if args.reactivate:
        if state_mgr.reactivate_pr(args.reactivate):
            print(f"[SUCCESS] Reactivated PR #{args.reactivate} to 'watching'.")
        else:
            print(f"[WARN] PR #{args.reactivate} was not registered.")
        return

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

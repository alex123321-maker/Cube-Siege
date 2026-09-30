"""
Signal review completion: run-scoped acknowledgement for Codex, or the
legacy Antigravity no-change marker and lock release.
"""
import argparse
import sys
import time
from pathlib import Path
from typing import Optional

_REPO_ROOT = Path(__file__).resolve().parent.parent.parent
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from tools.review_loop.config import REVIEW_LOOP_DIR
from tools.review_loop.state_manager import StateManager


def mark_run_completed(
    pr_number: int,
    state_manager: Optional[StateManager] = None,
    review_loop_dir: Optional[Path] = None,
    run_id: Optional[int] = None,
    status: str = "completed",
) -> None:
    state = state_manager or StateManager()
    pr = state.get_pr(pr_number)
    if pr and pr.get("agent_provider") == "codex":
        if run_id is None:
            raise ValueError("Codex completion requires --run-id from the dispatched task.")
        state.complete_codex_run(pr_number, run_id, status)
        print(f"[SUCCESS] Acknowledged Codex run {run_id} for PR #{pr_number}: {status}.")
        return
    if run_id is not None or status != "completed":
        raise ValueError("Run-scoped completion requires a registered Codex PR.")
    loop_dir = Path(review_loop_dir or REVIEW_LOOP_DIR)
    loop_dir.mkdir(parents=True, exist_ok=True)
    marker = loop_dir / f"pr_{pr_number}.done"
    marker.write_text(f"completed at {time.time()}\n", encoding="utf-8")

    if pr and pr.get("status") == "processing":
        state.reset_retry_count(pr_number)
        state.finalize_in_flight_events(pr_number)
        state.release_lock(pr_number)
        print(f"[SUCCESS] Released lock and finalized in-flight events for PR #{pr_number}.")
    else:
        print(f"[INFO] Wrote completion marker for PR #{pr_number}.")


def main() -> None:
    parser = argparse.ArgumentParser(description="Signal review run completion for a PR.")
    parser.add_argument("pr_number", type=int, help="PR number to mark completed")
    parser.add_argument("--run-id", type=int, help="Required for Codex; use the ID in the queued task.")
    parser.add_argument("--status", choices=["completed", "awaiting_design_decision"], default="completed")
    args = parser.parse_args()
    try:
        mark_run_completed(args.pr_number, run_id=args.run_id, status=args.status)
    except ValueError as exc:
        parser.error(str(exc))


if __name__ == "__main__":
    main()

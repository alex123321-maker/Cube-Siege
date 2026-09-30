"""Hidden scheduled-task entry point. Exit nonzero if the daemon stops unexpectedly."""
import argparse
import json
import os
import sys
import traceback
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding="utf-8"))
    repo = Path(config["repo_root"])
    os.environ["ASSET_REVIEW_REPO_ROOT"] = str(repo)
    os.environ["REVIEW_LOOP_CODEX_EXE"] = config["codex_exe"]
    os.chdir(repo)
    sys.path.insert(0, config["source_root"])
    log_path = repo / ".review_loop" / "watcher_codex_startup.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("a", encoding="utf-8", buffering=1) as log:
        sys.stdout = sys.stderr = log
        try:
            from tools.review_loop.watcher import main as run_watcher
            sys.argv = ["watcher.py", "--agent", "codex"]
            run_watcher()
        except BaseException:
            traceback.print_exc(file=log)
        finally:
            # Scheduler should restart after auth/startup failures as well as crashes.
            log.write("Watcher exited; scheduled recovery will retry.\n")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())

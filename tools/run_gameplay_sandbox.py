"""Launch the playable flat sandbox with isolated storage and bounded readiness.

Default: return after readiness while the interactive game continues running.
--smoke: finite headless scene initialization; this is not a balance playthrough.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import time

from verify import find_godot_binary

ROOT = Path(__file__).resolve().parent.parent
SCENE = "res://scenes/tools/gameplay_sandbox.tscn"
PROFILE = "user://gameplay_sandbox/profile/"


def stop_owned_tree(process: subprocess.Popen, deadline: float) -> None:
    if process.poll() is not None:
        return
    if os.name == "nt":
        subprocess.run(
            ["taskkill", "/PID", str(process.pid), "/T", "/F"],
            capture_output=True, timeout=max(0.1, min(5.0, deadline-time.monotonic())),
            check=False, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
    else:
        process.kill()
    process.wait(timeout=max(0.1, min(3.0, deadline-time.monotonic())))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--renderer", choices=["gl_compatibility", "forward_plus"], default="gl_compatibility")
    args = parser.parse_args()
    executable = find_godot_binary()
    if not executable:
        parser.error("Set GODOT_BIN or .godot_path to a Godot 4.6 executable.")
    output = ROOT / ".review_loop"
    output.mkdir(exist_ok=True)
    log_path = output / "gameplay-sandbox-run.log"
    command = [executable, "--path", str(ROOT), "--resolution", "1440x900",
               "--rendering-method", args.renderer]
    if args.smoke:
        command += ["--headless", "--quit-after", "120"]
    command += [SCENE, "--", "--gameplay-sandbox", "--test-profile=" + PROFILE]
    environment = os.environ.copy()
    # Set before process creation: autoload initialization cannot touch real saves.
    environment["CUBE_SIEGE_TEST_PROFILE"] = PROFILE
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0) if os.name == "nt" else 0
    deadline = time.monotonic() + 35.0
    with log_path.open("w", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                   env=environment, creationflags=flags)
        try:
            ready = False
            while time.monotonic() < deadline - 5.0:
                text = log_path.read_text(encoding="utf-8", errors="replace")
                if "SCRIPT ERROR:" in text or "ERROR:" in text:
                    raise RuntimeError(text[-6000:])
                ready = "GAMEPLAY_SANDBOX_READY" in text
                if ready or process.poll() is not None:
                    break
                time.sleep(0.1)
            if not ready:
                raise RuntimeError("TIMEOUT or early exit before sandbox readiness")
            if args.smoke:
                process.wait(timeout=max(0.1, deadline-time.monotonic()-5.0))
                text = log_path.read_text(encoding="utf-8", errors="replace")
                if process.returncode != 0 or "ERROR:" in text:
                    raise RuntimeError(text[-6000:])
            elif process.poll() is not None:
                raise RuntimeError("Interactive sandbox exited immediately after readiness")
            print(f"Playable sandbox ready. PID={process.pid}; log={log_path}; profile={PROFILE}")
            return 0
        except (RuntimeError, subprocess.TimeoutExpired) as error:
            stop_owned_tree(process, deadline)
            print(error)
            return 1


if __name__ == "__main__":
    raise SystemExit(main())

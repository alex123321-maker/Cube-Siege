"""Launch the read-only native ability viewer with isolated saves and bounded readiness.

Default: open the interactive laboratory and return its PID after readiness.
--smoke: bounded headless scene initialization. --capture: finite rendered demo.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import time

from verify import find_godot_binary

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--capture", action="store_true")
    parser.add_argument("--entry", type=int, default=1, choices=range(15), help="Ability index for capture (0-14).")
    parser.add_argument("--delay", type=float, default=0.23, help="Seconds after activation to capture.")
    args = parser.parse_args()
    executable = find_godot_binary()
    if not executable:
        parser.error("Set GODOT_BIN or .godot_path to a Godot 4.6 executable.")
    output = ROOT / ".review_loop"
    output.mkdir(exist_ok=True)
    log_path = output / "ability-lab-run.log"
    command = [executable, "--path", str(ROOT), "--resolution", "1440x900"]
    if args.smoke:
        command.append("--headless")
    command.append("res://scenes/tools/ability_lab.tscn")
    if args.smoke:
        command += ["--quit-after", "120"]
    command += ["--", "--ability-lab"]
    if args.capture:
        command += ["--lab-capture", f"--viewer-entry={args.entry}", f"--viewer-delay={args.delay}"]
    environment = os.environ.copy()
    environment["CUBE_SIEGE_TEST_PROFILE"] = "user://ability_lab/profile/"
    flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
    with log_path.open("w", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
                                   env=environment, creationflags=flags)
        try:
            deadline = time.monotonic() + 30
            ready = False
            while time.monotonic() < deadline:
                text = log_path.read_text(encoding="utf-8", errors="replace")
                if "SCRIPT ERROR:" in text or "ERROR:" in text:
                    raise RuntimeError(text[-6000:])
                ready = "ABILITY_LAB_READY" in text
                if ready or process.poll() is not None:
                    break
                time.sleep(0.1)
            if not ready:
                raise RuntimeError("TIMEOUT or early exit before laboratory readiness")
            if args.smoke or args.capture:
                process.wait(timeout=max(1, deadline - time.monotonic()))
                text = log_path.read_text(encoding="utf-8", errors="replace")
                if process.returncode or "ERROR:" in text:
                    raise RuntimeError(text[-6000:])
                if args.capture and "ABILITY_LAB_CAPTURE:" not in text:
                    raise RuntimeError("Rendered capture was not confirmed")
            print(f"Ability laboratory ready. PID={process.pid}; log={log_path}")
            return 0
        except (RuntimeError, subprocess.TimeoutExpired) as error:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            print(error)
            return 1


if __name__ == "__main__":
    raise SystemExit(main())

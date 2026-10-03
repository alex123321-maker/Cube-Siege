"""Bounded menu-to-sandbox integration with real gameplay Input and optional GPU media."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

from verify import find_godot_binary

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "screenshots_debug/sandbox"
TOTAL_DEADLINE_SECONDS = 195


def source_fingerprint() -> str:
    paths = []
    for directory, extension in [("scripts", "*.gd"), ("scenes", "*.tscn"), ("assets/abilities", "*.tres")]:
        paths.extend((ROOT / directory).rglob(extension))
    paths += [ROOT / "tools/gameplay_sandbox_smoke.gd", Path(__file__)]
    digest = hashlib.sha256()
    for path in sorted(set(paths)):
        digest.update(path.relative_to(ROOT).as_posix().encode())
        digest.update(b"\0")
        digest.update(path.read_bytes().replace(b"\r\n", b"\n"))
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=find_godot_binary())
    parser.add_argument("--capture", action="store_true")
    parser.add_argument("--movie", action="store_true", help="Also record a finite gameplay movie; requires --capture.")
    parser.add_argument("--ffmpeg", default="ffmpeg")
    args = parser.parse_args()
    if not args.godot or (args.movie and not args.capture):
        parser.error("Godot is required; --movie also requires --capture.")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    capture_dir = OUTPUT / "capture"
    capture_dir.mkdir(exist_ok=True)
    stem = "capture" if args.capture else "smoke"
    log_path = OUTPUT / f"{stem}.log"
    command = [args.godot, "--path", str(ROOT)]
    if args.capture:
        command += ["--rendering-method", "gl_compatibility", "--resolution", "1280x720", "--position", "-32000,-32000"]
    else:
        command += ["--headless"]
    if args.movie:
        command += ["--write-movie", str(capture_dir / "sandbox.avi"), "--fixed-fps", "30"]
    command += ["-s", "tools/gameplay_sandbox_smoke.gd", "--"]
    if args.capture:
        command += ["--capture"]
    environment = os.environ.copy()
    environment["CUBE_SIEGE_TEST_PROFILE"] = "user://sandbox_integration/"
    environment["PYTHONIOENCODING"] = "utf-8"
    before = source_fingerprint()
    started = time.monotonic()
    deadline = started + TOTAL_DEADLINE_SECONDS

    def remaining(stage_limit: float) -> float:
        budget = deadline - time.monotonic()
        if budget <= 0:
            raise subprocess.TimeoutExpired("sandbox integration deadline", TOTAL_DEADLINE_SECONDS)
        return min(stage_limit, budget)

    status, code = "FAIL", 1
    with log_path.open("w", encoding="utf-8") as log:
        try:
            result = subprocess.run(command, cwd=ROOT, env=environment, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=remaining(150), creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            code = result.returncode
        except subprocess.TimeoutExpired:
            code, status = 124, "TIMEOUT"
    text = log_path.read_text(encoding="utf-8", errors="replace")
    summary = re.search(r"GAMEPLAY_SANDBOX_SMOKE: (\d+)/(\d+) checks passed", text)
    unchanged = before == source_fingerprint()
    if code == 0 and summary and summary[1] == summary[2] and "ERROR:" not in text and unchanged:
        status = "PASS"
    movie_status = "not_requested"
    if args.movie and status == "PASS":
        try:
            with (OUTPUT / "movie-encode.log").open("w", encoding="utf-8") as log:
                encoded = subprocess.run([args.ffmpeg, "-y", "-i", str(capture_dir / "sandbox.avi"),
                    "-c:v", "libx264", "-crf", "24", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
                    "-an", str(capture_dir / "sandbox.mp4")], stdout=log, stderr=subprocess.STDOUT,
                    timeout=remaining(30), creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            decoded = subprocess.run([args.ffmpeg, "-v", "error", "-i", str(capture_dir / "sandbox.mp4"),
                "-f", "null", "-"], capture_output=True, timeout=remaining(15),
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            movie_status = "PASS" if encoded.returncode == 0 and decoded.returncode == 0 else "FAIL"
        except subprocess.TimeoutExpired:
            movie_status = "TIMEOUT"
        if movie_status != "PASS":
            status = "FAIL"
    try:
        revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True,
                                  text=True, check=True, timeout=remaining(5)).stdout.strip()
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError):
        revision, status = "unavailable", "FAIL"
    manifest = {"status": status, "exit_code": code, "command": command,
        "duration_seconds": round(time.monotonic() - started, 2), "git_head": revision, "source_sha256": before,
        "source_unchanged_during_run": unchanged, "movie_decode": movie_status,
        "checks_passed": int(summary[1]) if summary else 0, "checks_total": int(summary[2]) if summary else 0,
        "captures": {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                     for path in sorted(capture_dir.glob("*.png"))} if args.capture else {},
        "limits": "195s shared deadline: process 150s with 120s internal watchdog, encode 30s, decode 15s; native Input actions and controllers; stationary targets for weapon checks, live AI for navigation; not a balance playthrough"}
    (OUTPUT / f"{stem}-manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps({"status": status, "checks": f"{manifest['checks_passed']}/{manifest['checks_total']}", "log": str(log_path)}))
    return 0 if status == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())

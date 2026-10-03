"""Bounded production-scene Warrior integration smoke with isolated storage."""
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
OUTPUT = ROOT / "screenshots_debug/progression"


def source_fingerprint() -> str:
    paths = list((ROOT / "scripts/player").glob("*.gd"))
    for directory in ["scripts/progression", "scripts/run", "scripts/bosses", "scripts/ui", "scripts/combat"]:
        paths += list((ROOT / directory).glob("*.gd"))
    paths += list((ROOT / "scripts/effects").rglob("*.gd"))
    paths += list((ROOT / "scenes/bosses").glob("*.tscn"))
    paths += list((ROOT / "assets/models/bosses").glob("*.tscn"))
    paths += [ROOT / path for path in ["scenes/main.tscn", "scenes/player.tscn", "scenes/hud.tscn", "scenes/game_over_overlay.tscn", "scripts/main.gd", "scripts/hud.gd", "scripts/day_night_cycle.gd", "scripts/wave_director.gd", "scripts/player_prototype.gd", "scripts/save_manager.gd", "scripts/roster_manager.gd", "scripts/enemy_base.gd", "scripts/hitbox_area.gd", "scripts/hurtbox_area.gd", "scripts/map_generator.gd", "tools/warrior_run_smoke.gd", "tools/warrior_run_smoke.py"]]
    digest = hashlib.sha256()
    for path in sorted(set(paths)):
        digest.update(path.relative_to(ROOT).as_posix().encode())
        digest.update(b"\0")
        digest.update(path.read_bytes().replace(b"\r\n", b"\n"))
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=find_godot_binary())
    parser.add_argument("--capture", action="store_true", help="Also capture four GPU-rendered checkpoints.")
    parser.add_argument("--verbose", action="store_true", help="Include engine lifecycle diagnostics.")
    parser.add_argument("--immediate-teardown", action="store_true", help="Delete the gameplay owner while its final sword cast is still pending.")
    args = parser.parse_args()
    if not args.godot:
        parser.error("Godot not found; set GODOT_BIN or pass --godot.")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    stem = "run-capture" if args.capture else "run-smoke"
    log_path = OUTPUT / f"{stem}.log"
    env = os.environ.copy()
    env["CUBE_SIEGE_TEST_PROFILE"] = f"user://warrior_{stem}/"
    command = [args.godot, "--path", str(ROOT)]
    if args.verbose:
        command.append("--verbose")
    if args.capture:
        command += ["--rendering-method", "gl_compatibility", "--resolution", "1280x720", "--position", "-32000,-32000"]
    else:
        command += ["--headless"]
    command += ["-s", "tools/warrior_run_smoke.gd", "--", f"--test-profile={env['CUBE_SIEGE_TEST_PROFILE']}"]
    if args.capture:
        command.append("--capture")
    if args.immediate_teardown:
        command.append("--immediate-teardown")
    fingerprint_before = source_fingerprint()
    started = time.monotonic()
    status = "FAIL"
    with log_path.open("w", encoding="utf-8") as log:
        try:
            result = subprocess.run(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=180, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
            code = result.returncode
        except subprocess.TimeoutExpired:
            code, status = 124, "TIMEOUT"
    output = log_path.read_text(encoding="utf-8", errors="replace")
    summary = re.search(r"WARRIOR_RUN_SMOKE: (\d+)/(\d+) checks passed", output)
    fingerprint_after = source_fingerprint()
    if code == 0 and summary and summary[1] == summary[2] and "SCRIPT ERROR" not in output and "ERROR:" not in output and fingerprint_before == fingerprint_after:
        status = "PASS"
    manifest = {
        "status": status, "exit_code": code,
        "duration_seconds": round(time.monotonic() - started, 2),
        "checks_passed": int(summary[1]) if summary else 0,
        "checks_total": int(summary[2]) if summary else 0,
        "source_sha256": fingerprint_before,
        "source_unchanged_during_run": fingerprint_before == fingerprint_after,
        "immediate_teardown": args.immediate_teardown,
        "command": command, "profile": env["CUBE_SIEGE_TEST_PROFILE"],
        "limits": "180s process timeout; 150s internal watchdog; accelerated clocks, ordinary spawns disabled, real bosses held at 10 HP and hit by production sword; not balance playthrough",
        "captures": {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((OUTPUT / "run").glob("*.png"))} if args.capture else {},
    }
    (OUTPUT / f"{stem}-manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps({"status": status, "exit_code": code, "checks": f"{manifest['checks_passed']}/{manifest['checks_total']}", "log": str(log_path)}))
    return 0 if status == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())

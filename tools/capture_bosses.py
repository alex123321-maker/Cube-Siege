"""Record the bounded real-render boss review; never use the live save profile."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]


def source_fingerprint(script: str) -> str:
    paths = list((ROOT / "scripts/bosses").glob("*.gd")) + list((ROOT / "scripts/effects").rglob("*.gd")) + list((ROOT / "assets/models/bosses").glob("*.tscn")) + [ROOT / "scripts/combat/continuous_damage_cadence.gd"]
    paths += [ROOT / "scripts/player_prototype.gd", ROOT / "scripts/player/player_enemy_carry.gd", ROOT / "scripts/player/player_combat.gd", ROOT / "scripts/player/player_presentation.gd", ROOT / "scripts/player/warrior_talent_runtime.gd", ROOT / "scripts/player/player_movement.gd", ROOT / "scripts/player/player_health.gd", ROOT / "scripts/hitbox_area.gd", ROOT / "scripts/enemy_base.gd", ROOT / "scripts/progression/warrior_talent_catalog.gd", ROOT / "scripts/progression/warrior_run_build.gd", ROOT / "scripts/save_manager.gd", ROOT / "scripts/roster_manager.gd", ROOT / "assets/abilities/warrior_cleave.tres", ROOT / script, ROOT / "tools/capture_bosses.gd", Path(__file__)]
    if Path(script).name == "capture_elites.gd":
        paths += list((ROOT / "scripts/elites").glob("*.gd"))
        paths += [ROOT / "scripts/core/entity_registry.gd", ROOT / "scripts/run/warrior_run_coordinator.gd", ROOT / "scripts/day_night_cycle.gd", ROOT / "scripts/wave_director.gd"]
    digest = hashlib.sha256()
    for path in sorted(set(paths)):
        digest.update(path.relative_to(ROOT).as_posix().encode())
        digest.update(b"\0")
        digest.update(path.read_bytes().replace(b"\r\n", b"\n"))
    return digest.hexdigest()


def artifact_state(path: Path) -> tuple[int, int, int] | None:
    if not path.is_file():
        return None
    info = path.stat()
    return info.st_mtime_ns, info.st_ctime_ns, info.st_size


def fresh_artifacts(output: Path, log: str, previous: dict[str, tuple[int, int, int]]) -> tuple[list[Path], list[str]]:
    """Only explicit successful current-run writes may become evidence."""
    names = set(re.findall(r"^CAPTURE_FRAME saved=([^\r\n]+\.png)\s*$", log, re.MULTILINE))
    errors = []
    paths = []
    if not names:
        errors.append("no current-run frame write markers")
    names.add("gameplay_checks.json")
    for name in sorted(names):
        path = output / name
        # Validate observed file names without deleting any old/unrelated files.
        if Path(name).name != name or path.resolve().parent != output:
            errors.append(f"invalid capture artifact name: {name}")
            continue
        state = artifact_state(path)
        if state is None or state == previous.get(name):
            errors.append(f"missing or stale current-run artifact: {name}")
        else:
            paths.append(path)
    return paths, errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", default="D:/ProgramFiles/godot/Godot_v4.6.1-stable_win64.exe")
    parser.add_argument("--ffmpeg", default="D:/ProgramFiles/ffmpeg-master-latest-win64-gpl-shared/bin/ffmpeg.exe")
    parser.add_argument("--output", type=Path, default=ROOT / "screenshots_debug/bosses/capture")
    parser.add_argument("--script", default="tools/capture_bosses.gd")
    parser.add_argument("--marker", default="BOSS_CAPTURE")
    parser.add_argument("--stem", default="bosses")
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env["CUBE_SIEGE_TEST_PROFILE"] = f"user://capture_review_profile/{uuid.uuid4().hex}/"
    command = [args.godot, "--path", str(ROOT), "--resolution", "1280x720", "--position", "-32000,-32000", "--fixed-fps", "30", "--write-movie", str(output / f"{args.stem}.avi"), "-s", args.script, "--", f"--output={output.as_posix()}"]
    started = time.monotonic()
    deadline = started + 305.0
    fingerprint_before = source_fingerprint(args.script)
    previous_artifacts = {path.name: state for path in output.iterdir()
                          if path.suffix in [".png", ".json"] and (state := artifact_state(path)) is not None}
    status = "FAIL"
    (output / f"{args.stem}.mp4").unlink(missing_ok=True)
    with (output / "capture.log").open("w", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
        try:
            code = process.wait(timeout=min(240, max(1.0, deadline - time.monotonic())))
        except subprocess.TimeoutExpired:
            subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], stdout=log, stderr=log, timeout=15)
            code = 124
            status = "TIMEOUT"
    text = (output / "capture.log").read_text(encoding="utf-8", errors="replace")
    evidence, freshness_errors = fresh_artifacts(output, text, previous_artifacts)
    if code == 0 and f"{args.marker} pass=true" in text and "SCRIPT ERROR" not in text and "ERROR:" not in text:
        status = "PASS" if not freshness_errors else "FAIL"
        if freshness_errors:
            code = 2
    if status == "PASS":
        with (output / "encode.log").open("w", encoding="utf-8") as log:
            try:
                subprocess.run([args.ffmpeg, "-y", "-i", str(output / f"{args.stem}.avi"), "-c:v", "libx264", "-crf", "23", "-pix_fmt", "yuv420p", "-an", "-movflags", "+faststart", str(output / f"{args.stem}.mp4")], stdout=log, stderr=log, timeout=min(45, max(1.0, deadline - time.monotonic())), check=True)
            except subprocess.TimeoutExpired:
                status, code = "TIMEOUT", 124
            except subprocess.CalledProcessError:
                status, code = "FAIL", 2
    if status == "PASS":
        evidence.append(output / f"{args.stem}.mp4")
    files = {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in evidence}
    fingerprint = source_fingerprint(args.script)
    if fingerprint_before != fingerprint:
        status, code = "FAIL", 2
    revision = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True, timeout=min(10, max(1.0, deadline - time.monotonic())), check=True).stdout.strip()
    engine = subprocess.run([args.godot, "--version"], capture_output=True, text=True, timeout=min(10, max(1.0, deadline - time.monotonic())), check=True).stdout.strip()
    manifest = dict(status=status, exit_code=code, duration_seconds=round(time.monotonic() - started, 2), git_head=revision, godot_version=engine, resolution="1280x720", seed=330519, fixed_fps=30, source_sha256=fingerprint_before, source_unchanged_during_capture=fingerprint_before == fingerprint, fingerprint_scope="boss scripts/models, talent VFX, combat/cadence/carry/presentation/runtime hooks, profile initialization and capture scripts; elite script additionally binds all elite scripts and registry", profile=env["CUBE_SIEGE_TEST_PROFILE"], freshness_errors=freshness_errors, command=command, limits="305s total: render<=240s, encode<=45s, metadata<=20s; flat arena excludes final terrain/crowd/balance", files=files)
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(json.dumps({"status": status, "output": str(output), "exit_code": code}))
    return 0 if status == "PASS" else 2


if __name__ == "__main__":
    raise SystemExit(main())

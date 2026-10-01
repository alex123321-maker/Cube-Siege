"""Small, dependency-free VFX entry point. Artistic judgment remains explicit."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "tools/vfx_workbench/catalog.json"
REVIEW_ITEMS = ("ability_identity", "body_anatomy", "footprint_truth", "target_hits",
                "contrast_and_crowd", "timing_audio", "cleanup_and_budget")
DEFAULT_CASE = {"cleave": "day", "sword": "coverage", "mine": "day",
                "archer": "coverage", "stamps": "preview"}


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def catalog() -> dict:
    return read_json(CATALOG)


def godot_binary() -> str:
    configured = os.environ.get("GODOT_BIN", "")
    if not configured and (ROOT / ".godot_path").is_file():
        configured = (ROOT / ".godot_path").read_text(encoding="utf-8-sig").strip()
    result = configured or shutil.which("godot") or shutil.which("godot4")
    if not result:
        raise ValueError("Set GODOT_BIN or .godot_path (docs/AGENT_SETUP.md).")
    return str(result)


def fingerprint(root: Path = ROOT) -> str:
    """Include unstaged/untracked runtime and harness content, not just HEAD."""
    digest = hashlib.sha256()
    binary_suffixes = {".png", ".jpg", ".jpeg", ".webp", ".wav", ".ogg", ".glb"}
    suffixes = {".gd", ".py", ".json", ".gdshader", ".tres", ".tscn", ".gltf", ".import"} | binary_suffixes
    paths = [root / "project.godot"]
    for directory in ("scripts", "scenes", "assets", "tools"):
        paths.extend(p for p in (root / directory).rglob("*") if p.is_file()
                     and p.suffix in suffixes
                     and not any(part.startswith(".") or part in ("__pycache__", "bin")
                                 for part in p.relative_to(root / directory).parts))
    for path in sorted(paths):
        digest.update(path.relative_to(root).as_posix().encode())
        digest.update(b"\0")
        raw = path.read_bytes()
        digest.update(raw if path.suffix in binary_suffixes else raw.replace(b"\r\n", b"\n"))
        digest.update(b"\0")
    return digest.hexdigest()


def source_state() -> dict:
    result = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True,
                            text=True, timeout=15, check=True)
    version = subprocess.run([godot_binary(), "--version"], cwd=ROOT, capture_output=True,
                             text=True, timeout=15, check=True).stdout.strip()
    return {"head": result.stdout.strip(), "content_sha256": fingerprint(), "godot_version": version,
            "fingerprint_scope": "project.godot; scripts/scenes/assets/tools source and .import settings; text CRLF normalized. Excludes engine/native binaries, external packages, hardware and user save state."}


def checked_run(command: list[str], log: Path, timeout: float, marker: str = "") -> dict:
    start = time.monotonic()
    status = "FAIL"
    code = None
    with log.open("w", encoding="utf-8") as output:
        try:
            result = subprocess.run(command, cwd=ROOT, stdout=output,
                                    stderr=subprocess.STDOUT, timeout=timeout, check=False)
            code = result.returncode
        except subprocess.TimeoutExpired:
            status = "TIMEOUT"
    text = log.read_text(encoding="utf-8", errors="replace")
    # Existing editor shutdown leak diagnostics are retained, never hidden.
    fatal = any(token in text for token in ("SCRIPT ERROR", "Parse Error", "Failed to load"))
    fatal = fatal or any(line.startswith("ERROR:") and "resources still in use at exit" not in line
                         for line in text.splitlines())
    if code == 0 and not fatal and (not marker or marker in text):
        status = "PASS"
    return {"status": status, "exit_code": code, "seconds": round(time.monotonic() - start, 2),
            "command": command, "log": log.name,
            "reason": "runtime error or missing success marker" if code == 0 and status != "PASS" else ""}


def validate_catalog(data: dict, root: Path = ROOT) -> list[str]:
    errors = []
    for name, entry in data["families"].items():
        for key in ("profile", "effect", "harness", "test", "evidence"):
            if not (root / entry[key]).exists():
                errors.append(f"{name}: missing {key}: {entry[key]}")
    provenance = root / "assets/vfx/library/kenney/PROVENANCE.json"
    for item in read_json(provenance)["files"]:
        path = provenance.parent / item["file"]
        if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest() != item["sha256"]:
            errors.append(f"Asset provenance mismatch: {path.name}")
    return errors


def safe_output(value: str | None, family: str) -> Path:
    relative = value or f"screenshots_debug/vfx_workbench/{family}_{datetime.now(timezone.utc):%Y%m%dT%H%M%S%fZ}"
    path = (ROOT / relative).resolve()
    allowed = (ROOT / "screenshots_debug/vfx_workbench").resolve()
    if not path.is_relative_to(allowed) or path == allowed:
        raise ValueError("Output must be a new child of screenshots_debug/vfx_workbench/.")
    if path.exists():
        raise ValueError(f"Output already exists; choose a new folder: {path}")
    return path


def doctor(args: argparse.Namespace) -> int:
    errors = validate_catalog(catalog())
    if errors:
        print("\n".join(errors))
        return 2
    output = safe_output(args.output, "doctor")
    output.mkdir(parents=True)
    imported = checked_run([godot_binary(), "--headless", "--path", str(ROOT), "--editor", "--quit"],
                           output / "import.log", 120)
    if imported["status"] != "PASS":
        write_json(output / "run.json", imported)
        print(f"Editor import {imported['status']}; inspect {output / 'import.log'}")
        return 2
    run = checked_run([godot_binary(), "--headless", "--path", str(ROOT), "-s",
                       "tools/vfx_workbench/inspect_rigs.gd", "--", f"--report={output / 'rigs.json'}"],
                      output / "doctor.log", 60, "VFX_RIG_REPORT")
    write_json(output / "run.json", run)
    print(f"Catalog/provenance OK; rig inspection {run['status']}. Report: {output}")
    print("ffmpeg: " + (shutil.which("ffmpeg") or "optional, missing; AVI remains available"))
    return 0 if run["status"] == "PASS" else 2


def init_trial(args: argparse.Namespace) -> int:
    if not re.fullmatch(r"[a-z][a-z0-9_]{1,47}", args.name):
        raise ValueError("Name: 2–48 lowercase letters/digits/underscores, beginning with a letter.")
    entry = catalog()["families"][args.family]
    destination = ROOT / entry["profile"]
    destination = destination.parent / "trials" / (args.name + ".tres")
    brief = ROOT / "screenshots_debug/vfx_workbench" / args.name
    if destination.exists() or brief.exists():
        raise ValueError("Trial or brief already exists; this command never overwrites work.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / entry["profile"], destination)
    brief.mkdir(parents=True)
    relative = destination.relative_to(ROOT).as_posix()
    (brief / "BRIEF.md").write_text(
        f"# {args.name}: proposal, not evaluated\n\n"
        f"Family: {args.family}. Candidate: `{relative}`.\n\n"
        "User contract and authorized scope: TODO\n\n"
        "One intended sensation and dominant shape: TODO\n\n"
        "Visible difference from basic attack (body / area / hit reaction): TODO\n\n"
        "Actual source, damage event and geometry owner: TODO\n\n"
        "First diagnosis, 1–3 art controls to change, expected observation: TODO\n\n"
        f"Available controls: {entry['controls']}\n\n"
        f"Capture: `python tools/vfx_workbench.py capture {args.family} --profile {relative}`\n\n"
        "Run capture after the edit, then open index.html and motion clips. Fill review.json with\n"
        "specific observations; record unobserved conditions as skip with a reason.\n"
        "Do not replace the production preset until the evidence supports the change.\n",
        encoding="utf-8")
    print(f"Proposal: {relative}\nBrief: {brief / 'BRIEF.md'}")
    return 0


def capture(args: argparse.Namespace) -> int:
    entry = catalog()["families"][args.family]
    selected = args.case or [DEFAULT_CASE[args.family]]
    if "all" in selected:
        selected = list(entry["cases"])
    if len(set(selected)) != len(selected) or any(case not in entry["cases"] for case in selected):
        raise ValueError("Choose distinct cases from: " + ", ".join(entry["cases"]))
    profile = None
    if args.profile:
        profile = (ROOT / args.profile.removeprefix("res://")).resolve()
        if not profile.is_relative_to(ROOT / "assets/vfx") or not profile.is_file() or profile.suffix != ".tres":
            raise ValueError("Profile must be an existing .tres under assets/vfx/.")
        if args.family == "stamps":
            raise ValueError("Stamp preview uses both bundled presets; edit a duplicated scene for a custom preview.")
    output = safe_output(args.output, args.family)
    output.mkdir(parents=True)
    state = source_state()
    manifest = {"schema_version": 1, "family": args.family, "source": state,
                "created_utc": datetime.now(timezone.utc).isoformat(), "renderer": "project default",
                "fps": 60, "resolution": [1280, 720], "world_seed": 1337 if args.family != "stamps" else None,
                "capture_mode": "offline fixed-step movies; real-time renderer only for case profile",
                "profile": str(profile.relative_to(ROOT)) if profile else entry["profile"],
                "coverage_limits": entry["coverage_limits"], "expected_cases": selected, "cases": [], "artistic_status": "NOT_REVIEWED"}
    deadline = time.monotonic() + args.timeout
    for case in selected:
        if time.monotonic() >= deadline:
            manifest["cases"].append({"case": case, "status": "TIMEOUT", "reason": "suite deadline"})
            break
        folder = output / case
        (folder / "frames").mkdir(parents=True)
        command = [godot_binary(), "--path", str(ROOT)]
        is_profile = case == "profile"
        if not is_profile:
            command += ["--fixed-fps", "60", "--write-movie", str(folder / "motion.avi")]
        command += ["-s", entry["harness"], "--", f"--label={case}",
                    "--output=" + str(folder / "frames").replace("\\", "/")]
        command += entry["cases"][case]
        if profile and case != "basic":
            command += ["--profile=res://" + profile.relative_to(ROOT).as_posix()]
        marker = "CLEAVE_REAL_TIME_PROFILE" if is_profile else entry["success_marker"]
        run = checked_run(command, folder / "godot.log", min(240, deadline - time.monotonic()), marker)
        run["case"] = case
        run["conditions"] = entry["cases"][case]
        if not is_profile and not list((folder / "frames").glob("*.png")):
            run["status"] = "FAIL"
            run["reason"] = "no rendered frames"
        ffmpeg = shutil.which("ffmpeg")
        if run["status"] == "PASS" and not is_profile and ffmpeg and time.monotonic() < deadline:
            encode = checked_run([ffmpeg, "-nostdin", "-i", str(folder / "motion.avi"),
                                  "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-pix_fmt", "yuv420p",
                                  "-c:a", "aac", "-movflags", "+faststart", str(folder / "motion.mp4")],
                                 folder / "encode.log", min(60, deadline - time.monotonic()))
            run["encode_status"] = encode["status"]
        run["files"] = [{"path": p.relative_to(output).as_posix(), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
                        for p in sorted(folder.rglob("*")) if p.is_file()]
        manifest["cases"].append(run)
        write_json(output / "manifest.json", manifest)
        print(f"{case}: {run['status']} ({run['seconds']}s)", flush=True)
        if run["status"] != "PASS":
            break
    if fingerprint() != state["content_sha256"]:
        manifest["source_changed_during_capture"] = True
    write_json(output / "manifest.json", manifest)
    write_json(output / "review.json", {key: {"status": "pending", "observation": "", "evidence": []} for key in REVIEW_ITEMS})
    make_index(output, manifest)
    print(f"Evidence: {output / 'index.html'}\nArtistic judgment: NOT REVIEWED. Fill review.json after viewing.")
    return 0 if all(c["status"] == "PASS" for c in manifest["cases"]) and len(manifest["cases"]) == len(selected) else 2


def make_index(output: Path, manifest: dict) -> None:
    from html import escape
    chunks = ["<!doctype html><meta charset='utf-8'><title>VFX evidence</title>",
              "<style>body{background:#171d25;color:#eee;font:16px sans-serif;max-width:1200px;margin:30px auto}img{width:31%;margin:1%}video{width:90%}a{color:#aee}</style>",
              f"<h1>{escape(manifest['family'])}: evidence, awaiting art review</h1>",
              "<p>Offline movies establish appearance and timing, not real-time performance.</p>",
              f"<p>Coverage limits: {escape(manifest['coverage_limits'])}</p>"]
    for case in manifest["cases"]:
        folder = output / case["case"]
        chunks.append(f"<h2>{escape(case['case'])}: {escape(case['status'])}</h2>")
        if (folder / "motion.mp4").is_file():
            chunks.append(f"<video controls src='{case['case']}/motion.mp4'></video>")
        for frame in sorted((folder / "frames").glob("*.png")):
            path = frame.relative_to(output).as_posix()
            chunks.append(f"<a href='{path}'><img src='{path}' alt='{escape(frame.name)}'></a>")
        chunks.append(f"<p><a href='{case['case']}/godot.log'>Runtime log</a></p>")
    (output / "index.html").write_text("\n".join(chunks), encoding="utf-8")


def evidence_errors(output: Path, current: str) -> tuple[list[str], list[str]]:
    manifest = read_json(output / "manifest.json")
    technical, review = [], []
    if manifest["source"]["content_sha256"] != current or manifest.get("source_changed_during_capture"):
        technical.append("STALE: runtime/harness content changed; recapture this variant.")
    if not manifest.get("cases"):
        technical.append("No completed cases")
    if {case["case"] for case in manifest.get("cases", [])} != set(manifest.get("expected_cases", [])):
        technical.append("Incomplete requested coverage")
    available = set()
    for case in manifest["cases"]:
        if case["status"] != "PASS":
            technical.append(f"{case['case']}: {case['status']}")
        if not case.get("files"):
            technical.append(case["case"] + ": no retained evidence files")
        for item in case.get("files", []):
            path = (output / item["path"]).resolve()
            if not path.is_relative_to(output.resolve()) or not path.is_file():
                technical.append("Missing/outside evidence: " + item["path"])
            elif hashlib.sha256(path.read_bytes()).hexdigest() != item["sha256"]:
                technical.append("Altered evidence: " + item["path"])
            available.add(item["path"])
    judgments = read_json(output / "review.json")
    for key in REVIEW_ITEMS:
        item = judgments.get(key, {})
        if item.get("status") not in ("pass", "fail", "skip") or len(item.get("observation", "").strip()) < 12:
            review.append(key + ": pending observation")
        elif item["status"] == "fail":
            review.append(key + ": unresolved defect")
        elif item["status"] == "pass" and (not item.get("evidence") or any(p not in available for p in item["evidence"])):
            review.append(key + ": name existing evidence files")
    return technical, review


def check(args: argparse.Namespace) -> int:
    output = (ROOT / args.folder).resolve()
    technical, review = evidence_errors(output, fingerprint())
    manifest = read_json(output / "manifest.json")
    saved_engine = manifest["source"].get("godot_version")
    if saved_engine:
        current_engine = subprocess.run([godot_binary(), "--version"], cwd=ROOT, capture_output=True,
                                        text=True, timeout=15, check=True).stdout.strip()
        if saved_engine != current_engine:
            technical.append("STALE: Godot version changed")
    print("Technical evidence: " + ("FAIL" if technical else "CURRENT AND INTACT"))
    print("Recorded art review: " + ("INCOMPLETE / NEEDS WORK" if review else "RECORDED (not an automatic quality score)"))
    for line in technical + review:
        print("- " + line)
    print("Coverage and skipped conditions remain in manifest.json; automated checks do not judge beauty.")
    return 2 if technical or review else 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    doctor_parser = commands.add_parser("doctor", help="Check local catalog, asset hashes and six bound rig axes")
    doctor_parser.add_argument("--output")
    commands.add_parser("catalog", help="List reusable presets, sources and capture cases")
    init = commands.add_parser("init", help="Copy a known art preset and create a short working brief")
    init.add_argument("name")
    init.add_argument("--family", choices=[name for name in catalog()["families"] if name != "stamps"], default="cleave")
    render = commands.add_parser("capture", help="Record production entry points into a fresh evidence package")
    render.add_argument("family", choices=catalog()["families"])
    render.add_argument("--case", action="append", help="Repeat for coverage; all selects every family case")
    render.add_argument("--profile")
    render.add_argument("--output")
    render.add_argument("--timeout", type=float, default=600, help="Whole-suite deadline, including encoding")
    inspect = commands.add_parser("check", help="Check freshness/integrity and explicitly recorded observations")
    inspect.add_argument("folder")
    assets = commands.add_parser("assets", help="Discover/import declared VFX data from game_assets")
    actions = assets.add_subparsers(dest="assets_action", required=True)
    listing = actions.add_parser("list")
    listing.add_argument("--repo", default="../game_assets")
    transfer = actions.add_parser("import")
    transfer.add_argument("package", help="Factory-relative assets/... package")
    transfer.add_argument("--repo", default="../game_assets")
    transfer.add_argument("--candidate", action="store_true", help="Fresh build only; import into ignored preview storage")
    transfer.add_argument("--license-note", required=True)
    transfer.add_argument("--name", help="Fresh destination slug; never overwrite existing outputs")
    args = parser.parse_args()
    try:
        if args.command == "catalog":
            for name, entry in catalog()["families"].items():
                print(f"{name}: {entry['role']}\n  preset: {entry['profile']}\n  cases: {', '.join(entry['cases'])}")
            return 0
        if args.command == "assets":
            from vfx_asset_bridge import command
            return command(args, ROOT)
        if args.command == "capture" and not 1 <= args.timeout <= 1800:
            raise ValueError("Suite timeout must be 1–1800 seconds.")
        return {"doctor": doctor, "init": init_trial, "capture": capture, "check": check}[args.command](args)
    except (ValueError, OSError, subprocess.SubprocessError, KeyError) as error:
        print(f"FAIL: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())

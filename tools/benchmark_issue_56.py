"""Run one unchanged Godot harness against actual baseline/candidate checkouts."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import statistics
import subprocess
import time


def git(root: Path, *arguments: str) -> str:
    return subprocess.run(["git", *arguments], cwd=root, timeout=60, check=True,
                          capture_output=True, text=True, encoding="utf-8").stdout.strip()


def identity(root: Path) -> dict:
    paths = git(root, "ls-files", "scripts", "src", "scenes").splitlines()
    # Newly authored candidate sources are included, even before their final commit.
    paths.extend(str(p.relative_to(root)).replace("\\", "/")
                 for folder in ("scripts", "src", "scenes")
                 for p in (root / folder).rglob("*")
                 if p.suffix in {".gd", ".cpp", ".h", ".tscn"})
    hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest()
              for name in sorted(set(paths)) if (root / name).is_file()}
    binaries = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                for p in (root / "bin").glob("*.dll")}
    return {"path": str(root), "head": git(root, "rev-parse", "HEAD"),
            "source_sha256": hashes, "binary_sha256": binaries}


def summary(values: list[float]) -> dict[str, float]:
    ordered = sorted(values)
    if not ordered:
        raise ValueError("Missing measured samples")
    return {"median": statistics.median(ordered),
            "p95": ordered[math.ceil(len(ordered) * .95) - 1],
            "p99": ordered[math.ceil(len(ordered) * .99) - 1],
            "maximum": ordered[-1]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--frames", type=int, default=240)
    parser.add_argument("--counts", default="14,20,100,500")
    parser.add_argument("--timeout", type=float, default=300)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    harness = Path(__file__).with_suffix(".gd").resolve()
    metadata = {"started_at_utc": datetime.now(timezone.utc).isoformat(),
                "harness_sha256": hashlib.sha256(harness.read_bytes()).hexdigest(),
                "hardware": {"platform": platform.platform(), "processor": platform.processor(),
                             "logical_cpus": os.cpu_count()}, "versions": {}}
    deadline = time.monotonic() + args.timeout
    for label, checkout in (("baseline", args.baseline), ("candidate", args.candidate)):
        checkout = checkout.resolve()
        if label == "baseline" and git(checkout, "diff", "HEAD", "--", "scripts", "src", "scenes"):
            raise SystemExit("Baseline gameplay sources have modifications")
        metadata["versions"][label] = identity(checkout)
        output = (args.output_dir / f"{label}.json").resolve()
        command = [str(args.godot.resolve()), "--headless", "--path", str(checkout),
                   "-s", str(harness), "--", "--label", label, "--output", str(output),
                   "--frames", str(args.frames), "--counts", args.counts]
        metadata["versions"][label]["command"] = command
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError("Paired benchmark total deadline expired")
        completed = subprocess.run(command, cwd=checkout, timeout=remaining, capture_output=True,
                                   text=True, encoding="utf-8", errors="replace",
                                   env=dict(os.environ, CUBE_SIEGE_TEST_PROFILE=f"user://test_profile/benchmark56/{label}/"))
        log = completed.stdout + completed.stderr
        (args.output_dir / f"{label}.log").write_text(log, encoding="utf-8")
        print(log[-2000:], flush=True)
        if completed.returncode or "ERROR:" in log or "Parse Error:" in log:
            raise SystemExit(f"{label} benchmark failed; see {label}.log")
        measured = json.loads(output.read_text(encoding="utf-8"))
        for row in measured["results"]:
            if any(len(row[name]) != args.frames for name in
                   ("callback_ms", "engine_physics_monitor_ms", "memory_bytes")):
                raise SystemExit(f"{label} measurement window did not contain exactly {args.frames} samples")
            row["callback_summary_ms"] = summary(row["callback_ms"])
            row["memory_summary_bytes"] = summary(row["memory_bytes"])
            if row["scenario"] == "moving_target_real_wall" and not row["wall_removed"]:
                raise SystemExit("Dynamic physical wall destruction was not observed")
        output.write_text(json.dumps(measured, indent=2), encoding="utf-8")
    (args.output_dir / "manifest.json").write_text(json.dumps(metadata, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()

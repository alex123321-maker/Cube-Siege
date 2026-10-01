"""Consume game_assets VFX packages; never build, approve or modify the factory."""
from __future__ import annotations

import hashlib
import json
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

DATA_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".wav", ".ogg", ".glb", ".json", ".txt"}


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def local(base: Path, name: str) -> Path:
    if not isinstance(name, str) or not name or Path(name).is_absolute():
        raise ValueError("Expected a relative package path")
    path = (base / name).resolve()
    if not path.is_relative_to(base.resolve()):
        raise ValueError("Package path escapes its source: " + name)
    return path


def factory(value: str, game_root: Path) -> Path:
    repo = (game_root / value).resolve()
    if not (repo / "tools/quality_gate.py").is_file() or not (repo / "assets").is_dir():
        raise ValueError("Not a game_assets checkout: tools/quality_gate.py and assets are required")
    return repo


def discover(repo: Path) -> list[dict]:
    result = []
    for path in sorted((repo / "assets").rglob("manifest.json")):
        manifest = read(path)
        if manifest.get("type") != "vfx":
            continue
        result.append({"package": path.parent.relative_to(repo).as_posix(), "name": manifest.get("name"),
                       "quality_contract": (path.parent / "quality.json").is_file(),
                       "evidence_receipt": (path.parent / "review/evidence.json").is_file(),
                       "visual_review": (path.parent / "review/visual_review.json").is_file(),
                       "status": "DISCOVERED; run upstream gate, not approved"})
    return result


def exports(repo: Path, name: str) -> tuple[Path, dict[str, Path]]:
    package = local(repo, name)
    if not package.is_relative_to(repo / "assets"):
        raise ValueError("Package must be under factory assets/")
    manifest = read(package / "manifest.json")
    if manifest.get("type") != "vfx":
        raise ValueError("This bridge imports VFX packages only")
    declared = manifest.get("outputs")
    if not isinstance(declared, dict) or not declared:
        raise ValueError("manifest.outputs must declare nonempty exports")
    files = {}
    for name in declared.values():
        output = local(package, name)
        if not output.is_relative_to(package / "output") or not output.exists():
            raise ValueError("Export must exist below package output/: " + name)
        candidates = sorted(output.rglob("*")) if output.is_dir() else [output]
        for item in candidates:
            if not item.is_file():
                continue
            actual = item.resolve()
            if not actual.is_relative_to(package / "output"):
                raise ValueError("Linked export leaves package output/")
            if item.suffix.lower() not in DATA_SUFFIXES:
                raise ValueError("Unsupported runtime data export (dependencies need explicit integration): " + str(item))
            if item.suffix.lower() == ".glb":
                check_self_contained_glb(item)
            files[item.relative_to(package / "output").as_posix()] = item
    if not files:
        raise ValueError("No declared export files")
    return package, files


def check_self_contained_glb(path: Path) -> None:
    raw = path.read_bytes()
    if len(raw) < 20 or raw[:4] != b"glTF":
        raise ValueError("Invalid GLB: " + str(path))
    magic, version, total, chunk_size, kind = struct.unpack_from("<4sIIII", raw)
    if version != 2 or total != len(raw) or kind != 0x4E4F534A or 20 + chunk_size > len(raw):
        raise ValueError("Invalid GLB header/JSON chunk: " + str(path))
    metadata = json.loads(raw[20:20 + chunk_size])
    for item in metadata.get("buffers", []) + metadata.get("images", []):
        uri = item.get("uri")
        if uri is not None and not uri.startswith("data:"):
            raise ValueError("GLB has an external buffer/image; re-export self-contained: " + uri)


def run_gate(repo: Path, package: Path, candidate: bool, log: Path) -> dict:
    command = [sys.executable, str(repo / "tools/quality_gate.py"), "check", str(package)]
    if not candidate:
        command.append("--require-review")
    with log.open("w", encoding="utf-8") as output:
        result = subprocess.run(command, cwd=repo, stdout=output, stderr=subprocess.STDOUT,
                                timeout=60, check=False)
    text = log.read_text(encoding="utf-8", errors="replace")
    if result.returncode != 0 or "[OK] check:" not in text:
        raise ValueError("Upstream quality gate failed:\n" + text[-5000:])
    return {"command": command, "exit_code": result.returncode,
            "mode": "fresh_build_only" if candidate else "current_recorded_visual_review",
            "art_approval": "Not established by this importer"}


def import_package(game_root: Path, repo: Path, name: str, candidate: bool, license_note: str,
                   destination_name: str | None = None) -> Path:
    package, files = exports(repo, name)
    slug = destination_name or package.name
    if not re.fullmatch(r"[a-z][a-z0-9_]{1,63}", slug):
        raise ValueError("Destination name must be a lowercase package slug")
    if len(license_note.strip()) < 12:
        raise ValueError("Record the concrete rights/license source with --license-note before import")
    base = game_root / ("screenshots_debug/vfx_workbench/assets" if candidate else "assets/vfx/imported")
    base.mkdir(parents=True, exist_ok=True)
    destination = base / slug
    # No overwrite/update ambiguity: every changed delivery needs a fresh named package.
    if destination.exists():
        raise ValueError("Destination exists; preserve local work and choose a fresh --name")
    with tempfile.TemporaryDirectory(prefix=".vfx-import-", dir=base) as temporary:
        staging = Path(temporary)
        gate = run_gate(repo, package, candidate, staging / "upstream_gate.log")
        evidence = read(package / "review/evidence.json")
        receipt = {"schema_version": 1, "factory_checkout": str(repo),
                   "factory_package": package.relative_to(repo).as_posix(),
                   "upstream_evidence_digest": evidence["digest"], "upstream_gate": gate,
                   "status": "CANDIDATE_ONLY" if candidate else "UPSTREAM_REVIEW_RECORDED; NEEDS_GAME_VALIDATION",
                   "license_note": license_note, "imported_utc": datetime.now(timezone.utc).isoformat(), "files": []}
        for relative, path in files.items():
            target = staging / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
            receipt["files"].append({"path": relative, "sha256": hashlib.sha256(target.read_bytes()).hexdigest(),
                                     "source": path.relative_to(repo).as_posix()})
        snapshots = ["request.md", "manifest.json", "quality.json", "review/evidence.json", "review/visual_review.json"]
        for relative in snapshots:
            path = package / relative
            if path.is_file():
                target = staging / "upstream" / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
        # Keep original rights/provenance documents, even when not runtime exports.
        for path in package.rglob("*"):
            if path.is_file() and path.name.lower() in {"license", "license.txt", "license.md", "copying", "provenance.json"}:
                if not path.resolve().is_relative_to(package):
                    raise ValueError("Linked provenance leaves package")
                target = staging / "upstream" / path.relative_to(package)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
        # Gate again after copy to catch a changing build/review, then compare exported bytes.
        run_gate(repo, package, candidate, staging / "upstream_gate.log")
        for item in receipt["files"]:
            if hashlib.sha256((repo / item["source"]).read_bytes()).hexdigest() != item["sha256"]:
                raise ValueError("Upstream export changed during import; retry after authoring settles")
        if read(package / "review/evidence.json")["digest"] != receipt["upstream_evidence_digest"]:
            raise ValueError("Upstream evidence changed during import")
        (staging / "IMPORT_RECEIPT.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        if destination.exists():
            raise ValueError("Destination appeared during import; choose a fresh --name")
        staging.rename(destination)
    return destination


def command(args: object, game_root: Path) -> int:
    repo = factory(args.repo, game_root)
    if args.assets_action == "list":
        packages = discover(repo)
        print(json.dumps({"factory": str(repo), "vfx_packages": packages}, ensure_ascii=False, indent=2))
        if not packages:
            print("No VFX packages yet. See docs/vfx/GAME_ASSETS.md for the factory handoff.")
        return 0
    destination = import_package(game_root, repo, args.package, args.candidate, args.license_note, args.name)
    print("Imported data: " + str(destination))
    print("Preserved upstream status; run Godot import and production-camera review before integration.")
    return 0

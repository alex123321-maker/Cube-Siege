"""Validate the Blender runtime and built-in glTF/Python capabilities."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import bpy


def script_args() -> list[str]:
    return sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path)
    args = parser.parse_args(script_args())

    version = tuple(bpy.app.version)
    checks = {
        "version_at_least_5_2": version >= (5, 2, 0),
        "python_executes": True,
        "gltf_export_operator": hasattr(bpy.ops.export_scene, "gltf"),
        "gltf_import_operator": hasattr(bpy.ops.import_scene, "gltf"),
        "eevee_available": bool(
            {"BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"}
            & {item.identifier for item in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items}
        ),
    }
    report = {
        "blender_version": bpy.app.version_string,
        "python_version": sys.version.split()[0],
        "background": bpy.app.background,
        "checks": checks,
        "ok": all(checks.values()),
    }
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("ART_PIPELINE_BLENDER_VALIDATION=" + json.dumps(report, sort_keys=True))
    if not report["ok"]:
        raise SystemExit(1)


main()

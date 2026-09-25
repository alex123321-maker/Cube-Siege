"""Validate and export the EXPORT collection to game-ready GLB/glTF 2.0."""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

import bpy


def args_after_separator() -> list[str]:
    return sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []


def nearly(value: float, target: float, epsilon: float = 1e-5) -> bool:
    return abs(value - target) <= epsilon


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--collection", default="EXPORT")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args(args_after_separator())

    collection = bpy.data.collections.get(args.collection)
    if collection is None:
        raise RuntimeError(f"Required export collection '{args.collection}' was not found")
    candidates = [obj for obj in collection.all_objects if obj.type in {"MESH", "ARMATURE", "EMPTY"}]
    meshes = [obj for obj in candidates if obj.type == "MESH"]
    armatures = [obj for obj in candidates if obj.type == "ARMATURE"]
    if not meshes:
        raise RuntimeError("EXPORT collection contains no meshes")

    unapplied = []
    for obj in candidates:
        if obj.type != "MESH":
            continue
        if any(not nearly(component, 1.0) for component in obj.scale):
            unapplied.append(f"{obj.name}: scale={tuple(round(v, 6) for v in obj.scale)}")
    if unapplied:
        raise RuntimeError("Unapplied mesh scale is not allowed:\n" + "\n".join(unapplied))

    bpy.ops.object.select_all(action="DESELECT")
    for obj in candidates:
        obj.hide_set(False)
        obj.select_set(True)
    bpy.context.view_layer.objects.active = armatures[0] if armatures else meshes[0]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(args.output.resolve()),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_apply=True,
        export_materials="EXPORT",
        export_texcoords=True,
        export_normals=True,
        export_skins=True,
        export_animations=True,
        export_animation_mode=bpy.context.scene.get("gltf_animation_mode", "ACTIONS"),
        # Rigid NLA rigs also need constant pose channels (e.g. idle sword angle).
        export_optimize_animation_size=True,
        export_optimize_animation_keep_anim_object=True,
        export_extras=True,
        export_cameras=False,
        export_lights=False,
    )
    # Report the exported clips, not all per-object Blender actions (NLA joins these).
    with args.output.open("rb") as glb:
        glb.seek(12)
        json_size, chunk_type = struct.unpack("<II", glb.read(8))
        if chunk_type != 0x4E4F534A:
            raise RuntimeError("GLB is missing its JSON chunk")
        exported = json.loads(glb.read(json_size))
    report = {
        "output": str(args.output.resolve()),
        "bytes": args.output.stat().st_size,
        "mesh_objects": [obj.name for obj in meshes],
        "armatures": [obj.name for obj in armatures],
        "materials": sorted({slot.material.name for obj in meshes for slot in obj.material_slots if slot.material}),
        "animations": sorted(clip.get("name", "") for clip in exported.get("animations", [])),
        "scale_contract": "1 Blender unit = 1 metre; Z-up; front=-Y; glTF Y-up -> Godot front=+Z",
    }
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("ART_PIPELINE_GLTF_EXPORT=" + json.dumps(report, sort_keys=True))


main()

"""Build a locked, consistently scaled orthographic concept-sheet collection."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy


REFERENCE_COLLECTION = "REFERENCES"


def args_after_separator() -> list[str]:
    return sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []


def clear_existing_collection() -> None:
    existing = bpy.data.collections.get(REFERENCE_COLLECTION)
    if not existing:
        return
    for obj in list(existing.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(existing)


def add_reference(collection: bpy.types.Collection, name: str, image_path: Path, location: tuple[float, float, float], rotation: tuple[float, float, float], size: float) -> bpy.types.Object:
    if not image_path.is_file():
        raise FileNotFoundError(f"Reference image does not exist: {image_path}")
    image = bpy.data.images.load(str(image_path.resolve()), check_existing=True)
    empty = bpy.data.objects.new(name, None)
    empty.empty_display_type = "IMAGE"
    empty.data = image
    empty.empty_display_size = size
    empty.empty_image_depth = "BACK"
    empty.color[3] = 0.55
    empty.show_in_front = False
    empty.hide_select = True
    empty.hide_render = True
    empty.location = location
    empty.rotation_euler = rotation
    empty["reference_view"] = name.removeprefix("REF_").lower()
    empty["source_path"] = str(image_path.resolve())
    collection.objects.link(empty)
    return empty


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--front", required=True, type=Path)
    parser.add_argument("--side", type=Path, help="Single side view (placed as the right-side reference)")
    parser.add_argument("--left", type=Path, help="Optional explicit left-side view")
    parser.add_argument("--right", type=Path, help="Optional explicit right-side view")
    parser.add_argument("--back", required=True, type=Path)
    parser.add_argument("--three-quarter", dest="three_quarter", type=Path)
    parser.add_argument("--scale", type=float, default=2.0, help="Common empty display size in Blender metres")
    parser.add_argument("--offset", type=float, default=0.75, help="Distance from origin in metres")
    parser.add_argument("--output-blend", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args(args_after_separator())
    if not any((args.side, args.left, args.right)):
        parser.error("Provide --side or at least one of --left/--right")

    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    clear_existing_collection()
    collection = bpy.data.collections.new(REFERENCE_COLLECTION)
    scene.collection.children.link(collection)
    collection["purpose"] = "Locked concept-sheet references; never export"

    created = [
        add_reference(collection, "REF_FRONT", args.front, (0.0, args.offset, args.scale / 2), (math.radians(90), 0.0, 0.0), args.scale),
        add_reference(collection, "REF_BACK", args.back, (0.0, -args.offset, args.scale / 2), (math.radians(-90), 0.0, 0.0), args.scale),
    ]
    if args.side:
        created.append(add_reference(collection, "REF_SIDE", args.side, (args.offset, 0.0, args.scale / 2), (math.radians(90), 0.0, math.radians(90)), args.scale))
    if args.left:
        created.append(add_reference(collection, "REF_LEFT", args.left, (-args.offset, 0.0, args.scale / 2), (math.radians(90), 0.0, math.radians(-90)), args.scale))
    if args.right:
        created.append(add_reference(collection, "REF_RIGHT", args.right, (args.offset, 0.0, args.scale / 2), (math.radians(90), 0.0, math.radians(90)), args.scale))
    if args.three_quarter:
        created.append(
            add_reference(
                collection,
                "REF_THREE_QUARTER",
                args.three_quarter,
                (-args.offset, args.offset, args.scale / 2),
                (math.radians(90), 0.0, math.radians(-45)),
                args.scale,
            )
        )

    args.output_blend.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output_blend.resolve()))
    report = {
        "collection": REFERENCE_COLLECTION,
        "count": len(created),
        "common_scale_m": args.scale,
        "locked": all(obj.hide_select for obj in created),
        "hidden_from_render": all(obj.hide_render for obj in created),
        "views": {obj.name: {"location": list(obj.location), "source": obj["source_path"]} for obj in created},
        "output_blend": str(args.output_blend.resolve()),
    }
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("ART_PIPELINE_REFERENCE_SETUP=" + json.dumps(report, sort_keys=True))


main()

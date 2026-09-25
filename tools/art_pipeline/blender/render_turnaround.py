"""Render five neutral, repeatable review views from the currently opened .blend."""

from __future__ import annotations

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector


REVIEW_OBJECTS = "ART_PIPELINE_REVIEW"


def args_after_separator() -> list[str]:
    return sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []


def world_bounds(objects: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    points = [obj.matrix_world @ Vector(corner) for obj in objects for corner in obj.bound_box]
    if not points:
        raise RuntimeError("No visible mesh bounds found")
    return (
        Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points))),
        Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points))),
    )


def look_at(camera: bpy.types.Object, target: Vector) -> None:
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()


def make_material(name: str, color: tuple[float, float, float, float]) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.diffuse_color = color
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = color
    principled.inputs["Roughness"].default_value = 0.82
    return material


def add_area(collection: bpy.types.Collection, name: str, location: tuple[float, float, float], energy: float, size: float, target: Vector) -> None:
    data = bpy.data.lights.new(name, type="AREA")
    data.energy = energy
    data.shape = "DISK"
    data.size = size
    light = bpy.data.objects.new(name, data)
    collection.objects.link(light)
    light.location = location
    light.rotation_euler = (target - light.location).to_track_quat("-Z", "Y").to_euler()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--resolution", type=int, default=512)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args(args_after_separator())
    args.output_dir.mkdir(parents=True, exist_ok=True)

    scene = bpy.context.scene
    engines = {item.identifier for item in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items}
    scene.render.engine = "BLENDER_EEVEE" if "BLENDER_EEVEE" in engines else "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = args.resolution
    scene.render.resolution_y = args.resolution
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.filepath = ""
    if scene.world is None:
        scene.world = bpy.data.worlds.new("ReviewWorld")
    scene.world.color = (0.055, 0.055, 0.055)
    scene.view_settings.look = "AgX - Medium High Contrast"

    old = bpy.data.collections.get(REVIEW_OBJECTS)
    if old:
        for obj in list(old.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(old)
    review = bpy.data.collections.new(REVIEW_OBJECTS)
    scene.collection.children.link(review)

    render_meshes = [
        obj
        for obj in scene.objects
        if obj.type == "MESH" and not obj.hide_render and not obj.name.startswith("ReviewGround")
    ]
    minimum, maximum = world_bounds(render_meshes)
    center = (minimum + maximum) * 0.5
    size = maximum - minimum
    largest = max(size.x, size.y, size.z, 0.1)
    center.z = minimum.z + size.z * 0.52

    bpy.ops.mesh.primitive_plane_add(size=max(8.0, largest * 6.0), location=(center.x, center.y, minimum.z - 0.002))
    ground = bpy.context.object
    ground.name = "ReviewGround"
    for owner in list(ground.users_collection):
        owner.objects.unlink(ground)
    review.objects.link(ground)
    ground.data.materials.append(make_material("ReviewGroundMaterial", (0.12, 0.12, 0.12, 1.0)))

    camera_data = bpy.data.cameras.new("ReviewCamera")
    camera = bpy.data.objects.new("ReviewCamera", camera_data)
    review.objects.link(camera)
    scene.camera = camera
    camera.data.lens = 52.0
    camera.data.dof.use_dof = False

    light_radius = largest * 2.5
    add_area(review, "ReviewKey", (center.x - light_radius, center.y - light_radius, center.z + light_radius * 1.5), 900.0, largest * 2.0, center)
    add_area(review, "ReviewFill", (center.x + light_radius, center.y - light_radius * 0.3, center.z + light_radius), 450.0, largest * 2.5, center)
    add_area(review, "ReviewRim", (center.x, center.y + light_radius, center.z + light_radius), 650.0, largest * 1.5, center)

    distance = largest * 3.2
    views = {
        "front": Vector((center.x, center.y - distance, center.z)),
        "side": Vector((center.x - distance, center.y, center.z)),
        "back": Vector((center.x, center.y + distance, center.z)),
        "three_quarter": Vector((center.x - distance * 0.72, center.y - distance * 0.72, center.z + largest * 0.12)),
        "gameplay": Vector((center.x + distance * 0.75, center.y - distance * 0.75, center.z + distance)),
    }
    rendered: dict[str, str] = {}
    for name, location in views.items():
        camera.location = location
        camera.data.type = "PERSP" if name == "gameplay" else "ORTHO"
        camera.data.ortho_scale = largest * 1.35
        camera.data.lens = 52.0
        look_at(camera, center)
        output = (args.output_dir / f"{name}.png").resolve()
        scene.render.filepath = str(output)
        bpy.ops.render.render(write_still=True)
        rendered[name] = str(output)

    report = {
        "renders": rendered,
        "resolution": args.resolution,
        "engine": scene.render.engine,
        "bounds_blender_m": {"min": list(minimum), "max": list(maximum), "size": list(size)},
        "lighting": ["ReviewKey", "ReviewFill", "ReviewRim"],
        "neutral_review": True,
    }
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("ART_PIPELINE_TURNAROUND=" + json.dumps(report, sort_keys=True))


main()

"""Create a non-production, two-metre calibration blockout with a tiny test rig."""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bpy


def args_after_separator() -> list[str]:
    return sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []


def material(name: str, color: tuple[float, float, float, float], metallic: float = 0.0) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = color
    principled = mat.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = color
    principled.inputs["Roughness"].default_value = 0.72
    principled.inputs["Metallic"].default_value = metallic
    return mat


def cube(name: str, location: tuple[float, float, float], dimensions: tuple[float, float, float], mat: bpy.types.Material) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    return obj


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-blend", required=True, type=Path)
    args = parser.parse_args(args_after_separator())
    bpy.ops.wm.read_factory_settings(use_empty=True)

    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0
    scene["asset_kind"] = "pipeline_calibration_blockout_not_production_art"
    scene["scale_contract"] = "1 Blender unit = 1 metre; base at Z=0; front=-Y"

    export_collection = bpy.data.collections.new("EXPORT")
    scene.collection.children.link(export_collection)
    body_mat = material("CalibrationBlue", (0.08, 0.28, 0.62, 1.0))
    front_mat = material("FrontMarkerOrange", (1.0, 0.2, 0.03, 1.0))
    ground_mat = material("GroundMarker", (0.14, 0.14, 0.14, 1.0))

    pieces = [
        cube("CalibrationBody", (0.0, 0.0, 0.8), (0.8, 0.5, 1.6), body_mat),
        cube("CalibrationHead", (0.0, 0.0, 1.8), (0.6, 0.6, 0.4), body_mat),
        cube("FrontMarker", (0.0, -0.38, 1.1), (0.28, 0.26, 0.28), front_mat),
        cube("GroundScaleMarker", (0.0, 0.0, 0.025), (1.0, 1.0, 0.05), ground_mat),
    ]
    for obj in pieces:
        for collection in list(obj.users_collection):
            collection.objects.unlink(obj)
        export_collection.objects.link(obj)
        obj["pipeline_test_only"] = True

    armature_data = bpy.data.armatures.new("CalibrationSkeleton")
    armature = bpy.data.objects.new("CalibrationSkeleton", armature_data)
    export_collection.objects.link(armature)
    bpy.context.view_layer.objects.active = armature
    armature.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    root_bone = armature_data.edit_bones.new("Root")
    root_bone.head = (0.0, 0.0, 0.0)
    root_bone.tail = (0.0, 0.0, 1.0)
    marker_bone = armature_data.edit_bones.new("Marker")
    marker_bone.head = (0.0, 0.0, 1.0)
    marker_bone.tail = (0.0, 0.0, 2.0)
    marker_bone.parent = root_bone
    marker_bone.use_connect = True
    bpy.ops.object.mode_set(mode="POSE")

    marker_pose = armature.pose.bones["Marker"]
    marker_pose.rotation_mode = "XYZ"
    action = bpy.data.actions.new("calibration_idle")
    armature.animation_data_create()
    armature.animation_data.action = action
    for frame, angle in ((1, 0.0), (12, math.radians(5.0)), (24, 0.0)):
        marker_pose.rotation_euler[1] = angle
        marker_pose.keyframe_insert(data_path="rotation_euler", frame=frame)
    scene.frame_start = 1
    scene.frame_end = 24
    bpy.ops.object.mode_set(mode="OBJECT")
    armature.select_set(False)

    for obj in pieces:
        world_transform = obj.matrix_world.copy()
        obj.parent = armature
        obj.parent_type = "BONE"
        obj.parent_bone = "Marker" if obj.location.z >= 1.0 else "Root"
        obj.matrix_world = world_transform

    args.output_blend.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(args.output_blend.resolve()))
    print(f"Created calibration blockout: {args.output_blend.resolve()}")


main()

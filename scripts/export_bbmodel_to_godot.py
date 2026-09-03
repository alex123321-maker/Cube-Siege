"""
export_bbmodel_to_godot.py
Converts hero_warrior.bbmodel into a native Godot 4 scene (hero_warrior.tscn).
Builds:
- Node3D skeletal hierarchy matching Blockbench bones
- BoxMesh instances with scaled dimensions and offsets from bone pivots
- Beautiful stylized PBR materials (metal, cloth, armor, gold)
- AnimationPlayer with idle, walk, attack, and block animations
"""

import json
import math
import os

SCALE = 0.055  # 32 units * 0.055 = ~1.76m height in Godot

# Material definitions corresponding to Blockbench colors
PALETTE_COLORS = {
    0: {"albedo": "Color(0.25, 0.45, 0.75, 1)", "metallic": 0.1, "roughness": 0.8},    # Base tunic / blue cloth
    1: {"albedo": "Color(0.18, 0.22, 0.32, 1)", "metallic": 0.0, "roughness": 0.9},    # Dark under-tunic
    3: {"albedo": "Color(0.95, 0.78, 0.22, 1)", "metallic": 0.85, "roughness": 0.25},  # Gold trim / guard / pommel
    4: {"albedo": "Color(0.35, 0.22, 0.15, 1)", "metallic": 0.0, "roughness": 0.85},   # Leather grip
    5: {"albedo": "Color(0.85, 0.15, 0.18, 1)", "metallic": 0.1, "roughness": 0.5},    # Red plume / red shield
    7: {"albedo": "Color(0.55, 0.58, 0.62, 1)", "metallic": 0.6, "roughness": 0.4},    # Iron visor / greaves
    8: {"albedo": "Color(0.75, 0.80, 0.88, 1)", "metallic": 0.8, "roughness": 0.25},   # Steel breastplate / boss
    9: {"albedo": "Color(0.88, 0.92, 0.96, 1)", "metallic": 0.9, "roughness": 0.2}     # Polished steel blade
}

def load_bbmodel(filepath):
    with open(filepath, "r", encoding="utf-8") as f:
        return json.load(f)

def build_tree_maps(node, parent_name=None, bone_dict={}, element_to_bone={}, bone_paths={}, current_path=""):
    if isinstance(node, str):
        element_to_bone[node] = parent_name
        return

    b_name = node["name"]
    b_uuid = node["uuid"]
    b_origin = node.get("origin", [0, 0, 0])
    
    path = f"{current_path}/{b_name}" if current_path else b_name
    bone_paths[b_name] = path
    bone_paths[b_uuid] = path

    bone_dict[b_name] = {
        "uuid": b_uuid,
        "name": b_name,
        "origin": b_origin,
        "parent": parent_name,
        "children": [],
        "elements": []
    }
    if parent_name and parent_name in bone_dict:
        bone_dict[parent_name]["children"].append(b_name)

    for ch in node.get("children", []):
        if isinstance(ch, str):
            bone_dict[b_name]["elements"].append(ch)
            element_to_bone[ch] = b_name
        else:
            build_tree_maps(ch, b_name, bone_dict, element_to_bone, bone_paths, path)

def generate_tscn(bbmodel, output_path):
    elements = {e["uuid"]: e for e in bbmodel["elements"]}
    bone_dict = {}
    element_to_bone = {}
    bone_paths = {}

    for root_node in bbmodel.get("outliner", []):
        build_tree_maps(root_node, None, bone_dict, element_to_bone, bone_paths, "")

    lines = []
    lines.append('[gd_scene load_steps=100 format=3 uid="uid://hero_warrior_model_01"]')
    lines.append("")

    # 1. Materials SubResources
    mat_ids = {}
    for col_idx, col_data in PALETTE_COLORS.items():
        res_id = f"StandardMaterial3D_col_{col_idx}"
        mat_ids[col_idx] = res_id
        lines.append(f'[sub_resource type="StandardMaterial3D" id="{res_id}"]')
        lines.append(f'albedo_color = {col_data["albedo"]}')
        lines.append(f'metallic = {col_data["metallic"]}')
        lines.append(f'roughness = {col_data["roughness"]}')
        lines.append("")

    # 2. BoxMeshes SubResources
    mesh_ids = {}
    for el_uuid, el in elements.items():
        p_from = el["from"]
        p_to = el["to"]
        sx = round(abs(p_to[0] - p_from[0]) * SCALE, 5)
        sy = round(abs(p_to[1] - p_from[1]) * SCALE, 5)
        sz = round(abs(p_to[2] - p_from[2]) * SCALE, 5)
        
        col_idx = el.get("color", 0)
        mat_id = mat_ids.get(col_idx, mat_ids[0])

        mesh_id = f"BoxMesh_{el['name']}"
        mesh_ids[el_uuid] = mesh_id
        lines.append(f'[sub_resource type="BoxMesh" id="{mesh_id}"]')
        lines.append(f'material = SubResource("{mat_id}")')
        lines.append(f'size = Vector3({sx}, {sy}, {sz})')
        lines.append("")

    # 3. Animations SubResources
    anim_subres_ids = {}
    for anim in bbmodel.get("animations", []):
        anim_name = anim["name"]
        anim_id = f"Animation_{anim_name}"
        anim_subres_ids[anim_name] = anim_id

        length = float(anim.get("length", 1.0))
        loop_mode = 1 if anim.get("loop") == "loop" else 0

        lines.append(f'[sub_resource type="Animation" id="{anim_id}"]')
        lines.append(f'resource_name = "{anim_name}"')
        lines.append(f'length = {length}')
        if loop_mode == 1:
            lines.append('loop_mode = 1')

        track_idx = 0
        animators = anim.get("animators", {})

        for b_uuid, track_data in animators.items():
            b_path = bone_paths.get(b_uuid)
            if not b_path:
                continue

            rot_kfs = track_data.get("rotation", [])
            pos_kfs = track_data.get("position", [])

            # Rotation Track
            if rot_kfs:
                times = []
                values = []
                for kf in rot_kfs:
                    t = float(kf["time"])
                    dp = kf["data_points"][0]
                    rx = round(math.radians(float(dp.get("x", 0))), 5)
                    ry = round(math.radians(float(dp.get("y", 0))), 5)
                    rz = round(math.radians(float(dp.get("z", 0))), 5)
                    times.append(str(round(t, 4)))
                    values.append(f"Vector3({rx}, {ry}, {rz})")

                lines.append(f'tracks/{track_idx}/type = "value"')
                lines.append(f'tracks/{track_idx}/imported = false')
                lines.append(f'tracks/{track_idx}/enabled = true')
                lines.append(f'tracks/{track_idx}/path = NodePath("{b_path}:rotation")')
                lines.append(f'tracks/{track_idx}/interp = 1')
                lines.append(f'tracks/{track_idx}/loop_wrap = true')
                lines.append(f'tracks/{track_idx}/keys = {{')
                lines.append(f'"times": PackedFloat32Array({", ".join(times)}),')
                lines.append(f'"transitions": PackedFloat32Array({", ".join(["1"] * len(times))}),')
                lines.append(f'"update": 0,')
                lines.append(f'"values": [{", ".join(values)}]')
                lines.append('}')
                track_idx += 1

            # Position Track
            if pos_kfs:
                times = []
                values = []
                # Compute rest position of this bone
                b_name = b_path.split("/")[-1]
                b_info = bone_dict.get(b_name)
                parent_origin = bone_dict[b_info["parent"]]["origin"] if b_info.get("parent") else [0, 0, 0]
                rest_px = round((b_info["origin"][0] - parent_origin[0]) * SCALE, 5)
                rest_py = round((b_info["origin"][1] - parent_origin[1]) * SCALE, 5)
                rest_pz = round((b_info["origin"][2] - parent_origin[2]) * SCALE, 5)

                for kf in pos_kfs:
                    t = float(kf["time"])
                    dp = kf["data_points"][0]
                    dx = float(dp.get("x", 0)) * SCALE
                    dy = float(dp.get("y", 0)) * SCALE
                    dz = float(dp.get("z", 0)) * SCALE
                    px = round(rest_px + dx, 5)
                    py = round(rest_py + dy, 5)
                    pz = round(rest_pz + dz, 5)
                    times.append(str(round(t, 4)))
                    values.append(f"Vector3({px}, {py}, {pz})")

                lines.append(f'tracks/{track_idx}/type = "value"')
                lines.append(f'tracks/{track_idx}/imported = false')
                lines.append(f'tracks/{track_idx}/enabled = true')
                lines.append(f'tracks/{track_idx}/path = NodePath("{b_path}:position")')
                lines.append(f'tracks/{track_idx}/interp = 1')
                lines.append(f'tracks/{track_idx}/loop_wrap = true')
                lines.append(f'tracks/{track_idx}/keys = {{')
                lines.append(f'"times": PackedFloat32Array({", ".join(times)}),')
                lines.append(f'"transitions": PackedFloat32Array({", ".join(["1"] * len(times))}),')
                lines.append(f'"update": 0,')
                lines.append(f'"values": [{", ".join(values)}]')
                lines.append('}')
                track_idx += 1

        lines.append("")

    # 4. AnimationLibrary
    lines.append('[sub_resource type="AnimationLibrary" id="AnimationLibrary_warrior"]')
    lines.append('_data = {')
    anim_entries = [f'"{name}": SubResource("{subres_id}")' for name, subres_id in anim_subres_ids.items()]
    lines.append(",\n".join(anim_entries))
    lines.append('}')
    lines.append("")

    # 5. Scene Hierarchy Nodes
    lines.append('[node name="HeroWarrior" type="Node3D"]')
    lines.append("")

    lines.append('[node name="AnimationPlayer" type="AnimationPlayer" parent="."]')
    lines.append('libraries = {')
    lines.append('"": SubResource("AnimationLibrary_warrior")')
    lines.append('}')
    lines.append("")

    def emit_bone_node(b_name, parent_godot_path="."):
        b_info = bone_dict[b_name]
        p_name = b_info["parent"]
        p_origin = bone_dict[p_name]["origin"] if p_name else [0, 0, 0]

        lx = round((b_info["origin"][0] - p_origin[0]) * SCALE, 5)
        ly = round((b_info["origin"][1] - p_origin[1]) * SCALE, 5)
        lz = round((b_info["origin"][2] - p_origin[2]) * SCALE, 5)

        lines.append(f'[node name="{b_name}" type="Node3D" parent="{parent_godot_path}"]')
        if lx != 0 or ly != 0 or lz != 0:
            lines.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {lx}, {ly}, {lz})')
        lines.append("")

        bone_godot_path = f"{parent_godot_path}/{b_name}" if parent_godot_path != "." else b_name

        for el_uuid in b_info["elements"]:
            el = elements[el_uuid]
            p_from = el["from"]
            p_to = el["to"]
            cx = (p_from[0] + p_to[0]) / 2.0
            cy = (p_from[1] + p_to[1]) / 2.0
            cz = (p_from[2] + p_to[2]) / 2.0

            mx = round((cx - b_info["origin"][0]) * SCALE, 5)
            my = round((cy - b_info["origin"][1]) * SCALE, 5)
            mz = round((cz - b_info["origin"][2]) * SCALE, 5)

            mesh_node_name = el["name"]
            mesh_res = mesh_ids[el_uuid]

            lines.append(f'[node name="{mesh_node_name}" type="MeshInstance3D" parent="{bone_godot_path}"]')
            if mx != 0 or my != 0 or mz != 0:
                lines.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {mx}, {my}, {mz})')
            lines.append(f'mesh = SubResource("{mesh_res}")')
            lines.append("")

        for child_b_name in b_info["children"]:
            emit_bone_node(child_b_name, bone_godot_path)

    for b_name, b_info in bone_dict.items():
        if not b_info["parent"]:
            emit_bone_node(b_name, ".")

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"Successfully generated Godot scene: {output_path}")

if __name__ == "__main__":
    bb = load_bbmodel("assets/models/sources/hero_warrior.bbmodel")
    generate_tscn(bb, "assets/models/characters/hero_warrior.tscn")

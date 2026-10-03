"""Generate original articulated, code-native voxel bosses. No external assets.

The Python part/animation definitions are the editable source. The adjacent JSON
is their reviewable serialization; scenes are deterministic native exports.
Run from this checkout; outputs are restricted to boss assets.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NAMES = ["cairn", "gorgon", "ash_oracle", "mortar", "rift_warden", "rift_harbinger"]
PALETTES = [
    ["59645f", "89938b", "c4b993", "222d2a", "ffb438", "605040"],
    ["344550", "657b82", "b4af9a", "202b34", "ff5940", "514a3d"],
    ["403449", "69515a", "b6a39a", "211e2c", "ff843e", "75402e"],
    ["4c545b", "8a9493", "b5a675", "21292f", "ffc247", "675238"],
    ["3e425f", "7c7398", "bbb4d4", "24263d", "bf76ff", "655679"],
    ["342642", "79627f", "cec2d2", "20152b", "fc66cc", "52364f"],
]


def part(bone, name, position, size, material=0, rotation=(0, 0, 0)):
    return dict(bone=bone, name=name, position=position, size=size, material=material, rotation=rotation)


def model(stage):
    parts = []
    def add(*args, **kwargs):
        parts.append(part(*args, **kwargs))
    # Shared articulation, distinct authored silhouettes and part arrangements.
    add("Body", "Pelvis", (0, -0.35, 0), (1.15, 0.50, 0.70), 3)
    add("Body", "Torso", (0, 0.30, 0), (1.55, 1.35, 0.85), 0)
    add("Body", "Core", (0, 0.45, -0.46), (0.40, 0.48, 0.12), 4)
    add("Head", "Face", (0, 0.13, 0), (0.80, 0.70, 0.65), 1)
    add("Head", "Brow", (0, 0.31, -0.35), (0.90, 0.16, 0.14), 0)
    for side, sign in [("L", -1), ("R", 1)]:
        add("Head", f"Eye{side}", (sign * 0.22, 0.13, -0.34), (0.19, 0.10, 0.10), 4)
        add(f"Arm{side}", f"UpperArm{side}", (sign * 0.08, -0.25, 0), (0.46, 0.68, 0.60), 0)
        add(f"Arm{side}", f"Forearm{side}", (sign * 0.10, -0.78, 0), (0.54, 0.55, 0.66), 1)
        add(f"Leg{side}", f"Shin{side}", (0, -0.35, 0), (0.47, 0.85, 0.54), 0)
        add(f"Leg{side}", f"Foot{side}", (0, -0.78, -0.12), (0.63, 0.28, 0.84), 1)
    if stage == 1:
        for sign in [-1, 1]:
            for tier in range(3):
                add("Body", f"CairnPlate{sign}_{tier}", (sign * (0.60 + tier * 0.18), 0.75 - tier * 0.18, 0.1), (0.80, 0.24, 0.95), 1 + tier % 2)
            add("ArmL" if sign < 0 else "ArmR", f"MassiveFist{sign}", (sign * 0.05, -1.02, -0.08), (0.9, 0.62, 0.98), 2)
        add("Head", "StoneCrest", (0, 0.57, 0.03), (0.37, 0.52, 0.49), 2)
        for i in range(3):
            add("Body", f"Seal{i}", (0, 0.76 - i * 0.27, -0.48), (0.22, 0.12, 0.10), 4)
    elif stage == 2:
        add("Body", "ShoulderMantle", (0, 0.72, 0.14), (2.22, 0.50, 1.04), 1)
        add("Head", "Snout", (0, -0.02, -0.43), (0.84, 0.43, 0.67), 0)
        for sign in [-1, 1]:
            add("Head", f"HornBase{sign}", (sign * 0.53, 0.36, 0), (0.31, 0.40, 0.39), 2)
            add("Head", f"HornTip{sign}", (sign * 0.72, 0.62, -0.02), (0.25, 0.62, 0.25), 2, (0, 0, -sign * 34))
            add("Head", f"Tusk{sign}", (sign * 0.29, -0.16, -0.79), (0.13, 0.35, 0.18), 2, (-18, 0, 0))
            add("ArmL" if sign < 0 else "ArmR", f"Gauntlet{sign}", (0, -0.91, -0.12), (0.71, 0.43, 0.81), 0)
        for i in range(4):
            add("Body", f"SpinePlate{i}", (0, 0.85 - i * 0.28, 0.62), (0.65, 0.18, 0.43), 1)
    elif stage == 3:
        for i in range(4):
            add("Body", f"RobeTier{i}", (0, -0.33 - i * 0.18, 0), (1.18 + i * 0.12, 0.27, 0.80 + i * 0.10), i % 2)
        add("Head", "HoodTop", (0, 0.51, 0.04), (1.03, 0.30, 0.82), 0)
        for sign in [-1, 1]:
            add("Head", f"HoodSide{sign}", (sign * 0.46, 0.15, 0.05), (0.23, 0.78, 0.80), 0)
            add("Body", f"Collar{sign}", (sign * 0.60, 0.82, -0.05), (0.35, 0.66, 0.57), 2, (0, 0, sign * 20))
        add("ArmR", "StaffShaft", (0.05, -0.62, -0.48), (0.16, 2.80, 0.16), 5)
        add("ArmR", "StaffCenser", (0.05, 0.88, -0.48), (0.75, 0.40, 0.62), 2)
        add("ArmR", "StaffFlame", (0.05, 1.28, -0.48), (0.31, 0.49, 0.31), 4)
        add("ArmL", "AshBook", (-0.15, -0.95, -0.27), (0.69, 0.13, 0.70), 2, (12, 0, -12))
    elif stage == 4:
        add("Body", "ArmoredFrame", (0, 0.40, 0.18), (1.93, 1.25, 1.18), 1)
        add("Body", "Boiler", (0, 0.60, 0.94), (1.25, 1.42, 0.58), 5)
        for sign in [-1, 1]:
            add("Body", f"Cannon{sign}", (sign * 0.68, 1.17, -0.18), (0.60, 0.68, 1.66), 0, (-25, 0, 0))
            add("Body", f"Muzzle{sign}", (sign * 0.68, 1.45, -0.96), (0.46, 0.44, 0.10), 3, (-25, 0, 0))
            add("Body", f"CannonRim{sign}", (sign * 0.68, 1.46, -0.87), (0.70, 0.60, 0.20), 2, (-25, 0, 0))
            add("LegL" if sign < 0 else "LegR", f"Support{sign}", (0, -0.62, 0.18), (0.84, 0.72, 0.98), 1)
            add("ArmL" if sign < 0 else "ArmR", f"Piston{sign}", (sign * 0.1, -0.62, -0.16), (0.61, 0.82, 0.68), 2)
        add("Head", "Visor", (0, 0.14, -0.43), (0.97, 0.25, 0.14), 3)
    elif stage == 5:
        for sign in [-1, 1]:
            add("Body", f"CrystalPauldron{sign}", (sign * 0.93, 0.77, 0.03), (0.76, 0.56, 0.97), 1, (0, 0, sign * 12))
            add("Head", f"CrownPoint{sign}", (sign * 0.38, 0.64, 0), (0.20, 0.62, 0.24), 2, (0, 0, -sign * 15))
        add("ArmR", "Greatblade", (0.05, -1.63, -0.05), (0.42, 1.90, 0.19), 2)
        add("ArmR", "BladeCore", (0.05, -1.63, -0.16), (0.12, 1.65, 0.05), 4)
        add("ArmR", "SwordGuard", (0.05, -0.64, -0.05), (0.85, 0.16, 0.30), 1)
        add("ArmL", "ShieldTop", (-0.19, -0.38, -0.43), (1.04, 0.83, 0.22), 1)
        add("ArmL", "ShieldBottom", (-0.19, -1.07, -0.43), (0.70, 0.65, 0.22), 0)
        add("ArmL", "ShieldSeal", (-0.19, -0.66, -0.58), (0.27, 0.60, 0.09), 4)
        for i in range(3):
            add("Body", f"Cloak{i}", (0, 0.45 - i * 0.39, 0.61), (1.38 - i * 0.12, 0.51, 0.15), 5)
    else:
        # Broken, floating architecture: no conventional feet or weapon silhouette.
        parts = [p for p in parts if not p["bone"].startswith("Leg")]
        add("Body", "LowerShard", (0, -0.80, 0.02), (0.63, 0.74, 0.60), 1, (0, 0, 8))
        add("Body", "RiftHeart", (0, 0.34, -0.60), (0.62, 0.66, 0.23), 4)
        for sign in [-1, 1]:
            add("Head", f"CrownShard{sign}", (sign * 0.50, 0.78, 0.04), (0.22, 0.81, 0.34), 2, (0, 0, -sign * 17))
            add("Head", f"HaloSide{sign}", (sign * 0.82, 0.30, 0.28), (0.19, 0.85, 0.19), 4)
            add("ArmL" if sign < 0 else "ArmR", f"FloatingPillar{sign}", (sign * 0.40, -0.55, 0.10), (0.63, 1.09, 0.58), 1, (0, 0, sign * 15))
            add("ArmL" if sign < 0 else "ArmR", f"PillarSeal{sign}", (sign * 0.40, -0.50, -0.23), (0.18, 0.65, 0.11), 4)
        add("Head", "HaloTop", (0, 0.98, 0.28), (1.57, 0.18, 0.19), 4)
        for i, x in enumerate([-0.63, 0.0, 0.63]):
            add("Body", f"OrbitShard{i}", (x, -1.12 + abs(x) * 0.4, 0.48), (0.32, 0.39, 0.32), 2, (10, 0, i * 20 - 20))
    return dict(name=NAMES[stage-1], stage=stage, palette=PALETTES[stage-1], parts=parts,
                author="Original Cube Siege code-native geometry authored for this request; no downloaded media",
                units="meters; bottom-center model pivot; faces -Z; gameplay root at half_height")


def vec(value):
    return "Vector3(" + ", ".join(f"{v:.5f}" for v in value) + ")"


def track(lines, index, path, times, values):
    lines += [f'tracks/{index}/type = "value"', f'tracks/{index}/path = NodePath("{path}")',
              f'tracks/{index}/interp = 1', f'tracks/{index}/keys = {{"times": PackedFloat32Array({", ".join(map(str, times))}), "transitions": PackedFloat32Array({", ".join("1" for _ in times)}), "update": 0, "values": [{", ".join(vec(v) for v in values)}]}}']


def export(data):
    stage, name = data["stage"], data["name"]
    lines = ['[gd_scene format=3]', '']
    for i, color in enumerate(data["palette"]):
        rgb = [int(color[j:j+2], 16) / 255 for j in (0, 2, 4)]
        lines += [f'[sub_resource type="StandardMaterial3D" id="Mat{i}"]',
                  f'albedo_color = Color({rgb[0]}, {rgb[1]}, {rgb[2]}, 1)', 'roughness = 0.8']
        if i == 4:
            lines += ['emission_enabled = true', f'emission = Color({rgb[0]}, {rgb[1]}, {rgb[2]}, 1)', 'emission_energy_multiplier = 1.5']
        lines += ['']
    for i, p in enumerate(data["parts"]):
        lines += [f'[sub_resource type="BoxMesh" id="Mesh{i}"]', f'material = SubResource("Mat{p["material"]}")', f'size = {vec(p["size"])}', '']
    animation_names = ["idle", "move", "attack_0", "attack_1", "attack_2", "death"]
    for animation in animation_names:
        lines += [f'[sub_resource type="Animation" id="Anim_{animation}"]', f'resource_name = "{animation}"', 'length = 1.0']
        if animation in ("idle", "move"):
            lines += ['loop_mode = 1']
        if animation == "idle":
            lift = .17 if stage == 6 else .055
            track(lines, 0, "Body:position", [0, .5, 1], [(0, 1.5, 0), (0, 1.5+lift, 0), (0, 1.5, 0)])
        elif animation == "move":
            for i, (bone, sign) in enumerate([( "LegL",1), ("LegR",-1), ("ArmL",-1), ("ArmR",1)]):
                track(lines, i, f"{bone}:rotation", [0,.25,.75,1], [(0,0,0),(.27*sign,0,0),(-.27*sign,0,0),(0,0,0)])
        elif animation.startswith("attack_"):
            action = int(animation[-1])
            raise_angle = math.radians([105, 55, 85][action] + stage * 3)
            # Distinct whole-body pose and arm commitment for each encounter and action.
            track(lines, 0, "Body:rotation", [0,.5,.65,.72,.8,1], [(0,0,0),(-.12,0,.04*(stage%2)),(-.18,0,.04),( .23,0,-.04),( .14,0,0),(0,0,0)])
            for i, (bone, sign) in enumerate([("ArmL",-1),("ArmR",1)], 1):
                asymmetry = .55 if stage in (3,5) and bone == "ArmL" else 1
                twist = sign * (.24 if action == 1 else .10)
                track(lines, i, f"{bone}:rotation", [0,.5,.65,.72,.8,1], [(0,0,0),(raise_angle*asymmetry,twist,sign*.18),(raise_angle*asymmetry,twist,sign*.20),(.20,-twist,sign*.08),(.08,0,0),(0,0,0)])
            track(lines, 3, "Body/Head:rotation", [0,.5,.65,.72,1], [(0,0,0),(-.14,0,0),(-.17,0,0),(.17,0,0),(0,0,0)])
        else:
            track(lines, 0, "Body:rotation", [0,.3,1], [(0,0,0),(.2,0,.12),(1.1,0,.4)])
        lines += ['']
    lines += ['[sub_resource type="AnimationLibrary" id="Library"]', '_data = {']
    lines += [f'"{a}": SubResource("Anim_{a}")' + (',' if i < len(animation_names)-1 else '') for i,a in enumerate(animation_names)]
    lines += ['}', '', f'[node name="{name.title().replace("_", "")}" type="Node3D"]', '',
              '[node name="AnimationPlayer" type="AnimationPlayer" parent="."]', 'libraries = {"": SubResource("Library")}', '']
    bones = {"Body": (".",(0,1.5,0)), "Head": ("Body",(0,1.05,-.08)), "ArmL": (".",(-1.06,2.25,0)), "ArmR": (".",(1.06,2.25,0)), "LegL": (".",(-.43,.95,0)), "LegR": (".",(.43,.95,0))}
    for bone,(parent,position) in bones.items():
        lines += [f'[node name="{bone}" type="Node3D" parent="{parent}"]', f'position = {vec(position)}', '']
        for i,p in enumerate(data["parts"]):
            if p["bone"] != bone:
                continue
            path = "Body/Head" if bone == "Head" else bone
            lines += [f'[node name="{p["name"]}" type="MeshInstance3D" parent="{path}"]',
                      f'position = {vec(p["position"])}', f'rotation = {vec(tuple(math.radians(v) for v in p["rotation"]))}', f'mesh = SubResource("Mesh{i}")', '']
    destination = ROOT / "assets/models/bosses"
    destination.mkdir(parents=True, exist_ok=True)
    (destination/f"{name}.source.json").write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    (destination/f"{name}.tscn").write_text("\n".join(lines),encoding="utf-8")
    # Dedicated encounter scenes; no ambient contact-damage area.
    encounter = ['[gd_scene format=3]', f'[ext_resource type="Script" path="res://scripts/bosses/siege_boss.gd" id="boss"]',
                 '[ext_resource type="Script" path="res://scripts/hurtbox_area.gd" id="hurt"]',
                 f'[ext_resource type="PackedScene" path="res://assets/models/bosses/{name}.tscn" id="model"]',
                 '[sub_resource type="BoxShape3D" id="body"]','size = Vector3(2.2, 3.0, 2.2)',
                 '[sub_resource type="BoxShape3D" id="hurtshape"]','size = Vector3(2.4, 3.1, 2.4)',
                 f'[node name="Boss{name.title().replace("_", "")}" type="CharacterBody3D" groups=["boss", "enemies"]]',
                 'collision_layer = 4','collision_mask = 5','script = ExtResource("boss")', f'stage = {stage}',
                 '[node name="CollisionShape3D" type="CollisionShape3D" parent="."]','shape = SubResource("body")',
                 '[node name="Visuals" type="Node3D" parent="."]',
                 '[node name="Model" parent="Visuals" instance=ExtResource("model")]','position = Vector3(0, -1.5, 0)',
                 '[node name="Hurtbox" type="Area3D" parent="."]','collision_layer = 8','collision_mask = 0',
                 'script = ExtResource("hurt")','mesh_to_flash_path = NodePath("../Visuals/Model/Body/Torso")',
                 '[node name="CollisionShape3D" type="CollisionShape3D" parent="Hurtbox"]','shape = SubResource("hurtshape")']
    scenes = ROOT/"scenes/bosses"
    scenes.mkdir(parents=True, exist_ok=True)
    (scenes/f"boss_{stage:02d}_{name}.tscn").write_text("\n\n".join(encounter)+"\n",encoding="utf-8")


if __name__ == "__main__":
    for stage in range(1,7):
        export(model(stage))
    print("Generated six original boss models and encounter scenes.")

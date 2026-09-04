"""
generate_all_models.py
Generates production-ready Blockbench (.bbmodel) source files and exports them
to Godot 4 scenes (.tscn) for:
- Hero Warrior (Sword, Shield, Plate Armor, Helmet, Plume)
- Hero Archer (Cowl/Hood, Quiver, Arrows, Recurve Bow)
- Hero Engineer (Protective Apron, Welding Goggles, Heavy Wrench-Hammer, Powerpack)
- Decoy Dummy (Straw/Burlap body, Target, Floppy Archer Hat, Wood Stand)
- Temporary Turret (Tripod mount, Swivel ring, Twin-barrel Sentry Head)
- Remote Mine (Octagonal armored base, LED Beacon, Sensor Pins)

Each character includes 6 complete animations:
- idle (1.2s loop)
- walk (0.8s loop)
- attack (LMB, snappy strike)
- special (RMB, powerful signature ability)
- utility (Q, tactical defensive/deploy ability)
- ultimate (F, climax signature ability)
"""

import json
import math
import os
import re
import uuid
import base64
from PIL import Image, ImageDraw


def generate_model_texture(model_name: str, output_path: str) -> str:
    img = Image.new("RGBA", (64, 64), (0, 0, 0, 255))
    draw = ImageDraw.Draw(img)

    for col_idx, col_data in PALETTE_COLORS.items():
        tx = (col_idx % 8) * 8
        ty = (col_idx // 8) * 8

        # Base fill
        # Parse Godot Color(r, g, b, a)
        albedo_str = col_data["albedo"]
        m = re.findall(r"[0-9\.]+", albedo_str)
        if len(m) >= 3:
            br = int(float(m[0]) * 255)
            bg = int(float(m[1]) * 255)
            bb = int(float(m[2]) * 255)
        else:
            br, bg, bb = 128, 128, 128

        draw.rectangle([tx, ty, tx + 7, ty + 7], fill=(br, bg, bb, 255))

        # Specialized voxel micro-surface texturing
        if col_idx in [8, 7]: # Steel plate & iron
            # Bevel highlights
            draw.line([tx, ty, tx + 6, ty], fill=(min(255, br + 50), min(255, bg + 50), min(255, bb + 50), 255))
            draw.line([tx, ty, tx, ty + 6], fill=(min(255, br + 50), min(255, bg + 50), min(255, bb + 50), 255))
            # Bevel shadows
            draw.line([tx + 1, ty + 7, tx + 7, ty + 7], fill=(max(0, br - 60), max(0, bg - 60), max(0, bb - 60), 255))
            draw.line([tx + 7, ty + 1, tx + 7, ty + 7], fill=(max(0, br - 60), max(0, bg - 60), max(0, bb - 60), 255))
            # Plate seam
            draw.line([tx + 1, ty + 3, tx + 6, ty + 3], fill=(max(0, br - 40), max(0, bg - 40), max(0, bb - 40), 255))
            # 4 Corner rivets
            for rx, ry in [(tx + 1, ty + 1), (tx + 6, ty + 1), (tx + 1, ty + 6), (tx + 6, ty + 6)]:
                draw.point((rx, ry), fill=(max(0, br - 90), max(0, bg - 90), max(0, bb - 90), 255))
            draw.point((tx + 1, ty + 1), fill=(255, 255, 255, 255))

        elif col_idx == 9: # Polished blade steel
            draw.line([tx, ty, tx, ty + 7], fill=(255, 255, 255, 255))
            draw.line([tx + 7, ty, tx + 7, ty + 7], fill=(255, 255, 255, 255))
            draw.line([tx + 3, ty, tx + 3, ty + 7], fill=(160, 175, 195, 255))
            draw.line([tx + 4, ty, tx + 4, ty + 7], fill=(190, 205, 225, 255))

        elif col_idx == 3: # Gold trim
            draw.line([tx, ty, tx + 6, ty], fill=(255, 240, 140, 255))
            draw.line([tx, ty, tx, ty + 6], fill=(255, 240, 140, 255))
            draw.line([tx + 1, ty + 7, tx + 7, ty + 7], fill=(150, 100, 20, 255))
            draw.line([tx + 7, ty + 1, tx + 7, ty + 7], fill=(150, 100, 20, 255))
            draw.polygon([(tx + 3, ty + 2), (tx + 5, ty + 3), (tx + 3, ty + 5), (tx + 2, ty + 3)], fill=(255, 250, 180, 255))
            draw.point((tx + 3, ty + 3), fill=(255, 255, 220, 255))

        elif col_idx in [4, 12, 17, 21]: # Leathers
            # Edge stitches
            for sy in [ty + 1, ty + 3, ty + 5, ty + 7]:
                draw.point((tx, sy), fill=(min(255, br + 80), min(255, bg + 70), min(255, bb + 40), 255))
                draw.point((tx + 7, sy), fill=(min(255, br + 80), min(255, bg + 70), min(255, bb + 40), 255))
            draw.point((tx + 2, ty + 2), fill=(min(255, br + 30), bg, bb, 255))
            draw.point((tx + 5, ty + 5), fill=(max(0, br - 30), bg, bb, 255))

        elif col_idx in [0, 1, 5, 10, 11, 20]: # Woven fabrics
            for i in range(8):
                draw.point((tx + i, ty + ((i * 3) % 8)), fill=(min(255, br + 35), min(255, bg + 35), min(255, bb + 35), 255))
                draw.point((tx + i, ty + ((i * 3 + 4) % 8)), fill=(max(0, br - 35), max(0, bg - 35), max(0, bb - 35), 255))

        elif col_idx in [6, 14, 16, 35]: # Woods
            draw.line([tx, ty + 2, tx + 7, ty + 2], fill=(max(0, br - 35), max(0, bg - 30), max(0, bb - 25), 255))
            draw.line([tx, ty + 5, tx + 7, ty + 5], fill=(max(0, br - 35), max(0, bg - 30), max(0, bb - 25), 255))
            draw.line([tx + 2, ty, tx + 2, ty + 7], fill=(min(255, br + 50), min(255, bg + 45), min(255, bb + 35), 255))

        elif col_idx == 13: # Feather
            draw.line([tx + 3, ty, tx + 3, ty + 7], fill=(170, 185, 200, 255))
            for i in range(8):
                draw.point((tx + 1, ty + i), fill=(215, 225, 235, 255))
                draw.point((tx + 5, ty + i), fill=(215, 225, 235, 255))

        elif col_idx == 23: # Goggle lens cyan
            draw.rectangle([tx, ty, tx + 7, ty + 7], outline=(40, 45, 50, 255))
            draw.line([tx + 2, ty + 5, tx + 5, ty + 2], fill=(255, 255, 255, 255))
            draw.point((tx + 3, ty + 3), fill=(220, 255, 255, 255))

        elif col_idx == 22: # Brass
            draw.line([tx, ty, tx + 6, ty], fill=(250, 215, 120, 255))
            draw.line([tx, ty, tx, ty + 6], fill=(250, 215, 120, 255))
            draw.line([tx + 1, ty + 7, tx + 7, ty + 7], fill=(130, 95, 30, 255))
            draw.line([tx + 7, ty + 1, tx + 7, ty + 7], fill=(130, 95, 30, 255))
            draw.rectangle([tx + 3, ty + 2, tx + 4, ty + 5], fill=(170, 120, 40, 255))

        elif col_idx in [25, 26]: # Hazard stripes
            for px in range(8):
                for py in range(8):
                    if ((px + py) // 2) % 2 == 0:
                        draw.point((tx + px, ty + py), fill=(245, 200, 40, 255))
                    else:
                        draw.point((tx + px, ty + py), fill=(35, 35, 40, 255))

        elif col_idx == 30: # Straw burlap
            for i in range(8):
                draw.line([tx + i, ty + ((i * 2) % 8), tx + i, ty + ((i * 2 + 3) % 8)], fill=(250, 235, 160, 255))
                draw.point((tx + i, ty + ((i * 3) % 8)), fill=(160, 135, 70, 255))

        elif col_idx in [31, 32]: # Target
            draw.rectangle([tx, ty, tx + 7, ty + 7], fill=(240, 240, 240, 255))
            draw.ellipse([tx + 1, ty + 1, tx + 6, ty + 6], fill=(225, 45, 35, 255))
            draw.ellipse([tx + 2, ty + 2, tx + 5, ty + 5], fill=(245, 245, 245, 255))
            draw.rectangle([tx + 3, ty + 3, tx + 4, ty + 4], fill=(235, 30, 20, 255))

        elif col_idx in [24, 33]: # Turret steel & dark cast iron
            draw.line([tx, ty, tx + 6, ty], fill=(150, 160, 170, 255))
            draw.line([tx, ty, tx, ty + 6], fill=(150, 160, 170, 255))
            draw.line([tx + 1, ty + 7, tx + 7, ty + 7], fill=(65, 70, 75, 255))
            draw.line([tx + 7, ty + 1, tx + 7, ty + 7], fill=(65, 70, 75, 255))
            for bx, by in [(tx + 1, ty + 1), (tx + 6, ty + 1), (tx + 1, ty + 6), (tx + 6, ty + 6)]:
                draw.point((bx, by), fill=(40, 45, 50, 255))
                draw.point((bx, by + 1 if by == ty + 1 else by - 1), fill=(180, 190, 200, 255))

        elif col_idx in [27, 28]: # Indicator LEDs
            draw.ellipse([tx + 1, ty + 1, tx + 6, ty + 6], fill=(br, bg, bb, 255))
            draw.point((tx + 3, ty + 3), fill=(255, 255, 255, 255))
            draw.point((tx + 4, ty + 3), fill=(255, 255, 255, 255))

        else:
            # Subtle edge shading
            draw.line([tx, ty, tx + 6, ty], fill=(min(255, int(br * 1.2)), min(255, int(bg * 1.2)), min(255, int(bb * 1.2)), 255))
            draw.line([tx + 1, ty + 7, tx + 7, ty + 7], fill=(int(br * 0.8), int(bg * 0.8), int(bb * 0.8), 255))

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path, "PNG")

    with open(output_path, "rb") as f:
        return base64.b64encode(f.read()).decode("utf-8")

SCALE = 0.055  # 32 units * 0.055 = ~1.76m height in Godot

# Unified PBR Palette
PALETTE_COLORS = {
    # 0..9: Warrior & Steel & Basics
    0: {"name": "cloth_royal_blue", "albedo": "Color(0.22, 0.42, 0.76, 1)", "metallic": 0.05, "roughness": 0.8},
    1: {"name": "cloth_dark_navy", "albedo": "Color(0.14, 0.18, 0.28, 1)", "metallic": 0.0, "roughness": 0.9},
    2: {"name": "skin_peach", "albedo": "Color(0.92, 0.74, 0.60, 1)", "metallic": 0.0, "roughness": 0.85},
    3: {"name": "metal_gold", "albedo": "Color(0.95, 0.78, 0.22, 1)", "metallic": 0.85, "roughness": 0.25},
    4: {"name": "leather_brown", "albedo": "Color(0.38, 0.24, 0.16, 1)", "metallic": 0.05, "roughness": 0.85},
    5: {"name": "cloth_crimson", "albedo": "Color(0.85, 0.16, 0.20, 1)", "metallic": 0.1, "roughness": 0.55},
    6: {"name": "wood_dark", "albedo": "Color(0.28, 0.18, 0.12, 1)", "metallic": 0.0, "roughness": 0.9},
    7: {"name": "metal_iron", "albedo": "Color(0.52, 0.55, 0.60, 1)", "metallic": 0.65, "roughness": 0.45},
    8: {"name": "metal_steel_plate", "albedo": "Color(0.75, 0.80, 0.88, 1)", "metallic": 0.82, "roughness": 0.25},
    9: {"name": "metal_polished_steel", "albedo": "Color(0.90, 0.93, 0.97, 1)", "metallic": 0.92, "roughness": 0.18},

    # 10..19: Archer & Nature & Leather
    10: {"name": "cloth_forest_green", "albedo": "Color(0.18, 0.45, 0.30, 1)", "metallic": 0.05, "roughness": 0.8},
    11: {"name": "cloth_moss_green", "albedo": "Color(0.25, 0.58, 0.40, 1)", "metallic": 0.05, "roughness": 0.8},
    12: {"name": "leather_saddle", "albedo": "Color(0.48, 0.32, 0.20, 1)", "metallic": 0.05, "roughness": 0.85},
    13: {"name": "feather_white", "albedo": "Color(0.94, 0.96, 0.98, 1)", "metallic": 0.0, "roughness": 0.7},
    14: {"name": "wood_bow", "albedo": "Color(0.35, 0.22, 0.14, 1)", "metallic": 0.05, "roughness": 0.75},
    15: {"name": "string_glow", "albedo": "Color(0.85, 0.95, 0.9, 1)", "metallic": 0.2, "roughness": 0.3},
    16: {"name": "arrow_shaft", "albedo": "Color(0.78, 0.65, 0.45, 1)", "metallic": 0.0, "roughness": 0.8},
    17: {"name": "quiver_leather", "albedo": "Color(0.32, 0.20, 0.14, 1)", "metallic": 0.05, "roughness": 0.85},
    18: {"name": "eye_eagle_glow", "albedo": "Color(0.3, 1.0, 0.6, 1)", "metallic": 0.1, "roughness": 0.2, "emission": "Color(0.3, 1.0, 0.6, 1)", "emission_energy": 2.0},

    # 20..29: Engineer & Industrial & Brass
    20: {"name": "cloth_industrial_denim", "albedo": "Color(0.16, 0.28, 0.36, 1)", "metallic": 0.05, "roughness": 0.85},
    21: {"name": "leather_apron", "albedo": "Color(0.68, 0.46, 0.30, 1)", "metallic": 0.05, "roughness": 0.8},
    22: {"name": "metal_brass", "albedo": "Color(0.86, 0.64, 0.25, 1)", "metallic": 0.85, "roughness": 0.28},
    23: {"name": "goggle_lens_cyan", "albedo": "Color(0.15, 0.85, 0.92, 1)", "metallic": 0.3, "roughness": 0.1, "emission": "Color(0.15, 0.85, 0.92, 1)", "emission_energy": 2.5},
    24: {"name": "metal_dark_cast_iron", "albedo": "Color(0.24, 0.26, 0.28, 1)", "metallic": 0.75, "roughness": 0.45},
    25: {"name": "hazard_orange", "albedo": "Color(0.95, 0.48, 0.12, 1)", "metallic": 0.1, "roughness": 0.6},
    26: {"name": "hazard_yellow", "albedo": "Color(0.96, 0.78, 0.15, 1)", "metallic": 0.1, "roughness": 0.5},
    27: {"name": "indicator_red_glow", "albedo": "Color(1.0, 0.18, 0.15, 1)", "metallic": 0.1, "roughness": 0.3, "emission": "Color(1.0, 0.18, 0.15, 1)", "emission_energy": 3.0},
    28: {"name": "indicator_green_glow", "albedo": "Color(0.2, 0.95, 0.3, 1)", "metallic": 0.1, "roughness": 0.3, "emission": "Color(0.2, 0.95, 0.3, 1)", "emission_energy": 3.0},
    29: {"name": "pipe_copper", "albedo": "Color(0.82, 0.45, 0.32, 1)", "metallic": 0.85, "roughness": 0.35},

    # 30..39: Props (Decoy, Turret, Mine)
    30: {"name": "straw_burlap", "albedo": "Color(0.86, 0.78, 0.46, 1)", "metallic": 0.0, "roughness": 0.95},
    31: {"name": "target_red", "albedo": "Color(0.9, 0.2, 0.15, 1)", "metallic": 0.05, "roughness": 0.8},
    32: {"name": "target_white", "albedo": "Color(0.95, 0.95, 0.95, 1)", "metallic": 0.0, "roughness": 0.8},
    33: {"name": "turret_body_steel", "albedo": "Color(0.42, 0.46, 0.50, 1)", "metallic": 0.8, "roughness": 0.3},
    34: {"name": "turret_copper_accent", "albedo": "Color(0.85, 0.52, 0.22, 1)", "metallic": 0.82, "roughness": 0.32},
    35: {"name": "wood_timber", "albedo": "Color(0.45, 0.30, 0.18, 1)", "metallic": 0.0, "roughness": 0.9},
}

def uid():
    return str(uuid.uuid4())

def make_cube(name, p_from, p_to, origin, color=0, rot=[0, 0, 0]):
    tx = (color % 8) * 8
    ty = (color // 8) * 8
    return {
        "name": name,
        "uuid": uid(),
        "from": p_from,
        "to": p_to,
        "origin": origin,
        "rotation": rot,
        "color": color,
        "faces": {
            "north": {"uv": [tx, ty, tx + 8, ty + 8], "texture": 0},
            "south": {"uv": [tx, ty, tx + 8, ty + 8], "texture": 0},
            "east": {"uv": [tx, ty, tx + 8, ty + 8], "texture": 0},
            "west": {"uv": [tx, ty, tx + 8, ty + 8], "texture": 0},
            "up": {"uv": [tx, ty, tx + 8, ty + 8], "texture": 0},
            "down": {"uv": [tx, ty, tx + 8, ty + 8], "texture": 0}
        }
    }

def kf(time, x, y, z):
    return {
        "channel": "rotation",
        "time": time,
        "interpolation": "linear",
        "data_points": [{"x": str(x), "y": str(y), "z": str(z)}]
    }

def kf_pos(time, x, y, z):
    return {
        "channel": "position",
        "time": time,
        "interpolation": "linear",
        "data_points": [{"x": str(x), "y": str(y), "z": str(z)}]
    }

# --- 1. WARRIOR BUILDER ---
def build_hero_warrior():
    elements = []

    # Head & Helmet
    c_head = make_cube("head", [-4, 24, -4], [4, 32, 4], [0, 24, 0], color=2)
    c_crest = make_cube("helmet_crest", [-1, 32, -4.5], [1, 36.0, 4.5], [0, 24, 0], color=5)
    c_visor = make_cube("helmet_visor", [-4.3, 26, -4.8], [4.3, 29, -3.6], [0, 24, 0], color=7)
    c_helm_top = make_cube("helmet_top", [-4.2, 31, -4.2], [4.2, 32.5, 4.2], [0, 24, 0], color=8)

    # Torso & Plate
    c_torso = make_cube("torso", [-4, 12, -2], [4, 24, 2], [0, 12, 0], color=0)
    c_breastplate = make_cube("breastplate", [-4.5, 14.5, -2.7], [4.5, 23.5, 2.7], [0, 12, 0], color=8)
    c_belt = make_cube("belt", [-4.6, 12.0, -2.6], [4.6, 14.2, 2.6], [0, 12, 0], color=4)
    c_belt_buckle = make_cube("belt_buckle", [-1.5, 12.0, -2.8], [1.5, 14.2, -2.4], [0, 12, 0], color=3)

    # Right Arm & Sword
    c_r_arm = make_cube("right_arm", [-8, 12, -2], [-4, 24, 2], [-6, 22, 0], color=0)
    c_r_pauldron = make_cube("r_pauldron", [-8.6, 21.0, -2.6], [-4.2, 25.0, 2.6], [-6, 22, 0], color=3)
    c_sword_handle = make_cube("sword_handle", [-6.5, 11.5, -1.5], [-5.5, 13.5, 2.0], [-6, 12.5, 0], color=4)
    c_sword_pommel = make_cube("sword_pommel", [-6.8, 11.2, 2.0], [-5.2, 13.8, 3.0], [-6, 12.5, 0], color=3)
    c_sword_guard = make_cube("sword_guard", [-8.8, 11.0, -2.5], [-3.2, 14.0, -1.5], [-6, 12.5, 0], color=3)
    c_sword_blade = make_cube("sword_blade", [-6.4, 11.8, -17.0], [-5.6, 13.2, -2.5], [-6, 12.5, 0], color=9)

    # Left Arm & Shield
    c_l_arm = make_cube("left_arm", [4, 12, -2], [8, 24, 2], [6, 22, 0], color=0)
    c_l_pauldron = make_cube("l_pauldron", [4.2, 21.0, -2.6], [8.6, 25.0, 2.6], [6, 22, 0], color=3)
    c_shield = make_cube("shield", [7.8, 10.5, -4.5], [8.8, 23.5, 4.5], [6, 16, 0], color=5)
    c_shield_rim = make_cube("shield_rim", [7.7, 9.8, -4.8], [8.7, 24.2, 4.8], [6, 16, 0], color=3)
    c_shield_boss = make_cube("shield_boss", [8.8, 15.0, -1.5], [9.5, 19.0, 1.5], [6, 16, 0], color=8)

    # Legs
    c_r_leg = make_cube("right_leg", [-4, 0, -2], [0, 12, 2], [-2, 12, 0], color=7)
    c_r_greave = make_cube("r_greave", [-4.2, 1.0, -2.4], [0.2, 8.0, 2.4], [-2, 12, 0], color=8)
    c_l_leg = make_cube("left_leg", [0, 0, -2], [4, 12, 2], [2, 12, 0], color=7)
    c_l_greave = make_cube("l_greave", [-0.2, 1.0, -2.4], [4.2, 8.0, 2.4], [2, 12, 0], color=8)

    elements.extend([
        c_head, c_crest, c_visor, c_helm_top,
        c_torso, c_breastplate, c_belt, c_belt_buckle,
        c_r_arm, c_r_pauldron, c_sword_handle, c_sword_pommel, c_sword_guard, c_sword_blade,
        c_l_arm, c_l_pauldron, c_shield, c_shield_rim, c_shield_boss,
        c_r_leg, c_r_greave, c_l_leg, c_l_greave
    ])

    bone_sword = {
        "name": "sword", "uuid": uid(), "origin": [-6, 12.5, 0],
        "children": [c_sword_handle["uuid"], c_sword_pommel["uuid"], c_sword_guard["uuid"], c_sword_blade["uuid"]]
    }
    bone_shield = {
        "name": "shield", "uuid": uid(), "origin": [6, 16, 0],
        "children": [c_shield["uuid"], c_shield_rim["uuid"], c_shield_boss["uuid"]]
    }
    bone_head = {
        "name": "head", "uuid": uid(), "origin": [0, 24, 0],
        "children": [c_head["uuid"], c_crest["uuid"], c_visor["uuid"], c_helm_top["uuid"]]
    }
    bone_r_arm = {
        "name": "right_arm", "uuid": uid(), "origin": [-6, 22, 0],
        "children": [c_r_arm["uuid"], c_r_pauldron["uuid"], bone_sword]
    }
    bone_l_arm = {
        "name": "left_arm", "uuid": uid(), "origin": [6, 22, 0],
        "children": [c_l_arm["uuid"], c_l_pauldron["uuid"], bone_shield]
    }
    bone_torso = {
        "name": "torso", "uuid": uid(), "origin": [0, 12, 0],
        "children": [c_torso["uuid"], c_breastplate["uuid"], c_belt["uuid"], c_belt_buckle["uuid"], bone_head, bone_r_arm, bone_l_arm]
    }
    bone_r_leg = {
        "name": "right_leg", "uuid": uid(), "origin": [-2, 12, 0],
        "children": [c_r_leg["uuid"], c_r_greave["uuid"]]
    }
    bone_l_leg = {
        "name": "left_leg", "uuid": uid(), "origin": [2, 12, 0],
        "children": [c_l_leg["uuid"], c_l_greave["uuid"]]
    }
    outliner = [{
        "name": "root", "uuid": uid(), "origin": [0, 0, 0],
        "children": [bone_torso, bone_r_leg, bone_l_leg]
    }]

    # Animations
    anim_idle = {
        "name": "idle", "uuid": uid(), "loop": "loop", "length": 1.2,
        "animators": {
            bone_torso["uuid"]: {
                "name": "torso", "type": "bone",
                "position": [kf_pos(0.0, 0, 0, 0), kf_pos(0.6, 0, -0.5, 0), kf_pos(1.2, 0, 0, 0)],
                "rotation": [kf(0.0, 5, 0, 0), kf(0.6, 7, 0, 0), kf(1.2, 5, 0, 0)]
            },
            bone_head["uuid"]: {
                "name": "head", "type": "bone",
                "rotation": [kf(0.0, -5, 0, 0), kf(0.6, -7, 0, 0), kf(1.2, -5, 0, 0)]
            },
            bone_r_arm["uuid"]: {
                "name": "right_arm", "type": "bone",
                "rotation": [kf(0.0, -10, -5, 5), kf(0.6, -8, -5, 7), kf(1.2, -10, -5, 5)]
            },
            bone_sword["uuid"]: {
                "name": "sword", "type": "bone",
                "rotation": [kf(0.0, -15, 0, 0), kf(0.6, -15, 0, 0), kf(1.2, -15, 0, 0)]
            },
            bone_l_arm["uuid"]: {
                "name": "left_arm", "type": "bone",
                "rotation": [kf(0.0, -10, 5, -5), kf(0.6, -12, 7, -7), kf(1.2, -10, 5, -5)]
            }
        }
    }

    anim_walk = {
        "name": "walk", "uuid": uid(), "loop": "loop", "length": 0.8,
        "animators": {
            bone_r_leg["uuid"]: {
                "name": "right_leg", "type": "bone",
                "rotation": [kf(0.0, -30, 0, 0), kf(0.4, 30, 0, 0), kf(0.8, -30, 0, 0)]
            },
            bone_l_leg["uuid"]: {
                "name": "left_leg", "type": "bone",
                "rotation": [kf(0.0, 30, 0, 0), kf(0.4, -30, 0, 0), kf(0.8, 30, 0, 0)]
            },
            bone_r_arm["uuid"]: {
                "name": "right_arm", "type": "bone",
                "rotation": [kf(0.0, 30, 0, 5), kf(0.4, -30, 0, 5), kf(0.8, 30, 0, 5)]
            },
            bone_sword["uuid"]: {
                "name": "sword", "type": "bone",
                "rotation": [kf(0.0, -15, 0, 0), kf(0.4, -15, 0, 0), kf(0.8, -15, 0, 0)]
            },
            bone_l_arm["uuid"]: {
                "name": "left_arm", "type": "bone",
                "rotation": [kf(0.0, -30, 5, -5), kf(0.4, 30, 5, -5), kf(0.8, -30, 5, -5)]
            },
            bone_torso["uuid"]: {
                "name": "torso", "type": "bone",
                "position": [kf_pos(0.0, 0, 0, 0), kf_pos(0.2, 0, 0.5, 0), kf_pos(0.4, 0, 0, 0), kf_pos(0.6, 0, 0.5, 0), kf_pos(0.8, 0, 0, 0)],
                "rotation": [kf(0.0, 5, -5, 0), kf(0.4, 5, 5, 0), kf(0.8, 5, -5, 0)]
            }
        }
    }

    anim_attack = {
        "name": "attack", "uuid": uid(), "loop": "once", "length": 0.35,
        "animators": {
            bone_r_arm["uuid"]: {
                "name": "right_arm", "type": "bone",
                "rotation": [
                    kf(0.00, -10, -5, 5),
                    kf(0.10, -110, 15, -15),
                    kf(0.22, 40, 35, -20),
                    kf(0.35, -10, -5, 5)
                ]
            },
            bone_sword["uuid"]: {
                "name": "sword", "type": "bone",
                "rotation": [
                    kf(0.00, -15, 0, 0),
                    kf(0.10, 15, 0, 0),
                    kf(0.22, -45, 0, 0),
                    kf(0.35, -15, 0, 0)
                ]
            },
            bone_torso["uuid"]: {
                "name": "torso", "type": "bone",
                "rotation": [
                    kf(0.00, 5, 0, 0),
                    kf(0.10, -2, -25, 0),
                    kf(0.22, 12, 25, -5),
                    kf(0.35, 5, 0, 0)
                ]
            }
        }
    }

    anim_special = {
        "name": "special", "uuid": uid(), "loop": "once", "length": 0.55,
        "animators": {
            bone_r_arm["uuid"]: {
                "name": "right_arm", "type": "bone",
                "rotation": [
                    kf(0.00, -10, -5, 5),
                    kf(0.18, -145, 20, -30), # Big windup
                    kf(0.32, 55, 60, -25),   # Huge cleave sweep
                    kf(0.44, 25, 20, -10),
                    kf(0.55, -10, -5, 5)
                ]
            },
            bone_sword["uuid"]: {
                "name": "sword", "type": "bone",
                "rotation": [
                    kf(0.00, -15, 0, 0),
                    kf(0.18, 25, 0, 0),
                    kf(0.32, -60, 0, 0),
                    kf(0.55, -15, 0, 0)
                ]
            },
            bone_torso["uuid"]: {
                "name": "torso", "type": "bone",
                "position": [
                    kf_pos(0.00, 0, 0, 0),
                    kf_pos(0.18, 0, -0.6, -1.0),
                    kf_pos(0.32, 0, -0.8, 2.0),
                    kf_pos(0.55, 0, 0, 0)
                ],
                "rotation": [
                    kf(0.00, 5, 0, 0),
                    kf(0.18, -5, -45, 0),
                    kf(0.32, 18, 45, -5),
                    kf(0.55, 5, 0, 0)
                ]
            }
        }
    }

    anim_utility = {
        "name": "utility", "uuid": uid(), "loop": "hold", "length": 0.50,
        "animators": {
            bone_l_arm["uuid"]: {
                "name": "left_arm", "type": "bone",
                "position": [kf_pos(0.0, 0, 0, 0), kf_pos(0.2, 0, 1.2, 2.5), kf_pos(0.5, 0, 1.5, 3.0)],
                "rotation": [kf(0.0, -10, 5, -5), kf(0.2, -50, 50, 20), kf(0.5, -60, 60, 25)]
            },
            bone_torso["uuid"]: {
                "name": "torso", "type": "bone",
                "rotation": [kf(0.0, 5, 0, 0), kf(0.2, 14, -12, 0), kf(0.5, 15, -15, 0)]
            },
            bone_r_arm["uuid"]: {
                "name": "right_arm", "type": "bone",
                "rotation": [kf(0.0, -10, -5, 5), kf(0.2, 10, -12, 10), kf(0.5, 15, -15, 15)]
            }
        }
    }

    anim_block = dict(anim_utility)
    anim_block["name"] = "block"
    anim_block["uuid"] = uid()

    anim_ultimate = {
        "name": "ultimate", "uuid": uid(), "loop": "once", "length": 0.80,
        "animators": {
            bone_r_arm["uuid"]: {
                "name": "right_arm", "type": "bone",
                "rotation": [
                    kf(0.00, -10, -5, 5),
                    kf(0.25, -165, 0, 10), # Raise sword straight to sky
                    kf(0.55, -165, 0, 10), # Hold roar
                    kf(0.70, -60, 15, -5), # Point sword forward
                    kf(0.80, -10, -5, 5)
                ]
            },
            bone_sword["uuid"]: {
                "name": "sword", "type": "bone",
                "rotation": [
                    kf(0.00, -15, 0, 0),
                    kf(0.25, 45, 0, 0),
                    kf(0.55, 45, 0, 0),
                    kf(0.80, -15, 0, 0)
                ]
            },
            bone_l_arm["uuid"]: {
                "name": "left_arm", "type": "bone",
                "rotation": [
                    kf(0.00, -10, 5, -5),
                    kf(0.25, -45, 30, -20),
                    kf(0.55, -45, 30, -20),
                    kf(0.80, -10, 5, -5)
                ]
            },
            bone_head["uuid"]: {
                "name": "head", "type": "bone",
                "rotation": [
                    kf(0.00, -5, 0, 0),
                    kf(0.25, -25, 0, 0), # Look up in challenge
                    kf(0.55, -25, 0, 0),
                    kf(0.80, -5, 0, 0)
                ]
            },
            bone_torso["uuid"]: {
                "name": "torso", "type": "bone",
                "rotation": [
                    kf(0.00, 5, 0, 0),
                    kf(0.25, -10, 0, 0), # Puff chest out
                    kf(0.55, -10, 0, 0),
                    kf(0.80, 5, 0, 0)
                ]
            }
        }
    }

    return {
        "meta": {"format_version": "4.5", "model_format": "free", "box_uv": False},
        "name": "hero_warrior",
        "resolution": {"width": 64, "height": 64},
        "elements": elements,
        "outliner": outliner,
        "textures": [],
        "animations": [anim_idle, anim_walk, anim_attack, anim_special, anim_utility, anim_block, anim_ultimate]
    }

# --- 2. ARCHER BUILDER ---
def build_hero_archer():
    elements = []

    # Head, Cowl / Hood, Feather
    c_head = make_cube("head", [-3.8, 24, -3.8], [3.8, 31.6, 3.8], [0, 24, 0], color=2)
    c_hood = make_cube("hood_cowl", [-4.4, 24.5, -4.4], [4.4, 32.5, 4.4], [0, 24, 0], color=10)
    c_hood_back = make_cube("hood_tail", [-2.0, 22.0, 3.8], [2.0, 25.0, 5.2], [0, 24, 0], color=10)
    c_feather = make_cube("feather", [3.8, 29.0, 1.0], [4.6, 35.0, 2.5], [0, 24, 0], color=13)

    # Torso, Belt & Quiver
    c_torso = make_cube("torso", [-3.8, 12, -2], [3.8, 24, 2], [0, 12, 0], color=11)
    c_cloak = make_cube("cloak_torso", [-4.2, 14.0, -2.4], [4.2, 23.5, 2.5], [0, 12, 0], color=10)
    c_belt = make_cube("archer_belt", [-4.1, 12.0, -2.3], [4.1, 14.0, 2.3], [0, 12, 0], color=12)

    # Quiver on Back (slanted across shoulders)
    c_quiver = make_cube("quiver_tube", [1.0, 14.0, 2.2], [4.2, 26.0, 4.6], [2.6, 20.0, 3.4], color=17)
    c_arrow1 = make_cube("arrow_fletch1", [1.8, 25.5, 2.6], [2.6, 28.5, 3.4], [2.6, 20.0, 3.4], color=13)
    c_arrow2 = make_cube("arrow_fletch2", [2.6, 26.0, 3.4], [3.4, 29.2, 4.2], [2.6, 20.0, 3.4], color=13)

    # Left Arm & Bow
    c_l_arm = make_cube("left_arm", [3.8, 12, -1.8], [7.4, 24, 1.8], [5.6, 22, 0], color=11)
    c_l_bracer = make_cube("l_bracer", [3.6, 12.5, -2.0], [7.6, 16.5, 2.0], [5.6, 22, 0], color=12)
    # Recurve Bow (held in left hand, origin at [5.6, 14.0, 0])
    c_bow_grip = make_cube("bow_grip", [5.1, 12.5, -2.2], [6.1, 15.5, -1.2], [5.6, 14.0, -1.7], color=14)
    c_bow_upper = make_cube("bow_upper", [5.2, 15.5, -3.2], [6.0, 24.5, -1.4], [5.6, 14.0, -1.7], color=14)
    c_bow_lower = make_cube("bow_lower", [5.2, 3.5, -3.2], [6.0, 12.5, -1.4], [5.6, 14.0, -1.7], color=14)
    c_bow_tip_top = make_cube("bow_tip_top", [5.2, 24.5, -2.0], [6.0, 27.0, -0.8], [5.6, 14.0, -1.7], color=3)
    c_bow_tip_bot = make_cube("bow_tip_bot", [5.2, 1.0, -2.0], [6.0, 3.5, -0.8], [5.6, 14.0, -1.7], color=3)
    c_bow_string = make_cube("bow_string", [5.4, 2.0, -0.6], [5.8, 26.0, -0.2], [5.6, 14.0, -1.7], color=15)

    # Right Arm & Hand
    c_r_arm = make_cube("right_arm", [-7.4, 12, -1.8], [-3.8, 24, 1.8], [-5.6, 22, 0], color=11)
    c_r_bracer = make_cube("r_bracer", [-7.6, 12.5, -2.0], [-3.6, 16.5, 2.0], [-5.6, 22, 0], color=12)
    c_nocked_arrow = make_cube("nocked_arrow", [-5.8, 13.5, -12.0], [-5.4, 14.5, 0.0], [-5.6, 14.0, 0], color=16)

    # Legs & Boots
    c_r_leg = make_cube("right_leg", [-3.8, 0, -1.8], [-0.2, 12, 1.8], [-2, 12, 0], color=1)
    c_r_boot = make_cube("r_boot", [-4.0, 0.0, -2.2], [0.0, 6.0, 2.2], [-2, 12, 0], color=12)
    c_l_leg = make_cube("left_leg", [0.2, 0, -1.8], [3.8, 12, 1.8], [2, 12, 0], color=1)
    c_l_boot = make_cube("l_boot", [0.0, 0.0, -2.2], [4.0, 6.0, 2.2], [2, 12, 0], color=12)

    elements.extend([
        c_head, c_hood, c_hood_back, c_feather,
        c_torso, c_cloak, c_belt, c_quiver, c_arrow1, c_arrow2,
        c_l_arm, c_l_bracer, c_bow_grip, c_bow_upper, c_bow_lower, c_bow_tip_top, c_bow_tip_bot, c_bow_string,
        c_r_arm, c_r_bracer, c_nocked_arrow,
        c_r_leg, c_r_boot, c_l_leg, c_l_boot
    ])

    bone_bow = {
        "name": "bow", "uuid": uid(), "origin": [5.6, 14.0, -1.7],
        "children": [c_bow_grip["uuid"], c_bow_upper["uuid"], c_bow_lower["uuid"], c_bow_tip_top["uuid"], c_bow_tip_bot["uuid"], c_bow_string["uuid"]]
    }
    bone_arrow_hand = {
        "name": "arrow_hand", "uuid": uid(), "origin": [-5.6, 14.0, 0],
        "children": [c_nocked_arrow["uuid"]]
    }
    bone_head = {
        "name": "head", "uuid": uid(), "origin": [0, 24, 0],
        "children": [c_head["uuid"], c_hood["uuid"], c_hood_back["uuid"], c_feather["uuid"]]
    }
    bone_quiver = {
        "name": "quiver", "uuid": uid(), "origin": [2.6, 20.0, 3.4],
        "children": [c_quiver["uuid"], c_arrow1["uuid"], c_arrow2["uuid"]]
    }
    bone_l_arm = {
        "name": "left_arm", "uuid": uid(), "origin": [5.6, 22, 0],
        "children": [c_l_arm["uuid"], c_l_bracer["uuid"], bone_bow]
    }
    bone_r_arm = {
        "name": "right_arm", "uuid": uid(), "origin": [-5.6, 22, 0],
        "children": [c_r_arm["uuid"], c_r_bracer["uuid"], bone_arrow_hand]
    }
    bone_torso = {
        "name": "torso", "uuid": uid(), "origin": [0, 12, 0],
        "children": [c_torso["uuid"], c_cloak["uuid"], c_belt["uuid"], bone_quiver, bone_head, bone_r_arm, bone_l_arm]
    }
    bone_r_leg = {
        "name": "right_leg", "uuid": uid(), "origin": [-2, 12, 0],
        "children": [c_r_leg["uuid"], c_r_boot["uuid"]]
    }
    bone_l_leg = {
        "name": "left_leg", "uuid": uid(), "origin": [2, 12, 0],
        "children": [c_l_leg["uuid"], c_l_boot["uuid"]]
    }
    outliner = [{
        "name": "root", "uuid": uid(), "origin": [0, 0, 0],
        "children": [bone_torso, bone_r_leg, bone_l_leg]
    }]

    # Animations
    anim_idle = {
        "name": "idle", "uuid": uid(), "loop": "loop", "length": 1.2,
        "animators": {
            bone_torso["uuid"]: {
                "name": "torso", "type": "bone",
                "position": [kf_pos(0.0, 0, 0, 0), kf_pos(0.6, 0, -0.4, 0), kf_pos(1.2, 0, 0, 0)],
                "rotation": [kf(0.0, 4, 15, 0), kf(0.6, 6, 15, 0), kf(1.2, 4, 15, 0)]
            },
            bone_head["uuid"]: {
                "name": "head", "type": "bone",
                "rotation": [kf(0.0, -4, -15, 0), kf(0.6, -6, -15, 0), kf(1.2, -4, -15, 0)]
            },
            bone_l_arm["uuid"]: {
                "name": "left_arm", "type": "bone",
                "rotation": [kf(0.0, -35, 20, -10), kf(0.6, -32, 20, -10), kf(1.2, -35, 20, -10)]
            },
            bone_r_arm["uuid"]: {
                "name": "right_arm", "type": "bone",
                "rotation": [kf(0.0, -15, -10, 10), kf(0.6, -12, -10, 10), kf(1.2, -15, -10, 10)]
            },
            bone_arrow_hand["uuid"]: {
                "name": "arrow_hand", "type": "bone",
                "rotation": [kf(0.0, 45, 0, 0), kf(1.2, 45, 0, 0)]
            }
        }
    }

    anim_walk = {
        "name": "walk", "uuid": uid(), "loop": "loop", "length": 0.8,
        "animators": {
            bone_r_leg["uuid"]: {
                "name": "right_leg", "type": "bone",
                "rotation": [kf(0.0, -28, 0, 0), kf(0.4, 28, 0, 0), kf(0.8, -28, 0, 0)]
            },
            bone_l_leg["uuid"]: {
                "name": "left_leg", "type": "bone",
                "rotation": [kf(0.0, 28, 0, 0), kf(0.4, -28, 0, 0), kf(0.8, 28, 0, 0)]
            },
            bone_l_arm["uuid"]: {
                "name": "left_arm", "type": "bone",
                "rotation": [kf(0.0, -20, 15, -5), kf(0.4, -45, 25, -10), kf(0.8, -20, 15, -5)]
            },
            bone_r_arm["uuid"]: {
                "name": "right_arm", "type": "bone",
                "rotation": [kf(0.0, 25, -10, 5), kf(0.4, -25, -10, 5), kf(0.8, 25, -10, 5)]
            },
            bone_torso["uuid"]: {
                "name": "torso", "type": "bone",
                "position": [kf_pos(0.0, 0, 0, 0), kf_pos(0.2, 0, 0.4, 0), kf_pos(0.4, 0, 0, 0), kf_pos(0.6, 0, 0.4, 0), kf_pos(0.8, 0, 0, 0)],
                "rotation": [kf(0.0, 5, 10, 0), kf(0.4, 5, -10, 0), kf(0.8, 5, 10, 0)]
            }
        }
    }

    anim_attack = {
        "name": "attack", "uuid": uid(), "loop": "once", "length": 0.38,
        "animators": {
            bone_torso["uuid"]: {
                "name": "torso", "type": "bone",
                "rotation": [kf(0.0, 0, 25, 0), kf(0.18, 0, 35, 0), kf(0.24, 0, 15, 0), kf(0.38, 4, 15, 0)]
            },
            bone_l_arm["uuid"]: {
                "name": "left_arm", "type": "bone",
                "rotation": [
                    kf(0.00, -35, 20, -10),
                    kf(0.15, -85, 30, -5),  # Bow aimed forward
                    kf(0.24, -90, 30, -5),  # Bow recoil
                    kf(0.38, -35, 20, -10)
                ]
            },
            bone_r_arm["uuid"]: {
                "name": "right_arm", "type": "bone",
                "rotation": [
                    kf(0.00, -15, -10, 10),
                    kf(0.15, -80, -25, 20), # Draw string to cheek
                    kf(0.24, -30, -10, 35), # Release string release recoil
                    kf(0.38, -15, -10, 10)
                ]
            },
            bone_arrow_hand["uuid"]: {
                "name": "arrow_hand", "type": "bone",
                "position": [kf_pos(0.0, 0, 0, 0), kf_pos(0.15, 0, 0, 2.0), kf_pos(0.24, 0, 0, -4.0), kf_pos(0.38, 0, 0, 0)],
                "rotation": [kf(0.0, 0, 0, 0), kf(0.15, 0, 0, 0), kf(0.24, 0, 0, 0), kf(0.38, 45, 0, 0)]
            }
        }
    }

    anim_special = {
        "name": "special", "uuid": uid(), "loop": "once", "length": 0.50,
        "animators": {
            bone_torso["uuid"]: {
                "name": "torso", "type": "bone",
                "position": [kf_pos(0.0, 0, 0, 0), kf_pos(0.25, 0, -0.6, -0.8), kf_pos(0.34, 0, -0.3, 0.8), kf_pos(0.50, 0, 0, 0)],
                "rotation": [kf(0.0, 4, 15, 0), kf(0.25, 2, 45, 0), kf(0.34, 8, 10, 0), kf(0.50, 4, 15, 0)]
            },
            bone_l_arm["uuid"]: {
                "name": "left_arm", "type": "bone",
                "rotation": [
                    kf(0.00, -35, 20, -10),
                    kf(0.25, -92, 40, 0),   # High tension bow hold
                    kf(0.34, -105, 35, 10), # Heavy recoil back
                    kf(0.50, -35, 20, -10)
                ]
            },
            bone_r_arm["uuid"]: {
                "name": "right_arm", "type": "bone",
                "rotation": [
                    kf(0.00, -15, -10, 10),
                    kf(0.25, -90, -40, 30), # Deep draw past ear
                    kf(0.34, -20, -15, 45), # Huge snap release
                    kf(0.50, -15, -10, 10)
                ]
            }
        }
    }

    anim_utility = {
        "name": "utility", "uuid": uid(), "loop": "once", "length": 0.45,
        "animators": {
            bone_r_arm["uuid"]: {
                "name": "right_arm", "type": "bone",
                "rotation": [
                    kf(0.00, -15, -10, 10),
                    kf(0.15, 30, -20, 10),  # Reach to belt
                    kf(0.30, -90, -10, 10), # Underhand forward toss
                    kf(0.45, -15, -10, 10)
                ]
            },
            bone_torso["uuid"]: {
                "name": "torso", "type": "bone",
                "rotation": [kf(0.0, 4, 15, 0), kf(0.15, 10, -15, 0), kf(0.30, -5, 20, 0), kf(0.45, 4, 15, 0)]
            }
        }
    }

    anim_ultimate = {
        "name": "ultimate", "uuid": uid(), "loop": "once", "length": 0.70,
        "animators": {
            bone_l_arm["uuid"]: {
                "name": "left_arm", "type": "bone",
                "rotation": [
                    kf(0.00, -35, 20, -10),
                    kf(0.25, -145, 35, -35), # Spread arms wide like eagle wings
                    kf(0.50, -145, 35, -35),
                    kf(0.70, -35, 20, -10)
                ]
            },
            bone_r_arm["uuid"]: {
                "name": "right_arm", "type": "bone",
                "rotation": [
                    kf(0.00, -15, -10, 10),
                    kf(0.25, -145, -35, 35), # Spread arms wide like eagle wings
                    kf(0.50, -145, -35, 35),
                    kf(0.70, -15, -10, 10)
                ]
            },
            bone_head["uuid"]: {
                "name": "head", "type": "bone",
                "rotation": [kf(0.0, -4, -15, 0), kf(0.25, -30, 0, 0), kf(0.50, -30, 0, 0), kf(0.70, -4, -15, 0)]
            },
            bone_torso["uuid"]: {
                "name": "torso", "type": "bone",
                "position": [kf_pos(0.0, 0, 0, 0), kf_pos(0.25, 0, 0.8, 0), kf_pos(0.50, 0, 0.8, 0), kf_pos(0.70, 0, 0, 0)],
                "rotation": [kf(0.0, 4, 15, 0), kf(0.25, -12, 0, 0), kf(0.50, -12, 0, 0), kf(0.70, 4, 15, 0)]
            }
        }
    }

    return {
        "meta": {"format_version": "4.5", "model_format": "free", "box_uv": False},
        "name": "hero_archer",
        "resolution": {"width": 64, "height": 64},
        "elements": elements,
        "outliner": outliner,
        "textures": [],
        "animations": [anim_idle, anim_walk, anim_attack, anim_special, anim_utility, anim_ultimate]
    }

# --- 3. ENGINEER BUILDER ---
def build_hero_engineer():
    elements = []

    # Head & Goggles
    c_head = make_cube("head", [-4, 24, -4], [4, 32, 4], [0, 24, 0], color=2)
    c_hair = make_cube("engineer_hair", [-4.2, 29, -4.2], [4.2, 32.5, 4.2], [0, 24, 0], color=4)
    c_goggles_frame = make_cube("goggles_frame", [-4.4, 28.5, -4.6], [4.4, 30.5, -3.8], [0, 24, 0], color=22)
    c_lens_l = make_cube("goggle_lens_l", [1.0, 28.7, -4.8], [3.6, 30.3, -4.4], [0, 24, 0], color=23)
    c_lens_r = make_cube("goggle_lens_r", [-3.6, 28.7, -4.8], [-1.0, 30.3, -4.4], [0, 24, 0], color=23)
    c_goggles_strap = make_cube("goggles_strap", [-4.3, 28.8, -4.0], [4.3, 30.2, 4.2], [0, 24, 0], color=4)

    # Torso, Apron & Backpack Battery
    c_torso = make_cube("torso", [-4.2, 12, -2.2], [4.2, 24, 2.2], [0, 12, 0], color=20)
    c_apron = make_cube("leather_apron", [-4.4, 13.0, -2.5], [4.4, 22.5, 2.3], [0, 12, 0], color=21)
    c_pouch_l = make_cube("tool_pouch_l", [4.3, 13.0, -1.0], [5.3, 17.0, 1.8], [0, 12, 0], color=4)
    c_belt_buckle = make_cube("brass_buckle", [-1.5, 12.2, -2.7], [1.5, 14.2, -2.3], [0, 12, 0], color=22)
    # Mechanical Backpack
    c_backpack = make_cube("powerpack_box", [-3.5, 14.0, 2.3], [3.5, 23.5, 5.5], [0, 18, 3.5], color=24)
    c_battery_cell = make_cube("powerpack_cell", [-2.5, 15.0, 5.5], [2.5, 22.0, 6.5], [0, 18, 3.5], color=22)
    c_exhaust_pipe = make_cube("exhaust_pipe", [2.0, 22.0, 3.0], [3.2, 26.5, 4.2], [0, 18, 3.5], color=29)
    c_led_indicator = make_cube("indicator_light", [-2.5, 21.0, 5.6], [-1.2, 22.5, 6.6], [0, 18, 3.5], color=28)

    # Right Arm & Heavy Wrench-Hammer
    c_r_arm = make_cube("right_arm", [-8.2, 12, -2], [-4.2, 24, 2], [-6.2, 22, 0], color=20)
    c_r_glove = make_cube("r_heavy_glove", [-8.4, 11.5, -2.2], [-4.0, 16.0, 2.2], [-6.2, 22, 0], color=21)
    # Weapon: Heavy combination wrench-hammer held in right hand (pivot at [-6.2, 12.5, 0])
    c_tool_handle = make_cube("tool_handle", [-6.7, 10.0, -4.0], [-5.7, 14.0, 8.0], [-6.2, 12.5, 0], color=24)
    c_hammer_head = make_cube("hammer_head", [-7.5, 10.0, -9.0], [-4.9, 14.5, -4.0], [-6.2, 12.5, 0], color=24)
    c_hammer_face = make_cube("hammer_face", [-7.3, 10.2, -9.8], [-5.1, 14.3, -8.8], [-6.2, 12.5, 0], color=22)
    c_wrench_claw1 = make_cube("wrench_claw1", [-6.9, 9.5, 8.0], [-5.5, 11.5, 12.5], [-6.2, 12.5, 0], color=24)
    c_wrench_claw2 = make_cube("wrench_claw2", [-6.9, 12.5, 8.0], [-5.5, 14.5, 12.5], [-6.2, 12.5, 0], color=24)

    # Left Arm & Gadget
    c_l_arm = make_cube("left_arm", [4.2, 12, -2], [8.2, 24, 2], [6.2, 22, 0], color=20)
    c_l_glove = make_cube("l_heavy_glove", [4.0, 11.5, -2.2], [8.4, 16.0, 2.2], [6.2, 22, 0], color=21)
    c_detonator = make_cube("hand_detonator", [5.4, 11.0, -3.2], [7.0, 14.0, -1.2], [6.2, 12.5, 0], color=27)

    # Legs & Heavy Work Boots
    c_r_leg = make_cube("right_leg", [-4.2, 0, -2], [-0.2, 12, 2], [-2.2, 12, 0], color=20)
    c_r_boot = make_cube("r_work_boot", [-4.4, 0.0, -2.6], [0.0, 5.0, 2.4], [-2.2, 12, 0], color=24)
    c_l_leg = make_cube("left_leg", [0.2, 0, -2], [4.2, 12, 2], [2.2, 12, 0], color=20)
    c_l_boot = make_cube("l_work_boot", [0.0, 0.0, -2.6], [4.4, 5.0, 2.4], [2.2, 12, 0], color=24)

    elements.extend([
        c_head, c_hair, c_goggles_frame, c_lens_l, c_lens_r, c_goggles_strap,
        c_torso, c_apron, c_pouch_l, c_belt_buckle, c_backpack, c_battery_cell, c_exhaust_pipe, c_led_indicator,
        c_r_arm, c_r_glove, c_tool_handle, c_hammer_head, c_hammer_face, c_wrench_claw1, c_wrench_claw2,
        c_l_arm, c_l_glove, c_detonator,
        c_r_leg, c_r_boot, c_l_leg, c_l_boot
    ])

    bone_tool = {
        "name": "wrench", "uuid": uid(), "origin": [-6.2, 12.5, 0],
        "children": [c_tool_handle["uuid"], c_hammer_head["uuid"], c_hammer_face["uuid"], c_wrench_claw1["uuid"], c_wrench_claw2["uuid"]]
    }
    bone_gadget = {
        "name": "gadget", "uuid": uid(), "origin": [6.2, 12.5, 0],
        "children": [c_detonator["uuid"]]
    }
    bone_head = {
        "name": "head", "uuid": uid(), "origin": [0, 24, 0],
        "children": [c_head["uuid"], c_hair["uuid"], c_goggles_frame["uuid"], c_lens_l["uuid"], c_lens_r["uuid"], c_goggles_strap["uuid"]]
    }
    bone_backpack = {
        "name": "powerpack", "uuid": uid(), "origin": [0, 18, 3.5],
        "children": [c_backpack["uuid"], c_battery_cell["uuid"], c_exhaust_pipe["uuid"], c_led_indicator["uuid"]]
    }
    bone_r_arm = {
        "name": "right_arm", "uuid": uid(), "origin": [-6.2, 22, 0],
        "children": [c_r_arm["uuid"], c_r_glove["uuid"], bone_tool]
    }
    bone_l_arm = {
        "name": "left_arm", "uuid": uid(), "origin": [6.2, 22, 0],
        "children": [c_l_arm["uuid"], c_l_glove["uuid"], bone_gadget]
    }
    bone_torso = {
        "name": "torso", "uuid": uid(), "origin": [0, 12, 0],
        "children": [c_torso["uuid"], c_apron["uuid"], c_pouch_l["uuid"], c_belt_buckle["uuid"], bone_backpack, bone_head, bone_r_arm, bone_l_arm]
    }
    bone_r_leg = {
        "name": "right_leg", "uuid": uid(), "origin": [-2.2, 12, 0],
        "children": [c_r_leg["uuid"], c_r_boot["uuid"]]
    }
    bone_l_leg = {
        "name": "left_leg", "uuid": uid(), "origin": [2.2, 12, 0],
        "children": [c_l_leg["uuid"], c_l_boot["uuid"]]
    }
    outliner = [{
        "name": "root", "uuid": uid(), "origin": [0, 0, 0],
        "children": [bone_torso, bone_r_leg, bone_l_leg]
    }]

    # Animations
    anim_idle = {
        "name": "idle", "uuid": uid(), "loop": "loop", "length": 1.2,
        "animators": {
            bone_torso["uuid"]: {
                "name": "torso", "type": "bone",
                "position": [kf_pos(0.0, 0, 0, 0), kf_pos(0.6, 0, -0.5, 0), kf_pos(1.2, 0, 0, 0)],
                "rotation": [kf(0.0, 6, -5, 0), kf(0.6, 8, -5, 0), kf(1.2, 6, -5, 0)]
            },
            bone_head["uuid"]: {
                "name": "head", "type": "bone",
                "rotation": [kf(0.0, -6, 5, 0), kf(0.6, -8, 5, 0), kf(1.2, -6, 5, 0)]
            },
            bone_r_arm["uuid"]: {
                "name": "right_arm", "type": "bone",
                "rotation": [kf(0.0, -100, 10, -15), kf(0.6, -96, 10, -15), kf(1.2, -100, 10, -15)] # Resting on shoulder
            },
            bone_tool["uuid"]: {
                "name": "wrench", "type": "bone",
                "rotation": [kf(0.0, -35, 10, 0), kf(0.6, -35, 10, 0), kf(1.2, -35, 10, 0)]
            },
            bone_l_arm["uuid"]: {
                "name": "left_arm", "type": "bone",
                "rotation": [kf(0.0, -15, 10, -10), kf(0.6, -18, 10, -10), kf(1.2, -15, 10, -10)]
            }
        }
    }

    anim_walk = {
        "name": "walk", "uuid": uid(), "loop": "loop", "length": 0.8,
        "animators": {
            bone_r_leg["uuid"]: {
                "name": "right_leg", "type": "bone",
                "rotation": [kf(0.0, -32, 0, 0), kf(0.4, 32, 0, 0), kf(0.8, -32, 0, 0)]
            },
            bone_l_leg["uuid"]: {
                "name": "left_leg", "type": "bone",
                "rotation": [kf(0.0, 32, 0, 0), kf(0.4, -32, 0, 0), kf(0.8, 32, 0, 0)]
            },
            bone_r_arm["uuid"]: {
                "name": "right_arm", "type": "bone",
                "rotation": [kf(0.0, -70, 10, -10), kf(0.4, -110, 10, -15), kf(0.8, -70, 10, -10)]
            },
            bone_l_arm["uuid"]: {
                "name": "left_arm", "type": "bone",
                "rotation": [kf(0.0, -30, 10, -10), kf(0.4, 30, 10, -10), kf(0.8, -30, 10, -10)]
            },
            bone_torso["uuid"]: {
                "name": "torso", "type": "bone",
                "position": [kf_pos(0.0, 0, 0, 0), kf_pos(0.2, 0, 0.6, 0), kf_pos(0.4, 0, 0, 0), kf_pos(0.6, 0, 0.6, 0), kf_pos(0.8, 0, 0, 0)],
                "rotation": [kf(0.0, 6, -8, 0), kf(0.4, 6, 8, 0), kf(0.8, 6, -8, 0)]
            }
        }
    }

    anim_attack = {
        "name": "attack", "uuid": uid(), "loop": "once", "length": 0.48,
        "animators": {
            bone_r_arm["uuid"]: {
                "name": "right_arm", "type": "bone",
                "rotation": [
                    kf(0.00, -100, 10, -15),
                    kf(0.16, -145, 15, -20), # Cock hammer high
                    kf(0.30, 50, 20, -10),   # Smash hammer down
                    kf(0.40, 20, 10, -5),
                    kf(0.48, -100, 10, -15)
                ]
            },
            bone_tool["uuid"]: {
                "name": "wrench", "type": "bone",
                "rotation": [
                    kf(0.00, -35, 10, 0),
                    kf(0.16, 20, 0, 0),
                    kf(0.30, -70, 0, 0), # Slam hammer face down
                    kf(0.48, -35, 10, 0)
                ]
            },
            bone_torso["uuid"]: {
                "name": "torso", "type": "bone",
                "position": [kf_pos(0.0, 0, 0, 0), kf_pos(0.16, 0, 0.4, -0.5), kf_pos(0.30, 0, -1.0, 1.5), kf_pos(0.48, 0, 0, 0)],
                "rotation": [kf(0.0, 6, -5, 0), kf(0.16, -6, -20, 0), kf(0.30, 20, 20, -5), kf(0.48, 6, -5, 0)]
            }
        }
    }

    anim_special = {
        "name": "special", "uuid": uid(), "loop": "once", "length": 0.45,
        "animators": {
            bone_torso["uuid"]: {
                "name": "torso", "type": "bone",
                "position": [kf_pos(0.0, 0, 0, 0), kf_pos(0.20, 0, -2.0, 0.5), kf_pos(0.45, 0, 0, 0)],
                "rotation": [kf(0.0, 6, 0, 0), kf(0.20, 30, 0, 0), kf(0.45, 6, 0, 0)] # Squat to deploy
            },
            bone_l_arm["uuid"]: {
                "name": "left_arm", "type": "bone",
                "rotation": [
                    kf(0.00, -15, 10, -10),
                    kf(0.20, 45, 20, -20),  # Place turret down
                    kf(0.45, -15, 10, -10)
                ]
            },
            bone_r_arm["uuid"]: {
                "name": "right_arm", "type": "bone",
                "rotation": [
                    kf(0.00, -100, 10, -15),
                    kf(0.25, -20, 15, -10), # Tap wrench down on turret
                    kf(0.45, -100, 10, -15)
                ]
            }
        }
    }

    anim_utility = {
        "name": "utility", "uuid": uid(), "loop": "once", "length": 0.45,
        "animators": {
            bone_torso["uuid"]: {
                "name": "torso", "type": "bone",
                "position": [kf_pos(0.0, 0, 0, 0), kf_pos(0.18, 0, -1.5, 0.2), kf_pos(0.45, 0, 0, 0)],
                "rotation": [kf(0.0, 6, 0, 0), kf(0.18, 25, -15, 0), kf(0.45, 6, 0, 0)]
            },
            bone_l_arm["uuid"]: {
                "name": "left_arm", "type": "bone",
                "rotation": [
                    kf(0.00, -15, 10, -10),
                    kf(0.18, 40, -10, 15),  # Drop mine
                    kf(0.30, -50, -20, 25), # Click remote detonator
                    kf(0.45, -15, 10, -10)
                ]
            }
        }
    }

    anim_ultimate = {
        "name": "ultimate", "uuid": uid(), "loop": "once", "length": 0.75,
        "animators": {
            bone_l_arm["uuid"]: {
                "name": "left_arm", "type": "bone",
                "rotation": [
                    kf(0.00, -15, 10, -10),
                    kf(0.20, -125, -30, 45), # Bring radio handset to ear
                    kf(0.55, -125, -30, 45), # Hold radio & speak
                    kf(0.75, -15, 10, -10)
                ]
            },
            bone_r_arm["uuid"]: {
                "name": "right_arm", "type": "bone",
                "rotation": [
                    kf(0.00, -100, 10, -15),
                    kf(0.25, -60, 20, -20), # Point wrench forward at target
                    kf(0.55, -60, 20, -20),
                    kf(0.75, -100, 10, -15)
                ]
            },
            bone_head["uuid"]: {
                "name": "head", "type": "bone",
                "rotation": [kf(0.0, -6, 5, 0), kf(0.25, -10, 15, 0), kf(0.55, -10, 15, 0), kf(0.75, -6, 5, 0)]
            },
            bone_torso["uuid"]: {
                "name": "torso", "type": "bone",
                "rotation": [kf(0.0, 6, -5, 0), kf(0.25, 2, 10, 0), kf(0.55, 2, 10, 0), kf(0.75, 6, -5, 0)]
            }
        }
    }

    return {
        "meta": {"format_version": "4.5", "model_format": "free", "box_uv": False},
        "name": "hero_engineer",
        "resolution": {"width": 64, "height": 64},
        "elements": elements,
        "outliner": outliner,
        "textures": [],
        "animations": [anim_idle, anim_walk, anim_attack, anim_special, anim_utility, anim_ultimate]
    }

# --- 4. PROPS BUILDERS ---
def build_decoy_dummy():
    elements = []
    # Cross stand (wood)
    c_post = make_cube("wood_post", [-1.0, 0.0, -1.0], [1.0, 26.0, 1.0], [0, 0, 0], color=35)
    c_crossbar = make_cube("crossbar", [-8.0, 18.0, -1.0], [8.0, 20.0, 1.0], [0, 19, 0], color=35)
    c_base1 = make_cube("base_plank1", [-6.0, 0.0, -1.5], [6.0, 1.2, 1.5], [0, 0, 0], color=35)
    c_base2 = make_cube("base_plank2", [-1.5, 0.0, -6.0], [1.5, 1.2, 6.0], [0, 0, 0], color=35)

    # Straw Torso with Target
    c_torso = make_cube("straw_torso", [-4.5, 10.0, -3.0], [4.5, 23.0, 3.0], [0, 16, 0], color=30)
    c_target_outer = make_cube("target_outer", [-3.5, 13.0, -3.4], [3.5, 20.0, -2.9], [0, 16, 0], color=31)
    c_target_inner = make_cube("target_inner", [-2.0, 14.5, -3.6], [2.0, 18.5, -3.1], [0, 16, 0], color=32)
    c_target_bullseye = make_cube("target_bullseye", [-0.8, 15.5, -3.8], [0.8, 17.5, -3.3], [0, 16, 0], color=31)

    # Head & Floppy Archer Hat
    c_head = make_cube("straw_head", [-3.2, 23.0, -3.2], [3.2, 29.5, 3.2], [0, 23, 0], color=30)
    c_hat_brim = make_cube("hat_brim", [-5.5, 28.5, -5.5], [5.5, 29.8, 5.5], [0, 29, 0], color=10)
    c_hat_cone = make_cube("hat_cone", [-2.8, 29.8, -2.8], [2.8, 33.5, 2.8], [0, 29, 0], color=10)
    c_hat_feather = make_cube("hat_feather", [2.6, 31.0, 1.5], [3.4, 36.5, 2.8], [0, 29, 0], color=13)

    elements.extend([
        c_post, c_crossbar, c_base1, c_base2,
        c_torso, c_target_outer, c_target_inner, c_target_bullseye,
        c_head, c_hat_brim, c_hat_cone, c_hat_feather
    ])

    outliner = [{
        "name": "root", "uuid": uid(), "origin": [0, 0, 0],
        "children": [e["uuid"] for e in elements]
    }]

    return {
        "meta": {"format_version": "4.5", "model_format": "free", "box_uv": False},
        "name": "decoy_dummy",
        "resolution": {"width": 64, "height": 64},
        "elements": elements,
        "outliner": outliner,
        "textures": [],
        "animations": []
    }

def build_temp_turret():
    elements = []
    # Tripod Base
    c_center = make_cube("tripod_center", [-2.0, 1.0, -2.0], [2.0, 4.5, 2.0], [0, 0, 0], color=24)
    c_leg1 = make_cube("leg_front", [-1.5, 0.0, -7.0], [1.5, 2.5, -1.5], [0, 0, 0], color=33)
    c_leg2 = make_cube("leg_back_l", [-6.5, 0.0, 1.5], [-1.0, 2.5, 5.5], [0, 0, 0], color=33)
    c_leg3 = make_cube("leg_back_r", [1.0, 0.0, 1.5], [6.5, 2.5, 5.5], [0, 0, 0], color=33)
    c_pivot_ring = make_cube("swivel_ring", [-3.0, 4.5, -3.0], [3.0, 6.0, 3.0], [0, 5, 0], color=22)

    # Turret Head & Twin Barrels (under swivel bone)
    c_turret_box = make_cube("turret_housing", [-4.0, 6.0, -4.5], [4.0, 12.0, 4.5], [0, 8, 0], color=33)
    c_ammo_drum = make_cube("ammo_drum", [-5.5, 7.0, -2.0], [-4.0, 11.5, 3.0], [0, 8, 0], color=34)
    c_sensor_lens = make_cube("sensor_eye", [1.5, 9.0, -5.0], [3.5, 11.0, -4.2], [0, 8, 0], color=23)
    c_barrel_l = make_cube("barrel_left", [-3.2, 7.5, -12.0], [-1.6, 9.5, -4.5], [0, 8, 0], color=24)
    c_barrel_r = make_cube("barrel_right", [-0.8, 7.5, -12.0], [0.8, 9.5, -4.5], [0, 8, 0], color=24)

    elements.extend([
        c_center, c_leg1, c_leg2, c_leg3, c_pivot_ring,
        c_turret_box, c_ammo_drum, c_sensor_lens, c_barrel_l, c_barrel_r
    ])

    bone_swivel = {
        "name": "swivel", "uuid": uid(), "origin": [0, 6, 0],
        "children": [c_turret_box["uuid"], c_ammo_drum["uuid"], c_sensor_lens["uuid"], c_barrel_l["uuid"], c_barrel_r["uuid"]]
    }
    outliner = [{
        "name": "root", "uuid": uid(), "origin": [0, 0, 0],
        "children": [c_center["uuid"], c_leg1["uuid"], c_leg2["uuid"], c_leg3["uuid"], c_pivot_ring["uuid"], bone_swivel]
    }]

    return {
        "meta": {"format_version": "4.5", "model_format": "free", "box_uv": False},
        "name": "temp_turret",
        "resolution": {"width": 64, "height": 64},
        "elements": elements,
        "outliner": outliner,
        "textures": [],
        "animations": []
    }

def build_remote_mine():
    elements = []
    # Octagonal Landmine body
    c_plate = make_cube("mine_base", [-4.5, 0.0, -4.5], [4.5, 1.2, 4.5], [0, 0, 0], color=24)
    c_body = make_cube("mine_casing", [-4.0, 1.2, -4.0], [4.0, 3.0, 4.0], [0, 0, 0], color=24)
    c_rim = make_cube("mine_hazard_rim", [-3.5, 2.8, -3.5], [3.5, 3.4, 3.5], [0, 0, 0], color=25)
    # 4 Corner Sensor Bolts
    c_bolt1 = make_cube("sensor_pin1", [-3.2, 3.4, -3.2], [-2.4, 4.2, -2.4], [0, 0, 0], color=22)
    c_bolt2 = make_cube("sensor_pin2", [2.4, 3.4, -3.2], [3.2, 4.2, -2.4], [0, 0, 0], color=22)
    c_bolt3 = make_cube("sensor_pin3", [-3.2, 3.4, 2.4], [-2.4, 4.2, 3.2], [0, 0, 0], color=22)
    c_bolt4 = make_cube("sensor_pin4", [2.4, 3.4, 2.4], [3.2, 4.2, 3.2], [0, 0, 0], color=22)
    # Central Glowing Beacon Dome
    c_beacon = make_cube("beacon_light", [-1.5, 3.2, -1.5], [1.5, 4.5, 1.5], [0, 0, 0], color=27)

    elements.extend([c_plate, c_body, c_rim, c_bolt1, c_bolt2, c_bolt3, c_bolt4, c_beacon])
    outliner = [{
        "name": "root", "uuid": uid(), "origin": [0, 0, 0],
        "children": [e["uuid"] for e in elements]
    }]

    return {
        "meta": {"format_version": "4.5", "model_format": "free", "box_uv": False},
        "name": "remote_mine",
        "resolution": {"width": 64, "height": 64},
        "elements": elements,
        "outliner": outliner,
        "textures": [],
        "animations": []
    }

# --- 5. EXPORT TO GODOT 4 TSCN ---
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

def generate_tscn(bbmodel, output_path, root_node_name="ModelRoot"):
    elements = {e["uuid"]: e for e in bbmodel["elements"]}
    bone_dict = {}
    element_to_bone = {}
    bone_paths = {}

    for root_node in bbmodel.get("outliner", []):
        build_tree_maps(root_node, None, bone_dict, element_to_bone, bone_paths, "")

    lines = []
    uid_attr = f'uid="uid://cs_{bbmodel["name"]}_{str(uuid.uuid4())[:8]}"'
    lines.append(f'[gd_scene load_steps=120 format=3 {uid_attr}]')
    lines.append("")

    # 1. Texture ExtResource
    model_name = bbmodel["name"]
    tex_path = f"res://assets/models/textures/{model_name}.png"
    lines.append(f'[ext_resource type="Texture2D" path="{tex_path}" id="1_tex"]')
    lines.append("")

    # 2. Materials SubResources
    mat_ids = {}
    for col_idx, col_data in PALETTE_COLORS.items():
        res_id = f"StandardMaterial3D_col_{col_idx}"
        mat_ids[col_idx] = res_id
        tx = (col_idx % 8) * 8
        ty = (col_idx // 8) * 8
        uv_x = round(tx / 64.0, 5)
        uv_y = round(ty / 64.0, 5)
        lines.append(f'[sub_resource type="StandardMaterial3D" id="{res_id}"]')
        lines.append('albedo_texture = ExtResource("1_tex")')
        lines.append('texture_filter = 0')
        lines.append('uv1_scale = Vector3(0.125, 0.125, 1)')
        lines.append(f'uv1_offset = Vector3({uv_x}, {uv_y}, 0)')
        lines.append(f'metallic = {col_data["metallic"]}')
        lines.append(f'roughness = {col_data["roughness"]}')
        if "emission" in col_data:
            lines.append('emission_enabled = true')
            lines.append('emission_texture = ExtResource("1_tex")')
            lines.append(f'emission = {col_data["emission"]}')
            lines.append(f'emission_energy_multiplier = {col_data.get("emission_energy", 1.0)}')
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

        mesh_id = f"BoxMesh_{el['name']}_{str(uuid.uuid4())[:6]}"
        mesh_ids[el_uuid] = mesh_id
        lines.append(f'[sub_resource type="BoxMesh" id="{mesh_id}"]')
        lines.append(f'material = SubResource("{mat_id}")')
        lines.append(f'size = Vector3({sx}, {sy}, {sz})')
        lines.append("")

    # 3. Animations SubResources
    anim_subres_ids = {}
    animations = bbmodel.get("animations", [])
    for anim in animations:
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
                for kf_entry in rot_kfs:
                    t = float(kf_entry["time"])
                    dp = kf_entry["data_points"][0]
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
                b_name = b_path.split("/")[-1]
                b_info = bone_dict.get(b_name)
                parent_origin = bone_dict[b_info["parent"]]["origin"] if b_info and b_info.get("parent") else [0, 0, 0]
                rest_px = round((b_info["origin"][0] - parent_origin[0]) * SCALE, 5) if b_info else 0.0
                rest_py = round((b_info["origin"][1] - parent_origin[1]) * SCALE, 5) if b_info else 0.0
                rest_pz = round((b_info["origin"][2] - parent_origin[2]) * SCALE, 5) if b_info else 0.0

                for kf_entry in pos_kfs:
                    t = float(kf_entry["time"])
                    dp = kf_entry["data_points"][0]
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

    # 4. AnimationLibrary (if animations exist)
    if animations:
        lines.append(f'[sub_resource type="AnimationLibrary" id="AnimationLibrary_{bbmodel["name"]}"]')
        lines.append('_data = {')
        anim_entries = [f'"{name}": SubResource("{subres_id}")' for name, subres_id in anim_subres_ids.items()]
        lines.append(",\n".join(anim_entries))
        lines.append('}')
        lines.append("")

    # 5. Scene Hierarchy Nodes
    lines.append(f'[node name="{root_node_name}" type="Node3D"]')
    lines.append("")

    if animations:
        lines.append('[node name="AnimationPlayer" type="AnimationPlayer" parent="."]')
        lines.append('libraries = {')
        lines.append(f'"": SubResource("AnimationLibrary_{bbmodel["name"]}")')
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
    print(f"Generated scene: {output_path}")

def main():
    models = [
        (build_hero_warrior(), "assets/models/sources/hero_warrior.bbmodel", "assets/models/characters/hero_warrior.tscn", "HeroWarrior"),
        (build_hero_archer(), "assets/models/sources/hero_archer.bbmodel", "assets/models/characters/hero_archer.tscn", "HeroArcher"),
        (build_hero_engineer(), "assets/models/sources/hero_engineer.bbmodel", "assets/models/characters/hero_engineer.tscn", "HeroEngineer"),
        (build_decoy_dummy(), "assets/models/sources/decoy_dummy.bbmodel", "assets/models/props/decoy_dummy_model.tscn", "DecoyDummyModel"),
        (build_temp_turret(), "assets/models/sources/temp_turret.bbmodel", "assets/models/props/temp_turret_model.tscn", "TempTurretModel"),
        (build_remote_mine(), "assets/models/sources/remote_mine.bbmodel", "assets/models/props/remote_mine_model.tscn", "RemoteMineModel"),
    ]

    for bb, bb_path, tscn_path, root_name in models:
        m_name = bb["name"]
        tex_path = f"assets/models/textures/{m_name}.png"
        b64_data = generate_model_texture(m_name, tex_path)
        print(f"Generated texture atlas: {tex_path}")

        bb["textures"] = [{
            "name": m_name,
            "folder": "textures",
            "id": "0",
            "particle": False,
            "render_mode": "default",
            "visible": True,
            "mode": "bitmap",
            "saved": True,
            "uuid": uid(),
            "source": f"data:image/png;base64,{b64_data}",
            "width": 64,
            "height": 64,
            "relative_path": f"../textures/{m_name}.png"
        }]

        os.makedirs(os.path.dirname(bb_path), exist_ok=True)
        with open(bb_path, "w", encoding="utf-8") as f:
            json.dump(bb, f, indent=2)
        print(f"Saved bbmodel: {bb_path}")
        generate_tscn(bb, tscn_path, root_name)

if __name__ == "__main__":
    main()

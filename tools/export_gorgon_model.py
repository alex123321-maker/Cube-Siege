"""Author/export the original editable voxel Gorgon; one BB unit is 1/16 m.

Geometry is canonical in assets/models/sources/enemies/boss_gorgon.bbmodel.
Reuses the project's material-batched glTF exporter without altering buildings.
Native pose animation lives in scripts/enemies/gorgon_presentation.gd.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import uuid

import export_building_models as pipeline

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "assets/models/sources/enemies"
OUTPUT_DIR = ROOT / "assets/models/enemies"
PALETTE = [
    ("stone", "#59666b", 0.0, 0.92),
    ("stone_light", "#919b91", 0.0, 0.94),
    ("stone_shadow", "#39484e", 0.0, 0.94),
    ("basalt", "#252f34", 0.0, 0.92),
    ("moss", "#506448", 0.0, 0.96),
    ("horn", "#afa084", 0.0, 0.90),
    ("horn_tip", "#d7cbad", 0.0, 0.91),
    ("bronze", "#8b6446", 0.22, 0.75),
    ("ember", "#ee682b", 0.0, 0.82),
    ("flame", "#ffbb50", 0.0, 0.80),
    ("hot", "#ffe6a2", 0.0, 0.78),
]


def configure_pipeline() -> None:
    pipeline.PALETTE = PALETTE
    pipeline.SOURCE_DIR = SOURCE_DIR
    pipeline.OUTPUT_DIR = OUTPUT_DIR
    pipeline.stable_id = lambda key: str(uuid.uuid5(uuid.NAMESPACE_URL, "cube-siege/gorgon/" + key))


def author() -> None:
    model = pipeline.Model("boss_gorgon")
    model.groups = {
        "body": ((0, 1.1, 0.08), []),
        "head": ((0, 2.35, -0.45), []),
        "arm_left": ((-0.88, 2.28, 0.1), []),
        "arm_right": ((0.88, 2.28, 0.1), []),
        "leg_left": ((-0.48, 1.1, 0.08), []),
        "leg_right": ((0.48, 1.1, 0.08), []),
    }
    box = model.box
    box("waist", (0, 1.10, 0.10), (1.12, 0.40, 0.90), "stone_shadow", "body")
    box("chest", (0, 1.91, 0.12), (1.46, 1.36, 1.22), "stone", "body")
    box("hunched_back", (0, 2.39, 0.30), (1.23, 0.78, 1.10), "stone_shadow", "body", (10, 0, 0))
    box("chest_keystone", (0, 2.06, -0.55), (0.72, 0.96, 0.19), "stone_light", "body")
    box("chest_core", (0, 1.92, -0.662), (0.07, 0.65, 0.028), "ember", "body")
    box("core_cross_crack", (0.13, 2.14, -0.664), (0.24, 0.055, 0.028), "ember", "body")
    for sign, suffix in ((-1, "left"), (1, "right")):
        box("rib_plate_" + suffix, (sign * 0.52, 1.9, -0.5), (0.35, 0.82, 0.26), "stone_shadow", "body", (0, 0, -sign * 9))
        box("waist_plate_" + suffix, (sign * 0.35, 1.26, -0.42), (0.44, 0.26, 0.21), "stone_light", "body", (0, 0, sign * 10))
    box("skull", (0, 2.43, -0.61), (1.04, 0.75, 0.76), "stone", "head")
    box("forehead", (0, 2.75, -0.70), (0.84, 0.24, 0.67), "stone_light", "head", (8, 0, 0))
    box("muzzle", (0, 2.15, -1.01), (0.91, 0.34, 0.46), "stone_shadow", "head")
    box("nose", (0, 2.24, -1.25), (0.40, 0.20, 0.10), "basalt", "head")
    box("jaw", (0, 1.97, -0.97), (0.84, 0.20, 0.42), "stone_light", "head")
    for sign, suffix in ((-1, "left"), (1, "right")):
        box("eye_socket_" + suffix, (sign * 0.28, 2.48, -1.001), (0.38, 0.20, 0.075), "basalt", "head")
        box("eye_" + suffix, (sign * 0.28, 2.47, -1.045), (0.27, 0.12, 0.035), "flame", "head")
        box("eye_core_" + suffix, (sign * 0.28, 2.47, -1.065), (0.10, 0.10, 0.02), "hot", "head")
        box("brow_" + suffix, (sign * 0.26, 2.64, -1.03), (0.44, 0.15, 0.16), "stone_light", "head", (0, 0, -sign * 12))
        box("cheek_" + suffix, (sign * 0.44, 2.21, -0.94), (0.24, 0.35, 0.34), "stone", "head", (0, 0, sign * 9))
        box("horn_socket_" + suffix, (sign * 0.56, 2.72, -0.58), (0.28, 0.28, 0.32), "bronze", "head")
        box("horn_base_" + suffix, (sign * 0.68, 2.84, -0.58), (0.25, 0.37, 0.25), "horn", "head", (0, 0, -sign * 28))
        box("horn_tip_" + suffix, (sign * 0.88, 3.04, -0.69), (0.17, 0.42, 0.17), "horn_tip", "head", (-28, 0, -sign * 40))
        group = "arm_" + suffix
        box("shoulder_" + suffix, (sign * 0.91, 2.32, 0.1), (0.58, 0.67, 1.08), "stone", group, (0, 0, sign * 8))
        box("shoulder_cap_" + suffix, (sign * 0.92, 2.64, 0.13), (0.48, 0.20, 0.91), "stone_light", group, (0, 0, sign * 8))
        box("shoulder_moss_" + suffix, (sign * 0.93, 2.75, 0.37), (0.30, 0.035, 0.38), "moss", group)
        box("upper_arm_" + suffix, (sign * 0.94, 1.79, 0.05), (0.44, 0.64, 0.55), "stone_shadow", group)
        box("forearm_" + suffix, (sign * 0.97, 1.38, -0.09), (0.49, 0.57, 0.61), "stone", group, (8, 0, 0))
        box("fist_" + suffix, (sign * 0.97, 1.03, -0.14), (0.52, 0.45, 0.65), "stone_shadow", group)
        box("knuckles_" + suffix, (sign * 0.97, 1.10, -0.47), (0.47, 0.21, 0.09), "stone_light", group)
        group = "leg_" + suffix
        box("thigh_" + suffix, (sign * 0.48, 0.99, 0.13), (0.47, 0.43, 0.57), "stone_shadow", group)
        box("knee_" + suffix, (sign * 0.48, 0.76, -0.09), (0.53, 0.31, 0.53), "stone_light", group)
        box("shin_" + suffix, (sign * 0.48, 0.46, 0.06), (0.43, 0.39, 0.44), "stone", group)
        box("hoof_" + suffix, (sign * 0.48, 0.19, -0.13), (0.62, 0.38, 0.83), "basalt", group)
        box("hoof_split_" + suffix, (sign * 0.48, 0.15, -0.553), (0.045, 0.28, 0.015), "stone_light", group)
        box("hoof_band_" + suffix, (sign * 0.48, 0.33, -0.15), (0.64, 0.075, 0.78), "bronze", group)
    model.write()
    path = SOURCE_DIR / "boss_gorgon.bbmodel"
    data = json.loads(path.read_text(encoding="utf-8"))
    data["cube_siege"]["animation_driver"] = "res://scripts/enemies/gorgon_presentation.gd"
    data["cube_siege"]["forward_axis"] = "-Z (matches Gorgon's charge controller)"
    data["cube_siege"]["pose_states"] = ["idle", "walk", "attack", "death", "windup", "charge", "recovery"]
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--author", action="store_true")
    args = parser.parse_args()
    configure_pipeline()
    if args.author:
        author()
    pipeline.export(SOURCE_DIR / "boss_gorgon.bbmodel")


if __name__ == "__main__":
    main()

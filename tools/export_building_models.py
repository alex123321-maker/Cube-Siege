"""Export editable Blockbench building sources to compact, material-batched glTF.

One Blockbench unit is 1/16 metre. Sources, palettes and geometry are authored
for Cube Siege; no downloaded assets are used. Run with --author to recreate the
initial demo sources, or without it to export subsequent Blockbench edits.
"""
from __future__ import annotations

import argparse
import base64
import io
import json
import math
from pathlib import Path
import struct
import uuid

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "assets/models/sources/buildings"
OUTPUT_DIR = ROOT / "assets/models/buildings"
PALETTE = [
    ("wood", "#795038", 0.0, 0.85), ("wood_light", "#ae7b49", 0.0, 0.86),
    ("wood_dark", "#4b3228", 0.0, 0.9), ("iron", "#566170", 0.68, 0.45),
    ("steel", "#91a1ae", 0.7, 0.38), ("iron_dark", "#303b4a", 0.65, 0.5),
    ("stone", "#727581", 0.0, 0.94), ("stone_light", "#999b9e", 0.0, 0.96),
    ("cloth", "#426c79", 0.0, 0.96), ("gold", "#cf9e4c", 0.55, 0.4),
    ("coal", "#292b30", 0.0, 0.96), ("ember", "#ee5828", 0.0, 0.85),
    ("flame", "#ffb44b", 0.0, 0.82), ("hot", "#ffe99a", 0.0, 0.85),
]
NAMES = ["wood_wall", "iron_wall", "floor_spikes", "archer_tower", "ballista", "campfire", "workbench"]


def stable_id(key: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "cube-siege/demo-buildings/" + key))


class Model:
    def __init__(self, name: str):
        self.name = name
        self.elements: list[dict] = []
        self.groups: dict[str, tuple[tuple[float, float, float], list[str]]] = {"Body": ((0, 0, 0), [])}

    def box(self, name: str, center: tuple, size: tuple, material: str,
            group: str = "Body", rotation: tuple = (0, 0, 0)) -> None:
        index = next(i for i, p in enumerate(PALETTE) if p[0] == material)
        origin = self.groups[group][0]
        element_id = stable_id(self.name + "/" + name)
        self.elements.append({
            "name": name, "uuid": element_id, "type": "cube",
            "from": [round((c - s / 2) * 16, 5) for c, s in zip(center, size)],
            "to": [round((c + s / 2) * 16, 5) for c, s in zip(center, size)],
            "origin": [round(c * 16, 5) for c in center], "rotation": list(rotation),
            "color": index % 10, "export": True,
            "faces": {face: {"uv": [0, index * 8, 8, index * 8 + 8], "texture": 0}
                      for face in ("north", "south", "east", "west", "up", "down")},
            "cube_siege_material": material,
        })
        self.groups[group][1].append(element_id)

    def write(self) -> None:
        atlas = Image.new("RGBA", (8, len(PALETTE) * 8))
        for i, (_, color, _, _) in enumerate(PALETTE):
            ImageDraw.Draw(atlas).rectangle((0, i * 8, 7, i * 8 + 7), fill=color)
        png = io.BytesIO()
        atlas.save(png, format="PNG")
        data = {
            "meta": {"format_version": "4.5", "model_format": "free", "box_uv": False},
            "name": self.name, "resolution": {"width": 8, "height": len(PALETTE) * 8},
            "elements": self.elements,
            "outliner": [{"name": name, "uuid": stable_id(self.name + "/group/" + name),
                          "origin": [n * 16 for n in origin], "children": children,
                          "export": True, "isOpen": True}
                         for name, (origin, children) in self.groups.items()],
            "textures": [{"name": "building_palette.png", "id": "0", "uuid": stable_id("palette"),
                          "source": "data:image/png;base64," + base64.b64encode(png.getvalue()).decode(),
                          "width": 8, "height": len(PALETTE) * 8}],
            "animations": [],
            "cube_siege": {"units_per_metre": 16, "provenance": "Original Cube Siege voxel geometry",
                           "palette": PALETTE},
        }
        SOURCE_DIR.mkdir(parents=True, exist_ok=True)
        (SOURCE_DIR / f"{self.name}.bbmodel").write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def author_sources() -> None:
    m = Model("wood_wall")
    for i, x in enumerate((-0.35, 0, 0.35)):
        height = (1.88, 2.0, 1.92)[i]
        m.box(f"post_{i}", (x, height / 2, 0), (0.29, height, 0.72), "wood_light" if i == 1 else "wood")
        m.box(f"cap_{i}", (x, height - 0.1, 0), (0.19, 0.18, 0.62), "wood_light")
        m.box(f"grain_{i}", (x - 0.07, 0.98, 0.368), (0.035, 1.35, 0.02), "wood_dark")
    for y in (0.42, 1.38):
        for z in (-0.38, 0.38):
            m.box(f"rail_{y}_{z}", (0, y, z), (0.97, 0.13, 0.12), "wood_dark")
            for x in (-0.35, 0.35):
                m.box(f"rivet_{x}_{y}_{z}", (x, y, z * 1.18), (0.065, 0.065, 0.025), "steel")
    m.write()

    m = Model("iron_wall")
    m.box("stone_foot", (0, 0.13, 0), (1, 0.26, 1), "stone")
    m.box("armour_core", (0, 1.09, 0), (0.83, 1.64, 0.74), "iron_dark")
    for i, y in enumerate((0.57, 1.05, 1.53)):
        for z in (-0.395, 0.395):
            m.box(f"plate_{i}_{z}", (0, y, z), (0.84, 0.44, 0.1), "iron")
            for x in (-0.31, 0.31):
                m.box(f"bolt_{x}_{i}_{z}", (x, y + 0.13, z * 1.15), (0.075, 0.075, 0.035), "steel")
                m.box(f"thorn_{x}_{i}_{z}", (x, y - 0.07, z * 1.2), (0.10, 0.16, 0.19), "steel", rotation=(35, 0, 0))
    for x in (-0.455, 0.455):
        m.box(f"buttress_{x}", (x, 1.03, 0), (0.09, 1.82, 0.90), "steel")
    for x in (-0.35, 0, 0.35):
        m.box(f"crenel_{x}", (x, 1.91, 0), (0.22, 0.18, 0.9), "iron")
    m.write()

    m = Model("floor_spikes")
    m.groups["Spikes"] = ((0, 0, 0), [])
    for i, x in enumerate((-0.32, 0, 0.32)):
        m.box(f"plank_{i}", (x, 0.06, 0), (0.29, 0.12, 0.97), "wood" if i != 1 else "wood_light")
    for z in (-0.35, 0.35):
        m.box(f"binding_{z}", (0, 0.13, z), (0.99, 0.035, 0.10), "iron_dark")
    for i, x in enumerate((-0.3, 0, 0.3)):
        for j, z in enumerate((-0.3, 0, 0.3)):
            m.box(f"spike_base_{i}_{j}", (x, 0.23, z), (0.14, 0.19, 0.14), "iron", "Spikes")
            m.box(f"spike_tip_{i}_{j}", (x, 0.37, z), (0.075, 0.13, 0.075), "steel", "Spikes")
    m.write()

    m = Model("archer_tower")
    m.groups["BowPivot"] = ((0, 3.15, 0), [])
    m.box("foundation", (0, 0.13, 0), (1.16, 0.26, 1.16), "stone")
    for x in (-0.37, 0.37):
        for z in (-0.37, 0.37):
            m.box(f"upright_{x}_{z}", (x, 1.53, z), (0.22, 2.80, 0.22), "wood_dark")
            m.box(f"foot_band_{x}_{z}", (x, 0.33, z), (0.25, 0.15, 0.25), "iron")
    for z in (-0.38, 0.38):
        m.box(f"diagonal_{z}", (0, 1.58, z), (0.12, 2.15, 0.13), "wood", rotation=(0, 0, 17))
    for i, y in enumerate((0.5, 0.85, 1.2, 1.55, 1.9, 2.25, 2.6)):
        m.box(f"ladder_{i}", (0, y, 0.51), (0.48, 0.065, 0.09), "wood_light")
    m.box("floor", (0, 2.84, 0), (1.36, 0.20, 1.36), "wood_light")
    for z in (-0.62, 0.62):
        m.box(f"parapet_{z}", (0, 3.06, z), (1.38, 0.24, 0.14), "wood")
    for x in (-0.62, 0.62):
        m.box(f"parapet_{x}", (x, 3.06, 0), (0.14, 0.24, 1.1), "wood")
    m.box("banner", (0.40, 2.49, 0.66), (0.27, 0.48, 0.035), "cloth")
    m.box("banner_stripe", (0.40, 2.49, 0.685), (0.07, 0.45, 0.015), "gold")
    m.box("bow_stock", (0, 3.22, 0), (0.14, 0.13, 0.95), "wood_dark", "BowPivot")
    m.box("bow_limb", (0, 3.22, -0.33), (0.97, 0.12, 0.12), "wood_light", "BowPivot")
    m.box("bow_string", (0, 3.25, -0.16), (0.9, 0.02, 0.025), "gold", "BowPivot")
    m.box("arrow", (0, 3.32, -0.3), (0.035, 0.035, 0.92), "steel", "BowPivot")
    m.write()

    m = Model("ballista")
    m.groups["BowPivot"] = ((0, 2.32, 0), [])
    m.box("foundation", (0, 0.13, 0), (1.22, 0.26, 1.22), "stone")
    for i in range(4):
        y = 0.43 + i * 0.42
        m.box(f"stone_course_{i}", (0, y, 0), (1.10 - 0.04 * (i % 2), 0.38, 1.08), "stone_light" if i % 2 else "stone")
    for x in (-0.49, 0.49):
        m.box(f"iron_brace_{x}", (x, 1.08, 0), (0.07, 1.82, 1.09), "iron_dark")
    m.box("mount_platform", (0, 2.06, 0), (1.38, 0.18, 1.38), "iron")
    m.box("swivel", (0, 2.23, 0), (0.36, 0.2, 0.36), "steel")
    m.box("stock", (0, 2.38, 0), (0.25, 0.25, 1.53), "wood_dark", "BowPivot")
    m.box("guide", (0, 2.53, -0.15), (0.13, 0.055, 1.60), "iron", "BowPivot")
    for x in (-0.49, 0.49):
        m.box(f"limb_{x}", (x, 2.41, -0.44), (0.92, 0.19, 0.18), "wood", "BowPivot", rotation=(0, -12 if x < 0 else 12, 0))
        m.box(f"end_cap_{x}", (x * 1.78, 2.41, -0.35), (0.14, 0.23, 0.24), "steel", "BowPivot")
    m.box("bowstring", (0, 2.45, -0.08), (1.70, 0.035, 0.035), "gold", "BowPivot")
    m.box("bolt", (0, 2.58, -0.42), (0.065, 0.065, 1.6), "steel", "BowPivot")
    m.box("bolt_point", (0, 2.58, -1.16), (0.12, 0.11, 0.22), "steel", "BowPivot")
    m.box("crank", (0.36, 2.37, 0.50), (0.42, 0.075, 0.075), "iron", "BowPivot")
    m.box("crank_handle", (0.55, 2.29, 0.50), (0.08, 0.23, 0.08), "wood_light", "BowPivot")
    m.write()

    m = Model("campfire")
    m.groups["Flames"] = ((0, 0.3, 0), [])
    for i in range(8):
        angle = i * math.tau / 8
        x, z = math.sin(angle) * 0.40, math.cos(angle) * 0.40
        m.box(f"hearth_stone_{i}", (x, 0.12, z), (0.26, 0.23, 0.23), "stone_light" if i % 3 == 0 else "stone", rotation=(0, math.degrees(angle), 0))
    m.box("coals", (0, 0.075, 0), (0.54, 0.15, 0.54), "coal")
    for x in (-0.17, 0.17):
        m.box(f"log_lower_{x}", (x, 0.2, 0), (0.16, 0.16, 0.70), "wood_dark", rotation=(0, 24, 0))
    for z in (-0.13, 0.13):
        m.box(f"log_upper_{z}", (0, 0.30, z), (0.66, 0.16, 0.16), "wood", rotation=(0, 24, 0))
    m.box("ember_bed", (0, 0.27, 0), (0.40, 0.12, 0.36), "ember")
    m.box("flame_base", (0, 0.44, 0), (0.40, 0.30, 0.33), "ember", "Flames")
    m.box("flame_body", (-0.035, 0.65, 0), (0.25, 0.38, 0.23), "flame", "Flames")
    m.box("flame_heart", (0.04, 0.49, 0.04), (0.18, 0.30, 0.19), "hot", "Flames")
    m.box("flame_tip", (-0.06, 0.88, -0.02), (0.12, 0.23, 0.11), "flame", "Flames")
    m.box("flame_side", (0.19, 0.58, -0.03), (0.13, 0.28, 0.13), "flame", "Flames")
    m.write()


    m = Model("workbench")
    for x in (-0.6, 0.6):
        for z in (-0.37, 0.37):
            m.box(f"leg_{x}_{z}", (x, 0.44, z), (0.19, 0.88, 0.19), "wood_dark")
            m.box(f"iron_foot_{x}_{z}", (x, 0.10, z), (0.22, 0.16, 0.22), "iron")
    m.box("shelf", (0, 0.28, 0), (1.42, 0.09, 0.80), "wood")
    for z in (-0.45, 0.45):
        m.box(f"beam_{z}", (0, 0.74, z), (1.52, 0.19, 0.10), "wood")
    for i, x in enumerate((-0.56, -0.28, 0, 0.28, 0.56)):
        m.box(f"tabletop_{i}", (x, 0.91, 0), (0.27, 0.15, 1.05), "wood_light" if i % 2 else "wood")
    m.box("anvil_base", (-0.34, 1.04, 0), (0.51, 0.11, 0.41), "iron_dark")
    m.box("anvil_stem", (-0.34, 1.17, 0), (0.23, 0.18, 0.24), "iron")
    m.box("anvil_top", (-0.34, 1.29, 0), (0.61, 0.12, 0.33), "steel")
    m.box("anvil_horn", (-0.70, 1.28, 0), (0.20, 0.10, 0.19), "steel")
    m.box("hammer_handle", (0.35, 1.02, 0.14), (0.10, 0.075, 0.49), "wood_dark", rotation=(0, 27, 0))
    m.box("hammer_head", (0.44, 1.06, -0.04), (0.28, 0.14, 0.17), "iron")
    for x in (0.10, 0.32, 0.54):
        m.box(f"shelf_iron_{x}", (x, 0.39, 0), (0.17, 0.14, 0.31), "iron")
    m.box("cloth_front", (0.37, 0.67, 0.51), (0.38, 0.46, 0.035), "cloth")
    m.box("cloth_trim", (0.37, 0.47, 0.535), (0.38, 0.055, 0.025), "gold")
    m.write()


def rotate(point: list[float], origin: list[float], angles: list[float]) -> list[float]:
    x, y, z = [v - o for v, o in zip(point, origin)]
    ax, ay, az = [math.radians(a) for a in angles]
    y, z = y * math.cos(ax) - z * math.sin(ax), y * math.sin(ax) + z * math.cos(ax)
    x, z = x * math.cos(ay) + z * math.sin(ay), -x * math.sin(ay) + z * math.cos(ay)
    x, y = x * math.cos(az) - y * math.sin(az), x * math.sin(az) + y * math.cos(az)
    return [x + origin[0], y + origin[1], z + origin[2]]


def export(source: Path) -> None:
    bb = json.loads(source.read_text(encoding="utf-8"))
    scale = 1.0 / bb["cube_siege"]["units_per_metre"]
    palette = bb["cube_siege"]["palette"]
    palette_index = {p[0]: i for i, p in enumerate(palette)}
    elements = {el["uuid"]: el for el in bb["elements"] if el.get("export", True)}
    blob = bytearray()
    gltf = {"asset": {"version": "2.0", "generator": "Cube Siege editable Blockbench exporter"},
            "scene": 0, "scenes": [{"name": bb["name"], "nodes": []}], "nodes": [],
            "meshes": [], "accessors": [], "bufferViews": [], "buffers": [], "materials": []}
    for name, color, metal, rough in palette:
        srgb = [int(color.lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4)]
        # glTF factors are linear; Blockbench palette swatches are sRGB.
        rgba = [v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4 for v in srgb]
        mat = {"name": name, "pbrMetallicRoughness": {"baseColorFactor": rgba + [1],
               "metallicFactor": metal, "roughnessFactor": rough}}
        if name in ("ember", "flame", "hot"):
            mat["emissiveFactor"] = [v * (0.55 if name == "ember" else 0.85) for v in rgba]
        gltf["materials"].append(mat)

    def accessor(values: list, kind: str, bounds: bool = False) -> int:
        offset = len(blob)
        flat = [v for row in values for v in row]
        blob.extend(struct.pack("<" + "f" * len(flat), *flat))
        view = len(gltf["bufferViews"])
        gltf["bufferViews"].append({"buffer": 0, "byteOffset": offset, "byteLength": len(blob) - offset, "target": 34962})
        a = {"bufferView": view, "componentType": 5126, "count": len(values), "type": kind}
        if bounds:
            a["min"] = [min(v[i] for v in values) for i in range(3)]
            a["max"] = [max(v[i] for v in values) for i in range(3)]
        gltf["accessors"].append(a)
        return len(gltf["accessors"]) - 1

    # Counter-clockwise outward triangles, six independent face normals.
    face_indices = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                    (3, 7, 6, 2), (1, 2, 6, 5), (0, 4, 7, 3)]
    face_normals = [(0, 0, -1), (0, 0, 1), (0, -1, 0), (0, 1, 0), (1, 0, 0), (-1, 0, 0)]
    for group in bb["outliner"]:
        batches: dict[int, tuple[list, list]] = {}
        group_origin = group["origin"]
        for child in group["children"]:
            el = elements.get(child)
            if el is None:
                continue
            material = palette_index[el["cube_siege_material"]]
            positions, normals = batches.setdefault(material, ([], []))
            x0, y0, z0 = el["from"]
            x1, y1, z1 = el["to"]
            vertices = [[x0, y0, z0], [x1, y0, z0], [x1, y1, z0], [x0, y1, z0],
                        [x0, y0, z1], [x1, y0, z1], [x1, y1, z1], [x0, y1, z1]]
            rotated = [rotate(v, el["origin"], el["rotation"]) for v in vertices]
            for quad, normal in zip(face_indices, face_normals):
                normal_rotated = rotate(list(normal), [0, 0, 0], el["rotation"])
                for vertex_id in (quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]):
                    positions.append([(c - o) * scale for c, o in zip(rotated[vertex_id], group_origin)])
                    normals.append(normal_rotated)
        primitives = [{"attributes": {"POSITION": accessor(pos, "VEC3", True), "NORMAL": accessor(norm, "VEC3")},
                       "material": material, "mode": 4} for material, (pos, norm) in batches.items()]
        gltf["meshes"].append({"name": group["name"], "primitives": primitives})
        gltf["scenes"][0]["nodes"].append(len(gltf["nodes"]))
        gltf["nodes"].append({"name": group["name"], "mesh": len(gltf["meshes"]) - 1,
                              "translation": [o * scale for o in group_origin]})
    gltf["buffers"].append({"byteLength": len(blob), "uri": "data:application/octet-stream;base64," + base64.b64encode(blob).decode()})
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUTPUT_DIR / (source.stem + ".gltf")).write_text(json.dumps(gltf, separators=(",", ":")) + "\n", encoding="utf-8")
    print(f"Exported {source.stem}: {len(elements)} cubes, {sum(len(m['primitives']) for m in gltf['meshes'])} material batches")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--author", action="store_true", help="Create the original demo source geometry")
    args = parser.parse_args()
    if args.author:
        author_sources()
    for name in NAMES:
        export(SOURCE_DIR / (name + ".bbmodel"))


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
tools/gen_terrain_comparison.py

Генерирует capture comparison для Issue #26:
- Читает production PNG текстуры биомов
- Строит side-by-side сравнение: 5 биомов × before (prototype colors) + after (production PNG)
- Сохраняет в docs/terrain_capture/terrain_comparison.png

Требует только stdlib + Pillow (pip install Pillow).
"""

import os
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TEXTURES_DIR = REPO / "assets" / "environment" / "terrain_materials" / "textures"
OUTPUT_DIR = REPO / "docs" / "terrain_capture"

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("[ERROR] Pillow not installed. Run: pip install Pillow")
    sys.exit(1)

# Prototype colors from the old _create_voxel_texture() (pre-PR state)
PROTOTYPE_COLORS = {
    "Forest":    {"base": (51,  112, 51),  "accent": (38,  92,  38)},
    "Plains":    {"base": (97,  148, 56),  "accent": (217, 209, 89)},
    "Mountain":  {"base": (122, 125, 133), "accent": (89,  92,  97)},
    "Cliff":     {"base": (82,  77,  71),  "accent": (56,  51,  46)},
    "Dirt/Soil": {"base": None,             "accent": None},  # not in prototype
}

PRODUCTION_FILES = {
    "Forest":    "forest_grass_top.png",
    "Plains":    "plains_meadow_top.png",
    "Mountain":  "mountain_stone_top.png",
    "Cliff":     "cliff_side.png",
    "Dirt/Soil": "dirt_soil.png",
}

TILE_SIZE   = 128   # display size per tile (will scale 16x16 up)
LABEL_H     = 28
HEADER_H    = 36
PADDING     = 8
BIOMES      = ["Forest", "Plains", "Mountain", "Cliff", "Dirt/Soil"]
COLS        = 2  # before / after


def make_prototype_tile(biome: str, size: int) -> Image.Image:
    """Render old pattern-generated tile approximation."""
    info = PROTOTYPE_COLORS.get(biome, {})
    base   = info.get("base")
    accent = info.get("accent")

    img = Image.new("RGB", (16, 16), base or (100, 80, 60))
    if base and accent:
        pix = img.load()
        for y in range(16):
            for x in range(16):
                is_border = (x == 0 or x == 15 or y == 0 or y == 15)
                if biome == "Forest":
                    if is_border:
                        r, g, b = [max(0, int(c * 0.88)) for c in base]
                        pix[x, y] = (r, g, b)
                    elif ((x * 7 + y * 13) % 11) == 0:
                        pix[x, y] = accent
                elif biome == "Plains":
                    if is_border:
                        r, g, b = [max(0, int(c * 0.92)) for c in base]
                        pix[x, y] = (r, g, b)
                    elif (x == 4 and y == 5) or (x == 11 and y == 12) or (x == 7 and y == 9):
                        pix[x, y] = accent
                elif biome == "Mountain":
                    if is_border:
                        r, g, b = [max(0, int(c * 0.82)) for c in base]
                        pix[x, y] = (r, g, b)
                    elif ((x + y * 3) % 5) == 0:
                        pix[x, y] = accent
                    elif ((x * 2 + y) % 7) == 0:
                        r, g, b = [min(255, int(c * 1.12)) for c in base]
                        pix[x, y] = (r, g, b)
                elif biome == "Cliff":
                    if (y % 4) == 0:
                        r, g, b = [max(0, int(c * 0.75)) for c in base]
                        pix[x, y] = (r, g, b)
                    elif (y % 4) == 2:
                        pix[x, y] = accent
                    elif is_border:
                        r, g, b = [max(0, int(c * 0.85)) for c in base]
                        pix[x, y] = (r, g, b)

    return img.resize((size, size), Image.NEAREST)


def make_production_tile(biome: str, size: int) -> Image.Image:
    fname = PRODUCTION_FILES.get(biome)
    if not fname:
        img = Image.new("RGB", (size, size), (80, 60, 40))
        return img
    path = TEXTURES_DIR / fname
    img = Image.open(path).convert("RGB")
    return img.resize((size, size), Image.NEAREST)


def make_tiled_view(tile: Image.Image, repeats: int = 4) -> Image.Image:
    """Show tile repeated in a grid for tileability context."""
    w, h = tile.size
    out = Image.new("RGB", (w * repeats, h * repeats))
    for ry in range(repeats):
        for rx in range(repeats):
            out.paste(tile, (rx * w, ry * h))
    return out


def main():
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    tile_display = TILE_SIZE
    repeats = 4
    tiled_size = tile_display * repeats // 2   # 2x2 tiled preview at half tile

    col_w = tiled_size + PADDING * 2
    row_h = tiled_size + LABEL_H + PADDING * 2
    total_w = (col_w * 2) + PADDING * 3 + 120  # +120 for biome label col
    total_h = HEADER_H + row_h * len(BIOMES) + PADDING * 2

    canvas = Image.new("RGB", (total_w, total_h), (30, 30, 30))
    draw = ImageDraw.Draw(canvas)

    try:
        font_large = ImageFont.truetype("arial.ttf", 16)
        font_small = ImageFont.truetype("arial.ttf", 13)
    except Exception:
        font_large = ImageFont.load_default()
        font_small = font_large

    # Header
    draw.text((PADDING, PADDING // 2), "Terrain Material Comparison — Prototype vs Production (seed=1337)", fill=(240, 240, 240), font=font_large)
    draw.text((120 + PADDING + col_w // 2 - 40, HEADER_H - 20), "BEFORE (prototype)", fill=(220, 140, 80), font=font_small)
    draw.text((120 + PADDING * 2 + col_w + col_w // 2 - 40, HEADER_H - 20), "AFTER (production)", fill=(80, 200, 120), font=font_small)

    for i, biome in enumerate(BIOMES):
        y_base = HEADER_H + i * row_h + PADDING

        # Biome label
        draw.text((PADDING, y_base + tiled_size // 2), biome, fill=(220, 220, 220), font=font_large)

        # Before tile (prototype)
        before_tile = make_prototype_tile(biome, tile_display)
        before_tiled = make_tiled_view(before_tile.resize((tile_display // 2, tile_display // 2), Image.NEAREST), repeats=4)
        canvas.paste(before_tiled, (120 + PADDING, y_base + LABEL_H))
        draw.rectangle([120 + PADDING - 1, y_base + LABEL_H - 1,
                         120 + PADDING + tiled_size, y_base + LABEL_H + tiled_size], outline=(180, 120, 60), width=2)

        # After tile (production)
        after_tile = make_production_tile(biome, tile_display)
        after_tiled = make_tiled_view(after_tile.resize((tile_display // 2, tile_display // 2), Image.NEAREST), repeats=4)
        x_after = 120 + PADDING * 2 + col_w
        canvas.paste(after_tiled, (x_after, y_base + LABEL_H))
        draw.rectangle([x_after - 1, y_base + LABEL_H - 1,
                         x_after + tiled_size, y_base + LABEL_H + tiled_size], outline=(60, 180, 100), width=2)

        # Row separator
        draw.line([(0, y_base + row_h), (total_w, y_base + row_h)], fill=(60, 60, 60), width=1)

    out_path = OUTPUT_DIR / "terrain_comparison.png"
    canvas.save(out_path)
    print(f"[OK] Saved: {out_path}")

    # Also save individual production tiles scaled up for reference
    for biome, fname in PRODUCTION_FILES.items():
        tile = make_production_tile(biome, 256)
        tiled = make_tiled_view(tile.resize((64, 64), Image.NEAREST), repeats=6)
        safe_name = biome.lower().replace("/", "_").replace(" ", "_")
        tile_out = OUTPUT_DIR / f"after_{safe_name}.png"
        tiled.save(tile_out)
        print(f"[OK] Tileability: {tile_out}")

    # Before composite
    before_tiles = []
    for biome in BIOMES:
        t = make_prototype_tile(biome, 128)
        before_tiles.append(t)
    before_strip = Image.new("RGB", (128 * len(BIOMES), 128), (30, 30, 30))
    for idx, t in enumerate(before_tiles):
        before_strip.paste(t, (idx * 128, 0))
    before_strip.save(OUTPUT_DIR / "before_prototype_strip.png")
    print(f"[OK] Before strip: {OUTPUT_DIR / 'before_prototype_strip.png'}")


if __name__ == "__main__":
    main()

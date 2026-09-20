#!/usr/bin/env python3
"""
Generates side-by-side Before/After comparison images for Issue #25 Terrain Massing Pass.
"""

from pathlib import Path
from PIL import Image, ImageDraw

REPO_ROOT = Path(__file__).resolve().parent.parent
BEFORE_DIR = REPO_ROOT / "docs" / "screenshots" / "issue_25" / "before"
AFTER_DIR = REPO_ROOT / "docs" / "screenshots" / "issue_25" / "after"
COMP_DIR = REPO_ROOT / "docs" / "screenshots" / "issue_25" / "comparisons"

SCENARIOS = [
    ("01_long_mountain_slope.png", "01_long_mountain_slope_comparison.png", "Long Mountain Slope (Zebra Ladder vs Large Terraced Masses)"),
    ("02_cliff_height_50plus.png", "02_cliff_height_50plus_comparison.png", "Cliff at Height 50+ (Toothpick Stripes vs Grouped Escarpment)"),
    ("03_biome_transition_plains_mountains.png", "03_biome_transition_comparison.png", "Biome Transition Plains -> Mountains (Ledges & Strata)"),
    ("04_forest_hill.png", "04_forest_hill_comparison.png", "Forest Hill (Black Chasm Scars vs Natural Rolling Hillside)"),
    ("05_loaded_chunk_boundary.png", "05_loaded_chunk_boundary_comparison.png", "Loaded Chunk Boundary (Seamless Multi-Biome Border)"),
]

def main():
    COMP_DIR.mkdir(parents=True, exist_ok=True)

    for src_name, dst_name, title in SCENARIOS:
        before_path = BEFORE_DIR / src_name
        after_path = AFTER_DIR / src_name
        if not before_path.exists() or not after_path.exists():
            print(f"Skipping {src_name}, missing files")
            continue

        img_b = Image.open(before_path)
        img_a = Image.open(after_path)

        w, h = img_b.size
        header_h = 50
        comp_img = Image.new("RGB", (w * 2, h + header_h), color=(24, 28, 36))
        draw = ImageDraw.Draw(comp_img)

        # Draw headers
        draw.text((w // 2 - 140, 15), f"BEFORE (Baseline): {title}", fill=(240, 200, 100))
        draw.text((w + w // 2 - 140, 15), f"AFTER (Terrain Massing): {title}", fill=(100, 240, 140))

        # Paste images
        comp_img.paste(img_b, (0, header_h))
        comp_img.paste(img_a, (w, header_h))

        # Save
        out_path = COMP_DIR / dst_name
        comp_img.save(out_path)
        print(f"Generated comparison: {out_path}")

    print("All comparisons generated successfully.")

if __name__ == "__main__":
    main()

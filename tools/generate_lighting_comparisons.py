#!/usr/bin/env python3
"""
Generates side-by-side Before/After comparison images for Issue #24 Lighting Pass.
"""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

REPO_ROOT = Path(__file__).resolve().parent.parent
BEFORE_DIR = REPO_ROOT / "docs" / "screenshots" / "issue_24" / "before"
AFTER_DIR = REPO_ROOT / "docs" / "screenshots" / "issue_24" / "after"
COMP_DIR = REPO_ROOT / "docs" / "screenshots" / "issue_24" / "comparisons"

SCENARIOS = [
    ("01_forest_day.png", "01_forest_day_comparison.png", "Forest Day"),
    ("02_plains_day.png", "02_plains_day_comparison.png", "Plains Day"),
    ("03_mountains_day.png", "03_mountains_day_comparison.png", "Mountains Day"),
    ("04_forest_night.png", "04_forest_night_comparison.png", "Forest Night"),
    ("05_mountains_night.png", "05_mountains_night_comparison.png", "Mountains Night"),
    ("06_composition_hero_enemy_rock_tree.png", "06_composition_comparison.png", "Hero + Enemy + Rock + Tree Composition"),
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
        draw.text((w // 2 - 100, 15), f"BEFORE (Baseline): {title}", fill=(240, 200, 100))
        draw.text((w + w // 2 - 100, 15), f"AFTER (Final Look): {title}", fill=(100, 240, 140))

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

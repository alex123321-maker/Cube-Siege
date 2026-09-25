"""Create deterministic synthetic PNGs used only to test reference placement."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import bpy


COLORS = {
    "front": (0.7, 0.12, 0.12, 1.0),
    "side": (0.12, 0.55, 0.2, 1.0),
    "back": (0.12, 0.25, 0.75, 1.0),
    "three_quarter": (0.65, 0.35, 0.08, 1.0),
}


def args_after_separator() -> list[str]:
    return sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args(args_after_separator())
    args.output_dir.mkdir(parents=True, exist_ok=True)

    width, height = 128, 192
    for name, background in COLORS.items():
        image = bpy.data.images.new(f"synthetic_{name}", width=width, height=height, alpha=True)
        pixels: list[float] = []
        for y in range(height):
            for x in range(width):
                nx = abs((x + 0.5) / width - 0.5)
                ny = (y + 0.5) / height
                silhouette = nx < (0.12 if ny < 0.65 else 0.2) and 0.08 < ny < 0.9
                color = (0.92, 0.92, 0.92, 1.0) if silhouette else background
                pixels.extend(color)
        image.pixels.foreach_set(pixels)
        image.filepath_raw = str((args.output_dir / f"{name}.png").resolve())
        image.file_format = "PNG"
        image.save()
        bpy.data.images.remove(image)
    print(f"Created {len(COLORS)} synthetic references in {args.output_dir.resolve()}")


main()

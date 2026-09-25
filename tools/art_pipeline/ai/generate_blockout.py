#!/usr/bin/env python3
"""Explicit guard for the currently approved Blender-only pipeline configuration."""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--backend", default="blender-only", choices=("blender-only",))
    args = parser.parse_args()
    if not args.input.is_file():
        parser.error(f"Reference image does not exist: {args.input}")
    print("AI generation is disabled for the approved blender-only backend.")
    print("Import the concept sheet with blender/import_reference.py and build the silhouette manually.")
    print(f"No file was written to {args.output}.")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())

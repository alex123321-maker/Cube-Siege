#!/usr/bin/env python3
"""
tools/capture_terrain_comparison.py

Запускает Godot headless с capture_terrain.gd для получения
скриншотов биомов на фиксированном seed=1337.
Сохраняет результаты в docs/terrain_capture/
"""

import subprocess
import sys
import shutil
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GODOT_CANDIDATES = [
    r"D:\ProgramFiles\godot\Godot_v4.6.1-stable_win64_console.exe",
]

def find_godot():
    for c in GODOT_CANDIDATES:
        if Path(c).is_file():
            return c
    # Try .godot_path
    p = REPO / ".godot_path"
    if p.is_file():
        g = p.read_text(encoding="utf-8").strip()
        if Path(g).is_file():
            return g
    return shutil.which("godot")

def main():
    godot = find_godot()
    if not godot:
        print("[ERROR] Godot not found")
        sys.exit(1)

    script = REPO / "tools" / "capture_terrain.gd"
    if not script.is_file():
        print(f"[ERROR] {script} not found")
        sys.exit(1)

    print(f"[INFO] Running: {godot}")
    print(f"[INFO] Script: {script}")

    cmd = [godot, "--headless", "--path", str(REPO), "-s", str(script)]
    proc = subprocess.run(cmd, cwd=str(REPO))
    if proc.returncode != 0:
        print("[ERROR] Capture script failed")
        sys.exit(1)

    print("[OK] Capture complete. Check docs/terrain_capture/")

if __name__ == "__main__":
    main()

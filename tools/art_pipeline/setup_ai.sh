#!/usr/bin/env sh
set -eu

backend="${1:-blender-only}"
if [ "$backend" != "blender-only" ]; then
  echo "Only the reviewed blender-only backend is approved in this revision." >&2
  exit 2
fi

echo "Cube Siege AI backend: blender-only"
echo "No Python environment or checkpoint is installed."
echo "Run: python3 tools/art_pipeline/check_environment.py --format markdown"
echo "Re-evaluate docs/art_pipeline/LICENSES.md before approving a future backend."

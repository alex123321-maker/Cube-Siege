# Cube Siege art pipeline tools

This directory contains the reproducible tooling for an art-directed character workflow. Blender owns the artistic source; Godot consumes GLB. The current workstation uses the fully functional Blender-only path. No AI environment or checkpoint is required.

## One-command verification (Windows)

```powershell
.\tools\art_pipeline\setup_blender.ps1
.\tools\art_pipeline\verify_pipeline.ps1
```

Override discovery when tools live elsewhere:

```powershell
$env:BLENDER_BIN = 'D:\Tools\Blender\blender.exe'
$env:GODOT_BIN = 'D:\Tools\Godot\godot_console.exe'
.\tools\art_pipeline\verify_pipeline.ps1
```

The verification creates synthetic concept images under ignored `art/work/`, builds a non-production calibration blockout, renders five review angles, exports GLB, forces a Godot headless import, and validates scale, orientation, materials, skeleton, and animation names.

## Scripts

- `check_environment.py`: dependency-free hardware/tool report.
- `setup_blender.ps1`: pinned Blender 5.2.1 LTS portable install with SHA-256 verification.
- `setup_ai.ps1` / `setup_ai.sh`: reproducible no-op for the approved Blender-only backend.
- `blender/import_reference.py`: locked front/side/back/3-quarter reference planes.
- `blender/render_turnaround.py`: five neutral studio review renders.
- `godot/review_warrior.gd`: imported-runtime studio review and a controlled gameplay arena using the actual player/controller/camera; emits pose PNGs and asserted playback telemetry. Record with Godot `--write-movie`, then encode with FFmpeg. Reproduction commands are in `docs/art_pipeline/verification/warrior/README.md`.
- `blender/export_gltf.py`: strict `EXPORT` collection to GLB.
- `godot/validate_character_import.gd`: validates a production character's rig hooks, animation set, loops, and preserved timings.
- `godot/validate_import.gd`: Godot-side import contract check.
- `verify_pipeline.ps1`: end-to-end orchestration and evidence generation.

Production policy and commands live in `docs/art_pipeline/WORKFLOW.md`.

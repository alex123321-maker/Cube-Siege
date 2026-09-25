# Art-directed character pipeline

Cube Siege now has a local, free, reproducible path for future character work:

`approved concept sheet -> optional AI blockout -> Blender art direction and cleanup -> GLB 2.0 -> Godot validation`

On the verified workstation the optional AI stage is disabled, so the working path is:

`approved concept sheet -> manual Blender silhouette blockout -> cleanup -> GLB 2.0 -> Godot validation`

This setup does not create or redesign a hero and does not change gameplay, balance, rigs, animation timing, or runtime code. The committed `calibration_blockout` is a deliberately simple two-metre test object, not production character art.

## Decision

- DCC: Blender 5.2.1 LTS, built-in tools only.
- Runtime: the project's existing Godot 4.6.1 stable.
- Interchange: GLB / glTF 2.0.
- AI: Blender-only fallback because the workstation has Intel Arc integrated graphics and no NVIDIA/CUDA runtime.
- Add-ons: none required.
- Source ownership: final hero form must live in an art-directed `.blend`, not in `scripts/generate_all_models.py`.

## Start here

1. Read `HARDWARE.md` and run `python tools/art_pipeline/check_environment.py --format markdown`.
2. Install/validate Blender with `tools/art_pipeline/setup_blender.ps1`.
3. Follow `WORKFLOW.md` for references, review gates, export, and Godot checks.
4. Run `.\tools\art_pipeline\verify_pipeline.ps1` to reproduce the test evidence.
5. Consult `LICENSES.md` before enabling any AI backend and `TROUBLESHOOTING.md` when a step fails.

The end-to-end evidence is under `docs/art_pipeline/verification/`.

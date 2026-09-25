# Warrior / Issue #8 — repaired candidate

Built against [Issue #8](https://github.com/alex123321-maker/Cube-Siege/issues/8) and the supplied concept. This is an implemented, reviewable candidate, **not a declaration of final art approval or closure of the issue**.

## Result and corrections

- Editable source: `art/characters/warrior/hero_warrior.blend`; packed runtime texture and concept reference.
- Runtime: `assets/models/characters/hero_warrior.glb` and the original-UID `hero_warrior.tscn` wrapper. See `export_report.json` for actual export size, 74 mesh objects, eight materials and seven exported clips.
- Rest feet at ground zero, approximately 2 m height. Raw GLB faces +Z; the wrapper faces the actual player's -Z attack direction, without a scale correction.
- Restored the original rigid node hierarchy. Visible weapon meshes belong to the real sword/shield hooks, not an unrelated skeleton with empty compatibility nodes.
- Rebuilt sword grip/guard/blade ordering. Reassigned UVs to individual material panels rather than collage quadrants. Packed image path now refers to the actual runtime atlas.
- Export retains constant NLA object channels; without this, idle arm angles silently vanished while moving clips appeared correct.
- Shield board moved ahead of the forearm and centered on the fist. Added a rear cross-grip, two brackets and mounts. Close-ups show the hand behind the board, not intersecting it. A regression test checks hand/forearm clearance in five sampled poses of every clip, not merely attachment NodePaths.
- Gameplay code, damage rules and ability cooldowns were not changed.

## Animation contract

| Action | Runtime name | Duration | Loop |
| --- | --- | ---: | --- |
| Idle | `idle` | 1.20 s | yes |
| Run | `walk` | 0.80 s | yes |
| LMB | `attack` | 0.35 s | no |
| RMB | `special` | 0.50 s | no |
| Q | `utility` / `block` | 0.50 s | no |
| F | `ultimate` | 0.80 s | no |

Damage begins at **0.06 s for LMB** and **0.15 s for RMB** in `scripts/player/player_combat.gd`; exported blade poses reach forward at those times. The previous report confused the 0.16 s slash lifetime with windup. Tests cover contact direction/height, idle restoration, hand/grip attachment, knee articulation and a continuous in-place run loop.

## Evidence

- [Studio movie](warrior_studio.mp4): 1280×720, H.264, 30 FPS, 10 s. Imported Godot animations, Idle → Run → LMB → RMB → Q → F.
- [Gameplay movie](warrior_gameplay.mp4): same format and sequence, using the real player/controller/abilities/HUD/follow camera. Run is triggered by movement input; abilities use the player's normal entry points, not manual animation playback. Telemetry asserts the expected animations, movement speed 7 m/s and an acquired F duel target.
- `studio/`: front, side, back, three-quarter angles, sampled action poses, labeled before/after and **shield_grip_idle/run/block** close-ups. These are engine captures, not AI-generated previews.
- `gameplay/`: idle/run/crowd screenshots and `playback.json`; `studio/playback.json` records studio playback separately.
- `studio/before_after.png`: repository HEAD on the left, current candidate on the right, same camera and lighting. This compares the original repository asset, not the previous agent's intermediate export.

The gameplay review is a **controlled arena based on main.tscn**: procedural MapGenerator and initial roaming enemies are removed from the disposable review instance. Actual player, floor, lighting, HUD, portal and camera remain. Crowd uses 12 stationary, harmless dummy enemies for a repeatable silhouette check. This is not a claim of successful full-wave playtesting on the procedural map. No permanent map/gameplay edits were made.

## Verification and limitations

- GUT: **76/76 tests, 593 assertions**, including the shield regression that failed before the fix. Full output: `gut.log`.
- Imported-character contract: PASS, `import_report.json`.
- Complete `python tools/verify.py` audit: `verify.log` (compiler/build, import, GUT, Python tests, 100-frame runtime).
- Studio and controlled gameplay recordings completed without runtime errors or assertion failures.
- Existing test teardown warnings (unfreed children/ObjectDB/resource cleanup) remain visible in `gut.log`. The editor also reports resource cleanup at exit; passing exit codes are not a claim of zero warnings.
- A first run against the normal user profile failed tests that assume Warrior because the profile selected Engineer. Final tests use an isolated APPDATA directory; no user save was deleted to obtain a passing result.
- The exploratory procedural-map recording encountered enemy death scale-to-zero/inverse-transform errors in existing `enemy_base.gd`, outside the changed art pipeline. This task does not fix or certify that unrelated gameplay path.
- Visual matching, blend transitions and all possible collision/occlusion cases still require art/play review. The sampled clearance regression is not exhaustive collision detection.

## Texture uniqueness

Source: `art/textures/characters/warrior_material_atlas_source.png`.
Runtime: `assets/models/textures/warrior/hero_warrior_material_atlas.png`.

The source atlas was image-generated in the preceding work; this pass revised UV selection and materials rather than regenerating the bitmap. `asset_hashes.json` records current source/export/texture hashes. Warrior's runtime atlas differs from the Archer/Engineer atlases. The GLB embeds the runtime image; orphan extracted PNG siblings were moved out of runtime assets.

## Reproduce

From the repository root, set `BLENDER_BIN` and `GODOT_BIN` to the installed executables. See `art/characters/warrior/README.md` for Blender export commands.

```powershell
& $env:GODOT_BIN --headless --editor --path . --import --quit
& $env:GODOT_BIN --headless --path . --script res://tools/art_pipeline/godot/validate_character_import.gd -- --asset res://assets/models/characters/hero_warrior.tscn

# Preserve GitHub CLI discovery while isolating game saves for verification.
$env:GH_CONFIG_DIR = Join-Path $env:APPDATA 'GitHub CLI'
$env:APPDATA = Join-Path (Get-Location) 'art/work/issue-8/review-profile'
python tools/verify.py

& $env:GODOT_BIN --path . --resolution 1280x720 --fixed-fps 30 --write-movie art/work/issue-8/studio.avi --script res://tools/art_pipeline/godot/review_warrior.gd -- --mode studio --output res://art/work/issue-8/studio
& $env:GODOT_BIN --path . --resolution 1280x720 --fixed-fps 30 --write-movie art/work/issue-8/gameplay.avi --script res://tools/art_pipeline/godot/review_warrior.gd -- --mode gameplay --output res://art/work/issue-8/gameplay
ffmpeg -i art/work/issue-8/studio.avi -an -c:v libx264 -crf 20 -pix_fmt yuv420p -movflags +faststart art/work/issue-8/studio.mp4
```

Before/after is optional: pass `--before res://path/to/HEAD_snapshot.tscn` to studio mode. The saved proof used an ignored snapshot from `git show HEAD:assets/models/characters/hero_warrior.tscn`. The delivered videos trim setup frames; freshly recorded AVI includes setup.

## Cleanup

Superseded captures/report/video and duplicate extracted textures were moved to ignored `art/work/issue-8/superseded-evidence` and `superseded-texture-copies` (recoverable). The obsolete armature-only movie helper was replaced by runtime `review_warrior.gd`. Unrelated calibration pipeline files were preserved. Evidence is excluded from Godot asset scanning through `verification/.gdignore`.

# Warrior sword VFX pilot — 2026-09-29

## Scope and reproduction

Baseline revision: `ab1cc4d6f3314bb177d0dad8d0957b97409924c3`.
Working branch: `codex/vfx-slash-pilot`.

The normal warrior attack has a painted two-layer ribbon, a moving reveal, edge erosion, tapered fragments, and a textured contact accent. Gameplay numbers and attack timing are unchanged. Cleave, the engineer, and the archer retain their existing presentation.

Both recordings instantiate the production main scene and invoke `Player.perform_attack()`. Seed: 1337. Renderer: Forward+, Godot 4.6.1, Intel Arc. Render resolution: 1280×720, fixed simulation/render step: 60 FPS. The review harness stops AI and player input, hides HUD, keeps targets alive, and advances the real player animation. The four views are:

1. Detail view at 40% of the medium camera offset.
2. Medium game-camera distance during daytime.
3. Same game-camera distance with the production night lighting state.
4. Night view with 25 stationary targets, one repeatedly struck target.

The crowd view checks occlusion/readability with one active player attack. It does not demonstrate many concurrent attacks or a full combat performance benchmark. Movie Writer timings include capture overhead and are not used to claim a performance improvement.

Run from this checkout, with an isolated test save profile:

```powershell
$env:CUBE_SIEGE_TEST_PROFILE = 'user://test_profile/vfx_slash_pilot/'
& 'D:\ProgramFiles\godot\Godot_v4.6.1-stable_win64_console.exe' --path . --script res://tools/capture_slash_pilot.gd --fixed-fps 60 --resolution 1280x720 --write-movie docs/verification/vfx_slash_pilot/after.avi -- --label=after
```

The `before` recording was made before changing the production VFX code. Recreating it requires the baseline revision plus the same capture harness; relabeling a current render is explicitly rejected.

## Verification

- Existing GUT suite: 274 tests passed, 9,261 assertions. Its existing teardown/resource warnings remain; this is not a claim of a warning-free repository.
- Added focused tests: 2 passed, 7 assertions. They check 40 effect instances settling back to the original count, no contact effect on a miss, actual target positioning, and the unchanged 25 damage.
- Final targeted rerun after the last visual adjustment: 13/13 tests passed, 77 assertions (the new tests plus the existing VFX/abilities suite).
- Captures: 12 real attacks reduced the target from 10,000 to 9,700 HP. Active effect count returned to zero after settling.
- Import: no script parse errors, failed asset loads, or shader errors. Editor plugin shutdown reports 10 retained resources, also observed in the initial import before the changes.
- Final rendered run: no runtime/script/shader errors. An existing SpatialMaterial `specular` remapping warning is present.
- The native library was copied from the main checkout. No C++ files were changed or rebuilt. This was not a run of the full `tools/verify.py` audit.

## Visual assessment and next test

The selected rendered frames show a sharper silhouette and separated strands instead of the baseline translucent band. The bright daylight terrain and the existing whole-target white flash compete with the new contact accent; small texture details merge at the regular game-camera distance. Night contrast is stronger. These are limits to review, not automatic artistic acceptance.

This pilot establishes a reusable candidate and a repeatable comparison. It does not establish that a smaller model can independently match the desired art quality. After choosing an artistic target, that should be evaluated in a separate parameter-only task with the renderer and profile held fixed.

Texture generation method and full prompt: `assets/vfx/sword/README.md`.

## Delivered recordings

- `slash-comparison.mp4`: first 3 seconds show the baseline detail view; the next 12 seconds show the candidate in all four views, at normal speed.
- `slash-slow-motion.mp4`: one candidate swing at quarter speed, for inspecting shape and disappearance.
- `before_0_023.png` and `after_0_027.png`: selected detail frames. The other timestamped PNGs preserve the inspected sequence.

The raw Movie Writer AVI files were intermediate outputs. The compressed recordings and original PNG captures are retained.

# PR #41: sole contact and dash transition fixes

This revision addresses review comments 4110924758 and 4110924762 on `4681332802840daac795f57faac14ca1e9bd4735`. Its recordings supersede the parent bundle's original locomotion/foot-plant recordings. Character meshes, textures, Blender sources and weapon grip are unchanged; their original studio/reference views still apply.

## Fixes

- Contact is computed from the actual exported boot vertices, cached when a profile binds. All rigid boot pieces rotate together around a virtual ankle so the visible sole stays level; the two leg segments retain their lengths. Profiles enumerate the boot parts under each knee. No helper nodes or mesh deformation are introduced.
- Dash entry/exit smoothly blends planting, crouch and stride. Anchors follow body travel during release, and joint poses are filtered during the transition to avoid abrupt knee extension near the chain's reach limit. Gameplay dash speed, duration, input and collision motion are unchanged.
- Disabling the layer or switching class restores the original boot transforms.

## Reproduction and measured results

`tests/integration/test_foot_contact_geometry.gd` loads the real runtime models and independently enumerates their boot meshes. The same tests were run against the reviewed production scripts before the fix: two failures, one pass (`logs/review-regressions-before.log`). With the fix all three tests / 1,220 assertions pass (`logs/review-regressions-after.log`).

| Check | Reviewed revision | Fixed revision |
| --- | --- | --- |
| Lowest real boot vertex across full gait cycles | -0.199545 m | about -0.000001 m (floating-point tolerance) |
| Largest additional root correction change at dash transition, 60 Hz | 0.140000 m | 0.021493 m, blended over frames |
| Largest adjacent right-knee rotation change in dash cases | 1.621159 rad | 0.231628 rad |

Sole coverage: all three classes, forward/back/left/right, 3 and 7 m/s, both boots, 240 samples per case at 120 Hz, at least two full cycles (24 cases). Maximum stance clearance is 0.017895 m for Engineer forward at 7 m/s near maximum reach; the other cases are within numerical tolerance. Dash coverage: all three classes at four starting gait phases, actual `PlayerPresentation` and `CharacterBody3D` real velocity, production dash speed/duration, 80 samples per case at 60 Hz. Tests also assert that presentation leaves gameplay velocity unchanged.

Existing presentation tests pass: 15 tests / 410 assertions (`logs/review-presentation.log`). Full `python tools/verify.py` passes, including native build, editor import, GUT, Python tooling, Issue #18 and runtime smoke (`logs/review-verify-final.log`). The first full run had a timing-ratio failure in the unrelated Issue #18 world-performance check; its log is retained as `logs/review-verify.log`. The complete rerun passed without world-code changes.

## Actual runtime evidence

- `videos/{hero}-soles.mp4`: low camera; left is gait with planting disabled, right is the fixed production planting. This is an OFF/ON comparison, not footage of the buggy reviewed implementation.
- `videos/{hero}-motion.mp4`: full-body production presentation OFF/ON, directional movement, actions, dash, voxel transitions and gameplay-distance view.
- `{hero}-{soles,motion}/frame_0420.png` and `frame_0600.png`: directional movement.
- `frame_1560.png` through `frame_1580.png`: immediately before dash, during dash and after release. Dash starts at physics tick 1561. PNG captures occur after rendering, at 30 fps; the regression measurements above sample 60 Hz.
- `frame_1820.png`: voxel transition; `frame_2050.png`: distant view in the motion capture.
- `manifest.json`: SHA-256 of changed source files and media. Published GitHub attachments identify the full commit SHA.

Each movie is about 35 seconds at 1280x720/30 fps. Capture logs have no script/runtime errors; Godot reports low remaining disk space, but every movie completes with 1,061 frames. Artist acceptance remains independent of these numeric tests. This is flat-floor sole alignment using body floor height, not per-foot terrain raycasting or slope alignment; voxel transitions remain a documented limitation.

```powershell
godot --headless --path . --script addons/gut/gut_cmdln.gd -gtest=res://tests/integration/test_foot_contact_geometry.gd -gexit
godot --path . --resolution 1280x720 --fixed-fps 30 --write-movie art/work/hero-polish/review-r1-warrior-soles.avi --script res://tools/review_character_animation.gd -- --class 0 --plant --sole-level --frames 1060 --output res://art/work/hero-polish/review-r1-warrior-soles
python tools/verify.py
```

Use class 0/1/2 for Warrior/Archer/Engineer. Omit `--plant --sole-level` for full-body motion comparison.

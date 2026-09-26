# Hero models and animation review — #8, #9, #10, #12

All character pictures here are actual Blender or Godot renders. The user reference remains under `art/references/issue-9/`; it is not passed off as an exported model. Source `.blend` files are in `art/characters/{warrior,archer,engineer}`. The neighboring `game_assets` project's Blender → GLB workflow and class-family review conventions informed this work.

## Changes

- Warrior: a closed right fist, opposing thumb and physical sword socket; a forward low guard; preserved sword/shield hooks, existing armour and animation clocks.
- Archer: the supplied blonde elf reference replaces the rejected hood prototype. Angular emerald eyes with lashes and highlights, shaped hair/ears, scarf/cape, fitted leather, bow/quiver, articulated draw/release.
- Engineer: stocky workwear, goggles, apron, large pack, rigid elbows/knees and hand-attached wrench-hammer; individual material atlas.
- Common locomotion: authored forward-run knee keys no longer leak into a procedural stance. A cached two-segment visual solve holds stance endpoints in world space while the body travels. Class profiles provide leg lengths, stride, crouch and swing height. Gameplay velocity, facing and event timing are unchanged.

## Inspect

- `warrior-studio/sword_grip_*.png`: grip at idle, run, attack, special, block and ultimate.
- `archer-blender/face.png`, `three_quarter.png`: actual source model and latest eye revision.
- `{hero}-studio/`: turnarounds, action keyframes; Archer draw/release and Engineer .14/.15/.16 deployment samples.
- `{hero}-gameplay/`: real `main.tscn` player, camera, lighting and HUD, plus crowd. The disposable review removes map generation/roaming enemies for a controlled arena.
- `family/`: three heroes at the same scale/camera and a silhouette pass. Bounds report confirms the feet are around floor Y=0; studio shadow softness is not a model-origin offset.
- `videos/{hero}-gameplay.mp4`: Idle → Run → LMB → RMB → Q → F.
- `videos/{hero}-locomotion.mp4`: procedural OFF/ON, directional motion, aim/turns, moving actions, dash and voxel steps.
- `videos/foot-plant-{0,1,2}.mp4`: close-foot comparison, existing directional gait on the left and world stance solve on the right (Warrior/Archer/Engineer).

Before/after Archer and Engineer use the original HEAD scenes and the same review camera. Warrior's pre-grip front capture is preserved separately. Original pre-polish Warrior comparison remains in `../warrior/`.

## Verification and limits

`logs/verify-final.log`: complete `python tools/verify.py`, including native build, editor import, GUT and runtime checks. `logs/sword-grip-before.log` demonstrates the new grip regression failing on the previous mesh; `logs/sword-grip-after.log` records 234 passing tests. `logs/stance-final.log` records 15 passing presentation tests / 410 assertions, including forward/back/left/right stance for all three classes. Source/export hashes are in `manifest.json`.

The new stance solve uses the body's current floor height. It does **not** raycast each foot or align an ankle to a slope. It reduces flat-ground sliding; full terrain IK is not claimed. The older ray/lift prototype and evaluation remain under `docs/animation/issue12/`. The visual acceptance of fast strafe and voxel transitions must be assessed from the recordings; a passing endpoint test is not proof of artistic quality. #12's outstanding visual criterion is not silently marked complete.

`*-locomotion/report.json` contains paired presentation update timings from the captured review; these are debug-build samples recorded alongside rendering, not a production FPS guarantee. The full GUT run has existing shutdown ObjectDB/resource warnings; focused stance tests exit cleanly. Review scene script errors found during authoring were fixed before the final captures.

## Reproduce

```powershell
godot --headless --editor --path . --import --quit
godot --path . --resolution 1280x720 --script res://tools/art_pipeline/godot/review_heroes.gd -- --hero archer --mode studio --output res://art/work/hero-polish/archer-studio
godot --path . --resolution 1280x720 --write-movie art/work/hero-polish/archer-gameplay.avi --script res://tools/art_pipeline/godot/review_heroes.gd -- --hero archer --mode gameplay --output res://art/work/hero-polish/archer-gameplay
godot --path . --resolution 1280x720 --write-movie art/work/hero-polish/archer-locomotion.avi --script res://tools/review_character_animation.gd -- --class 1 --frames 1060 --output res://art/work/hero-polish/archer-locomotion
godot --path . --script res://tools/art_pipeline/godot/review_hero_family.gd
python tools/verify.py
```

Use class 0/1/2 for Warrior/Archer/Engineer; add `--plant --close-feet` for the foot comparison. Blender source READMEs document authoring, texture provenance and export commands. Final visual approval and issue closure are not inferred from local test success.

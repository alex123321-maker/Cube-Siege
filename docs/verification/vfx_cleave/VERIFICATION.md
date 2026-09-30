# Warrior cleave verification — 2026-09-30

Base revision: `722bac40e1f4ba8f4619501dcc579a7d290ed1f1`.
Godot 4.6.1, Windows, Forward+, Intel Arc Graphics. Art direction delegated
explicitly by the user: expressive VFX suitable for the existing voxel game,
with Dota 2 and Minecraft Dungeons as aesthetic inspirations.

## Results

- Build and headless import: PASS.
- GUT: **296/296 PASS**, including six new cleave integration checks.
- Python: **135/135 PASS**.
- Menu smoke: PASS; gameplay smoke: **24/24 PASS** (run separately after the
  full audit stopped at its world performance gate).
- Production-world recording: PASS. Five real special attacks, 17 confirmed
  target contacts, original live mastery-scaled damage, untouched target behind
  the player, zero active effects, zero camera offsets and zero settled blade
  trail surfaces. AI and player movement are frozen for this deterministic
  capture; the combat entry point and animation/presentation are production code.
- Reviewed actual PNGs for windup, release, erosion, day/night, game camera,
  crowd and side view. `cleave_preview.gif` and `cleave_showcase.mp4` are encoded
  from the unmodified Godot Movie Writer recording. The MP4 includes sound.

## Full audit limitation

`python tools/verify.py` is **not fully green**. Its world-generation performance
gate requires average streaming transitions below 250 ms. The final audit
measured 357.76 ms; an isolated repeat measured 317.27 ms, with all other 25
world checks passing. A clean managed worktree at the base revision, without
this change, also failed the same gate at **309.85 ms**, with 25/26 passing.
Thus the failure reproduces without the new cleave. The initial baseline full
audit had passed earlier in the session; performance is sensitive to the current
machine conditions. No terrain logic or acceptance thresholds were changed.

Both base and changed versions report the existing editor shutdown resource
warnings and the legacy `SpatialMaterial/specular` warning. The six cleave
tests and production capture have no new script errors or effect leaks.

Logs: `baseline_audit.log`, `final_audit.log`, `terrain_recheck.log`,
`baseline_terrain.log`, `cleave_tests.log`, `capture.log`.

## Reproduction

```powershell
python tools/verify.py
godot --headless --path . -s addons/gut/gut_cmdln.gd -gselect=test_cleave_vfx.gd -gexit
godot --path . --fixed-fps 60 --write-movie screenshots_debug/cleave.avi -s tools/capture_cleave.gd
```

`sovereign_0_000.png` is the resting frame, `009` is windup, `018` release,
`025` follow-through, `033` erosion and `065` settled. Other PNGs show the normal
day camera, normal night camera, night crowd and the opposite side of the arc.
No source reference image was supplied; the existing warrior, sword and world
are the in-game visual context. Geometry, shader and synthesized audio are
original assets; no raster image generator or mentor bridge was called.

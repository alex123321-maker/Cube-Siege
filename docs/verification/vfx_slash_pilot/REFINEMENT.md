# Sword VFX — contact refinement, 2026-09-29

This pass continues the ribbon direction that received positive user feedback. Its main change is a readable contact: a painted asymmetric warm burst, a short local light, and tapered fragments that spread, slow, darken, and disappear. The cool ribbon retains the first pass's shape and timing.

The old opaque white hit material hid the enemy. `HurtboxArea` now overlays a translucent warm highlight and restores the previous overlay after the last hit. It leaves the base material intact. This shared visual adjustment affects all hurtbox users, including hits from other classes.

## Contact timing correction

The first render of this refinement exposed missing contact VFX despite real damage. The previous implementation inspected hit results once, before some physics overlaps arrived. A regression test reproduced 25 damage with zero contact effects when a target entered the active swing after that query.

`HitboxArea` now emits a confirmed-hit signal after its existing damage call. The sword presentation listens to that signal, emits at most three contacts per swing, and does not duplicate contacts through the initial overlap query. Damage, hitbox dimensions, cooldowns, active windows, and animation clocks are unchanged.

`late-contact-before.log` records the failing test; `late-contact-after.log` records the passing fix. The earlier report's first-pass recording did not verify contact counts and should not be taken as proof that every hit created a contact effect.

## Render evidence

The same production world, seed, camera positions, lighting, and real `perform_attack()` path are used. The final Forward+ run recorded **12 hits, 12 contact effects, 300 damage, and zero remaining active effects**. The harness now fails if the twelve expected contacts are missing. See `refined-render.log`.

- `slash-refinement-comparison.mp4`: 3 seconds of the previously approved ribbon prototype, then 12 seconds of this refinement in detail/day/game camera/night/crowd views. Normal speed, 1280×720 at 60 FPS. The first segment is taken from the preserved prior recording, not a relabeled new render.
- `slash-refined-slow.mp4`: one refined swing at quarter speed.
- `refined_*.png`: original Godot frame captures. Inspected contact peak, decay, daytime camera, night, and crowd frames.

The burst is visible at the regular camera distance and the target retains its material. Fine painted texture still merges at that distance; silhouette, warm/cool separation, and timing carry most of the effect. The fixed-direction wide ribbon is still an exaggerated attack shape, not a trail sampled from the animated sword tip. Precise blade tracking remains a separate refinement.

The crowd scene has 25 stationary targets and one active attack. It is not a benchmark for many simultaneous attackers. Surface placement uses a small directional/camera offset from the real struck target, not a raycast-derived surface normal. Depth testing remains enabled.

## Validation

- Final full GUT suite: **279/279 tests passed, 9,276 assertions**, 46 scripts. Existing teardown warnings remain (13 warnings and one retained resource at shutdown); this is not a warning-free audit. See `refined-tests-final.log`.
- New highlight tests cover rapid retriggering, base material preservation, previous overlay restoration, and removal of the hurtbox while its visual mesh survives.
- Sword tests cover effect cleanup, misses, actual target positions, unchanged damage, and targets entering an active swing late.
- Final render completed without script or shader errors. Existing `specular` remapping and low disk-space warnings are recorded; capture completed successfully.
- Final import succeeded after texture import, with the previously observed ten-resource editor shutdown warning. The first import briefly reported the not-yet-imported new PNG; the subsequent import resolved it.
- `tools/verify.py` was attempted and stopped at the missing `godot-cpp/SConstruct` submodule in this isolated worktree. **The full native/build audit did not pass.** No C++ code was changed; the existing debug library copied from the main checkout was used for tests and renders. See `polish-full-audit.log`.

Each Godot import/test/capture subprocess used an actual bounded timeout (180/300/240 seconds). Encoding used a 90-second deadline per job. The full audit had its own phase timeouts and an outer 900-second process-tree deadline; it exited at the submodule check.

## Reusable art inputs

Generated with the built-in image tool: `assets/vfx/sword/sword_contact.png`, RGBA, 1254×1254. Copied without raster edits. Both texture prompts and provenance are saved in `assets/vfx/sword/README.md`. Contact size and lifetime join the existing profile controls in `steel_slash.tres`.

This pass was authored by the current assistant. It establishes a stronger reference asset and a rendered check, not yet proof of reproduction by a smaller model.

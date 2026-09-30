# Godot implementation notes

Read this reference only for Godot work. Follow the active repository's scene, GDScript, verification, and operation-timeout rules. Inspect the existing effect lifecycle and rendering backend before choosing nodes or shaders. Use documentation matching the installed engine version when API details matter.

## Attachment and timing

Locate the real weapon attachment, animated skeleton or pivot, and the ability's authoritative events. Decide explicitly which components remain weapon-local and which detach into world space. Sample or drive a trail from the blade's actual transforms when it should describe the swing; avoid an unrelated motion tween that merely starts at the same time.

Use an existing animation/event clock for coordinated presentation where possible. Keep damage authority in the gameplay system, with hit feedback consuming confirmed results. Inspect interruption, animation speed changes, rotation, movement, and multiple instances. The [AnimationTree documentation](https://docs.godotengine.org/en/stable/tutorials/animation/animation_tree.html) explains its relationship to AnimationPlayer and warns that animation node resources can be shared: use per-instance parameters appropriately rather than accidentally changing all actors.

## Materials, particles, and lifecycle

Use mesh/trail, particle, decal, or other representations according to the desired spatial behavior and budget. The shader breakdown in the art reference is one option. Shape, timing, and useful parameters matter more than reproducing its node graph. Inspect transparency sorting, depth interaction, culling, emission under the actual tonemapper, and reduced bloom. Keep per-instance effect animation independent when materials are shared.

For [GPUParticles3D](https://docs.godotengine.org/en/stable/classes/class_gpuparticles3d.html), evaluate local/world coordinates, one-shot restart behavior, visibility bounds, draw passes, and fixed simulation rate in the installed version. Seeded runs can support repeatable comparison. Bounds must cover the effect without needlessly keeping it visible; test camera rotation and terrain. Disable or release inactive emitters and meshes according to their lifecycle, including interrupted casts. Confirm that particles, audio, and temporary lights clean up after repetition and scene exit.

Expose the small set of controls needed for art iteration: geometric reach, phase progression, width/length, value, breakup, particle direction, and dissipation where applicable. Share gameplay geometry with presentation when appropriate; do not silently enlarge damage to match a decorative mesh. Avoid coupling a new global exposure, bloom, time-scale, or camera setting to one effect when a local treatment meets the brief. If the user authorizes a wider change, validate its effect on the rest of the game.

## Verification

Use the project's bounded import/script checks and targeted runtime validation. Render with the actual supported backend; headless success alone cannot establish the appearance of particles, glow, shader output, or camera feel. Record using the real ability/animation integration, not a detached reconstruction that bypasses the code under review. Keep diagnostic overlays separate from representative captures. Follow the art reference's recording coverage and performance distinction; use tests for lifecycle, geometry, or event behavior when they can catch meaningful regressions.

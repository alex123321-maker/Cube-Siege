# Archer basic-arrow impact kit

The reference [arrow_impact.tres](arrow_impact.tres) supplies a short directional contact for the player's ordinary arrow. Existing shot windup, cooldown, flight, collision, damage, tower arrows and piercing-arrow presentation retain their behavior.

Composition: a compact painted contact and dark edge for 0.16 s, nine faceted rebound shards for 0.32 s, and a translucent dust tuft fading by 0.34 s. The contact rotates with the incoming direction projected into the camera plane; shards travel back from the struck surface in world space. Scene depth remains enabled. Terrain contacts use a quieter neutral color and start at the projectile's last reachable position. Misses create no contact.

Each root owns a delta-based visual clock and cleanup. Shards share one MultiMesh; there are no physics fragments, lights or per-particle nodes. Visual randomness uses a local RNG and does not consume the gameplay random sequence. Twelve overlapping effects were checked for complete cleanup; this is not a mass-battle performance benchmark.

## Existing art provenance

The kit reuses the unmodified generated [sword contact](../sword/sword_contact.png) and [smoke puff](../mine/smoke_puff.png). Their prompts and provenance remain in the [sword README](../sword/README.md) and [mine README](../mine/README.md). No new raster generation or retouching was performed. Shape, orientation, shading and timing differ from the sword/mine effects.

## Bounded small-model assignment

Create a sibling `.tres` based on `arrow_impact.tres`. Keep its script and both texture references. Edit only exported art parameters from `scripts/vfx/arrow_impact_profile.gd`, inside their declared ranges. Do not edit gameplay, runtime code, shaders, source textures or the default resource. Target a precise perceptual change, for example: a harder initial impact with a shorter, less distracting tail under rapid fire. Preserve a physical arrow's warm neutral palette and directional rebound. Supply the exact values changed and the intended tradeoff.

Render the candidate with the real basic attack in daylight, at night, in a crowd and from a second shooting direction. Inspect the first contact, 2/5/9/15/24 frames afterward and the normal-speed sequence. The target must remain readable; a miss must not create an impact. Record parent corrections separately. No small-model trial was run for this archer iteration; this kit is the prepared input for one.

Capture: `tools/capture_archer_pilot.gd` with `--fixed-fps 60 --write-movie <output.avi> -- --label=<name> --profile=res://assets/vfx/archer/<candidate>.tres`. Use `--surface-check` for actual terrain collisions and misses. Set an isolated `CUBE_SIEGE_TEST_PROFILE`. For a real before recording, use the saved baseline implementation; the label alone must not simulate a baseline.

## Known existing gameplay defect

The original arrow's `HitboxArea` listener and its projectile listener both apply damage. The recorded basic attack therefore produces two 25-damage events per hit. This predates the VFX work and remains unchanged here; it must not be treated as intended balance. The capture's 36 damage events / 9100 remaining HP for 18 shots preserve that observed baseline only. A future gameplay fix must update those capture assertions.

See [verification and videos](../../../docs/verification/vfx_archer_pilot/REPORT.md).

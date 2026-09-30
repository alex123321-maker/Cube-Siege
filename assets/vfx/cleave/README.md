# Warrior cleave — Sovereign Edge

Original steel and gold presentation for the warrior's existing RMB special.
The silhouette is a sculpted half-moon with an ivory cutting bevel, two thin
gold filaments, a transparent pressure wake and voxel fragments. A 0.15-second
windup contracts toward the warrior; the blade releases on the existing damage
frame, then breaks into rectangular flecks. Real hit signals place the contact
glints on the targets. At most six contact bursts appear per attack; all targets
still receive damage.

`sovereign_edge.tres` controls art and sound. Combat retains its damage,
knockback, cooldown, hitbox and terrain connectivity. Mastery bonuses also remain
in effect. Camera feedback is a bounded, 0.20-second image-plane translation;
it never changes the isometric orientation or FOV. Ground cuts use nearby world
raycasts and skip disconnected elevations. They fade without modifying terrain.

Geometry and shaders are original procedural assets. No external raster art,
textures or AI image generation is required for these layers. The original
audio cue is deterministic synthesis, reproduced with:

```powershell
python tools/generate_cleave_audio.py
```

Reproduce the production-world recording (Godot 4.6.1, Forward+):

```powershell
godot --path . --fixed-fps 60 --write-movie screenshots_debug/cleave.avi -s tools/capture_cleave.gd
```

The capture uses the real `perform_special_attack()` entry point, freezes AI for
repeatability, and verifies live player damage (including mastery), a target
behind the player, confirmed hits and final cleanup. It records detail/day,
game/day, game/night, crowd/night and a side view. Captures are engine output,
not concepts. Relevant coverage: `tests/integration/test_cleave_vfx.gd` and the
existing sword trail/animation/camera/terrain suites.

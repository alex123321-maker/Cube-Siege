# Warrior cleave — Sovereign Edge

Original steel and gold presentation for the warrior's existing RMB special.
The silhouette is an asymmetric painted steel wedge with an ivory leading head,
a torn tail, a subdued pressure wake and directional voxel fragments. The head
travels across a compressed, banked frontal mesh; it does not remain as a bright
semicircular wall. A 0.15-second windup brightens the actual animated sword tip.
The existing world-space blade trail also uses the cleave painting during the
special. The release starts on the existing damage frame. Confirmed hit signals
place smaller contact glints on targets; at most six appear per attack, while all
targets still receive damage. Misses produce no contact flashes.

`sovereign_edge.tres` controls art and sound. Combat retains its damage,
knockback, cooldown, hitbox and terrain connectivity. Mastery bonuses also remain
in effect. Camera feedback is a bounded, 0.20-second image-plane translation;
it never changes the isometric orientation or FOV. Ground cuts use nearby world
raycasts and skip disconnected elevations. They fade without modifying terrain.

Geometry and shaders are original code. `cleave_ribbon_v2.png` is an original
2172 × 724 RGBA painting generated with the built-in Codex imagegen tool on
2026-09-30. Its alpha was preserved and no pixel editing was performed. Shader
UVs select the painted ribbon and retain its negative space; mipmaps are enabled
for the gameplay camera. The complete generation prompt is in [PROMPT.md](PROMPT.md).
No downloaded game assets are included. The original audio cue is deterministic
synthesis, reproduced with:

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

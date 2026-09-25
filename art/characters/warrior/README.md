# Warrior — Issue #8

`hero_warrior.blend` is the editable artistic source for the Issue #8 Warrior candidate, pending visual approval. The runtime export is `assets/models/characters/hero_warrior.glb`; `hero_warrior.tscn` is the stable Godot wrapper used by `scenes/player.tscn`. Geometry was script-assisted and revised in the Blender source; this is not a claim of manual-only production art.

## Contracts preserved

- 1 Blender unit = 1 metre, Z-up, model front = -Y, feet on Z=0.
- Raw GLB front = +Z after glTF conversion. The stable wrapper rotates 180° so the actual player faces its controller's -Z attack direction.
- Original rigid Node3D ownership is retained: `root/torso/head`, `root/torso/right_arm/sword`, `root/torso/left_arm/shield`, `root/right_leg`, `root/left_leg`. Knee pivots are children of the original legs; there is no parallel Skeleton3D or empty weapon-hook facade.
- Runtime animations: `idle` 1.2 s, `walk` 0.8 s, `attack` 0.35 s, `special` 0.5 s, `utility`/`block` 0.5 s, `ultimate` 0.8 s.
- `idle` and `walk` loop. Blender source names use the Godot-supported `-loop` suffix so imported runtime names stay unchanged and gain loop mode.
- LMB contact is 0.06 s and RMB contact is 0.15 s, matching damage start in `player_combat.gd`. The old 0.16 s value is slash lifetime, not windup.
- Shield board is offset ahead of the forearm. Its rear cross-grip is centered in the left fist and connects to two side brackets; the board is not embedded in the arm.
- Source animation actions are grouped by matching NLA track names. Tracks are muted for the saved rest pose; enable one named track on the pivots to preview it. Export with `NLA_TRACKS` and retain constant object channels, otherwise idle arm angles are lost.

## Texture source

The project-specific source atlas is `art/textures/characters/warrior_material_atlas_source.png`. The 1024×1024 runtime atlas is `assets/models/textures/warrior/hero_warrior_material_atlas.png`.

Image generation prompt used for the source atlas:

> Square orthographic hand-painted material atlas for a stylized voxel/cubic Cube Siege Warrior, based on the approved concept's material language: large clean regions of dark hammered steel, nearly-black padded cloth, worn brown leather, dark oak, restrained brass/gold, one cold-blue accent and a geometric shield emblem. Crisp low-frequency forms, readable at gameplay distance; no character, text, logo, watermark, photorealism, micro-noise, perspective or baked directional shadow.

The atlas was generated with the built-in image generation tool and then assigned through explicit single-panel UV regions and PBR roughness/metallic separation in Blender. The GLB embeds the runtime atlas (`gltf/embedded_image_handling=3`), so extracted sibling PNG copies are unnecessary. The packed texture points to the actual runtime PNG, not to the differently sized source atlas.

## Re-export and validate

```powershell
& $env:BLENDER_BIN --background art/characters/warrior/hero_warrior.blend --python-exit-code 1 `
  --python tools/art_pipeline/blender/export_gltf.py -- `
  --output assets/models/characters/hero_warrior.glb

& $env:GODOT_BIN --headless --editor --path . --import --quit
& $env:GODOT_BIN --headless --path . `
  --script res://tools/art_pipeline/godot/validate_character_import.gd -- `
  --asset res://assets/models/characters/hero_warrior.tscn
```

The temporary authoring helper is intentionally kept under ignored `art/work/issue-8/`; the `.blend`, not the helper, owns the final form.

Review captures and reproduction commands: `docs/art_pipeline/verification/warrior/README.md`.

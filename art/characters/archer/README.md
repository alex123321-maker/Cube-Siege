# Archer — reference revision for #9

`hero_archer.blend` is the editable source; `assets/models/characters/hero_archer.glb` is the runtime export. The wrapper retains its original UID. This is script-assisted Blender geometry, not an AI-generated image presented as a model.

The user's September 26 reference in `art/references/issue-9/archer_approved_target.png` supersedes the original hood requirement: blonde elf, pointed ears, layered hair, green scarf/cape, fitted brown leather and restrained gold. The later eye revision adds angular emerald irises, jade lower facets, upper lashes and two highlights, all attached to the head. The exact reference is packed into the Blender file.

The `root/torso/head`, arm, leg, bow, arrow and quiver hooks remain. Elbows and knees are rigid child joints. Bow/string and hand positions are baked together using an offline two-link solve. Clips retain idle 1.2 s, walk .8 s, attack .38 s, special .6 s, utility .4 s, ultimate .7 s; attack release .08 s and special release .28 s remain gameplay-owned. Source sampling/import uses 100 fps. Idle/walk use `-loop` source names for Godot import.

Coordinates: authored in Godot metres (+Y up, -Z front), converted to Blender Z up. This GLB already faces Godot -Z; unlike the older Warrior export, it needs no wrapper half-turn.

## Texture provenance

Source: `art/textures/characters/archer_reference_atlas_source.png`. Runtime: `assets/models/textures/archer/hero_archer_material_atlas.png`, 1024×1024, packed into the blend and GLB, unique to Archer. AI-assisted bitmap material source, explicit UV assignment and separate roughness/metallic values in Blender. Eye facets use solid colors deliberately so facial features remain crisp.

Final texture prompt brief: a flat orthographic material atlas for the supplied blonde elf Archer reference, quiet warm brown leather, olive cloth, honey blonde hair, warm skin, restrained matte gold, dark boot material and pale arrow feathers; broad readable material regions, subtle seams and grain, no baked lighting, character, labels or noisy wear. The discarded first atlas and first model are not runtime dependencies.

## Reproduce

```powershell
blender --background --python art/characters/author_archer_reference.py
blender --background art/characters/archer/hero_archer.blend --python tools/art_pipeline/blender/export_gltf.py -- --output assets/models/characters/hero_archer.glb
blender --background art/characters/archer/hero_archer.blend --python art/characters/render_archer_review.py
```

Authoring resets the scene; save manual refinements before rebuilding. Normal edits should use the canonical `.blend`, then export. Actual renders, gameplay, comparisons and validation: `docs/art_pipeline/verification/hero-polish/README.md`.

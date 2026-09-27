# Engineer — Blender revision for #10

`hero_engineer.blend` is the editable source; `assets/models/characters/hero_engineer.glb` is the runtime export. The existing wrapper UID and weapon/pack hooks remain.

The model retains goggles, a heavy wrench-hammer, utility apron and an asymmetric mechanical pack. Broad tapered torso, short legs, leather pads, angular beard/hair and pack vents distinguish it from the taller Archer and armoured Warrior. Elbows/knees articulate rigid geometry. Held equipment is baked with the hand solve.

Authored units and axes: Godot metres, +Y up, -Z front, converted to Blender Z up. Runtime needs no half-turn. Clip durations remain idle 1.2 s, walk .8 s, attack .48 s, special .4 s, utility .45 s, ultimate .75 s. Gameplay attack contact remains .12 s, turret placement .15 s. Import uses 100 fps; idle/walk loop.

Source texture: `art/textures/characters/engineer_material_atlas_source.png`. Unique 1024×1024 runtime texture: `assets/models/textures/engineer/hero_engineer_material_atlas.png`, packed in `.blend` and GLB. Bitmap material source was generated with the built-in image generator and explicitly mapped in Blender, with material-specific roughness and metallic values.

Final texture prompt brief: a quiet flat orthographic 4×4 material atlas for a stylized cubic Engineer; ochre work shirt, warm brown apron/leather, dark hair/beard, grey trousers, dark iron, restrained copper, cyan goggles and device accents; broad clean readable regions with subtle seams and grain, no character, perspective, labels, baked lighting or dense damage noise.

```powershell
blender --background --python art/characters/author_engineer_polish.py -- --class engineer
blender --background art/characters/engineer/hero_engineer.blend --python tools/art_pipeline/blender/export_gltf.py -- --output assets/models/characters/hero_engineer.glb
```

The authoring script resets the scene. The `.blend` owns final manual edits; export it directly after editing. Verification and actual gameplay media: `docs/art_pipeline/verification/hero-polish/README.md`.

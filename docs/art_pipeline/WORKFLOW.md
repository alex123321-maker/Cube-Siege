# Character production workflow

## Non-negotiable contracts

- Blender is the artistic source of truth. Final heroes are manually authored and art-directed.
- Godot remains the runtime. Do not change gameplay code, balance, rig hierarchy, animation names, or animation timing without a separately approved decision.
- `scripts/generate_all_models.py` remains available for prototypes, simple props, test assets, and utility content. It must not own the final artistic form of hero characters.
- AI output is optional blockout/reference geometry only. It is never production-ready by default.
- GLB/glTF 2.0 is the interchange format. Use FBX only after documenting a concrete blocker.

## Scale and orientation

| Contract | Value |
| --- | --- |
| Blender units | Metric; 1 unit = 1 metre |
| Hero target height | Approximately 2.0 m for the current visual/collision contract; deviations require art/gameplay review |
| Blender up | +Z |
| Blender asset front | -Y |
| Godot up | +Y |
| Godot asset front | +Z |
| Root/origin | Ground contact at zero; centered horizontally |
| Export scale | 1.0, Y Up enabled, mesh object scale applied |
| Weapon scale | Authored in metres in the same file; never corrected by per-instance Godot scale |

Godot's asset convention maps Blender front `-Y` to Godot model front `+Z` through the standard glTF Y-up conversion. The calibration test enforces 2.0 m height and a positive-Z front marker.

The player controller aims along `-Z`. A runtime wrapper must bridge the raw asset convention to that controller convention (Warrior uses a 180° Y rotation), not turn the mesh backward during gameplay. Validate the wrapper, not just the raw GLB marker.

## Phase 0 — references

Inputs are an approved Issue, a concept sheet, the existing model/rig contract, and the real gameplay camera. Store approved source art under `art/references/<issue-or-character>/`; temporary images belong under ignored `art/work/`.

Recommended views are front, left/right side, back, 3/4, plus a gameplay-camera reference. Use matching canvas, ground line, height, and neutral pose.

Create a Blender scene from images on Windows:

```powershell
& $env:BLENDER_BIN --background --factory-startup --python-exit-code 1 `
  --python tools/art_pipeline/blender/import_reference.py -- `
  --front art/references/issue-8/front.png `
  --side art/references/issue-8/side.png `
  --back art/references/issue-8/back.png `
  --three-quarter art/references/issue-8/three_quarter.png `
  --output-blend art/work/issue-8/blockout.blend
```

The script creates `REFERENCES`, applies one common two-metre display scale, positions views on the correct axes, labels objects, locks selection, and excludes them from rendering. It does not model a character.

Use `--left` and/or `--right` instead of `--side` when the sheet supplies both side views.

## Phase 1 — silhouette blockout

Use primitives and low-complexity geometry only. Resolve proportions, silhouette, equipment scale, and visual mass. Do not add polished textures, bolts, small decoration, or complex materials.

Required approval renders: front, side, back, 3/4, and the elevated gameplay-like view. Generate them from an open `.blend`:

```powershell
& $env:BLENDER_BIN --background art/work/issue-8/blockout.blend --python-exit-code 1 `
  --python tools/art_pipeline/blender/render_turnaround.py -- `
  --output-dir art/work/issue-8/review/silhouette
```

Do not proceed until silhouette readability holds at gameplay zoom and against enemy density.

## Phase 2 — secondary forms

After silhouette approval, add armor plates, hood, backpack, equipment, and other medium shapes. Preserve a hierarchy of clear large forms, controlled medium forms, and very few small forms.

## Phase 3 — detail and materials

Only after geometry approval: UVs, individual textures, material separation, controlled wear, and class-specific details. Favor planar surfaces, block-like construction, intentional bevels, simplified shapes, exaggerated readable equipment, and limited material complexity. Minecraft Dungeons is a readability/shape-hierarchy reference, not content to copy.

## Optional AI blockout cleanup gate

Before any AI mesh can be used, inspect and repair:

- topology, non-manifold areas, disconnected geometry, internal/hidden faces;
- excessive triangle count and high-frequency noise;
- asymmetry warping, hands, equipment, and hidden/backside hallucination;
- proportions and silhouette at gameplay distance;
- UV/texture artifacts and material sprawl.

Retopologize/rebuild into Cube Siege's planar, block-like style. Delete generated detail that does not improve readability. Never infer the back of a character from a single image as ground truth.

## Phase 4 — rig integration

Duplicate/import the existing approved skeleton and animation contract, bind the new mesh, weight paint, and test every existing animation. Keep names, hierarchy, root motion behavior, and gameplay timing unchanged unless Product Owner approval says otherwise. Export the armature in rest pose and ensure each animation action is included.

For existing rigid Node3D rigs, retain real mesh ownership under those animated pivots; do not substitute empty compatibility hooks next to an unrelated skeleton. Warrior uses matching NLA track names across its rigid pivots. Retain constant object animation channels during export so static poses such as idle grip angles survive. Check physical hand/equipment clearance in addition to NodePath existence.

## Phase 5 — export and Godot verification

Put exportable meshes, armatures, and necessary parents in a collection named `EXPORT`. Keep references, review cameras, and studio lights out of it. Apply mesh scale and triangulate deliberately.

```powershell
& $env:BLENDER_BIN --background art/work/issue-8/character.blend --python-exit-code 1 `
  --python tools/art_pipeline/blender/export_gltf.py -- `
  --output assets/models/characters/hero_candidate.glb `
  --report art/work/issue-8/export_report.json

& $env:GODOT_BIN --headless --editor --recovery-mode --import --path .
```

Then instantiate the imported scene in the actual Godot player scene and verify gameplay camera, movement, attacks, clipping, equipment, enemy density, silhouette, materials, skeleton hierarchy, and animation names. Do not add per-instance scale fixes; correct the `.blend` source and re-export.

## Reproduce the calibration proof

```powershell
.\tools\art_pipeline\verify_pipeline.ps1
```

The test output proves mesh/material import, metre scale, +Z model front, a two-bone hierarchy, `calibration_idle`, and five standard renders without touching hero assets.

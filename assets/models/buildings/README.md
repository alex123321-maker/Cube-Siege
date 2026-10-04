# Demo building models

These are original Cube Siege voxel assets. Editable canonical sources are in
`assets/models/sources/buildings/*.bbmodel`; no external artwork is included.
Source scale is 16 Blockbench units per metre, with ground origin at Y=0.

Run `python tools/export_building_models.py` after source geometry edits.
The exporter writes glTF with grouped, flat-shaded geometry and batches cubes
by material. Palette swatches are converted from sRGB to linear glTF factors.
`--author` recreates the initial sources and should only be used intentionally.
Keep the Body/BowPivot/Spikes/Flames group names: production scripts use them.

The five buildable defensive prefabs, campfire and starting workbench use these
models directly. The building hologram uses the same glTF as the final building.
Small icon illustrations in `assets/ui/buildings` are original SVG artwork.

Campfire demo defaults are exposed in `scripts/campfire.gd`: 5 m circular aura,
3 HP/s, 180 HP, 6 wood + 3 stone. A source refreshes every 0.25 s with a 0.6 s
fallback expiration. Leaving range, destruction or removal cancels that source.
Distinct regeneration sources add together, following the CubeSiege Space rule.

`tools/capture_demo_buildings.gd` renders the actual main-scene prefabs, build
menu, day/night model stage, front/profile hearth and 90 flame frames at 60 FPS.
Run it through a subprocess with a 90 s timeout; its own deadline is 65 s.
Output is under ignored `screenshots_debug/demo_buildings`. The stage diagnoses
model shape and light; it does not replace main-scene gameplay evidence or
establish a realtime performance measurement.

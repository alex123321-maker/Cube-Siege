# HUD ImageGen kit — Issue #52

Runtime PNGs are 256×256 exports of the 23 selected raster masters owned by
[the assets repository](https://github.com/alex123321-maker/assets).
They were generated with **Codex built-in ImageGen**. Godot MCP was used for
runtime integration, measurement and captures; it was not the image generator.

The source package is version 2, based on assets commit
`2e896cf314b89958189e273ac3491ddea71397d7`. Its Issue #52 changes are currently
uncommitted. [runtime_manifest.json](runtime_manifest.json) identifies the exact
master and export hashes, so the base commit is not misrepresented as containing
the new art. Prompts and masters remain in the source repository under
`assets/ui/hud_visual_kit/source/imagegen/`.

All 23 runtime exports and all 23 saved master hashes were checked against that
source package on 2026-10-01. No SVG or procedural illustration is used for the
functional icons. Technical slot frames remain raster UI components; the top
panels use the shared Godot Theme to avoid stretching baked decorative sections.

The canonical filenames agree with [naming_map.json](naming_map.json). Archer F
uses `archer_eagle_eye.png`, Engineer F uses `engineer_tactical_nuke.png`.
Retired 64px copies and the incorrect Sniper/Overclock IDs have no active runtime
references.

See the [runtime audit](../../../docs/screenshots/issue_52/README.md).

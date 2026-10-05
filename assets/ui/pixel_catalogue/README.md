# Selected pixel UI catalogue

The bitmap sources in `sources/` are byte-for-byte copies of the selected CubeSiege
reference catalogue from the assets repository at
`96400e1a956e87a84357ae7bc2914f2378755c2c`. `manifest.json` records each source SHA-256,
original Page identity, original candidate/approved reference status, and generation
provenance. The user's request to integrate this catalogue is recorded separately
from those original reference statuses.

Godot imports these original sRGB PNGs with lossless compression, no mipmaps, and an
explicit `process/size_limit`: 256 for icons/portraits, 128 for square UI frames,
compact keycap/bar frames and the phase/timer panel, and 512 for the remaining wide
UI components. The original PNG files are never resized or repainted.
`textures/*.tres` are `AtlasTexture` resources which clip transparent margins in
the imported coordinate system. Bounds include pixels whose source alpha exceeds
16/255; this omits faint stray alpha pixels outside the visible components. The
manifest retains both source-space bounds and imported-space regions.
Action-slot states, talent-node states and connector states share aligned region
extents so changing visual state does not shift their silhouettes.

`PixelUI.texture(key)` loads these resources for TextureRects and drawing.
`PixelUI.path(key)` supplies resource paths for existing icon catalogs.
`PixelUI.panel(key, padding)` creates an independent nine-slice StyleBoxTexture;
padding order is left, top, right, bottom. Bare HP/XP/wave fills use zero texture
margins and should receive `Vector4.ZERO` content padding.

The original resource panel has five baked cells. Use it as a whole texture with
aligned content, or use `ui_resource_portrait_cell` and `ui_resource_counter_cell`
to keep each border attached to its own content. The original tooltip panel has a
baked gold divider. Generic modal panels use the clean `ui_action_slot_normal`
frame (`ui_tooltip_panel_frame` is its semantic alias); `ui_tooltip_divider` exposes
the original divider separately for container-driven headers and bodies.
The phase/timer panel exposes its upper rectangle; the lower baked well is clipped
because this integration does not add a gameplay wave meter.

All three generated portraits, all fifteen hero actions including the approved
sword icon, nine Warrior talent icons, three documented synergies, building/resource
icons, state icons and reusable UI components are addressable. Archer mutation
references and additional state illustrations are available without adding any
new gameplay or unlock rules. Enemy skill art is outside this HUD integration.

Actual UI layout and text readability are verified in the game; the reference
catalogue alone does not establish runtime quality or artistic approval.

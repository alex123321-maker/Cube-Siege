# Pixel UI integration

The gameplay HUD and menus use the generated CubeSiege pixel catalogue from
`alex123321-maker/assets` at `96400e1a956e87a84357ae7bc2914f2378755c2c`.
The user's integration request is recorded in the catalogue manifest separately
from the original candidate/approved reference statuses.

## Presentation

- Three hero portraits and fifteen ability icons follow the selected class.
- Action frames expose normal, hover, pressed, disabled and cooldown states.
  Key labels and cooldown numbers remain live text; their artwork is separate.
- Resource counters, day/night header, HP/XP/boss bars and active statuses use
  the same steel, brass and navy visual family.
- Nine Warrior talents, their root, connections, state badges and three existing
  synergies use the new art. Unlock requirements and gameplay values are unchanged.
- Building categories, six available buildings, the workbench, settings,
  specializations and checkpoint selection share the presentation theme.
  The workbench's existing three tabs have localized titles.

`PixelUI` loads immutable source PNGs through imported `AtlasTexture` regions.
`PixelHUDTheme` supplies shared styles; content padding is independent of image
dimensions. Original PNGs and source hashes are retained in
`assets/ui/pixel_catalogue/manifest.json`. Additional illustrations are addressable
without adding undefined abilities, items, talents or enemy UI.

## Layout safeguards

The HUD keeps its existing 420×80 resource region, 360×56 phase region and six
82×120 action slots. Artwork is inset inside each slot frame. Long tooltip titles
and menu warnings wrap; resource counters retain exact values in their tooltips.
The building categories form a symmetric grid. Mastery cards and talent nodes
stay inside their panels at the supported logical viewport ratios.
The specialization button is drawn below modal dimmers and windows.

## Reproducing verification

Run `python tools/verify.py` for build, import, the complete GUT/Python suites,
procedural-world checks and menu/gameplay smoke tests. Layout regression tests are
`test_hud_layout.gd`, `test_ui_domain_separation.gd`, `test_pixel_ui_layout.gd`
and `test_pixel_menu_layout.gd` under `tests/integration/`.

For actual Vulkan-rendered screenshots, run the following with a rendering
display and a 100-second outer process timeout. Repeat with 1920×1080,
2560×1080 and 1920×1200; use a separate output/profile for each resolution.

```text
godot --path . --resolution 1280x720 -s tools/capture_pixel_ui.gd -- --width=1280 --height=720 --test-profile=user://pixel_ui_capture/1280x720/ --output=res://.review_loop/pixel_ui/1280x720
```

The capture harness loads the real game/menu scenes and saves 49 screenshots:
all three classes, every action tooltip, active statuses, boss-pending caption,
critical HP, boss health, long text, settings, all building categories, workbench tabs, specializations,
checkpoint selection and locked/opened talent trees. Its `geometry.json` records
screen/panel bounds, text measurements, slot spacing and failures. The stress
fixture uses billion-scale resource counts and upgraded ability descriptions.
This complements visual inspection; geometry checks alone do not approve art.

The repository's legacy SpatialMaterial `specular` warning still appears in game
captures. Headless editor shutdown also reports resources in use; script parsing,
game runtime and screenshots are checked independently.

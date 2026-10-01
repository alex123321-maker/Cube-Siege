# Issue #52 — audit and corrections, 2026-10-01

Worktree branch: `feat/52-hud-imagegen-layout`, game base
`e9b3c921188e294a94a0599787eb1715b8d60447`. Implementation and audit corrections
are uncommitted. This is local engineering evidence, not external art approval.

## Defects found and corrected

- The settings icon had an ineffective scene property (`icon_max_width` instead
  of a Theme constant). MCP measured the button at **82×74**, the day/night panel
  at **368×90**. `expand_icon`, a compact Button Theme variation and proper
  vertical alignment now resolve to **30×30** and **360×56**.
- The old panel textures had baked sections that did not match the new contents.
  Shared Theme panels replace their distorted layout. The portrait now has a
  transparent background, a useful model crop and a 64px region; resources fit
  the intended **420×80** panel instead of expanding to 420×86.
- Cooldown still used percentages of the whole slot. A shared **72×72** visual
  region now contains frame, icon and mask. All six slots are **82×120**, with
  8px gaps. Key bindings and names have separate areas; font sizes and label
  backgrounds improve contrast at 720p.
- `set_action()` previously hid a valid replacement icon after unavailable and
  retained cooldown from the old action. Replacement actions now reset all
  presentation layers; unavailable immediately clears mask/countdown. Missing
  required icons emit a diagnostic and stay unavailable.
- Initial resource events were emitted before HUD subscribed: the wallet had
  **16/8/4**, but HUD displayed **0/0/0**. The new regression test failed on all
  three values before the fix. HUD now reads the authoritative startup snapshot
  through an explicit dependency and receives subsequent wallet events. Large
  values use K/M/B; exact counts remain in tooltips.
- Earlier resize captures paused HUD processing as well as gameplay, leaving HP
  at stale coordinates. HUD now continues positioning while paused. Fresh MCP
  measurements compare the actual HP/XP center with Camera3D projection after
  resize and pan/zoom. No screenshot coordinates were retouched.
- Decorative HUD controls ignore mouse events; action slots/resource labels
  allow tooltips while passing clicks. Actual injected mouse motion displayed
  the Engineer F tooltip in [hud_tooltip_1280x720.png](hud_tooltip_1280x720.png).

## Runtime evidence

Windows 11 Home 10.0.26200, Godot 4.6.1 stable, **Vulkan 1.4.325 / Forward+ /
Intel Arc Graphics**. Logical base 1280×720, `canvas_items + expand`, window
content scale factor 1.0. System DPI variants were not separately exercised.

Godot MCP Native 1.0.8 was connected to this worktree. The complete arguments,
responses, seeds, world positions and resolved sizes are in
[runtime_mcp_audit.json](runtime_mcp_audit.json). Tools used include
`run_project`, `evaluate_runtime_expression`, `get_runtime_screenshot`,
`simulate_runtime_input_event` and `stop_project`.

| Window / capture | Logical HUD bounds | Result |
| --- | --- | --- |
| [1280×720](hud_1280x720.png) | 1280×720 | Fixed panels, square slots, projected overhead center |
| [1920×1080](hud_1920x1080.png) | 1280×720 | Same geometry |
| [2560×1440](hud_2560x1440.png) | 1280×720 | Same geometry |
| [2560×1080](hud_2560x1080.png) | 1706×720 | Correct horizontal anchors and overhead center |
| [1920×1200](hud_1920x1200.png) | 1280×800 | Correct vertical anchors and overhead center |

The sequence returns to 1280×720. Fullscreen was also captured at the actual
2880×1800 display size, then restored to windowed. The viewport/overhead
comparisons use live values, with a 0.01 logical pixel tolerance.

Warrior, Archer and Engineer have 720p/1080p class captures plus actual utility
and dash cooldown states. Further captures show sunset, night and unavailable
for each class, settings at 720p/1080p, level-up/card draft, boss, large resources
and **25/100 HP**. Engineer mine captures invoke the real gameplay owner:
[placed mine / “ПОДОРВАТЬ”](hud_engineer_place_1920x1080.png),
[detonation / 3.5s reload / “ПОСТАВИТЬ”](hud_engineer_detonate_1920x1080.png).
F captures use the actual Eagle Eye and Tactical Nuke handlers.

Capture fixtures pause the world for stable frames. Before class-specific ready
and utility captures they clear the owner's previous test cooldowns; they do
not change gameplay constants or saved player data. Captures are separate frames,
not a continuous video of resize. The before-audit capture uses a different
random world seed, so it is not a pixel-matched terrain comparison.

## Verification

`python tools/verify.py` completed with **exit 0** after the corrections:
native build, headless import, **310 GUT tests / 51 scripts**, **135 Python tests**,
26 procedural/combat checks, main-menu smoke and 24 gameplay checks across the
three classes. See [verify.log](verify.log).

The first audit attempt exceeded the default 600s build timeout. The MinGW
long-command workaround appended archive objects in individual processes.
Observed progress justified one finite retry with `VERIFY_TIMEOUT_SCONS=1200`;
that build succeeded. The failed attempt is preserved in
[verify_build_timeout.log](verify_build_timeout.log), not counted as PASS.

New local tests also cover startup resources, resized region/slot bounds,
cooldown → unavailable → ready, missing icon diagnostics, input filters and
world projection. The isolated headless projection test explicitly waits for
viewport setup and calls HUD projection; live automatic updates are checked
separately by MCP. Expected missing-icon errors are asserted by GUT.

All 23 runtime exports match source PNGs, and all 23 master hashes match saved
ImageGen provenance. Source-art clean-export checks from the implementation
remain applicable: this audit changed integration and selected the existing
256px exports without regenerating art. No user save was used for these runs.

Mentor request `cube-siege-52-audit-camera-test-20261001-a1`, job
`0c541a59-fec9-4e7f-b43f-e43d30fe2be8`, ended **blocked** because ChatGPT was not
ready (login/CAPTCHA/project access). No mentor answer or approval is claimed.
PR publishing, independent art acceptance, a continuous resize recording and
separate OS DPI checks remain outside this local audit evidence.

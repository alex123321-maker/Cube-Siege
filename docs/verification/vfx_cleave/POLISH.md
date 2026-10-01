# Cleave refinement — 2026-09-30

Build on local first implementation `4283ea9`, base `722bac40e1f4ba8f4619501dcc579a7d290ed1f1`.
Godot 4.6.1 / Forward+ / Intel Arc / Windows. Artistic direction and ability
presentation were explicitly delegated by the user. The combat parameters and
camera presets retain their existing behavior.

## Comparison and selection

All recordings use the production scene, seed 1337, 1280 × 720, 60 fixed steps
per second, the real special entry point and authored animation. AI and player
movement are frozen. The same positions, lighting, lens and timing are used for
each comparable pair. The portal's bright cyan glow is retained as real context.

| Variant | Observation from engine frames | Decision |
| --- | --- | --- |
| First / `sovereign_0_018.png` | Clear silhouette, but uniform bright concentric rims form a persistent wall | Replace |
| Painted v2 / `v2_0_018.png` | Irregular material; blade is hidden by the targets and contact sparks dominate | Reject |
| Raised v3 / `v3_0_018.png` | Dense dark steel body restores contrast over pale stone; tapered facets improve shape | Keep material and banked geometry |
| Static vs traveling / `v3_miss.mp4`, `v4_miss.mp4` | Static silhouette occupies most of the arc throughout its peak; traveling head advances to the right while leaving a thin tail | Choose traveling head |
| Final / `cleave_polished.mp4` | Traveling steel wedge without secondary gold ring; smaller, directional sparks and lower contact light compete less with the blade | Selected |

Time-ordered frames 009/018/021/025/033/065 were examined for anticipation,
peak, travel and dissipation. Normal camera frames were examined in daylight,
night and crowded night combat, plus detail and opposite side views. Misses and
a 90-degree actor rotation were captured separately. These are observed engine
frames, not concept renders. The selected clip includes the game's original
synthesized audio; sound playback quality was not independently auditioned.

The selected effect is the best of the demonstrated alternatives for this brief.
It is not a claim of an objective global optimum. More concentric rims and
larger gold sparks weakened the main read in the comparisons, so they were removed.

## Latest verification

- `python tools/verify.py`: **PASS all stages** — build, import, 297 GUT tests,
  135 Python tests, 26 world/combat checks, menu smoke and 24 gameplay smoke checks.
- Final hit capture: five releases, 17 contacts, correct live mastery-scaled
  damage, untouched sentinel behind the player, zero effects/camera offset/trail
  after settling.
- Final miss capture: five releases, zero contacts, unchanged target health,
  zero effects/camera offset/trail after settling.
- Rotated capture: one release, three contacts, correct damage and cleanup.
- New seventh cleave integration check: windup glint follows the moving weapon
  anchor and clears when its owner disappears. Existing tests cover contact
  budget versus damage, repeated casts, owner removal, class change and camera recovery.

The earlier streaming performance failure recorded in `VERIFICATION.md`
reproduced at the base revision; the latest full audit passed that same gate.
No world code or thresholds were modified. Legacy editor shutdown/resource and
SpatialMaterial warnings remain as previously documented.

## Real-time rendering cost

A separate run without Movie Writer warms the effect, samples 180 baseline
frames, then launches four bursts of eight overlapping releases plus 48 contact
effects. Samples with at least 16 active effects are retained (211 frames).
Godot viewport GPU/render CPU measurements are used, not movie encoding time.

| Measurement | Baseline | Stress |
| --- | ---: | ---: |
| GPU average | 3.69 ms | 4.42 ms |
| GPU p95 | 3.89 ms | 5.77 ms |
| GPU maximum | 4.63 ms | 8.60 ms |
| Render CPU average | 3.03 ms | 2.52 ms |
| Render CPU p95 | 4.11 ms | 3.46 ms |

Stress peak: 570 visible draw calls; zero active effects after cleanup. The lower
CPU average is measurement variability, not evidence of an optimization.
The GPU delta is 0.73 ms in this scene on this machine. This is a synthetic
presentation load; it does not measure total CPU gameplay cost, general hardware
coverage or a live eight-player game. Lower frame rates and moving attacks on
arbitrary slopes were not separately rendered; movement of the weapon anchor,
interruption, class change and bounded world-space trail behavior have automated
coverage. No numerical artistic score is assigned.

## Reproduce

```powershell
godot --path . --fixed-fps 60 --write-movie screenshots_debug/cleave_final.avi -s tools/capture_cleave.gd -- --label=final
godot --path . --fixed-fps 60 --write-movie screenshots_debug/cleave_final_miss.avi -s tools/capture_cleave.gd -- --label=finalmiss --miss
godot --path . --fixed-fps 60 --write-movie screenshots_debug/cleave_rotated.avi -s tools/capture_cleave.gd -- --only-phase=0 --label=rotated --facing-degrees=90
godot --path . -s tools/capture_cleave.gd -- --profile-real-time
```

`--static-head` selects the material's stationary reveal alternative; the old
comparison clips predate final removal of the gold ring/contact-light reduction.
Logs: `polish_audit.log`, `final_capture.log`, `final_miss.log`,
`final_rotated.log`, `real_time_profile.log`.

## Reusable skill

Source: [vfx-craft](../../../.agents/skills/vfx-craft/SKILL.md), also installed in
the user's Codex skills directory. Its structure and local links were validated;
a separate agent applied it to actual first/v2 frames and identified the missing
dominant silhouette without claiming unseen timing/audio/performance quality.
Use `$vfx-craft` for future ability VFX work. It teaches a comparison loop rather
than a universal blue/gold recipe or an unconditional perfection guarantee.

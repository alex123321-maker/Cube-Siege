# Warrior cleave: ability identity

Revision of local parent `d521936`, responding to the user's report that the
special looked like an ordinary attack, lacked torso animation and target hit
feedback, and did not communicate its size. The user explicitly authorized
changes to ability properties and presentation. This report and its captures
are saved with the implementation that produced them.

## Behavior and visual selection

- Dedicated 0.82-second animation: hips, torso, head, both arms and legs move
  through a coiled stance, horizontal sweep and recovery. Torso yaw changes
  from -64° to +64°; the actual sword anchors drive the blade trail.
- Shared `assets/abilities/warrior_cleave.tres` supplies the **3.8m / 180°**
  frontal sector to combat and presentation. The former box hitbox and visually
  compressed arc no longer define cleave. The ordinary attack restores its
  original collider.
- Windup lasts **0.28 seconds**. Ordinary attacks are held until **0.82 seconds
  from cast start**, allowing the full body action to read. Damage, knockback
  and the four-second special cooldown retain their existing values.
- A terrain-sampled outline shows the sector during anticipation and briefly
  after release. The broad steel crescent, torn painted interior and warm edge
  emphasize the same frontal footprint. Unsupported and large elevation gaps
  are omitted from the ground mesh; ordinary depth occlusion remains enabled.
- Confirmed hits create chest-height diagonal cuts, directional fragments and
  a short light accent. Cuts follow the struck actor during knockback. Target
  placement is an approximate visual surface placement using the target and
  camera transforms, **not an exact physics contact point**.
- All living struck enemies receive visual body recoil. Decorative cuts are
  capped at six per cast; this cap never restricts damage or body recoil.
  Recoil adds no stun, collision displacement or new status effect.

The earlier narrow traveling head was rejected for this revised brief: its
small instantaneous footprint reinforced the ordinary-attack impression.
The full crescent communicates a committed area ability. Its steel interior
retains breakup and contrast; the ground outline supplies reach without
requiring the target flashes to explain the shape.

The first full-body prototype was also rejected after the user spotted a
backward weapon arm. Its shoulder-to-tip quaternion used -Z in the warrior's
imported +Z-forward rig. The corrected clip uses bounded shoulder flexion,
twist and abduction, with the hand in front of the torso, a tucked shield and
a right-to-left forehand sweep. The wave's reveal direction matches that swing.
Front and sword-side recordings without VFX expose the pose throughout it.

The other playable models were checked independently: archer and engineer
are natively -Z-forward, while the warrior's scene wrapper converts its +Z
front to gameplay -Z. Actual eye/goggle geometry follows gameplay forward
at 0°, 90°, 180° and -90° body headings in the regression check. Front
engine captures also show the zombie, ranged skirmisher and siege breaker
facing gameplay forward. Their scene transforms require no change.

## Engine evidence

Windows / Godot 4.6.1 / Forward+ / Intel Arc, production `scenes/main.tscn`,
seed 1337, 1280×720, 60 fixed simulation steps per second. Camera offsets are
the game's ordinary `(15,20,15)` plus diagnostic detail and opposite side
views. The cyan portal, terrain and dressing are retained.

The real attack entry points are exercised. Player movement is frozen and
production presentation is advanced manually. Enemy AI speed is zero and
attacks are held, while physics, gravity and actual knockback remain enabled.
These are controlled demonstrations, not an unrestricted live play session.

`basic_vs_cleave.mp4` presents ordinary attack, cleave from the identical
normal camera, detail cleave, then crowded night cleave, at original speed
with captured game audio. The GIF is a silent 24fps convenience preview.
`anatomy_without_vfx.mp4` shows the corrected swing from the weapon side and
front. `tools/capture_model_forward.gd` reproduces the separate neutral
inspection of all three playable rigs and three enemy models.
`cleave_ability.mp4` preserves the complete five-view recording. The selected
time-ordered engine frames were inspected for windup, impact, follow-through
and settling; audio quality was not independently auditioned.

| Capture | Observed checks |
| --- | --- |
| Full five-view ability | Correct health, 5 releases, 21 decorative contacts, rear sentinel untouched |
| Ordinary attack, same setup | Central target hit; side and rear targets untouched; no cleave effects |
| Miss, ordinary camera | 1 release, 0 contacts, unchanged target health |
| Hero rotated 90°, ordinary camera | Correct health, 1 release, 3 contacts |
| All runs after settling | 0 active effects, 0 camera offset, empty sword trail |

The three frontal targets are at `(0,-1.8)`, `(±2.8,-1.0)` relative to the
warrior; the rear sentinel is at `(0,+2.2)`. Crowded views add 24 actors.
Displayed damage is 81 due to the production mastery state; isolated tests
assert the unmodified 60 base damage.

## Performance

A separate run without Movie Writer samples 180 baseline frames, then four
bursts of eight simultaneous releases and 48 decorative contacts. The 262
frames with at least 16 active effects are retained. Godot viewport renderer
measurements exclude movie encoding and do not establish total gameplay CPU
cost or a first-use hitch budget.

| Renderer measurement | Baseline | Stress |
| --- | ---: | ---: |
| GPU average | 4.01ms | 4.39ms |
| GPU p95 | 5.22ms | 5.04ms |
| GPU maximum | 5.88ms | 6.03ms |
| Render CPU average | 2.38ms | 2.57ms |
| Render CPU p95 | 3.82ms | 3.33ms |
| Render CPU maximum | 4.32ms | 4.64ms |

Peak: 617 visible draw calls; 0 effects after settling. Lower stress p95 is
measurement variability, not evidence of an optimization. This synthetic renderer
stress on one machine supports the selected visual density, not a guarantee
for every hardware configuration or a 500-enemy battle.

## Reproduction

Use the Godot executable recorded by `.godot_path`, with a finite subprocess
timeout (240 seconds for the full capture, 180 for individual runs).

```powershell
$godot = (Get-Content .godot_path -Raw).Trim()
& $godot --path . --fixed-fps 60 --write-movie screenshots_debug/ability_final.avi -s tools/capture_cleave.gd -- --label=final
& $godot --path . --fixed-fps 60 --write-movie screenshots_debug/ability_basic.avi -s tools/capture_cleave.gd -- --label=basic --only-phase=1 --basic
& $godot --path . --fixed-fps 60 --write-movie screenshots_debug/ability_miss.avi -s tools/capture_cleave.gd -- --label=miss --only-phase=1 --miss
& $godot --path . --fixed-fps 60 --write-movie screenshots_debug/ability_rotated.avi -s tools/capture_cleave.gd -- --label=rotated --only-phase=1 --facing-degrees=90
& $godot --path . -s tools/capture_cleave.gd -- --profile-real-time
```

Animation source is reproducible through `tools/generate_cleave_animation.gd`.
Retained PNGs cover the representative conditions; intermediate working
captures and logs live in ignored `screenshots_debug/`.

## Automated verification

`python tools/verify.py`: **PASS all stages** on the final implementation —
build, editor import, 302 GUT tests across 50 scripts, 135 Python tests,
26 world/combat/streaming checks, menu smoke and 24 gameplay smoke checks.
The final 11 cleave integration tests also passed directly, including the
hand-in-front-of-torso and blade-in-front-of-player regressions. Cleave-specific
checks cover damage and misses, true frontal boundaries, restoration of the
basic collider, visible torso motion, protected windup, following contacts,
body recoil recovery, terrain sampling at the caster before the first frame,
effect budgets, cancellation and complete cleanup.

An earlier audit in this iteration passed 301 GUT and 135 Python tests but
failed the world-generation timing gate at 454.40ms. The final audit passed
that same unchanged gate. Previous work had already reproduced its timing
failure on a clean base revision; this iteration modifies neither world
generation nor its thresholds. Both outcomes are preserved in the ignored
`ability_full_verify.log` and `ability_final_audit.log` files.

The existing SpatialMaterial/specular and editor shutdown resource warnings
remain; graphical ability and model recordings contain no new script errors.
The VFX skill's stock validator passed, and the updated repository and
installed personal skill copies match.

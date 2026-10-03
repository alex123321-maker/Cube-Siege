# Modified Warrior cleave and dismemberment

The modified cleave receives its radius, arc and duration directly from combat:
normal frontal cleave keeps the established VFX; whirlwind uses a full circular
boundary and two revolving pale steel ribbons; lunge follows the actual player
transform for the full 0.30-second contact window. Radius specialization scales
the visible boundary from the same value used by the collision cylinder. The
preparation ring uses the same arc/radius as the release. The player model wrapper
also turns through 360° during whirlwind's actual active duration, while body
orientation and damage geometry remain owned by gameplay. The wrapper returns to
its authored rotation on completion or model replacement/death.

`scripts/effects/warrior/warrior_talent_vfx.gd` contains original code-native meshes
and a 14-piece MultiMesh voxel breakup. Dismemberment starts at the actual killed
target/duel victory position, with a short cyan morale pulse showing the affected
radius. It does not create collision bodies or a persistent damaging area. Existing
confirmed target contact effects remain attached to real hits. Caster deletion or
death cancels a pending cleave visual; all components have finite lifetimes.

Hooks are limited to `PlayerCombat` charge/release presentation,
`PlayerPresentation` model-wrapper spin, and `WarriorTalentRuntime._dismember`
presentation. VFX do not grant talent bonuses, damage, healing or slows.

Run the real combat comparison recording with an isolated save profile:

```powershell
$env:CUBE_SIEGE_TEST_PROFILE = 'user://test_profile/'
python tools/capture_bosses.py --script tools/capture_warrior_talents.gd --marker TALENT_CAPTURE --stem talents --output screenshots_debug/talents/capture
```

The recording compares a basic sword attack, default frontal cleave and full
whirlwind under the same day camera, then shows whirlwind/lunge/radius under night
lighting, a miss, and dismemberment at a real duel victory location. It checks
actual health losses for front/rear/late-trajectory/safe sentinels, model rotation
restoration, the morale slow and effect cleanup. The first recording caught an
actual contact bug: broad-phase overlap could start before the target centre
entered the sector, so a rejected `area_entered` event was never reconsidered as
the lunge moved. Combat now samples active overlaps throughout its real window;
the existing hit ledger prevents repeated damage. The production-physics regression
is `tests/unit/test_warrior_cleave_trajectory.gd`.

The capture has a 305-second total deadline (render up to 240s, encoding up to 45s,
metadata up to 20s), explicit PASS/FAIL/TIMEOUT, logs, PNGs, MP4, gameplay-check JSON
and a limited source/file fingerprint. The arena is flat; generated terrain,
crowds, audio and real-time performance are not established by this recording.
The principles and primary source references in `BOSS_ENCOUNTERS.md` also apply:
authoritative visible geometry, clear commitment, restrained supporting layers,
and target feedback only from confirmed contacts.

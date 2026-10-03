# Warrior first version: canonical boss encounters

The authoritative attack vocabulary is the full nested
[Монстры](https://chatgpt.com/space/page_e08027496e6081918886b54f9774aa85) →
[Скилчек абилки](https://chatgpt.com/space/page_a121cb875bd8819188ad670f69181a20) branch,
read on 2026-10-03. Bosses use its seven mechanics and four radial variants.
The earlier generic sector/projectile fan/cross/reposition catalogue is replaced;
those are not live boss skills. The separate nine elite Pages have their own
implementation under `scripts/elites/`.

| Wave | Boss / original silhouette | Canonical attacks | Phases |
| --- | --- | --- | --- |
| 5 | Страж кургана / plated stone fists | Взрыв вокруг; Навесная атака | One |
| 10 | Горгон-Топтатель / horns, tusks, back plates | Сметающий рывок; Взрыв вокруг | One |
| 15 | Пепельный оракул / hood, staff, censer | Атака по линии; Радиальная слева направо; Подземная цепь взрывов | One |
| 20 | Мортирный колосс / boiler, twin cannons | Навесная атака; Радиальная справа налево; Подземная цепь взрывов | One |
| 25 | Страж Разлома / greatblade, crown, shield | Радиальная из центра к краям; Атака по линии; Погоня за следами | Below 50%: second phase |
| 30 | Вестник Разлома / suspended crystal, broken halo, orbit pillars | Радиальная от краёв к центру; Погоня за следами; Подземная цепь взрывов | Below 66% and 33%: second/third phases |

## Exact mechanical contracts

- [Навесная атака](https://chatgpt.com/space/page_de32ca7b52e88191bde9b0e9d9b9f1db): a real
  arcing projectile travels during the fixed landing-circle warning. An occupied
  landing deals one hit and leaves no second trap, including a parried or
  invulnerable contact. An empty landing arms a visible trap; its first subsequent
  entry deals one hit and consumes it. The delegated starting trap lifetime is 8s.
- [Атака по линии](https://chatgpt.com/space/page_c8b3c7dc5378819193fa8f4237c1a319), including its
  2026-10-03 update: the complete rectangle appears immediately and stays fixed.
  Preparation fill and actual beam front both travel at `reach / windup`. The
  active beam remains connected to the monster, and its entire reached tail
  deals DPS while occupied. Active duration equals preparation duration, with
  no extra full-length hold; the attack ends as its front reaches the end.
- [Радиальная атака](https://chatgpt.com/space/page_ce4118ce9c388191bd50b8243720e0ec): the full
  sector appears from the beginning. Preview and continuous active rays follow
  exactly the same angular route/speed, each anchored to the monster along its
  full length. Single rays traverse the full sector left→right or right→left;
  dual rays traverse half of it centre→edges or edges→centre. Each dual ray uses
  half the single-ray angular speed. Coincident dual rays count union exposure,
  avoiding accidental duplicate damage at the centre.
- [Взрыв вокруг](https://chatgpt.com/space/page_89d3c121b07c81919f5f417723ca5b77): a full fixed
  circle surrounds the monster throughout preparation. One instantaneous hit
  occurs at preparation end. The visual aftermath is harmless; no trap remains.
- [Подземная цепь взрывов](https://chatgpt.com/space/page_f828c62477008191917367abc999f7f8): points
  are selected when the cast begins, then appear sequentially. Every fixed small
  circle has its own countdown and instantaneous explosion. Exploded circles
  disappear while subsequent ones continue preparing. Starting balance uses
  seven points over a 6m region with 0.35s spacing; it does not track the hero.
- [Погоня за следами](https://chatgpt.com/space/page_c422cd6b535c8191a80682b62bb43a9c): exactly
  six sequential markers sample the real current hero position. Each stays fixed
  after appearing, has an independent countdown, and explodes once. A stopped
  hero can therefore receive six hits; continued movement leaves the danger behind.
- [Сметающий рывок](https://chatgpt.com/space/page_8d1e2a49cd4c8191981827ef5bace786): the full
  corridor is locked toward the hero at preparation start. The strip itself
  never causes damage. Only an actual collision-resolved moving-body segment
  can hit, once per dash, and carry the hero ahead of the body until dash end.
  Player motion goes through `move_and_collide`; walls release carry instead
  of allowing a teleport through terrain. Death, owner removal, terminal state,
  cancellation and dash end also release it. Ordinary input flags are not changed.

The radial HTML widget computes the same per-ray speed for its single and dual
variants. This conflicts with the Page's explicit requirement that dual rays be
slower. Production follows the prose: dual angular speed is multiplied by 0.5;
preview and active speed still match within every variant. Widget units and
slider defaults are illustrative, not fixed balancing requirements.

Line/radial `damage` means damage per second of actual exposure; other patterns
use damage per independent contact/explosion. The first continuous contact deals
its actual first dose immediately, subsequent doses use fixed 0.1s exposure
cadence, and exit/end flushes the residual. This avoids a parry/counter on every
physics tick without borrowing future damage for a brief touch. Line arrival and radial swept
exposure account for a physics frame crossing the front/ray, so fast rays cannot
skip a stationary player between samples. Ground attacks use the shared terrain
connectivity rules. Lobs and underground markers use the established terrain
independent XZ rule. All damage reaches the production player health receiver,
preserving shield overflow absorption, actual shield damage reflection, no
reflection lifesteal, and the shared slow stacking formula.

Profiles and numeric balance live in `scripts/bosses/boss_encounter_catalog.gd`.
Later phases multiply preparation/recovery and marker spacing by 0.88 or 0.76,
and damage by 1.12 or 1.24. Radial angular speed scales inversely to preparation,
with preview/active still identical. These are initial first-version values;
there is no claim of an established 2–3 hour progression balance/playtest.

Bosses have no basic contact attack and cannot be stunned or have preparation
interrupted by a hit. Slow affects approach/dash movement without interrupting
the attack clock. Death cancels every pending warning, continuous ray, trap,
marker and carry, then emits `defeated(self)` and `EventBus.boss_defeated` once.
The boss grants no XP/resources/relic locally; the run coordinator awards exactly
one level and completes the boss night.

## Art and integration

All six models are original code-native voxel geometry; no external assets were
downloaded. `tools/generate_boss_models.py` exports native `.tscn` models and
reviewable adjacent `.source.json`, including canonical attack assignments.
Regenerate with `python tools/generate_boss_models.py`. Units are metres, forward
is -Z, and the model pivot is at the feet. Each model has its own AnimationPlayer
idle/move/attack/death clips. Beam/channel poses hold through the active interval;
lob animations release early during the flight warning, and the sweep braces its
body before charging. Attack pose is sought from the real preparation/active/
recovery clock, rather than interrupted by taking a hit.

Full warning boundaries use a restrained fill and bright edge. Line progress and
radial rays share the exact geometry/functions used for damage. Active connected
rays gain a brighter raised body; lob flight is a moving crystal above the terrain;
armed traps retain a low crystal and a distinct persistent boundary. Instant
explosions have a brief harmless visual aftermath. Each boss keeps its own palette.

Public integration remains `configure(stage: int, target: Node3D)` on the six
`scenes/bosses/boss_0N_*.tscn`. Spawn at terrain height + `half_height` (1.5m).
`display_name`, `current_health`, `max_health`, `boss_health_changed`,
`phase_changed` and `attack_started` support the existing HUD. The legacy Gorgon
scene/projectile primitive remains for compatibility, outside the live catalogue.
No global timer coroutine survives an attack owner; hazards use finite owned
physics state. Marker resources contain only their fixed position/countdown and
visual node. Their count is bounded at seven/six rather than spawning a crowd.

Primary art references inform readability, not the canonical mechanics:
[Riot: Clarity in League](https://www.leagueoflegends.com/en-us/news/dev/clarity-in-league/),
[Riot Art Education: VFX](https://www.riotgames.com/en/artedu/visual-effects), and
[Supergiant: Hades updates](https://www.supergiantgames.com/blog/hades-updates/).

## Verification and evidence limits

The focused GUT config must use `dirs: []` and
`tests: ["res://tests/unit/test_siege_bosses.gd"]`; `-gtest` alone also loads the
configured directories. The suite checks the seven live mechanics/four radial
variants, original articulated models, warning safety, independent marker timing,
real current-position sampling, line reached-tail DPS, low-frame radial exposure,
trap entry versus occupied landing, moving-body-only contact, terrain rules,
single defeat/reward ownership, stun immunity, and owner-death cancellation.
Player carry wall/owner/death/terminal checks live in `test_player_enemy_carry.gd`.

`python tools/capture_bosses.py` records all 16 profile actions, two late-phase
samples and two empty-landing/moving-trail cases using production actors, damage receiver, camera/FOV and day/night
LightingProfile. It checks instantaneous damage, expected continuous exposure
and six independent trail explosions rather than assuming every attack hits once.
PNG warnings/impacts, MP4, gameplay JSON, log and source/file SHA manifest are
written under `screenshots_debug/bosses/capture/`.

The helper's total deadline is 305s (render ≤240s, encode ≤45s, metadata ≤20s),
with owned-process termination and explicit success marker requirements. The
flat review arena does not demonstrate final terrain/crowd readability, hardware
performance or a full-length playthrough. A source/file hash establishes
freshness/integrity, not an artistic verdict. Historical pre-correction recordings
do not verify this canonical implementation; fresh engine evidence is required.

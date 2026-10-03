# Warrior first version: six boss encounters

Bosses enter on waves 5, 10, 15, 20, 25 and 30. Their shared controller commits to a
visible footprint, preparation, impact and recovery. There is no basic contact
attack. Hits, parry and stun cannot cancel preparation; movement slows affect
approach and charge travel without altering the preparation clock. A defeated
boss cancels all its outstanding hazards/projectiles, emits `defeated(self)` and
`EventBus.boss_defeated` once, and provides no XP/resources/relic itself. The run
coordinator awards exactly one level and completes the boss night.

| Wave | Boss / silhouette | Committed attacks | Later phases |
| --- | --- | --- | --- |
| 5 | Страж кургана / stone fists, plated crest | Broad fist sector; marked stone collapse circle | One phase; 1.4–1.7s warnings |
| 10 | Горгон-Топтатель / horns, tusks, back plates | Straight charge corridor; close sector shockwave | One phase; 1.1–1.25s warnings |
| 15 | Пепельный оракул / hood, staff and censer | Three marked projectile paths; cross eruption; marked ember circle applying slow | One phase; 1–1.25s warnings |
| 20 | Мортирный колосс / boiler and twin cannons | Targeted mortar circle; straight cannon lane; close boiler burst | One phase; 1–1.2s warnings |
| 25 | Страж разлома / greatblade, crown and shield | Blade sector; five projectile paths; 250° sweep with safe rear wedge | Below 50% health: shorter warnings/recovery, faster bolts and stronger impacts |
| 30 | Вестник разлома / suspended crystal, broken halo and orbit pillars | Marked slowing circle; seven projectile paths; marked cross preceded by a clearance-checked reposition | Below 66% and 33% health: two further steps of warning/recovery and projectile acceleration |

These are initial values for a playable first version, not a claim that the final
2–3 hour progression target has been established through player testing. Profiles
and thresholds live in `scripts/bosses/boss_encounter_catalog.gd`. Each later
phase multiplies preparation/recovery by 0.88 or 0.76 and damage/projectile speed
by 1.12 or 1.24. Ground attacks respect the shared terrain connectivity rules;
marked aerial attacks use the existing terrain-independent rule. Projectiles
respect terrain height transitions and test their travelled segment for hits.
Each hazard/fan release consumes at most one player contact, including a parried
or invulnerable contact. Neighbouring fan lanes share a contact ledger so their
close-range overlap cannot multiply damage. Debuffs apply only after an actual
damaging contact. Projectile travel is bounded by the marked lane's range.

## Art and timing contract

All six models are original code-native voxel geometry. No external model,
texture or animation was downloaded. `tools/generate_boss_models.py` contains the
editable part and animation definitions, exports a reviewable `.source.json`
beside each native `.tscn`, and exports each encounter scene. Regenerate with:

```powershell
python tools/generate_boss_models.py
```

The root pivot is at the feet, metres are the unit, and forward is -Z. Each model
has an `AnimationPlayer` with its own idle/move/attack/death clips. The controller
seeks attack clips using the actual attack clock: 0–65% preparation, 65–80%
impact, 80–100% recovery. Taking a hit restores this pose rather than restarting
the attack. The shared warning language uses restrained transparent fill and a
bright exact boundary; each boss has a distinct palette and footprint/pattern.
Impact intensity appears only when damage becomes active. Projectile direction
is communicated before release by the marked paths and after release by an
elongated moving crystal.

Primary references were used for principles, not copied assets or exact combat:

- [Riot: Clarity in League](https://www.leagueoflegends.com/en-us/news/dev/clarity-in-league/)
  discusses identifying/reacting to gameplay, visual attention hierarchy,
  silhouettes, consistent effect/hitbox relationships and stronger contrast for
  dangerous dodgeable attacks. The inference applied here is to lock the warning
  footprint and make the active interval visually stronger.
- [Riot Art Education: Visual Effects](https://www.riotgames.com/en/artedu/visual-effects)
  connects thematic effects with restraint and gameplay clarity. Each encounter
  therefore keeps one palette and a modest number of simultaneous attacks.
- [Supergiant: Hades updates](https://www.supergiantgames.com/blog/hades-updates/)
  documents clearer Minotaur whirlwind preparation and charging sound pitch
  matching duration. The inference applied here is that faster late encounters
  still need a distinct committed warning and recovery, rather than surprise
  contact attacks.
- [Minecraft Dungeons: New Tower rotations](https://www.minecraft.net/en-us/article/dungeons--new-tower-rotations)
  describes smoothing floor difficulty and changing boss pairings for variety.
  [Adjusting endgame](https://www.minecraft.net/en-us/article/dungeons-dev-blog---adjusting-endgame)
  discusses less steep late progression. The applied inference is to teach a
  small vocabulary of circles/sectors/lanes early, then combine projectile counts,
  safe wedges and phase tempo later.

## Integration and verification

Instantiate the relevant `scenes/bosses/boss_0N_*.tscn`, call
`configure(stage: int, target: Node3D)`, add it to the world and position its body
at terrain height + `half_height` (1.5m). `display_name`, `current_health`,
`max_health` and `boss_health_changed(current,max)` support the boss HUD.
`phase_changed(phase)` and `attack_started(title,warning)` are optional presentation
signals. The old `boss_gorgon.tscn` is retained for compatibility with the ability
viewer; live waves use the six new scenes.

Run only the boss suite using a temporary GUT JSON config with `dirs: []` and
`tests: ["res://tests/unit/test_siege_bosses.gd"]` and `-gconfig=<absolute-path>`.
`-gtest` adds a test to configured directories, so it does not isolate the suite.
The tests cover all six models/action clips, warning safety, repeated hit guards,
ground cliffs versus marked aerial attacks, fast projectile segments, stun/hit
immunity, phase tempo, single defeat/no local reward, footprint boundaries and
the production player receiver without a Hurtbox child.

```powershell
$env:CUBE_SIEGE_TEST_PROFILE = 'user://test_profile/'
python tools/capture_bosses.py
```

The capture wrapper has a 305-second total deadline: rendering up to 240 seconds,
encoding up to 45 seconds and metadata up to 20 seconds. It stops only its launched
process on timeout, and requires an explicit
successful gameplay marker with no script errors. It produces PNG warning/impact
frames, MP4, actual health-loss checks, log and source/file SHA-256 manifest in
`screenshots_debug/bosses/capture/`. It uses the production actors, attack clocks,
camera offset/FOV and `LightingProfile` in a flat review arena; it does not claim
to verify final generated terrain, crowd readability, player balance or real-time
performance. Fixed-FPS recording follows
[Godot's Movie Maker](https://docs.godotengine.org/en/4.6/tutorials/animation/creating_movies.html).

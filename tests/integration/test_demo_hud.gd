extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/hud.tscn")

func _player() -> PlayerPrototype:
	var actor: PlayerPrototype = PLAYER_SCENE.instantiate() as PlayerPrototype
	add_child_autoqfree(actor)
	actor.set_physics_process(false)
	actor.max_health = 100.0
	actor.current_health = 50.0
	return actor

func test_regeneration_sources_stack_refresh_and_expire_independently() -> void:
	var actor: PlayerPrototype = _player()
	actor.status_effects.refresh_regeneration(101, 5.0, 3.0)
	actor.status_effects.refresh_regeneration(102, 3.0, 6.0)
	actor.status_effects.refresh_regeneration(101, 5.0, 3.0)
	assert_eq(actor.status_effects.regeneration_per_second(), 8.0, "Refreshing the same fire must not duplicate its contribution")
	actor.status_effects.advance(3.0)
	assert_almost_eq(actor.current_health, 74.0, 0.001)
	assert_eq(actor.status_effects.regeneration_per_second(), 3.0)
	actor.status_effects.advance(4.0)
	assert_almost_eq(actor.current_health, 83.0, 0.001, "Oversized delta only heals until the remaining source expires")
	assert_eq(actor.status_effects.regeneration_per_second(), 0.0)
	assert_true(actor.status_effects.get_active_effects().is_empty())

func test_aura_removal_max_health_and_death() -> void:
	var actor: PlayerPrototype = _player()
	actor.current_health = 99.0
	actor.status_effects.refresh_regeneration(1, 3.0)
	actor.status_effects.advance(0.5)
	assert_eq(actor.current_health, 100.0, "Regeneration cannot exceed maximum HP")
	actor.status_effects.remove_source(1)
	assert_eq(actor.status_effects.regeneration_per_second(), 0.0)
	actor.current_health = 0.0
	actor.status_effects.refresh_regeneration(1, 3.0)
	actor.status_effects.advance(0.5)
	assert_eq(actor.current_health, 0.0, "A fire cannot resurrect a dead player")
	assert_true(actor.status_effects.get_active_effects().is_empty())

func test_hud_statuses_show_true_timers_and_disappear_with_gameplay_state() -> void:
	var actor: PlayerPrototype = _player()
	actor.health.trigger_parry()
	actor.health.update_timers(0.25)
	var hud: CanvasLayer = HUD_SCENE.instantiate() as CanvasLayer
	hud.player_path = NodePath("../Player")
	add_child_autoqfree(hud)
	var bar: HUDStatusBar = hud.get_node("Margin/StatusEffects") as HUDStatusBar
	bar.refresh()
	assert_true(bar.visible)
	assert_eq(bar.get_child_count(), 1)
	var slot: HUDStatusSlot = bar.get_child(0) as HUDStatusSlot
	assert_almost_eq(slot.effect.remaining_ratio(), 0.5, 0.001, "The clock displays elapsed gameplay time, not a UI-owned timer")
	assert_eq(slot.effect.time_text(), "0.3с")
	assert_true(slot.tooltip_text.contains("Парирование"))
	actor.health.update_timers(0.3)
	bar.refresh()
	assert_false(bar.visible)
	assert_eq(bar.get_child_count(), 0)

func test_tooltips_use_current_upgraded_damage_and_actual_prefab_stats() -> void:
	var actor: PlayerPrototype = _player()
	actor.attack_damage = 50.0
	actor.special_damage = 120.0
	actor.is_dueling = true
	var sword: String = HUDAbilityDetails.describe(actor, 0)
	assert_true(sword.contains("Урон: 50"), "Base damage remains truthful for enemies outside the duel")
	assert_true(sword.contains("Урон по цели дуэли: 60"), "Duel damage and run upgrades must appear together")
	var cleave: String = HUDAbilityDetails.describe(actor, 1)
	assert_true(cleave.contains("Урон: 120"))
	assert_true(cleave.contains("Урон по цели дуэли: 144"))
	assert_true(cleave.contains("Радиус: 3.8"))
	actor.is_dueling = false
	actor.current_class = PlayerPrototype.CharacterClass.ARCHER
	assert_true(HUDAbilityDetails.describe(actor, 0).contains("Предельная дальность: 70"))
	assert_true(HUDAbilityDetails.describe(actor, 1).contains("Целей: 6"))
	actor.current_class = PlayerPrototype.CharacterClass.ENGINEER
	var turret: String = HUDAbilityDetails.describe(actor, 1)
	assert_true(turret.contains("Интервал выстрелов: 0.8"))
	assert_true(turret.contains("Длительность: 12"))
	var mine: String = HUDAbilityDetails.describe(actor, 3)
	assert_true(mine.contains("Урон взрыва: 250"))
	assert_true(mine.contains("Радиус взрыва: 4.5"))
	assert_true(HUDAbilityDetails.describe(actor, 4).contains("Длительность горения: 5"))

func test_talent_effect_snapshots_do_not_duplicate_hot_blood_healing() -> void:
	var actor: PlayerPrototype = _player()
	actor.talents.build().selected_talents.assign(["hot_blood", "dismemberment"])
	actor.talents._on_parry(true)
	actor.talents._dismember(actor.global_position)
	actor.talents.advance(1.0)
	assert_almost_eq(actor.current_health, 55.0, 0.001)
	var effects: Array[PlayerStatusEffect] = actor.status_effects.get_active_effects()
	actor.status_effects.get_active_effects()
	actor.status_effects.advance(1.0)
	assert_almost_eq(actor.current_health, 55.0, 0.001, "Presentation snapshots and aura advancement must never heal Hot Blood twice")
	var hot_blood: PlayerStatusEffect = _find_effect(effects, &"hot_blood")
	assert_not_null(hot_blood)
	assert_almost_eq(hot_blood.remaining_ratio(), 2.0 / 3.0, 0.001)
	var morale: PlayerStatusEffect = _find_effect(effects, &"morale")
	assert_almost_eq(morale.remaining_ratio(), 0.75, 0.001)
	assert_true(morale.description.contains("15%"), morale.description)

func test_counter_slow_stun_and_shield_clocks_keep_started_durations() -> void:
	var actor: PlayerPrototype = _player()
	actor.talents.build().selected_talents.assign(["counterattack"])
	actor.talents.build().specializations["parry_window"] = 2
	actor.abilities.perform_parry(actor)
	actor.health.update_timers(0.435)
	# A free respec may alter future parries, but cannot rewrite an active clock.
	actor.talents.build().specializations["parry_window"] = 5
	actor.talents.statuses.apply_slow("boss-web", 0.4, 2.0)
	actor.talents.statuses.apply_stun("impact", 2.0)
	actor.talents.statuses.advance(1.0)
	actor.health.shield_health = 12.0
	var effects: Array[PlayerStatusEffect] = actor.status_effects.get_active_effects()
	var counter: PlayerStatusEffect = _find_effect(effects, &"parry")
	assert_eq(counter.title, "Контратака")
	assert_almost_eq(counter.remaining_ratio(), 0.5, 0.001)
	var slow: PlayerStatusEffect = _find_effect(effects, &"slow:boss-web")
	assert_almost_eq(slow.remaining_ratio(), 0.5, 0.001)
	assert_true(slow.description.contains("40%"), slow.description)
	var stun: PlayerStatusEffect = _find_effect(effects, &"stun:impact")
	assert_almost_eq(stun.remaining_ratio(), 0.5, 0.001)
	assert_eq(_find_effect(effects, &"shield").time_text(), "12HP")
	actor.talents.statuses.apply_slow("boss-web", 0.4, 4.0)
	assert_almost_eq(_find_effect(actor.status_effects.get_active_effects(), &"slow:boss-web").remaining_ratio(), 1.0, 0.001, "Refreshing an independent source restarts its own clock")

func test_ability_details_follow_canonical_talents_and_specializations() -> void:
	var actor: PlayerPrototype = _player()
	actor.talents.build().selected_talents.assign(["counterattack", "wide_lunge", "whirlwind_cleave", "perfect_dash", "tempered_blade", "hot_blood"])
	actor.talents.build().specializations = {"attack_speed": 2, "cleave_radius": 2, "cleave_cooldown": 2, "lunge_distance": 1, "parry_window": 2, "hot_blood_healing": 2}
	actor.talents.refresh_stats()
	assert_true(HUDAbilityDetails.describe(actor, 0).contains("Перезарядка: 0.3 с"))
	var cleave: String = HUDAbilityDetails.describe(actor, 1)
	assert_true(cleave.contains("Радиус: 4.18 м"))
	assert_true(cleave.contains("Перезарядка: 3.45 с"))
	assert_true(cleave.contains("Сектор: 360"))
	assert_true(cleave.contains("Дальность выпада: 2.92 м"))
	assert_true(cleave.contains("Вихрь поражает на всей траектории"))
	assert_true(HUDAbilityDetails.describe(actor, 2).contains("Неуязвимость"))
	var parry: String = HUDAbilityDetails.describe(actor, 3)
	assert_true(parry.contains("Защитное окно: 0.87 с"))
	assert_true(parry.contains("Лечение при успехе: 5.8 HP/с"))
	actor.talents.build().selected_talents.erase("whirlwind_cleave")
	assert_true(HUDAbilityDetails.describe(actor, 1).contains("во время движения урона нет"))

func test_death_shrink_never_leaves_a_singular_body_transform() -> void:
	var enemy: EnemyBase = preload("res://scenes/enemy_dummy.tscn").instantiate() as EnemyBase
	add_child_autoqfree(enemy)
	var final_basis: Array[float] = []
	enemy.tree_exiting.connect(func() -> void: final_basis.append(enemy.global_basis.determinant()))
	enemy.die()
	await wait_seconds(1.3)
	assert_false(is_instance_valid(enemy), "Death still removes the body after its presentation completes")
	assert_eq(final_basis.size(), 1)
	if final_basis.size() == 1:
		assert_gt(absf(final_basis[0]), 0.0, "Physics and animated children must be able to invert the dying body's final transform")

func test_boss_pending_caption_stays_inside_the_day_night_panel() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child_autoqfree(viewport)
	var hud: CanvasLayer = HUD_SCENE.instantiate() as CanvasLayer
	viewport.add_child(hud)
	var cycle: DayNightCycle = DayNightCycle.new()
	add_child_autoqfree(cycle)
	cycle.set_process(false)
	cycle.boss_pending = true
	hud.day_night_cycle = cycle
	hud._update_day_night_label(0.0, true, 5)
	await get_tree().process_frame
	await get_tree().process_frame
	var top: Control = hud.get_node("Margin/TopCenter") as Control
	var resources: Control = hud.get_node("Margin/Resources") as Control
	assert_eq(top.size, Vector2(360, 56))
	assert_false(top.get_rect().intersects(resources.get_rect()))
	assert_eq(hud.day_night_timer_label.text, "ПОБЕДИТЕ\nБОССА")
	hud._update_day_night_label(60.0, false, 6)
	assert_eq(hud.day_night_timer_label.get_theme_font_size("font_size"), 14)

func test_alive_terminal_run_clears_snapshots_and_rejects_late_healing_sources() -> void:
	var actor: PlayerPrototype = _player()
	actor.talents.build().selected_talents.assign(["hot_blood", "dismemberment"])
	actor.health.trigger_parry()
	actor.talents._on_parry(true)
	actor.talents._dismember(actor.global_position)
	actor.status_effects.refresh_regeneration(1, 3.0, 2.0)
	var hud: CanvasLayer = HUD_SCENE.instantiate() as CanvasLayer
	hud.player_path = NodePath("../Player")
	add_child_autoqfree(hud)
	hud.status_bar.refresh()
	assert_true(hud.status_bar.visible)
	assert_gt(hud.status_bar.get_child_count(), 1)
	actor.status_effects.finish_run()
	actor.status_effects.finish_run() # Save retry can halt the same finished actor twice.
	hud.status_bar.refresh()
	assert_false(hud.status_bar.visible, "A living extracted hero must not display frozen healing/parry clocks")
	assert_eq(hud.status_bar.get_child_count(), 0)
	actor.status_effects.refresh_regeneration(2, 20.0, 5.0)
	actor.status_effects.advance(1.0)
	assert_eq(actor.status_effects.regeneration_per_second(), 0.0)
	assert_almost_eq(actor.current_health, 50.0, 0.001)
	assert_true(actor.status_effects.get_active_effects().is_empty())

func test_effect_setup_restarts_for_new_actor_and_sandbox_needs_no_run_build() -> void:
	var first: PlayerPrototype = _player()
	var effects: PlayerStatusEffects = first.status_effects
	effects.refresh_regeneration(1, 3.0, 2.0)
	effects.finish_run()
	var sandbox: PlayerPrototype = _player()
	sandbox.progression.run_build.end_run()
	effects.setup(sandbox)
	effects.refresh_regeneration(2, 3.0, 2.0)
	assert_false(effects.get_active_effects().is_empty(), "Standalone regeneration is independent of warrior run-build state")
	effects.advance(1.0)
	assert_almost_eq(sandbox.current_health, 53.0, 0.001)
	assert_almost_eq(first.current_health, 50.0, 0.001, "Rebinding must not heal the previous finished actor")

func _find_effect(effects: Array[PlayerStatusEffect], effect_id: StringName) -> PlayerStatusEffect:
	for effect: PlayerStatusEffect in effects:
		if effect.id == effect_id:
			return effect
	return null

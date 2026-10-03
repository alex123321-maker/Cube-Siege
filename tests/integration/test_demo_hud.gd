extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/hud.tscn")

func _player() -> PlayerPrototype:
	var actor: PlayerPrototype = PLAYER_SCENE.instantiate() as PlayerPrototype
	add_child_autoqfree(actor)
	actor.set_physics_process(false)
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
	assert_true(sword.contains("Урон: 60"), "Duel damage and run upgrades must appear together")
	var cleave: String = HUDAbilityDetails.describe(actor, 1)
	assert_true(cleave.contains("Урон: 144"))
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

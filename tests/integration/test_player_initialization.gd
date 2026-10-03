extends GutTest

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const CharacterDefinition = preload("res://scripts/resources/character_definition.gd")
var _snapshot: Dictionary = {}

func before_each() -> void:
	var save: Node = get_node("/root/SaveManager")
	_snapshot = save.snapshot_state()
	save.reset_to_defaults()

func after_each() -> void:
	get_node("/root/SaveManager").restore_state(_snapshot)

func test_player_initialization_defaults_warrior() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	
	assert_not_null(player.movement)
	assert_not_null(player.health)
	assert_not_null(player.progression)
	assert_not_null(player.aim)
	assert_not_null(player.interaction)
	assert_not_null(player.presentation)
	assert_not_null(player.combat)
	assert_not_null(player.abilities)
	assert_not_null(player.orientation)
	
	assert_eq(player.current_class, player.CharacterClass.WARRIOR)
	assert_eq(player.max_health, 105.0)
	assert_eq(player.current_health, 105.0)
	assert_almost_eq(player.speed, 7.14, 0.0001)
	assert_eq(player.attack_damage, 25.75)
	assert_eq(player.special_damage, 60.0)
	assert_eq(player.dash_speed, 18.0)
	assert_eq(player.dash_cooldown, 3.0)

	# Interaction sensor check
	var sensor = player.get_node_or_null("InteractionSensor") as Area3D
	assert_not_null(sensor, "Player scene must contain InteractionSensor Area3D")
	assert_eq(sensor.collision_mask, InteractionZone.INTERACTION_LAYER, "InteractionSensor mask must be 32 (Layer 6: InteractionZone)")

func test_player_set_class_archer_preserves_baseline_stats() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	
	player.set_class(player.CharacterClass.ARCHER, false)
	assert_eq(player.current_class, player.CharacterClass.ARCHER)
	assert_eq(player.max_health, 105.0)
	assert_almost_eq(player.speed, 7.14, 0.0001)
	assert_eq(player.attack_damage, 25.75)
	assert_eq(player.special_damage, 60.0)

func test_player_set_class_engineer_preserves_baseline_stats() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	
	player.set_class(player.CharacterClass.ENGINEER, false)
	assert_eq(player.current_class, player.CharacterClass.ENGINEER)
	assert_eq(player.max_health, 105.0)
	assert_almost_eq(player.speed, 7.14, 0.0001)
	assert_eq(player.attack_damage, 25.75)
	assert_eq(player.special_damage, 60.0)

func test_mastery_multipliers_applied_and_not_wiped_by_set_class() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)

	# Manually invoke apply_mastery_stats with known base stats
	player.attack_damage = 25.0
	player.max_health = 100.0
	player.current_health = 100.0
	player.speed = 7.0
	
	var roster = get_node_or_null("/root/RosterManager")
	if roster and roster.slots.size() > 0:
		roster.slots[0].unlocked_talents = WarriorTalentCatalog.TALENT_IDS.duplicate()
		player.apply_mastery_stats()
		assert_almost_eq(player.max_health, 115.0, 0.01)
		assert_almost_eq(player.attack_damage, 27.25, 0.01)
		assert_eq(player.special_damage, 60.0, "Permanent Bloodlust bonuses belong to basic attacks only")

		# Calling set_class must NOT overwrite mastery bonuses
		player.set_class(player.CharacterClass.ARCHER, false)
		assert_almost_eq(player.max_health, 115.0, 0.01)
		assert_almost_eq(player.attack_damage, 27.25, 0.01)

		# Reset slot
		roster.slots[0].unlocked_talents = WarriorTalentCatalog.STARTER_IDS.duplicate()

func test_player_root_retransmits_progression_signals() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)

	var xp_emitted: Array[Dictionary] = []
	var lvl_emitted: Array[int] = []

	player.xp_changed.connect(func(cur, mx, lvl):
		xp_emitted.append({"current": cur, "max": mx, "level": lvl})
	)
	player.level_up_reached.connect(func(lvl):
		lvl_emitted.append(lvl)
	)

	# Add XP: base xp_to_next_level is 100. Adding 50 XP triggers xp_changed
	player.add_xp(50.0)
	assert_eq(xp_emitted.size(), 1, "Player.xp_changed root signal must be emitted upon gaining XP")
	assert_almost_eq(xp_emitted[0].current, 50.0, 0.01)
	assert_eq(lvl_emitted.size(), 0, "Level up should not have triggered yet")

	# Add 100 XP more: triggers level up and xp_changed
	player.add_xp(100.0)
	assert_gt(xp_emitted.size(), 1, "Player.xp_changed must be emitted on level up as well")
	assert_eq(lvl_emitted.size(), 1, "Player.level_up_reached root signal must be emitted on level up")
	assert_eq(lvl_emitted[0], 2, "Level reached must be 2")


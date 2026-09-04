extends GutTest

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const CharacterDefinition = preload("res://scripts/resources/character_definition.gd")

func test_player_initialization_defaults_warrior() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	
	assert_not_null(player.movement)
	assert_not_null(player.health)
	assert_not_null(player.progression)
	assert_not_null(player.aim)
	assert_not_null(player.interaction)
	assert_not_null(player.presentation)
	
	assert_eq(player.current_class, player.CharacterClass.WARRIOR)
	assert_eq(player.max_health, 100.0)
	assert_eq(player.current_health, 100.0)
	assert_eq(player.speed, 7.0)
	assert_eq(player.attack_damage, 25.0)
	assert_eq(player.special_damage, 60.0)
	assert_eq(player.dash_speed, 18.0)
	assert_eq(player.dash_cooldown, 3.0)

	# Interaction sensor check
	var sensor = player.get_node_or_null("InteractionSensor") as Area3D
	assert_not_null(sensor, "Player scene must contain InteractionSensor Area3D")
	assert_false(sensor.monitorable, "InteractionSensor should not be monitorable")
	assert_eq(sensor.collision_mask, 9, "InteractionSensor mask must be 9 (layers 1 and 4)")

func test_player_set_class_archer_preserves_baseline_stats() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	
	player.set_class(player.CharacterClass.ARCHER, false)
	assert_eq(player.current_class, player.CharacterClass.ARCHER)
	assert_eq(player.max_health, 100.0)
	assert_eq(player.speed, 7.0)
	assert_eq(player.attack_damage, 25.0)
	assert_eq(player.special_damage, 60.0)

func test_player_set_class_engineer_preserves_baseline_stats() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	
	player.set_class(player.CharacterClass.ENGINEER, false)
	assert_eq(player.current_class, player.CharacterClass.ENGINEER)
	assert_eq(player.max_health, 100.0)
	assert_eq(player.speed, 7.0)
	assert_eq(player.attack_damage, 25.0)
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
		roster.slots[0].survival = 5 # +20 max HP bonus
		roster.slots[0].bloodlust = 5 # +10% damage
		player.apply_mastery_stats()
		assert_almost_eq(player.max_health, 120.0, 0.01)
		assert_almost_eq(player.attack_damage, 27.5, 0.01)

		# Calling set_class must NOT overwrite mastery bonuses
		player.set_class(player.CharacterClass.ARCHER, false)
		assert_almost_eq(player.max_health, 120.0, 0.01)
		assert_almost_eq(player.attack_damage, 27.5, 0.01)

		# Reset slot
		roster.slots[0].survival = 0
		roster.slots[0].bloodlust = 0


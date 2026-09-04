extends GutTest

const PLAYER_SCENE = preload("res://scenes/player.tscn")

func test_player_takes_damage() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	watch_signals(player)

	var initial_health: float = player.current_health
	player.take_damage(30.0)
	
	assert_eq(player.current_health, initial_health - 30.0)
	assert_signal_emitted_with_parameters(player, "health_changed", [initial_health - 30.0, player.max_health])

func test_player_parry_negates_damage() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	watch_signals(player)

	player.is_parrying = true
	var initial_health: float = player.current_health
	player.take_damage(40.0)

	assert_eq(player.current_health, initial_health, "Parry must negate incoming damage")
	assert_signal_emitted_with_parameters(player, "parry_triggered", [true])

func test_player_lethal_damage_triggers_death() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	watch_signals(player)

	player.take_damage(9999.0)
	assert_eq(player.current_health, 0.0)
	assert_signal_emitted(player, "player_died")

func test_player_healing() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	watch_signals(player)

	player.take_damage(50.0)
	var damaged_health: float = player.current_health
	
	player.heal(20.0)
	assert_eq(player.current_health, damaged_health + 20.0)

	# Overheal test
	player.heal(500.0)
	assert_eq(player.current_health, player.max_health, "Healing must not exceed max health")

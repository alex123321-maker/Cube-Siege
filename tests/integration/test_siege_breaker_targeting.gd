extends GutTest

const SIEGE_BREAKER_SCENE = preload("res://scenes/enemies/siege_breaker.tscn")

func test_siege_breaker_targets_nearest_building() -> void:
	var breaker = SIEGE_BREAKER_SCENE.instantiate()
	add_child_autoqfree(breaker)
	breaker.global_position = Vector3(0, 0, 0)

	var b_near = Node3D.new()
	b_near.add_to_group("buildings")
	add_child_autoqfree(b_near)
	b_near.global_position = Vector3(5, 0, 0)

	var b_far = Node3D.new()
	b_far.add_to_group("buildings")
	add_child_autoqfree(b_far)
	b_far.global_position = Vector3(20, 0, 0)

	breaker.find_target()
	assert_eq(breaker.target_entity, b_near, "SiegeBreaker must target nearest building")

func test_siege_breaker_falls_back_to_player_without_buildings() -> void:
	var breaker = SIEGE_BREAKER_SCENE.instantiate()
	add_child_autoqfree(breaker)
	breaker.global_position = Vector3(0, 0, 0)

	var player = Node3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)
	player.global_position = Vector3(10, 0, 0)

	breaker.find_target()
	assert_eq(breaker.target_entity, player, "SiegeBreaker must target player when no buildings exist")

func test_siege_breaker_duel_locks_target() -> void:
	var breaker = SIEGE_BREAKER_SCENE.instantiate()
	add_child_autoqfree(breaker)

	var b = Node3D.new()
	b.add_to_group("buildings")
	add_child_autoqfree(b)
	b.global_position = Vector3(2, 0, 0)

	var dummy_warrior = Node3D.new()
	add_child_autoqfree(dummy_warrior)
	dummy_warrior.global_position = Vector3(15, 0, 0)

	breaker.start_duel(dummy_warrior)
	assert_true(breaker.is_in_duel)
	assert_eq(breaker.target_entity, dummy_warrior, "Duel must lock targeting to duel opponent")

	# Finding target during duel must keep opponent as target
	breaker.find_target()
	assert_eq(breaker.target_entity, dummy_warrior)

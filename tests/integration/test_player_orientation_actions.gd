extends GutTest

## Integration tests for PlayerOrientation action buffering, movement scaling, death cancellation, and building decoupling (Issue #11).

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const BuildingSystem = preload("res://scripts/building_system.gd")

func after_each() -> void:
	Input.action_release("move_up")
	Input.action_release("move_down")
	Input.action_release("move_left")
	Input.action_release("move_right")

func test_wasd_immediate_movement_and_does_not_rotate_body() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)

	# Ensure default forward orientation (North, -Z)
	player.orientation.setup(Vector3(0.0, 0.0, -1.0))
	assert_almost_eq(player.body_facing_direction.z, -1.0, 0.01)

	# Simulate WASD rightward movement (East, +X)
	Input.action_press("move_right")
	player.movement.process_movement(player, 0.016, null, 1.0)
	Input.action_release("move_right")

	# Movement velocity starts immediately
	assert_gt(player.velocity.x, 0.0, "WASD movement starts immediately")
	# Movement should not automatically rotate the body
	assert_almost_eq(player.body_facing_direction.z, -1.0, 0.01, "WASD movement should not rotate body facing")

func test_backward_and_strafe_speed_scaled_by_curve() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.orientation.setup(Vector3(0.0, 0.0, -1.0))

	# 1. Moving forward: 0° -> multiplier 1.0
	player.orientation.process_orientation(player, 0.016, Vector3(0, 0, -1), Vector3(0, 0, -1))
	assert_almost_eq(player.directional_speed_multiplier, 1.0, 0.02)
	Input.action_press("move_up")
	player.movement.process_movement(player, 0.016, null, player.directional_speed_multiplier)
	Input.action_release("move_up")
	assert_almost_eq(absf(player.velocity.z), player.speed * 1.0, 0.1)

	# 2. Moving backward: 180° -> multiplier 0.50
	player.orientation.process_orientation(player, 0.016, Vector3(0, 0, -1), Vector3(0, 0, 1))
	assert_almost_eq(player.directional_speed_multiplier, 0.50, 0.03)
	Input.action_press("move_down")
	player.movement.process_movement(player, 0.016, null, player.directional_speed_multiplier)
	Input.action_release("move_down")
	assert_almost_eq(absf(player.velocity.z), player.speed * 0.50, 0.1)

func test_attack_within_tolerance_executes_immediately() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.orientation.setup(Vector3(0.0, 0.0, -1.0))
	player.combat.attack_cooldown_timer = 0.0

	var state: Array[bool] = [false]
	var test_action = func(): state[0] = true

	# Action within tolerance executes immediately
	var immediate: bool = player.orientation.request_action("test_atk", test_action, true, deg_to_rad(20.0), Vector3(0, 0, -1))
	assert_true(immediate, "Action in front should execute immediately")
	assert_true(state[0], "Callback should have fired immediately")
	assert_false(player.orientation.is_action_pending(), "No action should be pending in buffer")

func test_buffered_action_turns_and_auto_executes() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.orientation.setup(Vector3(0.0, 0.0, -1.0))

	var state: Array[bool] = [false]
	var test_action = func(): state[0] = true

	# Request action behind (180° away)
	var target_behind = Vector3(0.0, 0.0, 1.0)
	var immediate: bool = player.orientation.request_action("test_behind", test_action, true, deg_to_rad(15.0), target_behind)
	assert_false(immediate, "Action behind should not execute immediately")
	assert_false(state[0], "Callback should not fire immediately")
	assert_true(player.orientation.is_action_pending(), "Action should be queued in pending buffer")

	# Simulate physics process frames until rotation completes
	var max_frames: int = 60
	while player.orientation.is_action_pending() and max_frames > 0:
		player.orientation.process_orientation(player, 0.016, target_behind, Vector3.ZERO)
		max_frames -= 1

	assert_false(player.orientation.is_action_pending(), "Pending action should be cleared after auto-execution")
	assert_true(state[0], "Buffered action should automatically execute once facing tolerance is reached")

func test_cancel_buffered_action_on_player_death() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.orientation.setup(Vector3(0.0, 0.0, -1.0))

	var state: Array[bool] = [false]
	var test_action = func(): state[0] = true

	# Buffer action behind
	player.orientation.request_action("test_death", test_action, true, deg_to_rad(15.0), Vector3(0, 0, 1))
	assert_true(player.orientation.is_action_pending())

	# Player takes lethal damage
	player.take_damage(9999.0)
	assert_false(player.orientation.is_action_pending(), "Pending action must be canceled upon player death")
	assert_false(state[0], "Canceled action must never execute")

func test_non_directional_actions_execute_without_facing_requirement() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.orientation.setup(Vector3(0.0, 0.0, -1.0))
	player.orientation.aim_direction = Vector3(0.0, 0.0, 1.0) # Aiming 180° behind

	# Warrior Utility: Parry stance does not require facing
	player.health.parry_cooldown_timer = 0.0
	player.perform_utility()

	assert_true(player.health.is_parrying, "Parry stance must activate immediately without waiting for turn")
	assert_false(player.orientation.is_action_pending(), "Utility must not be placed in orientation pending buffer")

func test_building_placement_without_facing_requirement() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.orientation.setup(Vector3(0.0, 0.0, -1.0))

	var building_system = BuildingSystem.new()
	add_child_autoqfree(building_system)

	# Give plenty of resources for placement
	building_system.wallet.add_resource(50, 50, 50)
	building_system.select_prefab(building_system.PrefabType.WOOD_WALL)

	var target_cell = Vector2i(4, 4)
	var target_pos = Vector3(4.0, 0.0, 4.0)

	# Even though player is facing North (-Z), building at (4, 4) succeeds immediately
	building_system.place_building(target_pos, target_cell, building_system.PrefabType.WOOD_WALL)
	assert_true(building_system.placed_buildings.has(target_cell), "Building should be placed immediately regardless of player body facing direction")
	assert_false(player.orientation.is_action_pending(), "Building system must never queue into player orientation buffer")

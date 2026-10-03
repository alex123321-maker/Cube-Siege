extends GutTest

## Unit tests for MonsterLocomotion (authoritative voxel step-up, cliff rejection, bounds, knockback).

const MonsterLocomotionScript = preload("res://scripts/movement/monster_locomotion.gd")
const BOSS_GORGON_SCENE = preload("res://scenes/enemies/boss_gorgon.tscn")
const ENEMY_DUMMY_SCENE = preload("res://scenes/enemy_dummy.tscn")
const SIEGE_BREAKER_SCENE = preload("res://scenes/enemies/siege_breaker.tscn")

func test_spawn_y_calculation_for_all_archetypes() -> void:
	var terrain_y: float = 3.0

	# Grunt / Skirmisher (root at center, feet at -0.9)
	var grunt = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(grunt)
	var grunt_spawn_y = MonsterLocomotion.calculate_spawn_y(terrain_y, grunt)
	assert_almost_eq(grunt_spawn_y, 3.9, 0.001, "Grunt spawn Y should place feet exactly at terrain surface")

	# Siege Breaker (root at center, feet at -1.2)
	var siege = SIEGE_BREAKER_SCENE.instantiate()
	add_child_autoqfree(siege)
	var siege_spawn_y = MonsterLocomotion.calculate_spawn_y(terrain_y, siege)
	assert_almost_eq(siege_spawn_y, 4.2, 0.001, "Siege Breaker spawn Y should place feet at terrain surface")

	# Gorgon (root at feet, feet at 0.0)
	var gorgon = BOSS_GORGON_SCENE.instantiate()
	add_child_autoqfree(gorgon)
	var gorgon_spawn_y = MonsterLocomotion.calculate_spawn_y(terrain_y, gorgon)
	assert_almost_eq(gorgon_spawn_y, 3.0, 0.001, "Gorgon spawn Y should place feet at terrain surface without 1.5m offset bug")

func test_boss_gorgon_and_grunt_vertical_bounds() -> void:
	var gorgon = BOSS_GORGON_SCENE.instantiate()
	add_child_autoqfree(gorgon)
	gorgon.global_position = Vector3(0, 0, 0)
	var g_bounds = MonsterLocomotion.get_body_vertical_bounds(gorgon)
	assert_almost_eq(g_bounds.x, 0.0, 0.01, "Gorgon feet bottom bound must be at Y=0.0 when root is at Y=0.0")
	assert_almost_eq(g_bounds.y, 3.0, 0.01, "Gorgon head top bound must be at Y=3.0")

	var grunt = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(grunt)
	grunt.global_position = Vector3(0, 0.9, 0)
	var m_bounds = MonsterLocomotion.get_body_vertical_bounds(grunt)
	assert_almost_eq(m_bounds.x, 0.0, 0.01, "Grunt feet bottom bound must be at Y=0.0 when root is at Y=0.9")
	assert_almost_eq(m_bounds.y, 1.8, 0.01, "Grunt head top bound must be at Y=1.8")

func test_locomotion_constants_match_design_specification() -> void:
	assert_almost_eq(MonsterLocomotion.MAX_STEP_HEIGHT, 1.05, 0.01, "Max step climb height must support 1-block voxels")
	assert_almost_eq(MonsterLocomotion.MAX_CLIFF_DROP, 1.95, 0.01, "Max cliff drop must reject 2-block or greater drop")
	assert_almost_eq(MonsterLocomotion.GRAVITY, 25.0, 0.01, "Locomotion gravity")

func test_vertical_knockback_preservation_from_spikes() -> void:
	var body: CharacterBody3D = CharacterBody3D.new()
	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	col.shape = box
	body.add_child(col)
	add_child_autoqfree(body)
	body.global_position = Vector3(0.0, 0.9, 0.0)

	# Spike trap applies Vector3.UP * 2.0 knockback impulse
	var spike_impulse: Vector3 = Vector3.UP * 2.0
	var res = MonsterLocomotion.process_locomotion(
		body,
		1.0 / 60.0,
		Vector3.ZERO,
		spike_impulse,
		0.9,
		0.4,
		0.0
	)

	assert_gt(body.velocity.y, 1.0, "Upward impulse from spikes must be added to body velocity.y")
	var remaining_kb: Vector3 = res.get("knockback", Vector3.ZERO)
	assert_almost_eq(remaining_kb.y, 0.0, 0.01, "Vertical knockback impulse should be consumed into velocity")

func test_no_height_accumulation_on_flat_ground() -> void:
	var body: CharacterBody3D = CharacterBody3D.new()
	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	col.shape = box
	body.add_child(col)
	add_child_autoqfree(body)

	body.global_position = Vector3(0.0, 0.9, 0.0)
	var smooth_offset: float = 0.0

	for frame in range(10):
		var res = MonsterLocomotion.process_locomotion(
			body,
			1.0 / 60.0,
			Vector3.ZERO,
			Vector3.ZERO,
			0.9,
			0.4,
			smooth_offset
		)
		smooth_offset = float(res.get("smooth_offset_y", 0.0))

	assert_almost_eq(smooth_offset, 0.0, 0.05, "Smooth offset must not accumulate height on flat ground")

func test_step_smooth_offset_decays_over_time() -> void:
	var body: CharacterBody3D = CharacterBody3D.new()
	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	col.shape = box
	body.add_child(col)
	add_child_autoqfree(body)

	var initial_offset: float = -1.0
	var smooth_offset: float = initial_offset

	for frame in range(30):
		var res = MonsterLocomotion.process_locomotion(
			body,
			1.0 / 60.0,
			Vector3.ZERO,
			Vector3.ZERO,
			0.9,
			0.4,
			smooth_offset
		)
		smooth_offset = float(res.get("smooth_offset_y", 0.0))

	assert_gt(smooth_offset, initial_offset, "Negative smooth offset must decay towards zero")
	assert_lt(absf(smooth_offset), 0.1, "After 0.5s, smooth offset should be nearly zero")

func test_step_up_budget_never_exceeds_frame_speed_allowance() -> void:
	# Build step: floor at Y=0, step at Y=1
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.collision_layer = 1
	var f_col: CollisionShape3D = CollisionShape3D.new()
	var f_box: BoxShape3D = BoxShape3D.new()
	f_box.size = Vector3(10.0, 1.0, 10.0)
	f_col.shape = f_box
	floor_body.add_child(f_col)
	add_child_autoqfree(floor_body)
	floor_body.global_position = Vector3(0.0, -0.5, 0.0)

	var step_body: StaticBody3D = StaticBody3D.new()
	step_body.collision_layer = 1
	var s_col: CollisionShape3D = CollisionShape3D.new()
	var s_box: BoxShape3D = BoxShape3D.new()
	s_box.size = Vector3(2.0, 1.0, 2.0)
	s_col.shape = s_box
	step_body.add_child(s_col)
	add_child_autoqfree(step_body)
	step_body.global_position = Vector3(1.4, 0.5, 0.0)

	var body: CharacterBody3D = CharacterBody3D.new()
	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	col.shape = box
	body.add_child(col)
	add_child_autoqfree(body)
	# Place body with small 0.02m gap in front of step
	# Step face is at X = 1.4 - 1.0 = 0.4. Body radius is 0.4.
	# When body is at X = -0.02, body front is at 0.38, gap is exactly 0.02m!
	body.global_position = Vector3(-0.02, 0.9, 0.0)

	var delta: float = 1.0 / 60.0
	var speed: float = 3.2
	var max_allowed_budget: float = speed * delta # approx 0.05333m

	await wait_physics_frames(2)

	var pos_before = body.global_position
	MonsterLocomotion.process_locomotion(
		body,
		delta,
		Vector3(speed, 0, 0),
		Vector3.ZERO,
		0.9,
		0.4,
		0.0
	)
	var pos_after = body.global_position
	var moved_h: float = Vector2(pos_after.x - pos_before.x, pos_after.z - pos_before.z).length()

	assert_lte(moved_h, max_allowed_budget + 0.0001, "Total horizontal displacement in single frame must not exceed speed * delta")

func test_validate_safe_spawn_point_outside_tree() -> void:
	# Add ground
	var ground: StaticBody3D = StaticBody3D.new()
	ground.collision_layer = 1
	var g_col: CollisionShape3D = CollisionShape3D.new()
	var g_box: BoxShape3D = BoxShape3D.new()
	g_box.size = Vector3(20.0, 1.0, 20.0)
	g_col.shape = g_box
	ground.add_child(g_col)
	add_child_autoqfree(ground)
	ground.global_position = Vector3(0.0, -0.5, 0.0)

	# Add an obstacle in world
	var obstacle: StaticBody3D = StaticBody3D.new()
	obstacle.collision_layer = 1
	var o_col: CollisionShape3D = CollisionShape3D.new()
	var o_box: BoxShape3D = BoxShape3D.new()
	o_box.size = Vector3(1.0, 2.0, 1.0)
	o_col.shape = o_box
	obstacle.add_child(o_col)
	add_child_autoqfree(obstacle)
	obstacle.global_position = Vector3(5.0, 1.0, 0.0)

	await wait_physics_frames(2)

	var space_state: PhysicsDirectSpaceState3D = get_viewport().find_world_3d().direct_space_state
	var unparented_mob = ENEMY_DUMMY_SCENE.instantiate()
	# DO NOT add unparented_mob to tree - this specifically tests B8 fix!

	# 1. Clear supported spot
	var clear_pos = Vector3(0.0, 0.9, 0.0)
	var is_clear = MonsterLocomotion.validate_safe_spawn_point(space_state, unparented_mob, clear_pos)
	assert_true(is_clear, "Valid supported spot must pass safe spawn validation even when body is outside scene tree")

	# 2. Occupied spot (overlapping obstacle at X=5.0)
	var occupied_pos = Vector3(5.0, 0.9, 0.0)
	var is_occupied = MonsterLocomotion.validate_safe_spawn_point(space_state, unparented_mob, occupied_pos)
	assert_false(is_occupied, "Occupied spot must be rejected by safe spawn validation")

	unparented_mob.queue_free()

func test_align_starting_entities_success_and_failure_handling() -> void:
	var ground: StaticBody3D = StaticBody3D.new()
	ground.collision_layer = 1
	var g_col: CollisionShape3D = CollisionShape3D.new()
	var g_box: BoxShape3D = BoxShape3D.new()
	g_box.size = Vector3(50.0, 1.0, 50.0)
	g_col.shape = g_box
	ground.add_child(g_col)
	add_child_autoqfree(ground)
	ground.global_position = Vector3(0.0, -0.5, 0.0)

	var main_script = preload("res://scripts/main.gd")
	var main_node = Node3D.new()
	main_node.set_script(main_script)
	add_child_autoqfree(main_node)

	var mock_map = Node.new()
	var script = GDScript.new()
	script.source_code = "extends Node\nfunc get_voxel_height(_x: int, _z: int) -> int:\n\treturn 0\n"
	script.reload()
	mock_map.set_script(script)
	main_node.add_child(mock_map)
	main_node.map_generator = mock_map

	var enemies_node = Node3D.new()
	main_node.add_child(enemies_node)
	main_node.enemies_container = enemies_node

	await wait_physics_frames(2)

	# 1. Safe spawn candidate:
	var safe_enemy = ENEMY_DUMMY_SCENE.instantiate()
	enemies_node.add_child(safe_enemy)
	safe_enemy.global_position = Vector3(10.0, 0.0, 10.0)
	await wait_physics_frames(1)

	main_node._align_starting_entities()
	assert_true(safe_enemy.is_inside_tree(), "Safe starting enemy must remain in scene tree")
	assert_almost_eq(safe_enemy.global_position.y, 0.9, 0.05, "Safe starting enemy must be aligned to safe ground Y")

	# 2. Obstacle blocking initial pos and all 8 alternative offsets:
	var obstacle: StaticBody3D = StaticBody3D.new()
	obstacle.collision_layer = 1
	var o_col: CollisionShape3D = CollisionShape3D.new()
	var o_box: BoxShape3D = BoxShape3D.new()
	o_box.size = Vector3(5.0, 3.0, 5.0)
	o_col.shape = o_box
	obstacle.add_child(o_col)
	add_child_autoqfree(obstacle)
	obstacle.global_position = Vector3(-10.0, 1.5, -10.0)

	await wait_physics_frames(2)

	var blocked_enemy = ENEMY_DUMMY_SCENE.instantiate()
	enemies_node.add_child(blocked_enemy)
	blocked_enemy.global_position = Vector3(-10.0, 0.0, -10.0)
	await wait_physics_frames(1)

	var reg = get_node_or_null("/root/EntityRegistry")
	if reg:
		reg.register_enemy(blocked_enemy)
		assert_true(reg.get_enemies().has(blocked_enemy), "Blocked enemy registered initially")

	main_node._align_starting_entities()

	assert_false(blocked_enemy.is_inside_tree(), "Completely blocked starting enemy must be removed from scene tree")
	if reg:
		assert_false(reg.get_enemies().has(blocked_enemy), "Blocked enemy must be unregistered from EntityRegistry upon alignment failure")

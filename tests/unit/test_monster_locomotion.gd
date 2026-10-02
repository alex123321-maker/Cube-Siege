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

extends GutTest

## Unit tests for MonsterLocomotion (authoritative voxel step-up, cliff rejection, height calculations).

const MonsterLocomotionScript = preload("res://scripts/movement/monster_locomotion.gd")

func test_spawn_y_calculation_for_all_archetypes() -> void:
	# Terrain at height 3.0
	var terrain_y: float = 3.0
	
	# Grunt / Skirmisher (half-height 0.9)
	var grunt_spawn_y = MonsterLocomotion.calculate_spawn_y(terrain_y, 0.9)
	assert_almost_eq(grunt_spawn_y, 3.9, 0.001, "Grunt spawn Y should place feet exactly at terrain surface")
	
	# Siege Breaker (half-height 1.2)
	var siege_spawn_y = MonsterLocomotion.calculate_spawn_y(terrain_y, 1.2)
	assert_almost_eq(siege_spawn_y, 4.2, 0.001, "Siege Breaker spawn Y should place feet at terrain surface without 0.3m ground penetration")
	
	# Gorgon (half-height 1.5)
	var gorgon_spawn_y = MonsterLocomotion.calculate_spawn_y(terrain_y, 1.5)
	assert_almost_eq(gorgon_spawn_y, 4.5, 0.001, "Gorgon spawn Y should place feet at terrain surface")

func test_locomotion_constants_match_design_specification() -> void:
	assert_almost_eq(MonsterLocomotion.MAX_STEP_HEIGHT, 1.05, 0.01, "Max step climb height must support 1-block voxels")
	assert_almost_eq(MonsterLocomotion.MAX_CLIFF_DROP, 1.95, 0.01, "Max cliff drop must reject 2-block or greater drop")
	assert_almost_eq(MonsterLocomotion.GRAVITY, 25.0, 0.01, "Locomotion gravity")

func test_no_height_accumulation_on_flat_ground() -> void:
	# Create a CharacterBody3D with collision shape on flat ground
	var body: CharacterBody3D = CharacterBody3D.new()
	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	col.shape = box
	body.add_child(col)
	add_child_autoqfree(body)
	
	body.global_position = Vector3(0.0, 0.9, 0.0)
	var smooth_offset: float = 0.0
	
	# Simulate 10 frames on flat ground with zero velocity
	for frame in range(10):
		smooth_offset = MonsterLocomotion.process_locomotion(
			body,
			1.0 / 60.0,
			Vector3.ZERO,
			0.9,
			0.4,
			smooth_offset
		)
	
	# Smooth offset should decay towards 0.0 and body should not float
	assert_almost_eq(smooth_offset, 0.0, 0.05, "Smooth offset must not accumulate height on flat ground")

func test_step_smooth_offset_decays_over_time() -> void:
	var body: CharacterBody3D = CharacterBody3D.new()
	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	col.shape = box
	body.add_child(col)
	add_child_autoqfree(body)

	var initial_offset: float = -1.0 # 1 block step-up visual offset
	var smooth_offset: float = initial_offset

	# Process 30 frames (0.5 seconds) with zero movement
	for frame in range(30):
		smooth_offset = MonsterLocomotion.process_locomotion(
			body,
			1.0 / 60.0,
			Vector3.ZERO,
			0.9,
			0.4,
			smooth_offset
		)

	assert_gt(smooth_offset, initial_offset, "Negative smooth offset must decay towards zero")
	assert_lt(absf(smooth_offset), 0.1, "After 0.5s, smooth offset should be nearly zero")

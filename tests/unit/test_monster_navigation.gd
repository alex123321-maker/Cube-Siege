extends GutTest

## Unit tests for MonsterFlowfield navigation on discrete voxel terrain and dynamic obstacles.

const MonsterFlowfieldScript = preload("res://scripts/navigation/monster_flowfield.gd")

func test_height_transition_rule_passable_within_one_block() -> void:
	var heights: Dictionary = {
		Vector2i(0, 0): 1,
		Vector2i(1, 0): 2, # +1 block step: passable!
		Vector2i(2, 0): 4, # +2 block cliff: impassable!
		Vector2i(0, 1): 0, # -1 block step: passable!
		Vector2i(0, 2): -2 # -2 block cliff: impassable!
	}

	var height_fn = func(x: int, z: int) -> int:
		var key = Vector2i(x, z)
		if heights.has(key):
			return heights[key]
		return 0

	var ff = MonsterFlowfield.new(12345, height_fn)

	# 0,0 (h=1) to 1,0 (h=2): diff = 1 <= 1 -> true
	assert_true(ff.is_step_passable(Vector2i(0, 0), Vector2i(1, 0)), "1-block step up must be passable")

	# 1,0 (h=2) to 2,0 (h=4): diff = 2 > 1 -> false
	assert_false(ff.is_step_passable(Vector2i(1, 0), Vector2i(2, 0)), "2-block cliff up must be impassable")

	# 0,0 (h=1) to 0,1 (h=0): diff = -1 <= 1 -> true
	assert_true(ff.is_step_passable(Vector2i(0, 0), Vector2i(0, 1)), "1-block step down must be passable")

	# 0,1 (h=0) to 0,2 (h=-2): diff = -2 > 1 -> false
	assert_false(ff.is_step_passable(Vector2i(0, 1), Vector2i(0, 2)), "2-block cliff down must be impassable")

func test_wall_blocks_step_and_dynamic_toggle() -> void:
	var height_fn = func(_x: int, _z: int) -> int: return 0
	var ff = MonsterFlowfield.new(12345, height_fn)

	var wall_cell = Vector2i(5, 5)
	assert_true(ff.is_step_passable(Vector2i(5, 4), wall_cell), "Before wall placement, cell should be passable")

	# Place wall
	ff.set_cell_blocked(wall_cell, true)
	assert_false(ff.is_step_passable(Vector2i(5, 4), wall_cell), "Cell with wall must be impassable")

	# Destroy wall
	ff.set_cell_blocked(wall_cell, false)
	assert_true(ff.is_step_passable(Vector2i(5, 4), wall_cell), "Destroyed wall cell must become passable again")

func test_diagonal_corner_cutting_is_prevented_in_step_and_los() -> void:
	var height_fn = func(_x: int, _z: int) -> int: return 0
	var ff = MonsterFlowfield.new(12345, height_fn)

	# Diagonal step from (0,0) to (1,1) with (1,0) and (0,1) blocked (B4 counterexample)
	ff.set_cell_blocked(Vector2i(1, 0), true)
	ff.set_cell_blocked(Vector2i(0, 1), true)

	assert_false(ff.is_step_passable(Vector2i(0, 0), Vector2i(1, 1)), "Cannot cut corner diagonally past a blocked wall")

	# Direct line of sight from (0.5, 0, 0.5) to (1.5, 0, 1.5) must not bypass diagonal corner restriction
	var dir = ff.get_flow_direction(Vector3(0.5, 0, 0.5), Vector3(1.5, 0, 1.5), 0.4)
	assert_ne(dir, Vector3(1, 0, 1).normalized(), "LoS must not cut closed diagonal corner")
	assert_true(dir.x <= 0.0 or dir.z <= 0.0, "Flow direction must detour around blocked corner cells (B4)")

func test_unreachable_target_returns_zero_vector() -> void:
	var height_fn = func(_x: int, _z: int) -> int: return 0
	var ff = MonsterFlowfield.new(12345, height_fn)

	# Completely box in target at (10, 10) with walls
	var target_cell = Vector2i(10, 10)
	var target_pos = Vector3(10.5, 0.0, 10.5)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			ff.set_cell_blocked(Vector2i(target_cell.x + dx, target_cell.y + dz), true)

	# Outside mob at (0, 0)
	var mob_pos = Vector3(0.5, 0.0, 0.5)
	var dir = ff.get_flow_direction(mob_pos, target_pos, 0.4)
	assert_eq(dir, Vector3.ZERO, "Unreachable target must return Vector3.ZERO, never fall back into wall (§3.2)")

func test_building_target_perimeter_seeding() -> void:
	var height_fn = func(_x: int, _z: int) -> int: return 0
	var ff = MonsterFlowfield.new(12345, height_fn)

	# Wood wall placed at (10, 10)
	var wall_cell = Vector2i(10, 10)
	var wall_pos = Vector3(10.5, 0.0, 10.5)
	ff.set_cell_blocked(wall_cell, true)

	# Siege breaker at (7.5, 0, 10.5) targeting the wall
	var mob_pos = Vector3(7.5, 0.0, 10.5)
	var dir = ff.get_flow_direction(mob_pos, wall_pos, 0.7)

	assert_gt(dir.length_squared(), 0.01, "Should have valid flow direction to building perimeter")
	assert_gt(dir.x, 0.0, "Flow direction should lead towards the building perimeter")

func test_multi_target_cache_prevents_ping_pong_rebuild() -> void:
	var height_fn = func(_x: int, _z: int) -> int: return 0
	var ff = MonsterFlowfield.new(12345, height_fn)

	var player_pos = Vector3(15.5, 0.0, 0.5)
	var building_pos = Vector3(0.5, 0.0, 15.5)

	ff.reset_rebuild_count()

	# Frame 1: Grunt queries player, Siege Breaker queries building
	var _d1 = ff.get_flow_direction(Vector3(1.0, 0.0, 0.0), player_pos, 0.4)
	var _d2 = ff.get_flow_direction(Vector3(0.0, 0.0, 1.0), building_pos, 0.7)

	var count_after_init = ff.get_rebuild_count()
	assert_eq(count_after_init, 2, "Initial build for 2 distinct targets should be 2")

	# Simulate 20 alternating queries in the same tick window (simulating mixed wave frames)
	for i in range(20):
		var _p = ff.get_flow_direction(Vector3(1.0 + float(i) * 0.01, 0.0, 0.0), player_pos, 0.4)
		var _b = ff.get_flow_direction(Vector3(0.0, 0.0, 1.0 + float(i) * 0.01), building_pos, 0.7)

	assert_eq(ff.get_rebuild_count(), 2, "Alternating target queries within recalc interval must not trigger ping-pong rebuilds (B6)")

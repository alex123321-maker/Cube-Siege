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

func test_diagonal_corner_cutting_is_prevented() -> void:
	var height_fn = func(_x: int, _z: int) -> int: return 0
	var ff = MonsterFlowfield.new(12345, height_fn)

	# Diagonal step from (0,0) to (1,1)
	# Orthogonal neighbors are (1,0) and (0,1)
	# If either is blocked, diagonal corner cutting must be prevented
	ff.set_cell_blocked(Vector2i(1, 0), true)
	assert_false(ff.is_step_passable(Vector2i(0, 0), Vector2i(1, 1)), "Cannot cut corner diagonally past a blocked wall")

	ff.set_cell_blocked(Vector2i(1, 0), false)
	assert_true(ff.is_step_passable(Vector2i(0, 0), Vector2i(1, 1)), "Diagonal movement without adjacent walls is allowed")

func test_flowfield_navigation_around_obstacle_to_target() -> void:
	var height_fn = func(_x: int, _z: int) -> int: return 0
	var ff = MonsterFlowfield.new(12345, height_fn)

	# Target at (10, 0)
	var target_pos = Vector3(10.5, 0.0, 0.5)

	# Put a wall directly in front of mob at (5, 0)
	ff.set_cell_blocked(Vector2i(5, 0), true)
	ff.update_field_if_needed(target_pos, 16)

	# Mob at (4, 0) should navigate around (5, 0), directing north (0, -1) or south (0, 1), not into the wall
	var mob_pos = Vector3(4.5, 0.0, 0.5)
	var dir = ff.get_flow_direction(mob_pos, target_pos, 0.4)
	assert_gt(dir.length_squared(), 0.01, "Should have valid flow direction")
	# Direction X should not push directly into blocked wall (1, 0, 0)
	assert_ne(dir, Vector3(1, 0, 0), "Should detour around wall instead of heading straight into it")

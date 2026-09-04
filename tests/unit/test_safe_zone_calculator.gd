extends GutTest

const SafeZoneCalculator = preload("res://scripts/algorithms/safe_zone_calculator.gd")

func test_fewer_than_four_walls_returns_empty() -> void:
	var walls_empty: Array[Vector2i] = []
	var res_empty = SafeZoneCalculator.calculate_safe_cells(walls_empty)
	assert_eq(res_empty.size(), 0, "Empty walls should return empty safe zone")

	var walls_three: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(0, 1)
	]
	var res_three = SafeZoneCalculator.calculate_safe_cells(walls_three)
	assert_eq(res_three.size(), 0, "Fewer than 4 walls cannot enclose a tile")

func test_closed_single_tile_enclosed() -> void:
	# 8 walls forming a 3x3 box around center tile (1, 1)
	# (0,0) (1,0) (2,0)
	# (0,1)   .   (2,1)
	# (0,2) (1,2) (2,2)
	var walls: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(0, 1),                 Vector2i(2, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)
	]
	var safe_cells = SafeZoneCalculator.calculate_safe_cells(walls)
	assert_eq(safe_cells.size(), 1, "Exactly 1 tile should be enclosed")
	assert_true(safe_cells.has(Vector2i(1, 1)), "Tile (1,1) should be enclosed")

func test_open_contour_not_enclosed() -> void:
	# Missing bottom wall (U-shape)
	var walls: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(0, 1),                 Vector2i(2, 1),
		Vector2i(0, 2),                 Vector2i(2, 2)
	]
	var safe_cells = SafeZoneCalculator.calculate_safe_cells(walls)
	assert_eq(safe_cells.size(), 0, "Open U-shaped contour must not enclose interior")

func test_diagonal_gap_leaks_and_does_not_enclose() -> void:
	# Diamond shape with diagonal gaps (4 walls touching diagonally only):
	#    (1,0)
	# (0,1) (2,1)
	#    (1,2)
	# In 4-way orthogonal connectivity, flood-fill leaks through (0,0), (2,0), (0,2), (2,2) into center (1,1)
	var walls: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(2, 1),
		Vector2i(1, 2)
	]
	var safe_cells = SafeZoneCalculator.calculate_safe_cells(walls)
	assert_eq(safe_cells.size(), 0, "Diagonal gap must allow flood-fill to penetrate under 4-connected topology")

func test_broken_wall_invalidates_safe_zone() -> void:
	var walls: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(0, 1),                 Vector2i(2, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2)
	]
	var safe_before = SafeZoneCalculator.calculate_safe_cells(walls)
	assert_eq(safe_before.size(), 1, "Closed contour is safe")

	# Destroy wall at (1, 0)
	walls.erase(Vector2i(1, 0))
	var safe_after = SafeZoneCalculator.calculate_safe_cells(walls)
	assert_eq(safe_after.size(), 0, "Breached contour must yield 0 safe cells")

func test_multiple_independent_enclosures() -> void:
	# Room 1 around (1,1): x in [0,2], z in [0,2]
	# Room 2 around (5,1): x in [4,6], z in [0,2]
	var walls: Array[Vector2i] = [
		# Room 1
		Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(0, 1),                 Vector2i(2, 1),
		Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
		# Room 2
		Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0),
		Vector2i(4, 1),                 Vector2i(6, 1),
		Vector2i(4, 2), Vector2i(5, 2), Vector2i(6, 2)
	]
	var safe_cells = SafeZoneCalculator.calculate_safe_cells(walls)
	assert_eq(safe_cells.size(), 2, "Both rooms should each enclose 1 cell")
	assert_true(safe_cells.has(Vector2i(1, 1)), "Room 1 tile (1,1) enclosed")
	assert_true(safe_cells.has(Vector2i(5, 1)), "Room 2 tile (5,1) enclosed")

func test_nested_internal_walls() -> void:
	# 5x5 outer box around interior 3x3, with an internal wall inside
	# Outer box: x in [0, 4], z in [0, 4]
	var walls: Array[Vector2i] = []
	for x in range(5):
		walls.append(Vector2i(x, 0))
		walls.append(Vector2i(x, 4))
	for z in range(1, 4):
		walls.append(Vector2i(0, z))
		walls.append(Vector2i(4, z))
	# Add an inner obstacle wall at (2, 2)
	walls.append(Vector2i(2, 2))

	var safe_cells = SafeZoneCalculator.calculate_safe_cells(walls)
	# 3x3 interior = 9 cells minus 1 wall cell at (2,2) = 8 safe cells
	assert_eq(safe_cells.size(), 8, "Internal cells minus inner wall should be enclosed")
	assert_false(safe_cells.has(Vector2i(2, 2)), "Wall tile itself cannot be a safe zone cell")

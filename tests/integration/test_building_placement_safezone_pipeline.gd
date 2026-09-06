extends GutTest

const BuildingSystemClass = preload("res://scripts/building_system.gd")
const SafeZoneDetectorClass = preload("res://scripts/safe_zone_detector.gd")
const WaveDirectorClass = preload("res://scripts/wave_director.gd")

class MockTerrainMap extends Node:
	var heights: Dictionary = {}

	func _init() -> void:
		add_to_group("map_generator")

	func set_cell_height(x: int, z: int, h: int) -> void:
		heights[Vector2i(x, z)] = h

	func get_voxel_height(x: int, z: int) -> int:
		return heights.get(Vector2i(x, z), 0)

func test_placed_walls_to_safe_zone_detector_to_wave_director_pipeline() -> void:
	var building_system = BuildingSystemClass.new()
	add_child_autoqfree(building_system)
	building_system.wallet.add_resource(100, 100, 100)

	var wave_director = WaveDirectorClass.new()
	add_child_autoqfree(wave_director)

	var detector = SafeZoneDetectorClass.new()
	add_child_autoqfree(detector)
	detector.building_system = building_system
	detector.wave_director = wave_director

	# Build a closed 3x3 perimeter of 8 walls enclosing cell (5, 5)
	# Perimeter cells: (4,4), (5,4), (6,4), (4,5), (6,5), (4,6), (5,6), (6,6)
	var perimeter_coords: Array[Vector2i] = [
		Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4),
		Vector2i(4, 5),                 Vector2i(6, 5),
		Vector2i(4, 6), Vector2i(5, 6), Vector2i(6, 6)
	]

	for c in perimeter_coords:
		var place_pos = Vector3(float(c.x) + 0.5, 0.0, float(c.y) + 0.5)
		building_system.place_building(place_pos, c, BuildingSystemClass.PrefabType.WOOD_WALL)

	detector.recalculate_safe_zone()

	# SafeZoneDetector must find enclosed cell (5, 5)
	assert_eq(detector.current_safe_cells.size(), 1, "Exactly 1 enclosed safe cell must be detected")
	assert_true(detector.current_safe_cells.has(Vector2i(5, 5)), "Enclosed cell must be (5, 5)")

	# WaveDirector must receive safe zone cells
	assert_true(wave_director.safe_zone_cells.has(Vector2i(5, 5)), "WaveDirector must store safe cell (5, 5)")

	# Test continuous positions inside cell (5, 5): [5.0, 6.0) x [5.0, 6.0)
	var inside_positions: Array[Vector3] = [
		Vector3(5.05, 0.0, 5.05),
		Vector3(5.50, 0.0, 5.50),
		Vector3(5.95, 0.0, 5.95),
		Vector3(5.20, 0.0, 5.80)
	]
	for p in inside_positions:
		var cell: Vector2i = TerrainCombatRules.world_pos_to_voxel(p)
		assert_eq(cell, Vector2i(5, 5), "Continuous position %s must map strictly to cell (5, 5)" % str(p))
		assert_true(wave_director.safe_zone_cells.has(cell), "Spawn at %s must be rejected by safe zone" % str(p))

	# Test continuous positions outside cell (5, 5)
	var outside_positions: Array[Vector3] = [
		Vector3(3.5, 0.0, 5.5),  # Outside to the West
		Vector3(7.5, 0.0, 5.5),  # Outside to the East
		Vector3(5.5, 0.0, 3.5),  # Outside to the North
		Vector3(5.5, 0.0, 7.5),  # Outside to the South
		Vector3(8.0, 0.0, 8.0)   # Far outside
	]
	for p in outside_positions:
		var cell: Vector2i = TerrainCombatRules.world_pos_to_voxel(p)
		assert_ne(cell, Vector2i(5, 5), "Outside position %s must not map to cell (5, 5)" % str(p))
		assert_false(wave_director.safe_zone_cells.has(cell), "Spawn at %s outside safe zone must NOT be rejected" % str(p))

func test_building_placement_on_high_flat_terrain_y50() -> void:
	var mock_map = MockTerrainMap.new()
	mock_map.set_cell_height(10, 10, 55)
	add_child_autoqfree(mock_map)

	var building_system = BuildingSystemClass.new()
	add_child_autoqfree(building_system)
	building_system.wallet.add_resource(50, 50, 50)

	var target_cell = Vector2i(10, 10)
	var expected_pos = Vector3(10.5, 55.0, 10.5)

	building_system.place_building(expected_pos, target_cell, BuildingSystemClass.PrefabType.WOOD_WALL)
	assert_true(building_system.placed_buildings.has(target_cell), "Building must be stored at cell (10, 10)")

	var placed_wall = building_system.placed_buildings[target_cell]
	assert_not_null(placed_wall, "Placed wall instance must exist")
	assert_eq(placed_wall.global_position, expected_pos, "Wall on high terrain must be placed at Y=55.0")
	assert_eq(placed_wall.grid_coord, target_cell, "Wall grid_coord must match (10, 10)")

func test_building_placement_near_step_and_cliff_boundaries() -> void:
	var mock_map = MockTerrainMap.new()
	# cell (2, 2) height 10, cell (3, 2) height 11 (+1 step), cell (4, 2) height 13 (+2 cliff)
	mock_map.set_cell_height(2, 2, 10)
	mock_map.set_cell_height(3, 2, 11)
	mock_map.set_cell_height(4, 2, 13)
	add_child_autoqfree(mock_map)

	var building_system = BuildingSystemClass.new()
	add_child_autoqfree(building_system)
	building_system.wallet.add_resource(50, 50, 50)

	# Place wall at lower cell (2, 2)
	var pos_low = Vector3(2.5, 10.0, 2.5)
	building_system.place_building(pos_low, Vector2i(2, 2), BuildingSystemClass.PrefabType.WOOD_WALL)
	var wall_low = building_system.placed_buildings[Vector2i(2, 2)]

	# Wall bounding box: center at 2.5, size 1.0 -> X spans [2.0, 3.0]
	# Boundary with cell (3, 2) is exactly at X = 3.0. It sits flush against the step, without clipping.
	assert_eq(wall_low.global_position.x, 2.5)
	assert_eq(wall_low.global_position.y, 10.0)
	assert_eq(wall_low.global_position.z, 2.5)

	# Place wall at step cell (3, 2) adjacent to +2 cliff at cell (4, 2)
	var pos_step = Vector3(3.5, 11.0, 2.5)
	building_system.place_building(pos_step, Vector2i(3, 2), BuildingSystemClass.PrefabType.WOOD_WALL)
	var wall_step = building_system.placed_buildings[Vector2i(3, 2)]

	assert_eq(wall_step.global_position.x, 3.5)
	assert_eq(wall_step.global_position.y, 11.0)
	assert_eq(wall_step.global_position.z, 2.5)

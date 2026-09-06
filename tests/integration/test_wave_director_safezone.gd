extends GutTest

const WaveDirectorClass = preload("res://scripts/wave_director.gd")

class MockEnemy extends Node3D:
	var died: bool = false

	func _init() -> void:
		add_to_group("enemies")

	func _enter_tree() -> void:
		var reg = get_node_or_null("/root/EntityRegistry")
		if reg:
			reg.register_enemy(self)

	func _exit_tree() -> void:
		var reg = get_node_or_null("/root/EntityRegistry")
		if reg:
			reg.unregister_enemy(self)

	func die() -> void:
		died = true

func before_each() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg:
		reg.clear()

func test_wave_director_safe_zone_cells_storage() -> void:
	var director = WaveDirectorClass.new()
	add_child_autoqfree(director)

	var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1)]
	director.set_safe_zone_cells(cells)

	assert_eq(director.safe_zone_cells.size(), 3)
	assert_true(director.safe_zone_cells.has(Vector2i(0, 0)))
	assert_true(director.safe_zone_cells.has(Vector2i(1, 1)))
	assert_false(director.safe_zone_cells.has(Vector2i(5, 5)))

func test_wave_director_morning_sun_destroys_enemies() -> void:
	var director = WaveDirectorClass.new()
	add_child_autoqfree(director)

	var enemy1 = MockEnemy.new()
	var enemy2 = MockEnemy.new()
	add_child_autoqfree(enemy1)
	add_child_autoqfree(enemy2)

	director._on_phase_changed(false, 2) # is_night = false

	assert_true(enemy1.died, "Morning phase transition should kill surviving enemy 1")
	assert_true(enemy2.died, "Morning phase transition should kill surviving enemy 2")

func test_wave_director_morning_sun_destroys_preexisting_and_spawned_enemies() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	var director = WaveDirectorClass.new()
	add_child_autoqfree(director)

	# 1 pre-existing enemy registered via tree / EntityRegistry
	var pre_existing = MockEnemy.new()
	add_child_autoqfree(pre_existing)
	if reg:
		reg.register_enemy(pre_existing)

	# 1 spawned enemy
	var spawned = MockEnemy.new()
	add_child_autoqfree(spawned)
	if reg:
		reg.register_enemy(spawned)

	assert_eq(get_tree().get_nodes_in_group("enemies").size(), 2)
	if reg:
		assert_eq(reg.get_enemy_count(), 2, "EntityRegistry must track both pre-existing and spawned enemies")

	# Dawn arrives
	director._on_phase_changed(false, 3)

	assert_true(pre_existing.died, "Morning sun must destroy pre-existing enemies")
	assert_true(spawned.died, "Morning sun must destroy spawned wave enemies")

class MockMapGenerator extends Node:
	func get_voxel_height(x: int, _z: int) -> int:
		# Cliff at voxel edge x=1: cell 0 (x < 1) has height 0, cell 1 (x >= 1) has height 4
		return 4 if x >= 1 else 0

func test_wave_director_spawn_height_on_fractional_voxel_boundaries() -> void:
	var mock_map = MockMapGenerator.new()
	mock_map.add_to_group("map_generator")
	add_child_autoqfree(mock_map)

	var director = WaveDirectorClass.new()
	add_child_autoqfree(director)

	# Fractional position x=0.75 is physically within cell 0 [0.0, 1.0)
	# floorf(0.75) -> 0. Height must be 0.0 (old roundf(0.75) returned 1 -> height 4.0!)
	var surface_y_in_cell_0: float = director.get_terrain_surface_y(Vector3(0.75, 0.0, 0.0))
	assert_eq(surface_y_in_cell_0, 0.0, "x=0.75 must map to voxel cell 0 with surface height 0.0")

	# Fractional position x=1.05 is physically within cell 1 [1.0, 2.0)
	# floorf(1.05) -> 1. Height must be 4.0
	var surface_y_in_cell_1: float = director.get_terrain_surface_y(Vector3(1.05, 0.0, 0.0))
	assert_eq(surface_y_in_cell_1, 4.0, "x=1.05 must map to voxel cell 1 with surface height 4.0")

	# Negative fractional coordinate boundary: -0.25 is in cell -1 [-1.0, 0.0)
	var surface_y_neg: float = director.get_terrain_surface_y(Vector3(-0.25, 0.0, 0.0))
	assert_eq(surface_y_neg, 0.0, "x=-0.25 must map to voxel cell -1 with surface height 0.0")

	# Safe zone boundary with fractional coordinates:
	# safe zone cell (0, 0) must reject x=0.75 (cell 0), but not x=1.05 (cell 1)
	director.set_safe_zone_cells([Vector2i(0, 0)])
	var cell_075: Vector2i = TerrainCombatRules.world_pos_to_voxel(Vector3(0.75, 0.0, 0.0))
	var cell_105: Vector2i = TerrainCombatRules.world_pos_to_voxel(Vector3(1.05, 0.0, 0.0))
	assert_true(director.safe_zone_cells.has(cell_075), "x=0.75 maps to cell (0, 0) and is inside safe zone")
	assert_false(director.safe_zone_cells.has(cell_105), "x=1.05 maps to cell (1, 0) and is outside safe zone")


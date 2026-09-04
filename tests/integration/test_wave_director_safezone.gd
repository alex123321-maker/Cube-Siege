extends GutTest

const WaveDirectorClass = preload("res://scripts/wave_director.gd")

class MockEnemy extends Node3D:
	var died: bool = false

	func _init() -> void:
		add_to_group("enemies")

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

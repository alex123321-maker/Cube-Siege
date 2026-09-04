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

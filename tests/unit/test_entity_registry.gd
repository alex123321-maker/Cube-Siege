extends GutTest

const EntityRegistryScript = preload("res://scripts/core/entity_registry.gd")

func test_entity_registry_building_tracking() -> void:
	var registry = EntityRegistryScript.new()
	add_child_autoqfree(registry)

	var b1 = Node3D.new()
	var b2 = Node3D.new()
	add_child_autoqfree(b1)
	add_child_autoqfree(b2)
	b1.global_position = Vector3(5, 0, 0)
	b2.global_position = Vector3(25, 0, 0)

	registry.register_building(b1)
	registry.register_building(b2)
	assert_eq(registry.get_buildings().size(), 2)

	var nearest = registry.get_nearest_building(Vector3(0, 0, 0))
	assert_eq(nearest, b1, "Nearest building should be b1")

	registry.unregister_building(b1)
	assert_eq(registry.get_buildings().size(), 1)
	assert_eq(registry.get_nearest_building(Vector3(0, 0, 0)), b2)

func test_entity_registry_enemy_and_boss_tracking() -> void:
	var registry = EntityRegistryScript.new()
	add_child_autoqfree(registry)

	var e1 = Node.new()
	var boss = Node.new()
	add_child_autoqfree(e1)
	add_child_autoqfree(boss)

	registry.register_enemy(e1)
	assert_eq(registry.get_enemy_count(), 1)

	assert_false(registry.has_active_boss())
	registry.register_boss(boss)
	assert_true(registry.has_active_boss())

	registry.unregister_boss(boss)
	assert_false(registry.has_active_boss())

	registry.clear()
	assert_eq(registry.get_enemy_count(), 0)
	assert_eq(registry.get_buildings().size(), 0)

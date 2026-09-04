extends Node

## Centralized runtime entity registry for buildings, enemies, and bosses.
## Avoids full SceneTree traversals on hot physics frames.

var buildings: Array[Node3D] = []
var enemies: Array[Node] = []
var bosses: Array[Node] = []

func _ready() -> void:
	var eb = get_node_or_null("/root/EventBus")
	if eb:
		eb.building_placed.connect(func(_id, _cell, b): if b is Node3D: register_building(b))
		eb.building_destroyed.connect(func(_cell, b): if b is Node3D: unregister_building(b))
		eb.boss_spawned.connect(func(boss): register_boss(boss))
		eb.boss_defeated.connect(func(boss): unregister_boss(boss))
		eb.enemy_killed.connect(func(enemy, _pos): unregister_enemy(enemy))

func register_building(b: Node3D) -> void:
	if b and not buildings.has(b):
		buildings.append(b)

func unregister_building(b: Node3D) -> void:
	buildings.erase(b)

func get_buildings() -> Array[Node3D]:
	_cleanup_buildings()
	return buildings

func get_nearest_building(pos: Vector3) -> Node3D:
	var nearest: Node3D = null
	var min_dist_sq: float = INF
	for i in range(buildings.size() - 1, -1, -1):
		var b = buildings[i]
		if not is_instance_valid(b):
			buildings.remove_at(i)
			continue
		var d_sq: float = pos.distance_squared_to(b.global_position)
		if d_sq < min_dist_sq:
			min_dist_sq = d_sq
			nearest = b
	return nearest

func register_enemy(e: Node) -> void:
	if e and not enemies.has(e):
		enemies.append(e)

func unregister_enemy(e: Node) -> void:
	enemies.erase(e)

func get_enemy_count() -> int:
	_cleanup_enemies()
	return enemies.size()

func get_enemies() -> Array[Node]:
	_cleanup_enemies()
	return enemies

func register_boss(boss: Node) -> void:
	if boss and not bosses.has(boss):
		bosses.append(boss)

func unregister_boss(boss: Node) -> void:
	bosses.erase(boss)

func has_active_boss() -> bool:
	_cleanup_bosses()
	return not bosses.is_empty()

func clear() -> void:
	buildings.clear()
	enemies.clear()
	bosses.clear()

func _cleanup_buildings() -> void:
	for i in range(buildings.size() - 1, -1, -1):
		if not is_instance_valid(buildings[i]):
			buildings.remove_at(i)

func _cleanup_enemies() -> void:
	for i in range(enemies.size() - 1, -1, -1):
		if not is_instance_valid(enemies[i]):
			enemies.remove_at(i)

func _cleanup_bosses() -> void:
	for i in range(bosses.size() - 1, -1, -1):
		if not is_instance_valid(bosses[i]):
			bosses.remove_at(i)

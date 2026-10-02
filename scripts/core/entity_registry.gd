extends Node

## Centralized runtime entity registry for buildings, enemies, and bosses.
## Avoids full SceneTree traversals on hot physics frames.

var buildings: Array[Node3D] = []
var enemies: Array[Node] = []
var bosses: Array[Node] = []
var monster_flowfield: MonsterFlowfield = MonsterFlowfield.new()

func _ready() -> void:
	var eb = get_node_or_null("/root/EventBus")
	if eb:
		eb.building_placed.connect(func(_id, cell, b):
			if b is Node3D:
				register_building(b)
				if b.is_in_group("walls") or (b.is_in_group("buildings") and not b.is_in_group("traps")):
					monster_flowfield.set_cell_blocked(cell, true)
		)
		eb.building_destroyed.connect(func(cell, b):
			if b is Node3D:
				unregister_building(b)
			monster_flowfield.set_cell_blocked(cell, false)
		)
		eb.boss_spawned.connect(func(boss): register_boss(boss))
		eb.boss_defeated.connect(func(boss): unregister_boss(boss))
		eb.enemy_killed.connect(func(enemy, _pos): unregister_enemy(enemy))

	call_deferred("_scan_existing_entities")

func _scan_existing_entities() -> void:
	if not is_inside_tree():
		return
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Node3D:
			register_building(b as Node3D)
	for e in get_tree().get_nodes_in_group("enemies"):
		register_enemy(e)
	for boss in get_tree().get_nodes_in_group("boss"):
		register_boss(boss)

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
	_spatial_buckets.clear()
	_last_spatial_frame = -1

const BUCKET_SIZE: float = 2.5
var _spatial_buckets: Dictionary = {} # Vector2i -> Array[Node3D]
var _last_spatial_frame: int = -1

func update_spatial_buckets_if_needed() -> void:
	var current_frame: int = Engine.get_physics_frames()
	if current_frame == _last_spatial_frame:
		return
	_last_spatial_frame = current_frame
	_spatial_buckets.clear()

	_cleanup_enemies()
	for e in enemies:
		if e is Node3D and is_instance_valid(e) and (e as Node3D).is_inside_tree():
			var node3d = e as Node3D
			if "is_dying" in node3d and node3d.is_dying:
				continue
			var bx: int = int(floorf(node3d.global_position.x / BUCKET_SIZE))
			var bz: int = int(floorf(node3d.global_position.z / BUCKET_SIZE))
			var key: Vector2i = Vector2i(bx, bz)
			if not _spatial_buckets.has(key):
				var arr: Array[Node3D] = []
				_spatial_buckets[key] = arr
			_spatial_buckets[key].append(node3d)

## Queries nearby active enemies within radius on the horizontal plane.
## Excludes enemies on different vertical tiers (> 1.8m height separation).
func get_nearby_enemies(pos: Vector3, radius: float, self_node: Node = null) -> Array[Node3D]:
	update_spatial_buckets_if_needed()
	var results: Array[Node3D] = []
	var min_bx: int = int(floorf((pos.x - radius) / BUCKET_SIZE))
	var max_bx: int = int(floorf((pos.x + radius) / BUCKET_SIZE))
	var min_bz: int = int(floorf((pos.z - radius) / BUCKET_SIZE))
	var max_bz: int = int(floorf((pos.z + radius) / BUCKET_SIZE))
	var r_sq: float = radius * radius

	for bx in range(min_bx, max_bx + 1):
		for bz in range(min_bz, max_bz + 1):
			var key: Vector2i = Vector2i(bx, bz)
			if _spatial_buckets.has(key):
				var bucket: Array[Node3D] = _spatial_buckets[key]
				for other in bucket:
					if other == self_node:
						continue
					var dy: float = absf(other.global_position.y - pos.y)
					if dy > 1.8:
						continue
					var dx: float = other.global_position.x - pos.x
					var dz: float = other.global_position.z - pos.z
					if (dx * dx + dz * dz) <= r_sq:
						results.append(other)
	return results

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

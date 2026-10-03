extends Node

## Centralized runtime entity registry for buildings, enemies, bosses, and resources.
## Avoids full SceneTree traversals on hot physics frames and keeps navigation state synchronized.

var player: Node3D = null
var buildings: Array[Node3D] = []
var enemies: Array[Node] = []
var bosses: Array[Node] = []
var monster_flowfield: MonsterFlowfield = MonsterFlowfield.new()

var building_to_cell: Dictionary = {} # Node3D -> Vector2i
var resource_to_cell: Dictionary = {} # Node3D -> Vector2i

func _physics_process(delta: float) -> void:
	monster_flowfield.advance(delta)

func _ready() -> void:
	var eb = get_node_or_null("/root/EventBus")
	if eb:
		eb.building_placed.connect(func(_id, _cell, b):
			if b is Node3D:
				register_building(b as Node3D)
		)
		eb.building_destroyed.connect(func(_cell, b):
			if b is Node3D:
				unregister_building(b as Node3D)
		)
		eb.boss_spawned.connect(func(boss): register_boss(boss))
		eb.boss_defeated.connect(func(boss): unregister_boss(boss))
		eb.enemy_killed.connect(func(enemy, _pos): unregister_enemy(enemy))

	call_deferred("_scan_existing_entities")

func _scan_existing_entities() -> void:
	if not is_inside_tree():
		return
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty() and players[0] is Node3D:
		register_player(players[0] as Node3D)
	for b in get_tree().get_nodes_in_group("buildings"):
		if b is Node3D:
			register_building(b as Node3D)
	for r in get_tree().get_nodes_in_group("resource_nodes"):
		if r is Node3D:
			register_resource(r as Node3D)
	for e in get_tree().get_nodes_in_group("enemies"):
		register_enemy(e)
	for boss in get_tree().get_nodes_in_group("boss"):
		register_boss(boss)

func register_player(p: Node3D) -> void:
	if is_instance_valid(p) and p.is_inside_tree():
		player = p
	else:
		player = null

func unregister_player(p: Node3D) -> void:
	if player == p or not is_instance_valid(player):
		player = null

func get_player() -> Node3D:
	if not is_instance_valid(player) or not player.is_inside_tree():
		player = null
		if is_inside_tree():
			var players: Array[Node] = get_tree().get_nodes_in_group("player")
			for candidate in players:
				if is_instance_valid(candidate) and candidate is Node3D and candidate.is_inside_tree():
					player = candidate as Node3D
					break
	return player

func register_building(b: Node3D) -> void:
	if not b or not is_instance_valid(b):
		return
	if not buildings.has(b):
		buildings.append(b)
	# Check if building is blocking (walls and solid structures, excluding non-blocking traps)
	if b.is_in_group("walls") or (b.is_in_group("buildings") and not b.is_in_group("traps")):
		var cell: Vector2i = Vector2i(int(floorf(b.global_position.x)), int(floorf(b.global_position.z)))
		if building_to_cell.has(b):
			var old_cell: Vector2i = building_to_cell[b]
			if old_cell != cell:
				monster_flowfield.set_cell_blocked(old_cell, false)
		building_to_cell[b] = cell
		monster_flowfield.set_cell_blocked(cell, true)

func unregister_building(b: Node3D) -> void:
	buildings.erase(b)
	if building_to_cell.has(b):
		var cell: Vector2i = building_to_cell[b]
		building_to_cell.erase(b)
		monster_flowfield.set_cell_blocked(cell, false)

func register_resource(r: Node3D) -> void:
	if not r or not is_instance_valid(r):
		return
	var cell: Vector2i = Vector2i(int(floorf(r.global_position.x)), int(floorf(r.global_position.z)))
	if resource_to_cell.has(r):
		var old_cell: Vector2i = resource_to_cell[r]
		if old_cell != cell:
			monster_flowfield.set_cell_blocked(old_cell, false)
	resource_to_cell[r] = cell
	monster_flowfield.set_cell_blocked(cell, true)

func unregister_resource(r: Node3D) -> void:
	if resource_to_cell.has(r):
		var cell: Vector2i = resource_to_cell[r]
		resource_to_cell.erase(r)
		monster_flowfield.set_cell_blocked(cell, false)

func get_buildings() -> Array[Node3D]:
	_cleanup_buildings()
	return buildings

func get_nearest_building(pos: Vector3) -> Node3D:
	var nearest: Node3D = null
	var min_dist_sq: float = INF
	for i in range(buildings.size() - 1, -1, -1):
		var b_cand = buildings[i]
		if not is_instance_valid(b_cand) or not (b_cand is Node3D):
			buildings.remove_at(i)
			continue
		var b: Node3D = b_cand as Node3D
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
	player = null
	buildings.clear()
	enemies.clear()
	bosses.clear()
	building_to_cell.clear()
	resource_to_cell.clear()
	_spatial_buckets.clear()
	_last_spatial_frame = -1
	monster_flowfield.clear_all()
	monster_flowfield.clear_lookups()

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
## Automatically expands query radius to cover large neighbors (e.g. Boss Gorgon radius 1.2m)
## and evaluates actual 3D vertical volume overlap rather than asymmetric root offsets.
func get_nearby_enemies(pos: Vector3, radius: float, self_node: Node = null) -> Array[Node3D]:
	update_spatial_buckets_if_needed()
	var results: Array[Node3D] = []

	# Maximum neighbor radius across archetypes is 1.2m (Boss Gorgon) + 0.65m avoidance margin.
	# Query radius must cover self_radius + 1.85m to ensure large neighbors are detected before contact.
	var query_radius: float = maxf(radius + 1.85, 2.5)

	var min_bx: int = int(floorf((pos.x - query_radius) / BUCKET_SIZE))
	var max_bx: int = int(floorf((pos.x + query_radius) / BUCKET_SIZE))
	var min_bz: int = int(floorf((pos.z - query_radius) / BUCKET_SIZE))
	var max_bz: int = int(floorf((pos.z + query_radius) / BUCKET_SIZE))

	var self_bounds: Vector2
	if self_node and self_node is CharacterBody3D:
		self_bounds = MonsterLocomotion.get_body_vertical_bounds(self_node as CharacterBody3D)
	else:
		self_bounds = Vector2(pos.y - 0.9, pos.y + 0.9)

	for bx in range(min_bx, max_bx + 1):
		for bz in range(min_bz, max_bz + 1):
			var key: Vector2i = Vector2i(bx, bz)
			if _spatial_buckets.has(key):
				var bucket: Array[Node3D] = _spatial_buckets[key]
				for other in bucket:
					if other == self_node:
						continue

					# Check 3D vertical volume overlap (immune to different root-to-feet authored offsets)
					var other_bounds: Vector2
					if other is CharacterBody3D:
						other_bounds = MonsterLocomotion.get_body_vertical_bounds(other as CharacterBody3D)
					else:
						other_bounds = Vector2(other.global_position.y - 0.9, other.global_position.y + 0.9)

					if maxf(self_bounds.x, other_bounds.x) > minf(self_bounds.y, other_bounds.y) + 0.3:
						continue # Separate vertical tiers (no volume overlap)

					var other_radius: float = float(other.get("radius")) if other.get("radius") != null else 0.4
					var max_interact_dist: float = radius + other_radius + 0.65
					var dx: float = other.global_position.x - pos.x
					var dz: float = other.global_position.z - pos.z
					if (dx * dx + dz * dz) <= (max_interact_dist * max_interact_dist):
						results.append(other)
	return results

func _cleanup_buildings() -> void:
	for i in range(buildings.size() - 1, -1, -1):
		var b_cand = buildings[i]
		if not is_instance_valid(b_cand):
			if building_to_cell.has(b_cand):
				var cell: Vector2i = building_to_cell[b_cand]
				building_to_cell.erase(b_cand)
				monster_flowfield.set_cell_blocked(cell, false)
			buildings.remove_at(i)

func _cleanup_enemies() -> void:
	for i in range(enemies.size() - 1, -1, -1):
		if not is_instance_valid(enemies[i]):
			enemies.remove_at(i)

func _cleanup_bosses() -> void:
	for i in range(bosses.size() - 1, -1, -1):
		if not is_instance_valid(bosses[i]):
			bosses.remove_at(i)

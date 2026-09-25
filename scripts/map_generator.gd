extends Node3D
class_name MapGenerator

## MapGenerator: Expandable procedural voxel world with Forest, Plains,
## and Mountains macro-biomes, local chunk streaming, and deterministic generation.

signal map_generated(seed_used: int)

@export var random_seed: bool = true
@export var custom_seed: int = 1337
@export var load_radius_chunks: int = 3   # 7x7 chunks = 49 chunks (~96m across)
@export var unload_radius_chunks: int = 5 # Chunks beyond ~80m are unloaded
@export var portal_clear_radius: float = 6.5
@export var map_radius: int = 32 # Retained for API compatibility

var actual_seed: int = 0
var active_chunks: Dictionary = {}        # Vector2i -> Node3D (Terrain chunk)
var chunk_resources: Dictionary = {}      # Vector2i -> Array[Node]
var harvested_cells: Dictionary = {}      # Vector3i -> bool
var occupied_building_cells: Dictionary = {} # Vector2i -> true
var last_player_chunk: Vector2i = Vector2i(-999999, -999999)
var pending_load_chunks: Array[Vector2i] = []
@export var max_chunk_loads_per_frame: int = 1

var terrain_container: Node3D = null
var resources_container: Node3D = null
var event_bus: Node = null

# Materials
var mat_forest: StandardMaterial3D
var mat_plains: StandardMaterial3D
var mat_mountains: StandardMaterial3D
var mat_cliff: StandardMaterial3D

# Preloaded scenes
const SCENE_TREE = preload("res://scenes/resource_tree.tscn")
const SCENE_STONE = preload("res://scenes/resource_stone.tscn")
const SCENE_IRON = preload("res://scenes/resource_iron.tscn")
const EnvironmentScatter = preload("res://scripts/world/environment_scatter.gd")

@export_enum("Low", "Medium", "High") var scatter_density_level: int = EnvironmentScatter.PRODUCTION_DENSITY

func _ready() -> void:
	add_to_group("map_generator")
	terrain_container = get_node_or_null("Terrain")
	if not terrain_container:
		terrain_container = Node3D.new()
		terrain_container.name = "Terrain"
		add_child(terrain_container)

	resources_container = get_node_or_null("Resources")
	if not resources_container:
		resources_container = Node3D.new()
		resources_container.name = "Resources"
		add_child(resources_container)

	setup_materials()
	event_bus = get_node_or_null("/root/EventBus")
	_connect_building_events()
	_refresh_occupied_building_cells()
	generate_world()

func _exit_tree() -> void:
	if event_bus and event_bus.has_signal("building_placed") and event_bus.is_connected("building_placed", _on_building_placed):
		event_bus.disconnect("building_placed", _on_building_placed)
	if event_bus and event_bus.has_signal("building_destroyed") and event_bus.is_connected("building_destroyed", _on_building_destroyed):
		event_bus.disconnect("building_destroyed", _on_building_destroyed)
	for coord in active_chunks.keys():
		_free_chunk(coord)
	active_chunks.clear()
	chunk_resources.clear()

func setup_materials() -> void:
	## Load production terrain materials from authored asset resources.
	## These replace the previous runtime-generated prototype textures.
	mat_forest = load("res://assets/environment/terrain_materials/textures/material_forest.tres")
	mat_plains = load("res://assets/environment/terrain_materials/textures/material_plains.tres")
	mat_mountains = load("res://assets/environment/terrain_materials/textures/material_mountains.tres")
	mat_cliff = load("res://assets/environment/terrain_materials/textures/material_cliff.tres")


func generate_world() -> void:
	if random_seed:
		actual_seed = randi()
	else:
		actual_seed = custom_seed

	# Clear previous loaded chunks
	for coord in active_chunks.keys():
		_free_chunk(coord)
	active_chunks.clear()
	chunk_resources.clear()
	pending_load_chunks.clear()

	if terrain_container:
		for c in terrain_container.get_children():
			c.queue_free()
	if resources_container:
		for c in resources_container.get_children():
			c.queue_free()

	# Initial chunk loading around Portal (0, 0)
	for cz in range(-load_radius_chunks, load_radius_chunks + 1):
		for cx in range(-load_radius_chunks, load_radius_chunks + 1):
			load_chunk(cx, cz)

	last_player_chunk = Vector2i(0, 0)
	map_generated.emit(actual_seed)

func _process(_delta: float) -> void:
	var player_node: Node3D = _find_player()
	if not player_node:
		return

	var px: float = player_node.global_position.x
	var pz: float = player_node.global_position.z
	var cur_chunk: Vector2i = Vector2i(
		int(floorf(px / float(ChunkBuilder.CHUNK_SIZE))),
		int(floorf(pz / float(ChunkBuilder.CHUNK_SIZE)))
	)

	if cur_chunk != last_player_chunk:
		update_player_chunks(cur_chunk, false)
		last_player_chunk = cur_chunk

	# Amortize pending chunk generation across frames
	if not pending_load_chunks.is_empty():
		pending_load_chunks.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da: int = (a.x - cur_chunk.x) * (a.x - cur_chunk.x) + (a.y - cur_chunk.y) * (a.y - cur_chunk.y)
			var db: int = (b.x - cur_chunk.x) * (b.x - cur_chunk.x) + (b.y - cur_chunk.y) * (b.y - cur_chunk.y)
			return da < db
		)
		var loaded: int = 0
		while not pending_load_chunks.is_empty() and loaded < max_chunk_loads_per_frame:
			var next_chunk: Vector2i = pending_load_chunks.pop_front()
			if not active_chunks.has(next_chunk):
				var dx: int = absi(next_chunk.x - cur_chunk.x)
				var dz: int = absi(next_chunk.y - cur_chunk.y)
				if dx <= unload_radius_chunks and dz <= unload_radius_chunks:
					load_chunk(next_chunk.x, next_chunk.y)
					loaded += 1

func _find_player() -> Node3D:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		return players[0] as Node3D
	return null

func update_player_chunks(center_chunk: Vector2i, immediate: bool = true) -> void:
	# 1. Load or queue missing chunks in load radius
	for cz in range(center_chunk.y - load_radius_chunks, center_chunk.y + load_radius_chunks + 1):
		for cx in range(center_chunk.x - load_radius_chunks, center_chunk.x + load_radius_chunks + 1):
			var coord: Vector2i = Vector2i(cx, cz)
			if not active_chunks.has(coord):
				if immediate:
					load_chunk(cx, cz)
				elif not pending_load_chunks.has(coord):
					pending_load_chunks.append(coord)

	# 2. Unload distant chunks outside unload radius immediately
	var to_unload: Array[Vector2i] = []
	for coord: Vector2i in active_chunks.keys():
		var dx: int = absi(coord.x - center_chunk.x)
		var dz: int = absi(coord.y - center_chunk.y)
		if dx > unload_radius_chunks or dz > unload_radius_chunks:
			to_unload.append(coord)

	for coord: Vector2i in to_unload:
		unload_chunk(coord.x, coord.y)

	# 3. Discard pending chunks that moved outside unload radius
	if not immediate and not pending_load_chunks.is_empty():
		var valid_pending: Array[Vector2i] = []
		for p: Vector2i in pending_load_chunks:
			var dx: int = absi(p.x - center_chunk.x)
			var dz: int = absi(p.y - center_chunk.y)
			if dx <= unload_radius_chunks and dz <= unload_radius_chunks and not active_chunks.has(p):
				valid_pending.append(p)
		pending_load_chunks = valid_pending

func load_chunk(cx: int, cz: int) -> void:
	var coord: Vector2i = Vector2i(cx, cz)
	if active_chunks.has(coord):
		return
	_refresh_occupied_building_cells()

	# Build terrain mesh & collision
	var terrain_data: Dictionary = ChunkBuilder.build_chunk_terrain(
		cx,
		cz,
		actual_seed,
		mat_forest,
		mat_plains,
		mat_mountains,
		mat_cliff
	)

	var mesh: ArrayMesh = terrain_data["mesh"]
	var shape: Shape3D = terrain_data["shape"]

	var chunk_body: StaticBody3D = StaticBody3D.new()
	chunk_body.name = "Chunk_%d_%d" % [cx, cz]
	chunk_body.collision_layer = 1
	chunk_body.collision_mask = 0
	chunk_body.add_to_group("terrain")

	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	mesh_inst.mesh = mesh
	chunk_body.add_child(mesh_inst)

	if shape:
		var col_shape: CollisionShape3D = CollisionShape3D.new()
		col_shape.shape = shape
		chunk_body.add_child(col_shape)

	if terrain_container:
		terrain_container.add_child(chunk_body)
	else:
		add_child(chunk_body)

	active_chunks[coord] = chunk_body

	# Spawn resources and decorative details for this chunk
	var spawned_nodes: Array[Node] = []
	_spawn_chunk_resources(cx, cz, spawned_nodes)
	chunk_resources[coord] = spawned_nodes

func unload_chunk(cx: int, cz: int) -> void:
	var coord: Vector2i = Vector2i(cx, cz)
	if not active_chunks.has(coord):
		return
	_free_chunk(coord)
	active_chunks.erase(coord)
	chunk_resources.erase(coord)

func _free_chunk(coord: Vector2i) -> void:
	if active_chunks.has(coord):
		var body: Node = active_chunks[coord]
		if is_instance_valid(body):
			body.queue_free()

	if chunk_resources.has(coord):
		var nodes: Array = chunk_resources[coord]
		for n in nodes:
			if is_instance_valid(n):
				n.queue_free()

func _spawn_chunk_resources(cx: int, cz: int, out_nodes: Array[Node]) -> void:
	var origin_x: int = cx * ChunkBuilder.CHUNK_SIZE
	var origin_z: int = cz * ChunkBuilder.CHUNK_SIZE
	var scatter_instances: Dictionary = {}

	for lz in range(ChunkBuilder.CHUNK_SIZE):
		for lx in range(ChunkBuilder.CHUNK_SIZE):
			var wx: int = origin_x + lx
			var wz: int = origin_z + lz

			var dist: float = Vector2(float(wx), float(wz)).length()
			if dist <= portal_clear_radius:
				continue

			var y: int = BiomeSystem.get_voxel_height(wx, wz, actual_seed)
			var cell_key: Vector3i = Vector3i(wx, y, wz)
			if harvested_cells.has(cell_key):
				continue

			var h_pos: Vector3 = Vector3(float(wx) + 0.5, float(y), float(wz) + 0.5)

			# Deterministic hash for resource attempt and rolls
			var cell_seed: int = int((wx * 73856093) ^ (wz * 19349663) ^ (actual_seed * 83492791))
			var rng: RandomNumberGenerator = RandomNumberGenerator.new()
			rng.seed = cell_seed

			var attempt_roll: float = rng.randf()
			var biome_info: Dictionary = {}
			var continuous_h: float = 0.0
			var res_type: ResourceDistribution.ResourceType = ResourceDistribution.ResourceType.NONE
			if attempt_roll <= 0.16: # Preserve the existing resource attempt rate.
				biome_info = BiomeSystem.sample_biome_weights(float(wx), float(wz), actual_seed)
				continuous_h = BiomeSystem.sample_height(float(wx), float(wz), actual_seed)
				var res_roll: float = rng.randf()
				res_type = ResourceDistribution.roll_blended_resource_type(biome_info["weights"], continuous_h, res_roll)

			if res_type == ResourceDistribution.ResourceType.NONE:
				if _is_building_cell_occupied(Vector2i(wx, wz)):
					continue
				if not EnvironmentScatter.cluster_is_active(wx, wz, actual_seed):
					continue
				if biome_info.is_empty():
					biome_info = BiomeSystem.sample_biome_weights(float(wx), float(wz), actual_seed)
					continuous_h = BiomeSystem.sample_height(float(wx), float(wz), actual_seed)
				var mountain_weight: float = float(biome_info["weights"].get(BiomeSystem.BiomeType.MOUNTAINS, 0.0))
				var ledge_direction: Vector2i = Vector2i.ZERO
				if mountain_weight >= 0.45 and continuous_h > 5.0:
					ledge_direction = EnvironmentScatter.find_cliff_ledge_direction(wx, wz, actual_seed)
				var prop_id: StringName = EnvironmentScatter.choose_prop(
					wx,
					wz,
					actual_seed,
					cell_seed,
					biome_info["weights"],
					continuous_h,
					scatter_density_level,
					BiomeSystem.is_mountain_trail(wx, wz, actual_seed),
					ledge_direction != Vector2i.ZERO
				)
				if not prop_id.is_empty():
					var scatter_position: Vector3 = h_pos
					var rotation_offset: float = 0.0
					if prop_id == &"moss_cliff_ledge":
						scatter_position += Vector3(float(ledge_direction.x), 0.0, float(ledge_direction.y)) * 0.48
						rotation_offset = atan2(float(ledge_direction.x), float(ledge_direction.y))
					var scatter_transform: Transform3D = EnvironmentScatter.make_instance_transform(prop_id, scatter_position, cell_seed, rotation_offset)
					EnvironmentScatter.append_instance(scatter_instances, prop_id, scatter_transform, Vector2i(wx, wz))
				continue

			var form_roll: float = rng.randf()
			var var_roll: float = rng.randf()
			var details: Dictionary = ResourceDistribution.resolve_spawn_details(res_type, biome_info["weights"], continuous_h, form_roll, var_roll)

			# Ensure mountain trail corridor is NEVER blocked by solid FULL_DEPOSIT obstacles
			if BiomeSystem.is_mountain_trail(wx, wz, actual_seed):
				if details["deposit_form"] == ResourceDistribution.DepositForm.FULL_DEPOSIT:
					details["deposit_form"] = ResourceDistribution.DepositForm.FREE_PICKUP
					details["yield_amount"] = mini(int(details["yield_amount"]), 2)


			if details["deposit_form"] == ResourceDistribution.DepositForm.FREE_PICKUP:
				var pickup: FreeResourcePickup = FreeResourcePickup.new()
				pickup.resource_type = details["resource_type"]
				pickup.yield_amount = details["yield_amount"]
				pickup.variation_index = details["variation_index"]
				pickup.position = h_pos
				if resources_container:
					resources_container.add_child(pickup)
				else:
					add_child(pickup)
				out_nodes.append(pickup)

			elif details["deposit_form"] == ResourceDistribution.DepositForm.FULL_DEPOSIT:
				var node: Node3D = null
				var rock_visual_index: int = ResourceRock.visual_variant_for_cell(cell_seed)
				if res_type == ResourceDistribution.ResourceType.WOOD:
					node = SCENE_TREE.instantiate()
					if node.has_method("configure_tree"):
						node.configure_tree(details["variation_index"], details["yield_amount"])
				elif res_type == ResourceDistribution.ResourceType.STONE:
					node = SCENE_STONE.instantiate()
					if node.has_method("configure_rock"):
						node.configure_rock(0, details["yield_amount"], details["tier"], rock_visual_index)
				elif res_type == ResourceDistribution.ResourceType.IRON:
					node = SCENE_IRON.instantiate()
					if node.has_method("configure_rock"):
						node.configure_rock(1, details["yield_amount"], details["tier"], rock_visual_index)

				if node:
					node.position = h_pos
					if resources_container:
						resources_container.add_child(node)
					else:
						add_child(node)
					out_nodes.append(node)

				var forest_weight: float = float(biome_info["weights"].get(BiomeSystem.BiomeType.FOREST, 0.0))
				var moss_id: StringName = EnvironmentScatter.choose_associated_moss(
					res_type,
					forest_weight,
					cell_seed,
					scatter_density_level
				)
				if not moss_id.is_empty() and not _is_building_cell_occupied(Vector2i(wx, wz)):
					var moss_transform: Transform3D = EnvironmentScatter.make_instance_transform(moss_id, h_pos, cell_seed)
					EnvironmentScatter.append_instance(scatter_instances, moss_id, moss_transform, Vector2i(wx, wz))

	for scatter_node: Node in EnvironmentScatter.create_multimesh_nodes(scatter_instances):
		if resources_container:
			resources_container.add_child(scatter_node)
		else:
			add_child(scatter_node)
		out_nodes.append(scatter_node)

func _connect_building_events() -> void:
	if not event_bus:
		return
	if event_bus.has_signal("building_placed") and not event_bus.is_connected("building_placed", _on_building_placed):
		event_bus.connect("building_placed", _on_building_placed)
	if event_bus.has_signal("building_destroyed") and not event_bus.is_connected("building_destroyed", _on_building_destroyed):
		event_bus.connect("building_destroyed", _on_building_destroyed)

func _refresh_occupied_building_cells() -> void:
	for building_system: Node in get_tree().get_nodes_in_group("building_system"):
		var placed_buildings: Dictionary = building_system.get("placed_buildings")
		for cell_value: Variant in placed_buildings:
			occupied_building_cells[cell_value] = true

func _is_building_cell_occupied(cell: Vector2i) -> bool:
	return occupied_building_cells.has(cell)

func _on_building_placed(_building_id: String, cell: Vector2i, _building: Node) -> void:
	occupied_building_cells[cell] = true
	_remove_scatter_at_cell(cell)

func _on_building_destroyed(cell: Vector2i, _building: Node) -> void:
	occupied_building_cells.erase(cell)

func _remove_scatter_at_cell(cell: Vector2i) -> void:
	var chunk_coord: Vector2i = Vector2i(
		floori(float(cell.x) / float(ChunkBuilder.CHUNK_SIZE)),
		floori(float(cell.y) / float(ChunkBuilder.CHUNK_SIZE))
	)
	if not chunk_resources.has(chunk_coord):
		return
	var nodes: Array = chunk_resources[chunk_coord]
	for node_index: int in range(nodes.size() - 1, -1, -1):
		var node: Node = nodes[node_index]
		if not node is MultiMeshInstance3D or not String(node.name).begins_with("Scatter_"):
			continue
		var scatter: MultiMeshInstance3D = node as MultiMeshInstance3D
		var cells: Array = scatter.get_meta("scatter_cells", [])
		var retained_cells: Array[Vector2i] = []
		var retained_transforms: Array[Transform3D] = []
		for instance_index: int in range(scatter.multimesh.instance_count):
			var instance_cell: Vector2i = cells[instance_index] if instance_index < cells.size() else Vector2i(-2147483648, -2147483648)
			if instance_cell == cell:
				continue
			retained_cells.append(instance_cell)
			retained_transforms.append(scatter.multimesh.get_instance_transform(instance_index))
		if retained_transforms.size() == scatter.multimesh.instance_count:
			continue
		if retained_transforms.is_empty():
			nodes.remove_at(node_index)
			node.queue_free()
			continue
		scatter.multimesh.instance_count = retained_transforms.size()
		for instance_index: int in retained_transforms.size():
			scatter.multimesh.set_instance_transform(instance_index, retained_transforms[instance_index])
		scatter.set_meta("scatter_cells", retained_cells)

## Public authoritative height lookup: returns integer voxel height at world (x, z).
func get_voxel_height(x: int, z: int) -> int:
	return BiomeSystem.get_voxel_height(x, z, actual_seed)

## Public authoritative continuous height lookup at world (x, z).
func sample_height(x: float, z: float) -> float:
	return BiomeSystem.sample_height(x, z, actual_seed)

## Public authoritative biome lookup at world (x, z).
func sample_biome(x: float, z: float) -> Dictionary:
	return BiomeSystem.sample_biome_weights(x, z, actual_seed)

## Records that a resource at world_pos was harvested, preventing respawn upon chunk reload.
func record_harvest(world_pos: Vector3) -> void:
	var wx: int = int(floorf(world_pos.x))
	var wz: int = int(floorf(world_pos.z))
	var wy: int = BiomeSystem.get_voxel_height(wx, wz, actual_seed)
	var key: Vector3i = Vector3i(wx, wy, wz)
	harvested_cells[key] = true

func is_harvested(world_pos: Vector3) -> bool:
	var wx: int = int(floorf(world_pos.x))
	var wz: int = int(floorf(world_pos.z))
	var wy: int = BiomeSystem.get_voxel_height(wx, wz, actual_seed)
	var key: Vector3i = Vector3i(wx, wy, wz)
	return harvested_cells.has(key)

# Backward-compatibility helpers
func create_cube(x: int, y_layer: int, z: int, mat: Material) -> void:
	pass

func spawn_resource(scene: PackedScene, pos: Vector3) -> void:
	if scene and resources_container:
		var res: Node3D = scene.instantiate()
		resources_container.add_child(res)
		res.global_position = pos

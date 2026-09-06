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
var last_player_chunk: Vector2i = Vector2i(-999999, -999999)

var terrain_container: Node3D = null
var resources_container: Node3D = null

# Materials
var mat_forest: StandardMaterial3D
var mat_plains: StandardMaterial3D
var mat_mountains: StandardMaterial3D
var mat_cliff: StandardMaterial3D

# Preloaded scenes
const SCENE_TREE = preload("res://scenes/resource_tree.tscn")
const SCENE_STONE = preload("res://scenes/resource_stone.tscn")
const SCENE_IRON = preload("res://scenes/resource_iron.tscn")

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
	generate_world()

func _exit_tree() -> void:
	for coord in active_chunks.keys():
		_free_chunk(coord)
	active_chunks.clear()
	chunk_resources.clear()

func setup_materials() -> void:

	mat_forest = StandardMaterial3D.new()
	mat_forest.albedo_texture = _create_voxel_texture(Color(0.20, 0.44, 0.20, 1.0), Color(0.15, 0.36, 0.15, 1.0), 0)
	mat_forest.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat_forest.roughness = 0.85

	mat_plains = StandardMaterial3D.new()
	mat_plains.albedo_texture = _create_voxel_texture(Color(0.38, 0.58, 0.22, 1.0), Color(0.85, 0.82, 0.35, 1.0), 1)
	mat_plains.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat_plains.roughness = 0.85

	mat_mountains = StandardMaterial3D.new()
	mat_mountains.albedo_texture = _create_voxel_texture(Color(0.48, 0.49, 0.52, 1.0), Color(0.35, 0.36, 0.38, 1.0), 2)
	mat_mountains.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat_mountains.roughness = 0.90

	mat_cliff = StandardMaterial3D.new()
	mat_cliff.albedo_texture = _create_voxel_texture(Color(0.32, 0.30, 0.28, 1.0), Color(0.22, 0.20, 0.18, 1.0), 3)
	mat_cliff.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat_cliff.roughness = 0.92

func _create_voxel_texture(base_col: Color, accent_col: Color, pattern_type: int) -> ImageTexture:
	var img: Image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in range(16):
		for x in range(16):
			var col: Color = base_col
			var is_border: bool = (x == 0 or x == 15 or y == 0 or y == 15)
			match pattern_type:
				0: # Forest grass with blade accents
					if is_border:
						col = base_col.darkened(0.12)
					elif ((x * 7 + y * 13) % 11) == 0:
						col = accent_col
				1: # Plains meadow with tiny wildflower speckles
					if is_border:
						col = base_col.darkened(0.08)
					elif (x == 4 and y == 5) or (x == 11 and y == 12) or (x == 7 and y == 9):
						col = accent_col
				2: # Mountain slate facets and chisel lines
					if is_border:
						col = base_col.darkened(0.18)
					elif ((x + y * 3) % 5) == 0:
						col = accent_col
					elif ((x * 2 + y) % 7) == 0:
						col = base_col.lightened(0.12)
				3: # Cliff horizontal strata layers
					if (y % 4) == 0:
						col = base_col.darkened(0.25)
					elif (y % 4) == 2:
						col = accent_col
					elif is_border:
						col = base_col.darkened(0.15)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


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
		update_player_chunks(cur_chunk)
		last_player_chunk = cur_chunk

func _find_player() -> Node3D:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		return players[0] as Node3D
	return null

func update_player_chunks(center_chunk: Vector2i) -> void:
	# 1. Load missing chunks in load radius
	for cz in range(center_chunk.y - load_radius_chunks, center_chunk.y + load_radius_chunks + 1):
		for cx in range(center_chunk.x - load_radius_chunks, center_chunk.x + load_radius_chunks + 1):
			var coord: Vector2i = Vector2i(cx, cz)
			if not active_chunks.has(coord):
				load_chunk(cx, cz)

	# 2. Unload distant chunks outside unload radius
	var to_unload: Array[Vector2i] = []
	for coord: Vector2i in active_chunks.keys():
		var dx: int = absi(coord.x - center_chunk.x)
		var dz: int = absi(coord.y - center_chunk.y)
		if dx > unload_radius_chunks or dz > unload_radius_chunks:
			to_unload.append(coord)

	for coord: Vector2i in to_unload:
		unload_chunk(coord.x, coord.y)

func load_chunk(cx: int, cz: int) -> void:
	var coord: Vector2i = Vector2i(cx, cz)
	if active_chunks.has(coord):
		return

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
			if attempt_roll > 0.16: # Base density of attempts ~16%
				continue

			var biome_info: Dictionary = BiomeSystem.sample_biome_weights(float(wx), float(wz), actual_seed)
			var biome: BiomeSystem.BiomeType = biome_info["primary"]
			var continuous_h: float = BiomeSystem.sample_height(float(wx), float(wz), actual_seed)

			var res_roll: float = rng.randf()
			var res_type: ResourceDistribution.ResourceType = ResourceDistribution.roll_blended_resource_type(biome_info["weights"], continuous_h, res_roll)

			if res_type == ResourceDistribution.ResourceType.NONE:
				# Spawn non-colliding decorative details for Plains
				if biome == BiomeSystem.BiomeType.PLAINS and rng.randf() < 0.45:
					var grass: Node3D = _create_decorative_grass(h_pos, rng)
					if resources_container:
						resources_container.add_child(grass)
					else:
						add_child(grass)
					out_nodes.append(grass)
				continue

			var form_roll: float = rng.randf()
			var var_roll: float = rng.randf()
			var details: Dictionary = ResourceDistribution.resolve_spawn_details(res_type, biome, continuous_h, form_roll, var_roll)

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
				if res_type == ResourceDistribution.ResourceType.WOOD:
					node = SCENE_TREE.instantiate()
					if node.has_method("configure_tree"):
						node.configure_tree(details["variation_index"], details["yield_amount"])
				elif res_type == ResourceDistribution.ResourceType.STONE:
					node = SCENE_STONE.instantiate()
					if node.has_method("configure_rock"):
						node.configure_rock(0, details["yield_amount"], details["tier"], details["variation_index"])
				elif res_type == ResourceDistribution.ResourceType.IRON:
					node = SCENE_IRON.instantiate()
					if node.has_method("configure_rock"):
						node.configure_rock(1, details["yield_amount"], details["tier"], details["variation_index"])

				if node:
					node.position = h_pos
					if resources_container:
						resources_container.add_child(node)
					else:
						add_child(node)
					out_nodes.append(node)

func _create_decorative_grass(pos: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var grass_node: Node3D = Node3D.new()
	grass_node.position = pos
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	var h: float = 0.3 + rng.randf() * 0.35
	box.size = Vector3(0.3, h, 0.3)
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.36 + rng.randf() * 0.1, 0.65 + rng.randf() * 0.1, 0.20, 1.0)
	mat.roughness = 0.9
	box.material = mat
	mesh_inst.mesh = box
	mesh_inst.position.y = h * 0.5
	mesh_inst.rotation_degrees.y = rng.randf() * 180.0
	grass_node.add_child(mesh_inst)
	return grass_node

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

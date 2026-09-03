extends Node3D
class_name MapGenerator

signal map_generated(seed_used: int)

@export var random_seed: bool = true
@export var custom_seed: int = 1337
@export var map_radius: int = 32 # 64x64 grid (-32 to 32)
@export var portal_clear_radius: float = 6.5

var actual_seed: int = 0
var noise_height: FastNoiseLite
var noise_forest: FastNoiseLite
var noise_minerals: FastNoiseLite

const SCENE_TREE = preload("res://scenes/resource_tree.tscn")
const SCENE_STONE = preload("res://scenes/resource_stone.tscn")
const SCENE_IRON = preload("res://scenes/resource_iron.tscn")

@onready var resources_container: Node3D = $Resources
@onready var terrain_container: Node3D = $Terrain

# Materials
var mat_grass_cliff: StandardMaterial3D
var mat_rock_cliff: StandardMaterial3D
var mat_border_cliff: StandardMaterial3D

func _ready() -> void:
	setup_materials()
	generate_world()

func setup_materials() -> void:
	mat_grass_cliff = StandardMaterial3D.new()
	mat_grass_cliff.albedo_color = Color(0.24, 0.42, 0.22, 1.0)
	mat_grass_cliff.roughness = 0.85

	mat_rock_cliff = StandardMaterial3D.new()
	mat_rock_cliff.albedo_color = Color(0.42, 0.44, 0.46, 1.0)
	mat_rock_cliff.roughness = 0.9

	mat_border_cliff = StandardMaterial3D.new()
	mat_border_cliff.albedo_color = Color(0.25, 0.26, 0.28, 1.0)
	mat_border_cliff.roughness = 0.95

func init_noises() -> void:
	if random_seed:
		actual_seed = randi()
	else:
		actual_seed = custom_seed

	noise_height = FastNoiseLite.new()
	noise_height.seed = actual_seed
	noise_height.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_height.frequency = 0.045

	noise_forest = FastNoiseLite.new()
	noise_forest.seed = actual_seed + 101
	noise_forest.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_forest.frequency = 0.08

	noise_minerals = FastNoiseLite.new()
	noise_minerals.seed = actual_seed + 202
	noise_minerals.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_minerals.frequency = 0.075

func generate_world() -> void:
	init_noises()

	# Clear previous children if any
	for c in resources_container.get_children():
		c.queue_free()
	for c in terrain_container.get_children():
		c.queue_free()

	# Generate Grid
	for x in range(-map_radius, map_radius + 1):
		for z in range(-map_radius, map_radius + 1):
			generate_cell(x, z)

	emit_signal("map_generated", actual_seed)

func generate_cell(x: int, z: int) -> void:
	var dist_from_center: float = Vector2(x, z).length()
	var is_border: bool = (abs(x) >= map_radius - 2 or abs(z) >= map_radius - 2)

	# 1. Border mountains (Height 3 cubes stacked: y=0, 1, 2)
	if is_border:
		create_cube(x, 0, z, mat_border_cliff)
		create_cube(x, 1, z, mat_border_cliff)
		create_cube(x, 2, z, mat_border_cliff)
		return

	# 2. Portal Sanctuary: strictly flat at Y=0, no obstacles
	if dist_from_center <= portal_clear_radius:
		return

	# 3. Sample elevation noise
	var h_val: float = noise_height.get_noise_2d(float(x), float(z))

	if h_val > 0.38:
		# High cliff rock (Height 2 cubes stacked: y=0, 1) - impassable chokepoints
		create_cube(x, 0, z, mat_rock_cliff)
		create_cube(x, 1, z, mat_rock_cliff)
		return
	elif h_val > 0.18:
		# Low plateau (Height 1 cube: y=0, top surface is y=1.0)
		create_cube(x, 0, z, mat_grass_cliff)

	# 4. Resource generation on walkable ground (Height 0.0 on plains, 1.0 on hill)
	var spawn_y: float = 1.0 if h_val > 0.18 else 0.0

	var f_val: float = noise_forest.get_noise_2d(float(x), float(z))
	var m_val: float = noise_minerals.get_noise_2d(float(x), float(z))

	# Cluster rules
	if f_val > 0.34 and randf() < 0.40:
		spawn_resource(SCENE_TREE, Vector3(x, spawn_y, z))
	elif m_val > 0.36 and randf() < 0.35:
		if m_val > 0.52:
			spawn_resource(SCENE_IRON, Vector3(x, spawn_y, z))
		else:
			spawn_resource(SCENE_STONE, Vector3(x, spawn_y, z))

func create_cube(x: int, y_layer: int, z: int, mat: Material) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	terrain_container.add_child(body)
	body.global_position = Vector3(float(x), float(y_layer) + 0.5, float(z))
	body.collision_layer = 1
	body.collision_mask = 0
	body.add_to_group("terrain")

	# 1.0 x 1.0 x 1.0 Cube Mesh
	var mesh_inst: MeshInstance3D = MeshInstance3D.new()
	var box_mesh: BoxMesh = BoxMesh.new()
	box_mesh.size = Vector3(1.0, 1.0, 1.0)
	box_mesh.material = mat
	mesh_inst.mesh = box_mesh
	body.add_child(mesh_inst)

	# 1.0 x 1.0 x 1.0 Cube Collision Box
	var col: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = Vector3(1.0, 1.0, 1.0)
	col.shape = box_shape
	body.add_child(col)

func spawn_resource(scene: PackedScene, pos: Vector3) -> void:
	var res: Node3D = scene.instantiate()
	resources_container.add_child(res)
	res.global_position = pos

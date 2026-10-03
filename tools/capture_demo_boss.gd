extends SceneTree

## Bounded diagnostic capture of the real Gorgon warning/charge on voxel stairs.
## Godot --path . -s tools/capture_demo_boss.gd --write-movie <output.avi>
const BOSS_SCENE: PackedScene = preload("res://scenes/enemies/boss_gorgon.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

class StairTerrain extends MapGenerator:
	func _ready() -> void:
		set_process(false)

	func get_voxel_height(_x: int, z: int) -> int:
		if z < -12:
			return 3
		if z < -8:
			return 2
		return 1 if z < -4 else 0

var output_dir: String = "screenshots_debug/demo_polish/boss"

func _initialize() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	call_deferred("_capture")

func _floor(parent: Node3D, position: Vector3, size: Vector3, color: Color) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	var box_shape: BoxShape3D = BoxShape3D.new()
	box_shape.size = size
	shape_node.shape = box_shape
	body.add_child(shape_node)
	var mesh_node: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material = material
	mesh_node.mesh = mesh
	body.add_child(mesh_node)
	parent.add_child(body)
	body.global_position = position

func _capture() -> void:
	create_timer(30.0).timeout.connect(func() -> void:
		push_error("DEMO_BOSS_CAPTURE TIMEOUT after 30 seconds")
		quit(1)
	)
	DirAccess.make_dir_recursive_absolute(output_dir)
	var world: Node3D = Node3D.new()
	root.add_child(world)
	current_scene = world
	var terrain: StairTerrain = StairTerrain.new()
	terrain.add_to_group("map_generator")
	world.add_child(terrain)
	_floor(world, Vector3(0, -0.5, -4), Vector3(30, 1, 32), Color(0.22, 0.31, 0.18))
	_floor(world, Vector3(0, 0.5, -6), Vector3(30, 1, 4), Color(0.28, 0.37, 0.21))
	_floor(world, Vector3(0, 1.0, -10), Vector3(30, 2, 4), Color(0.32, 0.39, 0.24))
	_floor(world, Vector3(0, 1.5, -16), Vector3(30, 3, 8), Color(0.36, 0.42, 0.28))
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.10, 0.15, 0.18)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.75, 0.80, 0.86)
	environment.environment.ambient_light_energy = 0.7
	world.add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(15, 20, 11)
	camera.rotation_degrees = Vector3(-43.3, 45, 0)
	camera.fov = 45.0
	world.add_child(camera)
	camera.make_current()
	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	world.add_child(player)
	player.global_position = Vector3(3.5, 1.9, -6)
	player.set_physics_process(false)
	player.set_process(false)
	camera.make_current()
	var registry: Node = root.get_node_or_null("EntityRegistry")
	if registry:
		registry.monster_flowfield.set_height_lookup(terrain.get_voxel_height)
	var boss: CharacterBody3D = BOSS_SCENE.instantiate()
	world.add_child(boss)
	boss.global_position = Vector3(0, 0, 4)
	boss.target_player = player
	boss.charge_cooldown_timer = 99.0
	for _frame in range(4):
		await physics_frame
	boss.start_telegraph(Vector3.FORWARD)
	for frame in range(190):
		await physics_frame
		await process_frame
		await RenderingServer.frame_post_draw
		if frame in [10, 55, 105, 155]:
			var image: Image = root.get_texture().get_image()
			var path: String = "%s/boss_%03d.png" % [output_dir, frame]
			if image.save_png(path) != OK:
				push_error("Could not save " + path)
				quit(1)
				return
	print("DEMO_BOSS_CAPTURE PASS: 190 physics frames, real windup/charge/recovery")
	quit(0)

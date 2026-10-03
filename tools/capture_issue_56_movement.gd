extends SceneTree

## Capture visual proof for Issue #56:
## 1. Authoritative 1-block step-up assist on voxel stairs.
## 2. Local crowd avoidance and physical collision without mutual penetration.
## 3. Monster archetypes (Grunt, Skirmisher, Siege Breaker, Boss Gorgon).

const ENEMY_DUMMY_SCENE = preload("res://scenes/enemy_dummy.tscn")
const SKIRMISHER_SCENE = preload("res://scenes/enemies/ranged_skirmisher.tscn")
const SIEGE_BREAKER_SCENE = preload("res://scenes/enemies/siege_breaker.tscn")
const BOSS_GORGON_SCENE = preload("res://scenes/enemies/boss_gorgon.tscn")
const PLAYER_SCENE = preload("res://scenes/player.tscn")

var _output_dir: String = "review"
var _frames_dir: String = "review/frames_56"
var _frame_count: int = 0

func _initialize() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	call_deferred("_run_capture")

func _create_voxel_step(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> StaticBody3D:
	var body = StaticBody3D.new()
	parent.add_child(body)
	body.collision_layer = 1
	body.collision_mask = 0
	body.global_position = pos

	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)

	var mesh_inst = MeshInstance3D.new()
	var box_mesh = BoxMesh.new()
	box_mesh.size = size
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	box_mesh.material = mat
	mesh_inst.mesh = box_mesh
	body.add_child(mesh_inst)

	return body

func _run_capture() -> void:
	var watchdog = create_timer(30.0)
	watchdog.timeout.connect(func():
		push_error("[Watchdog] Capture timed out!")
		quit(1)
	)

	DirAccess.make_dir_recursive_absolute(_output_dir)
	DirAccess.make_dir_recursive_absolute(_frames_dir)

	var scene_root: Node3D = Node3D.new()
	root.add_child(scene_root)
	current_scene = scene_root

	# Environment
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.15, 0.18)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.70, 0.75)
	env_node.environment = env
	scene_root.add_child(env_node)

	var sun = DirectionalLight3D.new()
	scene_root.add_child(sun)
	sun.position = Vector3(15, 25, 15)
	sun.rotation_degrees = Vector3(-50, 45, 0)
	sun.shadow_enabled = true

	# Base ground at Y = 0 (top at Y = 0)
	_create_voxel_step(scene_root, Vector3(0, -0.5, 0), Vector3(40, 1, 40), Color(0.20, 0.28, 0.18))

	# Voxel Staircase from Z = 2 to Z = -6 (steps at Y = 1.0, 2.0, 3.0)
	# Step 1: Y = 1.0 (center at Y = 0.5, height = 1)
	_create_voxel_step(scene_root, Vector3(0, 0.5, 0), Vector3(8, 1, 3), Color(0.35, 0.38, 0.32))
	# Step 2: Y = 2.0 (center at Y = 1.0, height = 2)
	_create_voxel_step(scene_root, Vector3(0, 1.0, -3), Vector3(8, 2, 3), Color(0.40, 0.43, 0.36))
	# Step 3: Y = 3.0 (center at Y = 1.5, height = 3)
	_create_voxel_step(scene_root, Vector3(0, 1.5, -6), Vector3(8, 3, 3), Color(0.45, 0.48, 0.40))

	# Player Target at top of stairs (Z = -6, Y = 3.0)
	var player = PLAYER_SCENE.instantiate() as CharacterBody3D
	scene_root.add_child(player)
	player.global_position = Vector3(0, 3.0, -6.0)

	# Monsters at base of stairs moving up towards player
	var grunt1 = ENEMY_DUMMY_SCENE.instantiate() as CharacterBody3D
	scene_root.add_child(grunt1)
	grunt1.global_position = Vector3(-1.2, 0.0, 4.0)

	var grunt2 = ENEMY_DUMMY_SCENE.instantiate() as CharacterBody3D
	scene_root.add_child(grunt2)
	grunt2.global_position = Vector3(1.2, 0.0, 4.2)

	var skirmisher = SKIRMISHER_SCENE.instantiate() as CharacterBody3D
	scene_root.add_child(skirmisher)
	skirmisher.global_position = Vector3(0.0, 0.0, 5.5)

	var siege = SIEGE_BREAKER_SCENE.instantiate() as CharacterBody3D
	scene_root.add_child(siege)
	siege.global_position = Vector3(-2.2, 0.0, 6.5)

	var gorgon = BOSS_GORGON_SCENE.instantiate() as CharacterBody3D
	scene_root.add_child(gorgon)
	gorgon.global_position = Vector3(2.5, 0.0, 7.5)

	# Camera: Isometric view framed to observe stair climb and crowd interaction
	var camera = Camera3D.new()
	scene_root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 45.0
	camera.position = Vector3(9.0, 8.5, 9.0)
	camera.look_at(Vector3(0.0, 1.5, -1.0), Vector3.UP)
	camera.make_current()

	# Settle physics for 5 frames
	for f in 5:
		await process_frame

	print("[Capture] Starting frame recording...")

	# Simulate 120 physics frames (~2.0 seconds) capturing progression
	for frame_idx in range(120):
		await process_frame
		await physics_frame

		# Capture viewport
		var img: Image = root.get_texture().get_image()
		var frame_path: String = "%s/frame_%04d.png" % [_frames_dir, frame_idx]
		img.save_png(frame_path)

		if frame_idx == 40:
			img.save_png("%s/issue_56_stairs_climb.png" % _output_dir)
			print("[Capture] Saved review/issue_56_stairs_climb.png")

		if frame_idx == 85:
			img.save_png("%s/issue_56_crowd_separation.png" % _output_dir)
			print("[Capture] Saved review/issue_56_crowd_separation.png")

	print("[Capture] Completed recording 120 frames.")
	quit(0)

extends SceneTree

## Capture visual proof for Issue #54:
## Resource pickup floating text lifecycle: spawn -> rise/fade -> complete deletion.

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const TREE_SCENE = preload("res://scenes/resource_tree.tscn")
const STONE_SCENE = preload("res://scenes/resource_stone.tscn")
const HUD_SCENE = preload("res://scenes/hud.tscn")

var _output_dir: String = "review"
var _frames_dir: String = "review/frames"
var _frame_count: int = 0

func _initialize() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	call_deferred("_run_capture")

func _run_capture() -> void:
	var watchdog = create_timer(25.0)
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
	env.background_color = Color(0.14, 0.18, 0.22)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.70, 0.75)
	env_node.environment = env
	scene_root.add_child(env_node)

	var sun = DirectionalLight3D.new()
	sun.position = Vector3(10, 20, 10)
	sun.rotation_degrees = Vector3(-45, 40, 0)
	sun.shadow_enabled = true
	scene_root.add_child(sun)

	# Ground
	var floor_body = StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	floor_shape.shape = box
	floor_shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(floor_shape)

	var floor_mesh = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(30, 30)
	var floor_mat = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.25, 0.38, 0.22)
	plane_mesh.material = floor_mat
	floor_mesh.mesh = plane_mesh
	floor_body.add_child(floor_mesh)
	scene_root.add_child(floor_body)

	# HUD
	var hud = HUD_SCENE.instantiate() as CanvasLayer
	scene_root.add_child(hud)

	# Player
	var player = PLAYER_SCENE.instantiate() as CharacterBody3D
	scene_root.add_child(player)
	player.global_position = Vector3(0, 0, 0)

	var bs = BuildingSystem.new()
	bs.name = "BuildingSystem"
	player.add_child(bs)
	player.building_system = bs

	# Tree and Stone Rock
	var tree = TREE_SCENE.instantiate() as ResourceTree
	scene_root.add_child(tree)
	tree.global_position = Vector3(1.8, 0, 0)

	var stone = STONE_SCENE.instantiate() as ResourceRock
	scene_root.add_child(stone)
	stone.global_position = Vector3(-1.8, 0, 0)

	# Camera: positioned to frame both resources and their rising floating texts
	var camera: Camera3D = Camera3D.new()
	scene_root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 52.0
	camera.position = Vector3(0.0, 3.0, 5.8)
	camera.look_at(Vector3(0.0, 1.6, 0.0), Vector3.UP)
	camera.make_current()

	# Settle initial state
	for i in 15:
		await process_frame

	tree.fell_tree()
	stone.break_rock()

	for i in 10:
		await process_frame

	# Phase 1: Resource ready for harvest
	await _record_frame("1_resource_ready.png")

	# Trigger harvest on tree
	tree.harvest(player)

	# Record sequence of 36 frames (~1.2s at 30fps)
	for f in 36:
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		var frame_path: String = _frames_dir.path_join("frame_%03d.png" % _frame_count)
		img.save_png(frame_path)
		_frame_count += 1

		if f == 4:
			img.save_png(_output_dir.path_join("2_pickup_spawned.png"))
		elif f == 16:
			img.save_png(_output_dir.path_join("3_pickup_rising.png"))
		elif f == 34:
			img.save_png(_output_dir.path_join("4_pickup_cleared.png"))

	# Also trigger stone harvest to show stone notification
	stone.harvest(player)
	for f in 36:
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		var frame_path: String = _frames_dir.path_join("frame_%03d.png" % _frame_count)
		img.save_png(frame_path)
		_frame_count += 1

	print("[Issue54 Capture] Recorded %d frames in %s" % [_frame_count, _frames_dir])
	quit(0)

func _record_frame(rel_path: String) -> void:
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var capture: Image = root.get_texture().get_image()
	if capture and not capture.is_empty():
		capture.save_png(_output_dir.path_join(rel_path))
		print("[Issue54 Capture] Saved keyframe: " + rel_path)

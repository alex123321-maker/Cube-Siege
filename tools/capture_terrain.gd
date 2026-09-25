extends SceneTree
## Render deterministic terrain views after the camera and streaming have settled.
## godot --path . --script res://tools/capture_terrain.gd [-- --output res://directory]

const CAPTURE_POINTS: Array[Dictionary] = [
	{"name": "runtime_forest_close", "cell": Vector2i(35, 15), "distance": 10.0},
	{"name": "runtime_forest_gameplay", "cell": Vector2i(35, 15), "distance": 24.0},
	{"name": "runtime_plains", "cell": Vector2i(-35, 55), "distance": 24.0},
	{"name": "runtime_mountain_top", "cell": Vector2i(-75, -115), "distance": 24.0},
	{"name": "runtime_cliff", "cell": Vector2i(-75, -115), "distance": 12.0},
	{"name": "runtime_forest_plains_boundary", "cell": Vector2i(0, 60), "distance": 24.0},
	{"name": "runtime_plains_mountain_boundary", "cell": Vector2i(-60, -15), "distance": 24.0},
]

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Terrain screenshots require a rendering display.")
		quit(1)
		return
	var output: String = "res://docs/terrain_capture"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = args.find("--output")
	if index >= 0 and index + 1 < args.size():
		output = args[index + 1]
	DirAccess.make_dir_recursive_absolute(output)
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	var map: MapGenerator = main.get_node("MapGenerator")
	map.random_seed = false
	map.custom_seed = 1337
	root.add_child(main)
	current_scene = main
	# Freeze gameplay in this disposable review scene while retaining terrain and lighting.
	main.process_mode = Node.PROCESS_MODE_DISABLED
	var player: Node3D = main.get_node("Player")
	player.visible = false
	main.get_node("Enemies").visible = false
	var hud: CanvasLayer = main.get_node_or_null("HUD") as CanvasLayer
	if hud:
		hud.visible = false
	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 500.0
	camera.make_current()
	for point: Dictionary in CAPTURE_POINTS:
		var cell: Vector2i = point.cell
		var target: Vector3 = Vector3(cell.x, map.get_voxel_height(cell.x, cell.y), cell.y)
		map.update_player_chunks(Vector2i(floori(cell.x / 16.0), floori(cell.y / 16.0)), true)
		camera.size = point.distance
		camera.position = target + Vector3(25, 32, 25)
		camera.look_at(target, Vector3.UP)
		for frame: int in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		var capture: Image = root.get_texture().get_image()
		if capture == null or capture.is_empty() or capture.save_png(output.path_join(point.name + ".png")) != OK:
			push_error("Cannot save terrain view: " + point.name)
			quit(1)
			return
		print("[Capture] Saved: " + point.name)
	quit(0)

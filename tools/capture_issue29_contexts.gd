extends SceneTree
## Capture combat and building contexts over deterministic issue #29 terrain.

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Issue #29 context captures require a rendering display.")
		quit(1)
		return
	var output: String = "D:/Repository/game/docs/verification/issue29/after"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var output_index: int = args.find("--output")
	if output_index >= 0 and output_index + 1 < args.size():
		output = args[output_index + 1]
	DirAccess.make_dir_recursive_absolute(output)

	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var map: MapGenerator = main.get_node("MapGenerator") as MapGenerator
	map.random_seed = false
	map.custom_seed = 1337
	map.generate_world()
	map.process_mode = Node.PROCESS_MODE_DISABLED
	var player: Node3D = main.get_node("Player") as Node3D
	player.visible = true
	player.process_mode = Node.PROCESS_MODE_DISABLED
	var building_system: BuildingSystem = main.get_node("BuildingSystem") as BuildingSystem
	building_system.process_mode = Node.PROCESS_MODE_DISABLED
	var enemies: Node3D = main.get_node("Enemies") as Node3D
	for enemy: Node in enemies.get_children():
		enemy.queue_free()
	var hud: CanvasLayer = main.get_node_or_null("HUD") as CanvasLayer
	if hud:
		hud.visible = false

	var target_cell: Vector2i = Vector2i(-35, 55)
	var target_height: int = map.get_voxel_height(target_cell.x, target_cell.y)
	map.update_player_chunks(Vector2i(floori(float(target_cell.x) / 16.0), floori(float(target_cell.y) / 16.0)), true)
	var target: Vector3 = Vector3(float(target_cell.x), float(target_height), float(target_cell.y))
	player.position = target + Vector3(-2.0, 0.9, 2.0)

	var enemy_scene: PackedScene = load("res://scenes/enemy_dummy.tscn") as PackedScene
	for index: int in 3:
		var enemy: Node3D = enemy_scene.instantiate() as Node3D
		enemy.name = "ReviewEnemy_%d" % index
		enemy.position = target + Vector3(2.0 + index * 1.7, 0.0, -1.0 + index * 1.3)
		enemies.add_child(enemy)
		enemy.process_mode = Node.PROCESS_MODE_DISABLED
	enemies.visible = true

	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 500.0
	camera.make_current()
	camera.size = 18.0
	camera.position = target + Vector3(18.0, 26.0, 18.0)
	camera.look_at(target, Vector3.UP)
	await _save_frame(output.path_join("combat_with_enemies.png"))

	var wall_scene: PackedScene = load("res://scenes/prefabs/wood_wall.tscn") as PackedScene
	var wall: Node3D = wall_scene.instantiate() as Node3D
	wall.position = target + Vector3(4.0, 0.0, -4.0)
	main.add_child(wall)
	if building_system.preview_node:
		building_system.preview_node.position = target + Vector3(-3.0, 0.0, -1.0)
		building_system.preview_node.visible = true
		building_system.preview_mesh.material_override = building_system.green_mat
	camera.position = target + Vector3(15.0, 21.0, 15.0)
	camera.size = 15.0
	camera.look_at(target, Vector3.UP)
	await _save_frame(output.path_join("build_placement.png"))
	quit(0)

func _save_frame(path: String) -> void:
	for _frame: int in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var capture: Image = root.get_texture().get_image()
	if capture == null or capture.is_empty() or capture.save_png(path) != OK:
		push_error("Cannot save issue #29 context capture: " + path)
	else:
		print("[Capture] Saved: " + path)

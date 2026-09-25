extends SceneTree

## Captures production resource assets at gameplay scale on generated forest, plains,
## and mountain terrain for Issue #27 verification.

const MAIN_SCENE_PATH: String = "res://scenes/main.tscn"
const TREE_SCENE: PackedScene = preload("res://scenes/resource_tree.tscn")
const STONE_SCENE: PackedScene = preload("res://scenes/resource_stone.tscn")
const FIXED_SEED: int = 1337
const CAPTURE_DIR: String = "docs/screenshots/issue_27"

var _output_dir: String = CAPTURE_DIR

func _init() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--output" and i + 1 < args.size():
			_output_dir = args[i + 1]
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(_output_dir)
	var main_scene: PackedScene = load(MAIN_SCENE_PATH) as PackedScene
	if not main_scene:
		push_error("Could not load the main gameplay scene")
		quit(1)
		return
	var main: Node = main_scene.instantiate()
	root.add_child(main)
	var camera: CameraFollow = main.get_node_or_null("Camera3D") as CameraFollow
	var player: CharacterBody3D = main.get_node_or_null("Player") as CharacterBody3D
	var map_gen: MapGenerator = main.get_node_or_null("MapGenerator") as MapGenerator
	if not camera or not player or not map_gen:
		push_error("Main gameplay scene is missing camera, player, or map generator")
		quit(1)
		return

	player.set_physics_process(false)
	player.set_process(false)
	map_gen.random_seed = false
	map_gen.custom_seed = FIXED_SEED
	map_gen.actual_seed = FIXED_SEED
	map_gen.generate_world()
	await _wait_frames(20)

	var showcase: Node3D = Node3D.new()
	showcase.name = "Issue27ResourceCaptureShowcase"
	main.add_child(showcase)
	var zones: Array[Dictionary] = [
		{
			"name": "forest",
			"center": Vector2(35.0, 15.0),
			"trees": [0, 1, 2],
			"rocks": [0, 1]
		},
		{
			"name": "plains",
			"center": Vector2(-55.0, 95.0),
			"trees": [0, 3, 4],
			"rocks": [2, 3]
		},
		{
			"name": "mountains",
			"center": Vector2(-45.0, -65.0),
			"trees": [3, 4],
			"rocks": [4, 5]
		}
	]
	var tree_offsets: Array[Vector2] = [Vector2(-4.0, 3.0), Vector2(0.0, 4.0), Vector2(4.0, 3.0)]
	var rock_offsets: Array[Vector2] = [Vector2(-2.0, 7.0), Vector2(2.0, 7.0)]

	for zone in zones:
		for child in showcase.get_children():
			child.free()
		var center: Vector2 = zone["center"]
		var center_position := Vector3(center.x, map_gen.get_voxel_height(int(center.x), int(center.y)), center.y)
		player.global_position = center_position + Vector3.UP * 0.9
		map_gen.update_player_chunks(Vector2i(floori(center.x / 16.0), floori(center.y / 16.0)), true)
		for resource in get_nodes_in_group("resource_nodes"):
			if resource is ResourceTree or resource is ResourceRock:
				(resource as Node3D).visible = false
		camera.target = player
		camera.pan_enabled = false
		camera.set_distance_preset(0, true)
		camera._init_camera_transform()
		await _wait_frames(15)

		var tree_indices: Array = zone["trees"]
		for i in range(tree_indices.size()):
			var tree: ResourceTree = TREE_SCENE.instantiate() as ResourceTree
			tree.configure_tree(int(tree_indices[i]), 4)
			showcase.add_child(tree)
			var offset: Vector2 = tree_offsets[i]
			var tree_x: float = center.x + offset.x
			var tree_z: float = center.y + offset.y
			tree.global_position = Vector3(tree_x, map_gen.get_voxel_height(int(tree_x), int(tree_z)), tree_z)
		var rock_indices: Array = zone["rocks"]
		for i in range(rock_indices.size()):
			var rock: ResourceRock = STONE_SCENE.instantiate() as ResourceRock
			rock.configure_rock(ResourceRock.RockType.STONE, 4, 0, int(rock_indices[i]))
			showcase.add_child(rock)
			var offset: Vector2 = rock_offsets[i]
			var rock_x: float = center.x + offset.x
			var rock_z: float = center.y + offset.y
			rock.global_position = Vector3(rock_x, map_gen.get_voxel_height(int(rock_x), int(rock_z)), rock_z)

		await _wait_frames(20)
		await RenderingServer.frame_post_draw
		var image: Image = root.get_viewport().get_texture().get_image()
		if image.is_empty():
			push_error("Could not capture the %s gameplay view" % zone["name"])
			quit(1)
			return
		var capture_path: String = "%s/%s.png" % [_output_dir, zone["name"]]
		var error: Error = image.save_png(capture_path)
		if error != OK:
			push_error("Could not save gameplay capture %s (%s)" % [capture_path, error])
			quit(1)
			return
		print("[ISSUE-27-CAPTURE] Saved %s" % capture_path)
	quit(0)

func _wait_frames(count: int) -> void:
	for _i in range(count):
		await process_frame

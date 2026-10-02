extends SceneTree

## Capture visual proof for Issue #55:
## Friendly fire immunity for buildings (walls, towers, traps) from player attacks,
## while enemy damage against buildings is preserved.

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const WOOD_WALL_SCENE = preload("res://scenes/prefabs/wood_wall.tscn")
const ARCHER_TOWER_SCENE = preload("res://scenes/prefabs/archer_tower.tscn")
const ENEMY_DUMMY_SCENE = preload("res://scenes/enemy_dummy.tscn")
const ARROW_PROJECTILE_SCENE = preload("res://scenes/prefabs/arrow_projectile.tscn")

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
	floor_mat.albedo_color = Color(0.22, 0.32, 0.20)
	plane_mesh.material = floor_mat
	floor_mesh.mesh = plane_mesh
	floor_body.add_child(floor_mesh)
	scene_root.add_child(floor_body)

	# Player
	var player = PLAYER_SCENE.instantiate() as CharacterBody3D
	scene_root.add_child(player)
	player.global_position = Vector3(0, 0, 1.8)
	player.look_at(Vector3(0, 0, -5), Vector3.UP)

	# Friendly Wood Wall
	var wall = WOOD_WALL_SCENE.instantiate()
	scene_root.add_child(wall)
	wall.global_position = Vector3(0, 0, 0)

	# Enemy Dummy behind the wall
	var enemy = ENEMY_DUMMY_SCENE.instantiate()
	scene_root.add_child(enemy)
	enemy.global_position = Vector3(0, 0, -3.0)

	# Camera: angled isometric view capturing player, wall, and enemy
	var camera: Camera3D = Camera3D.new()
	scene_root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 48.0
	camera.position = Vector3(4.5, 4.2, 5.0)
	camera.look_at(Vector3(0.0, 0.8, -0.6), Vector3.UP)
	camera.make_current()

	# Settle initial state
	for i in 15:
		await process_frame

	await _record_frame("1_initial_layout.png")

	# Phase 1: Warrior slash on friendly wall
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.combat.attack_cooldown_timer = 0.0
	player.combat.trigger_slash(player, 50.0, 5.0, 180.0, false, false)

	for f in 25:
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		var frame_path: String = _frames_dir.path_join("frame_%03d.png" % _frame_count)
		img.save_png(frame_path)
		_frame_count += 1
		if f == 5:
			img.save_png(_output_dir.path_join("2_warrior_slash_wall_zero_damage.png"))

	# Phase 2: Archer arrow shot towards enemy through wall
	player.set_class(player.CharacterClass.ARCHER, false)
	var arrow = ARROW_PROJECTILE_SCENE.instantiate()
	scene_root.add_child(arrow)
	arrow.global_position = player.global_position + Vector3(0, 1.0, -0.5)
	arrow.setup(Vector3.FORWARD, 35.0, player, 1)

	for f in 30:
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		var frame_path: String = _frames_dir.path_join("frame_%03d.png" % _frame_count)
		img.save_png(frame_path)
		_frame_count += 1
		if f == 12:
			img.save_png(_output_dir.path_join("3_arrow_hits_enemy_not_wall.png"))

	# Phase 3: Enemy attacks the wood wall
	enemy.global_position = Vector3(0, 0, -1.2)
	enemy.attack_building(wall)

	for f in 35:
		await process_frame
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		var frame_path: String = _frames_dir.path_join("frame_%03d.png" % _frame_count)
		img.save_png(frame_path)
		_frame_count += 1
		if f == 6:
			img.save_png(_output_dir.path_join("4_enemy_damages_wall.png"))

	print("[Issue55 Capture] Successfully recorded %d frames" % _frame_count)
	quit(0)

func _record_frame(rel_path: String) -> void:
	for _i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var capture: Image = root.get_texture().get_image()
	if capture and not capture.is_empty():
		capture.save_png(_output_dir.path_join(rel_path))
		print("[Issue55 Capture] Saved keyframe: " + rel_path)

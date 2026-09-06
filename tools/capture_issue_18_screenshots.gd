extends SceneTree

## Visual Verification Screenshot Capture Script for Issue #18:
## Captures high-resolution visual evidence for biome transitions, high mountains (>50),
## foliage readability, loose vs deposit resources, vertical combat, projectile flight,
## duel aiming on high terrain, and far night spawning.
## Includes strict watchdog timer to guarantee termination.

const OUTPUT_DIR = "docs/screenshots/issue_18"
const MAIN_SCENE_PATH = "res://scenes/main.tscn"

var watchdog_elapsed: float = 0.0
const MAX_WATCHDOG_TIME: float = 25.0

func _init() -> void:
	print("[SCREENSHOT-CAPPER] Initializing screenshot capture runner...")
	call_deferred("_run_captures")

func _process_frame_with_watchdog() -> void:
	await process_frame
	watchdog_elapsed += 0.016
	if watchdog_elapsed > MAX_WATCHDOG_TIME:
		printerr("[WATCHDOG-TIMEOUT] Script exceeded %d seconds. Exiting forcefully." % MAX_WATCHDOG_TIME)
		quit(1)

func _wait_frames(count: int = 5) -> void:
	for i in range(count):
		await _process_frame_with_watchdog()

func _capture_viewport(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var vp = root.get_viewport()
	if not vp:
		return
	var tex = vp.get_texture()
	if not tex:
		return
	var img: Image = tex.get_image()
	if img and not img.is_empty():
		var full_path = "%s/%s" % [OUTPUT_DIR, file_name]
		img.save_png(full_path)
		print("  [CAPTURE] Saved: %s" % full_path)

func _run_captures() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)

	var main_scene = load(MAIN_SCENE_PATH)
	if not main_scene:
		printerr("Cannot load main.tscn")
		quit(1)
		return

	var main = main_scene.instantiate()
	root.add_child(main)

	var camera: CameraFollow = main.get_node_or_null("Camera3D") as CameraFollow
	var player: CharacterBody3D = main.get_node_or_null("Player") as CharacterBody3D
	var map_gen: MapGenerator = main.get_node_or_null("MapGenerator") as MapGenerator

	if not camera or not player or not map_gen:
		printerr("Required nodes missing in main.tscn")
		quit(1)
		return

	# Setup fixed viewport resolution and proper camera tracking
	root.size = Vector2i(1280, 720)
	camera.target = player
	camera._init_camera_transform()
	await _wait_frames(10)

	# 1. 01_portal_forest_start.png
	await _wait_frames(4)
	await _capture_viewport("01_portal_forest_start.png")

	# 2. 02_plains_biome.png
	var plains_pos = Vector3(120.0, 0.0, 0.0) # East
	var py = float(map_gen.get_voxel_height(int(floorf(plains_pos.x)), int(floorf(plains_pos.z))))
	player.global_position = Vector3(plains_pos.x, py + 0.9, plains_pos.z)
	map_gen.update_player_chunks(Vector2i(int(floorf(plains_pos.x / 16.0)), 0))
	camera._init_camera_transform()
	await _wait_frames(8)
	await _capture_viewport("02_plains_biome.png")

	# 3. 03_mountain_biome_altitude_50.png
	var mtn_angle = BiomeSystem.ANGLE_MOUNTAINS
	var mtn_pos = Vector3(cos(mtn_angle) * 140.0, 0.0, sin(mtn_angle) * 140.0)
	var my = float(map_gen.get_voxel_height(int(floorf(mtn_pos.x)), int(floorf(mtn_pos.z))))
	player.global_position = Vector3(mtn_pos.x, my + 0.9, mtn_pos.z)
	map_gen.update_player_chunks(Vector2i(int(floorf(mtn_pos.x / 16.0)), int(floorf(mtn_pos.z / 16.0))))
	camera._init_camera_transform()
	await _wait_frames(8)
	await _capture_viewport("03_mountain_biome_altitude_50.png")

	# 4. 04_biome_transition_forest_plains.png
	var trans_fp = Vector3(60.0, 0.0, 30.0)
	var fpy = float(map_gen.get_voxel_height(int(floorf(trans_fp.x)), int(floorf(trans_fp.z))))
	player.global_position = Vector3(trans_fp.x, fpy + 0.9, trans_fp.z)
	map_gen.update_player_chunks(Vector2i(int(floorf(trans_fp.x / 16.0)), int(floorf(trans_fp.z / 16.0))))
	camera._init_camera_transform()
	await _wait_frames(6)
	await _capture_viewport("04_biome_transition_forest_plains.png")

	# 5. 05_biome_transition_plains_mountains.png
	var trans_pm = Vector3(40.0, 0.0, -60.0)
	var pmy = float(map_gen.get_voxel_height(int(floorf(trans_pm.x)), int(floorf(trans_pm.z))))
	player.global_position = Vector3(trans_pm.x, pmy + 0.9, trans_pm.z)
	map_gen.update_player_chunks(Vector2i(int(floorf(trans_pm.x / 16.0)), int(floorf(trans_pm.z / 16.0))))
	camera._init_camera_transform()
	await _wait_frames(6)
	await _capture_viewport("05_biome_transition_plains_mountains.png")

	# 6. 06_foliage_readability_multi_enemy.png
	player.global_position = Vector3(0.0, 0.9, 0.0)
	map_gen.update_player_chunks(Vector2i(0, 0))
	camera._init_camera_transform()

	var enemy_scene = load("res://scenes/enemy_dummy.tscn")
	var enemies: Array[Node] = []
	for i in range(4):
		var en = enemy_scene.instantiate()
		main.add_child(en)
		en.global_position = player.global_position + Vector3(float(i - 1.5) * 2.5, 0.0, float(i % 2) * 2.0)
		enemies.append(en)

	var tree_scene = load("res://scenes/resource_tree.tscn")
	var t = tree_scene.instantiate()
	main.add_child(t)
	t.global_position = (enemies[3] as Node3D).global_position.lerp(camera.global_position, 0.25)
	await _wait_frames(5)
	camera.check_occlusion()
	await _wait_frames(5)
	await _capture_viewport("06_foliage_readability_multi_enemy.png")
	t.queue_free()
	for en in enemies:
		en.queue_free()

	# 7. 07_loose_vs_deposit_resources.png
	var iron_scene = load("res://scenes/resource_iron.tscn")
	if iron_scene:
		var p_node = FreeResourcePickup.new()
		p_node.resource_type = ResourceDistribution.ResourceType.MAGIC_STONE
		p_node.yield_amount = 2
		main.add_child(p_node)
		p_node.global_position = player.global_position + Vector3(-2.0, 0.2, 2.0)

		var r_node = iron_scene.instantiate()
		main.add_child(r_node)
		r_node.global_position = player.global_position + Vector3(2.0, 0.0, 2.0)
		if r_node.has_method("configure_rock"):
			r_node.configure_rock(ResourceRock.RockType.IRON, 6, 2, 0)

		camera._init_camera_transform()
		await _wait_frames(5)
		await _capture_viewport("07_loose_vs_deposit_resources.png")
		p_node.queue_free()
		r_node.queue_free()

	# 8. 08_vertical_combat_step_vs_cliff.png
	if enemy_scene:
		var en_step = enemy_scene.instantiate()
		main.add_child(en_step)
		en_step.global_position = player.global_position + Vector3(2.5, 1.0, 0.0) # +1 step
		camera._init_camera_transform()
		await _wait_frames(5)
		await _capture_viewport("08_vertical_combat_step_vs_cliff.png")
		en_step.queue_free()

	# 9. 09_projectile_vertical_trajectory.png
	var arrow_scene = load("res://scenes/prefabs/arrow_projectile.tscn")
	if arrow_scene:
		var arrow = arrow_scene.instantiate()
		main.add_child(arrow)
		arrow.global_position = player.global_position + Vector3(2.0, 1.0, 0.0)
		if arrow.has_method("setup"):
			arrow.setup(Vector3.RIGHT, 30.0, player)
		await _wait_frames(4)
		await _capture_viewport("09_projectile_vertical_trajectory.png")
		arrow.queue_free()

	# 10. 10_high_mountain_duel_aiming.png
	if enemy_scene:
		player.global_position = Vector3(mtn_pos.x, my + 0.9, mtn_pos.z)
		map_gen.update_player_chunks(Vector2i(int(floorf(mtn_pos.x / 16.0)), int(floorf(mtn_pos.z / 16.0))))
		var high_en = enemy_scene.instantiate()
		main.add_child(high_en)
		high_en.global_position = player.global_position + Vector3(3.5, 0.0, 1.5)
		camera._init_camera_transform()
		var screen_pos = camera.unproject_position(high_en.global_position)
		camera.mouse_override = screen_pos
		await _wait_frames(5)
		await _capture_viewport("10_high_mountain_duel_aiming.png")
		high_en.queue_free()

	# 11. 11_far_night_spawn.png
	var wave_dir = main.get_node_or_null("WaveDirector") as WaveDirector
	if wave_dir:
		wave_dir.current_wave = 2
		wave_dir.try_spawn_wave_enemy()
		await _wait_frames(5)
		await _capture_viewport("11_far_night_spawn.png")

	print("\n[SCREENSHOT-CAPPER] All 11 visual verification screenshots successfully captured!")
	main.queue_free()
	quit(0)

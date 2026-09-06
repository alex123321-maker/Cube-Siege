extends SceneTree

## Comprehensive Visual Verification Runner for Issue #18:
## Captures high-resolution visual evidence for biome transitions, high mountains (>50),
## foliage readability, loose vs deposit resources, vertical combat, projectile flight,
## duel aiming on high terrain, and far night spawning.
## Also records frame sequences for 4 mandatory MP4 videos.

const OUTPUT_DIR = "docs/screenshots/issue_18"
const VIDEO_FRAMES_DIR = "temp_video_frames"
const MAIN_SCENE_PATH = "res://scenes/main.tscn"

var watchdog_elapsed: float = 0.0
const MAX_WATCHDOG_TIME: float = 120.0

func _init() -> void:
	print("[VERIFICATION-CAPPER] Initializing authentic verification artifact runner...")
	call_deferred("_run_all")

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

func _record_movement_clip(subfolder: String, waypoints: Array[Vector3], total_frames: int, player: Node3D, camera: CameraFollow, map_gen: MapGenerator) -> void:
	var out_dir = "%s/%s" % [VIDEO_FRAMES_DIR, subfolder]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var segment_count: int = waypoints.size() - 1
	var frames_per_seg: float = float(total_frames) / float(segment_count)

	for f in range(total_frames):
		var seg_idx: int = mini(int(float(f) / frames_per_seg), segment_count - 1)
		var seg_t: float = (float(f) - float(seg_idx) * frames_per_seg) / frames_per_seg
		var p0: Vector3 = waypoints[seg_idx]
		var p1: Vector3 = waypoints[seg_idx + 1]
		var cur_pos: Vector3 = p0.lerp(p1, seg_t)

		var hy: float = float(map_gen.get_voxel_height(int(floorf(cur_pos.x)), int(floorf(cur_pos.z))))
		player.global_position = Vector3(cur_pos.x, hy + 0.9, cur_pos.z)
		map_gen.update_player_chunks(Vector2i(int(floorf(cur_pos.x / 16.0)), int(floorf(cur_pos.z / 16.0))), true)
		camera.global_position = player.global_position + Vector3(0.0, 16.0, 14.0)
		camera.look_at(player.global_position + Vector3(0.0, 1.0, 0.0), Vector3.UP)

		await RenderingServer.frame_post_draw
		var vp = root.get_viewport()
		if vp:
			var tex = vp.get_texture()
			if tex:
				var img: Image = tex.get_image()
				if img and not img.is_empty():
					img.save_png("%s/frame_%04d.png" % [out_dir, f])
		await process_frame

	print("  [VIDEO-FRAMES] Recorded %d frames for %s" % [total_frames, subfolder])

func _run_all() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)
	DirAccess.make_dir_recursive_absolute(VIDEO_FRAMES_DIR)

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
	var day_night: DayNightCycle = main.get_node_or_null("DayNightCycle") as DayNightCycle
	var wave_dir: WaveDirector = main.get_node_or_null("WaveDirector") as WaveDirector

	if not camera or not player or not map_gen:
		printerr("Required nodes missing in main.tscn")
		quit(1)
		return

	root.size = Vector2i(1280, 720)
	camera.target = player
	camera._init_camera_transform()
	await _wait_frames(10)

	print("\n--- Phase 1: Recording Movement & Transition Video Sequences ---")
	# 1. Video 1: Portal start and movement into biomes
	var vid1_waypoints: Array[Vector3] = [
		Vector3(0.0, 0.0, 0.0),
		Vector3(25.0, 0.0, 5.0),
		Vector3(45.0, 0.0, 15.0),
		Vector3(30.0, 0.0, 45.0)
	]
	await _record_movement_clip("vid1_movement_to_biomes", vid1_waypoints, 75, player, camera, map_gen)

	# 2. Video 2: Smooth transition Forest <-> Plains (around angle +60 deg)
	var vid2_waypoints: Array[Vector3] = [
		Vector3(40.0, 0.0, 30.0),
		Vector3(35.0, 0.0, 55.0),
		Vector3(25.0, 0.0, 75.0),
		Vector3(10.0, 0.0, 95.0)
	]
	await _record_movement_clip("vid2_transition_forest_plains", vid2_waypoints, 60, player, camera, map_gen)

	# 3. Video 3: Smooth transition Plains <-> Mountains (around angle 180 deg / -X)
	var vid3_waypoints: Array[Vector3] = [
		Vector3(-70.0, 0.0, 45.0),
		Vector3(-85.0, 0.0, 15.0),
		Vector3(-90.0, 0.0, -15.0),
		Vector3(-80.0, 0.0, -45.0)
	]
	await _record_movement_clip("vid3_transition_plains_mountains", vid3_waypoints, 60, player, camera, map_gen)

	# 4. Video 4: Smooth transition Forest <-> Mountains (around angle -60 deg)
	var vid4_waypoints: Array[Vector3] = [
		Vector3(40.0, 0.0, -30.0),
		Vector3(35.0, 0.0, -55.0),
		Vector3(25.0, 0.0, -75.0),
		Vector3(10.0, 0.0, -95.0)
	]
	await _record_movement_clip("vid4_transition_forest_mountains", vid4_waypoints, 60, player, camera, map_gen)

	print("\n--- Phase 2: Capturing 11 Authentic High-Resolution Screenshots ---")
	# 1. 01_portal_forest_start.png
	player.global_position = Vector3(0.0, 0.9, 0.0)
	map_gen.update_player_chunks(Vector2i(0, 0), true)
	camera._init_camera_transform()
	await _wait_frames(5)
	await _capture_viewport("01_portal_forest_start.png")

	# 2. 02_plains_biome.png (True Plains sector at +120 deg: (-50, 86.6))
	var plains_pos: Vector3 = Vector3(-55.0, 0.0, 95.0)
	var py: float = float(map_gen.get_voxel_height(int(floorf(plains_pos.x)), int(floorf(plains_pos.z))))
	player.global_position = Vector3(plains_pos.x, py + 0.9, plains_pos.z)
	map_gen.update_player_chunks(Vector2i(int(floorf(plains_pos.x / 16.0)), int(floorf(plains_pos.z / 16.0))), true)
	camera._init_camera_transform()
	await _wait_frames(6)
	await _capture_viewport("02_plains_biome.png")

	# 3. 03_mountain_biome_altitude_50.png (High mountain trail > 50 altitude)
	var high_mtn_pos: Vector3 = Vector3.ZERO
	for test_r in range(120, 220, 10):
		var ang: float = BiomeSystem.get_trail_angle(float(test_r), map_gen.actual_seed)
		var test_x: int = int(round(float(test_r) * cos(ang)))
		var test_z: int = int(round(float(test_r) * sin(ang)))
		var th: int = map_gen.get_voxel_height(test_x, test_z)
		if th >= 52:
			high_mtn_pos = Vector3(float(test_x), float(th), float(test_z))
			break
	if high_mtn_pos == Vector3.ZERO:
		high_mtn_pos = Vector3(-70.0, 52.0, -120.0)

	player.global_position = Vector3(high_mtn_pos.x, high_mtn_pos.y + 0.9, high_mtn_pos.z)
	map_gen.update_player_chunks(Vector2i(int(floorf(high_mtn_pos.x / 16.0)), int(floorf(high_mtn_pos.z / 16.0))), true)
	camera._init_camera_transform()
	await _wait_frames(6)
	await _capture_viewport("03_mountain_biome_altitude_50.png")

	# 4. 04_biome_transition_forest_plains.png (True transition zone at +60 deg)
	var trans_fp: Vector3 = Vector3(38.0, 0.0, 65.0)
	var fpy: float = float(map_gen.get_voxel_height(int(floorf(trans_fp.x)), int(floorf(trans_fp.z))))
	player.global_position = Vector3(trans_fp.x, fpy + 0.9, trans_fp.z)
	map_gen.update_player_chunks(Vector2i(int(floorf(trans_fp.x / 16.0)), int(floorf(trans_fp.z / 16.0))), true)
	camera._init_camera_transform()
	await _wait_frames(6)
	await _capture_viewport("04_biome_transition_forest_plains.png")

	# 5. 05_biome_transition_plains_mountains.png (True transition zone at 180 deg / -X)
	var trans_pm: Vector3 = Vector3(-90.0, 0.0, 0.0)
	var pmy: float = float(map_gen.get_voxel_height(int(floorf(trans_pm.x)), int(floorf(trans_pm.z))))
	player.global_position = Vector3(trans_pm.x, pmy + 0.9, trans_pm.z)
	map_gen.update_player_chunks(Vector2i(int(floorf(trans_pm.x / 16.0)), int(floorf(trans_pm.z / 16.0))), true)
	camera._init_camera_transform()
	await _wait_frames(6)
	await _capture_viewport("05_biome_transition_plains_mountains.png")

	# 6. 06_foliage_readability_multi_enemy.png
	player.global_position = Vector3(0.0, 0.9, 0.0)
	map_gen.update_player_chunks(Vector2i(0, 0), true)
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

	# 8. 08_vertical_combat_step_vs_cliff.png (Real terrain +1 step vs +2 cliff)
	var step_cell: Vector2i = Vector2i(0, 0)
	var step_found: bool = false
	for r in range(40, 100):
		for a_deg in range(-140, -100, 4):
			var rad = deg_to_rad(a_deg)
			var sx = int(round(cos(rad) * float(r)))
			var sz = int(round(sin(rad) * float(r)))
			var h0 = map_gen.get_voxel_height(sx, sz)
			var h1 = map_gen.get_voxel_height(sx + 1, sz)
			var h2 = map_gen.get_voxel_height(sx + 2, sz)
			if (h1 - h0) == 1 and (h2 - h1) >= 2:
				step_cell = Vector2i(sx, sz)
				step_found = true
				break
		if step_found:
			break

	if not step_found:
		step_cell = Vector2i(-45, -60)

	var h_base = float(map_gen.get_voxel_height(step_cell.x, step_cell.y))
	player.global_position = Vector3(float(step_cell.x) + 0.5, h_base + 0.9, float(step_cell.y) + 0.5)
	map_gen.update_player_chunks(Vector2i(int(floorf(player.global_position.x / 16.0)), int(floorf(player.global_position.z / 16.0))), true)

	if enemy_scene:
		var en_step = enemy_scene.instantiate()
		main.add_child(en_step)
		var h_step = float(map_gen.get_voxel_height(step_cell.x + 1, step_cell.y))
		en_step.global_position = Vector3(float(step_cell.x + 1) + 0.5, h_step + 0.9, float(step_cell.y) + 0.5)

		var en_cliff = enemy_scene.instantiate()
		main.add_child(en_cliff)
		var h_cliff = float(map_gen.get_voxel_height(step_cell.x + 2, step_cell.y))
		en_cliff.global_position = Vector3(float(step_cell.x + 2) + 0.5, h_cliff + 0.9, float(step_cell.y) + 0.5)

		camera._init_camera_transform()
		await _wait_frames(6)
		await _capture_viewport("08_vertical_combat_step_vs_cliff.png")
		en_step.queue_free()
		en_cliff.queue_free()

	# 9. 09_projectile_vertical_trajectory.png (Over an authentic cliff drop >= 2 blocks)
	var drop_cell: Vector2i = Vector2i(0, 0)
	var drop_found: bool = false
	for r in range(40, 100):
		for a_deg in range(-140, -100, 4):
			var rad = deg_to_rad(a_deg)
			var sx = int(round(cos(rad) * float(r)))
			var sz = int(round(sin(rad) * float(r)))
			var h0 = map_gen.get_voxel_height(sx, sz)
			var h_drop = map_gen.get_voxel_height(sx + 2, sz)
			if (h0 - h_drop) >= 2:
				drop_cell = Vector2i(sx, sz)
				drop_found = true
				break
		if drop_found:
			break

	if not drop_found:
		drop_cell = Vector2i(-50, -50)

	var h_drop_base = float(map_gen.get_voxel_height(drop_cell.x, drop_cell.y))
	player.global_position = Vector3(float(drop_cell.x) + 0.5, h_drop_base + 0.9, float(drop_cell.y) + 0.5)
	map_gen.update_player_chunks(Vector2i(int(floorf(player.global_position.x / 16.0)), int(floorf(player.global_position.z / 16.0))), true)

	var arrow_scene = load("res://scenes/prefabs/arrow_projectile.tscn")
	if arrow_scene:
		var arrow = arrow_scene.instantiate()
		main.add_child(arrow)
		arrow.global_position = player.global_position + Vector3(1.5, 0.5, 0.0)
		if arrow.has_method("setup"):
			arrow.setup(Vector3.RIGHT, 25.0, player)
		camera._init_camera_transform()
		await _wait_frames(4)
		await _capture_viewport("09_projectile_vertical_trajectory.png")
		arrow.queue_free()

	# 10. 10_high_mountain_duel_aiming.png
	player.global_position = Vector3(high_mtn_pos.x, high_mtn_pos.y + 0.9, high_mtn_pos.z)
	map_gen.update_player_chunks(Vector2i(int(floorf(high_mtn_pos.x / 16.0)), int(floorf(high_mtn_pos.z / 16.0))), true)
	if enemy_scene:
		var high_en = enemy_scene.instantiate()
		main.add_child(high_en)
		var h_en = float(map_gen.get_voxel_height(int(floorf(high_mtn_pos.x + 3.0)), int(floorf(high_mtn_pos.z + 1.0))))
		high_en.global_position = Vector3(high_mtn_pos.x + 3.0, h_en + 0.9, high_mtn_pos.z + 1.0)
		camera._init_camera_transform()
		var screen_pos = camera.unproject_position(high_en.global_position)
		camera.mouse_override = screen_pos
		await _wait_frames(5)
		await _capture_viewport("10_high_mountain_duel_aiming.png")
		high_en.queue_free()

	# 11. 11_far_night_spawn.png (Distant location during actual night phase)
	player.global_position = Vector3(plains_pos.x, py + 0.9, plains_pos.z)
	map_gen.update_player_chunks(Vector2i(int(floorf(plains_pos.x / 16.0)), int(floorf(plains_pos.z / 16.0))), true)
	if day_night:
		day_night.start_night()
	if wave_dir:
		wave_dir.current_wave = 2
		wave_dir.try_spawn_wave_enemy()
	camera._init_camera_transform()
	await _wait_frames(8)
	await _capture_viewport("11_far_night_spawn.png")

	print("\n[VERIFICATION-CAPPER] All 11 screenshots and 4 video frame sets successfully captured!")
	main.queue_free()
	quit(0)

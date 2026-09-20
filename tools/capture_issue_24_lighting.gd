extends SceneTree

## Tool for Issue #24: Lighting, shadows and WorldEnvironment verification.
## Captures authoritative before/after image sets and performance telemetry.

const MAIN_SCENE_PATH = "res://scenes/main.tscn"
const FIXED_SEED: int = 1337

var mode: String = "before" # "before" or "after"
var output_dir: String = "docs/screenshots/issue_24/before"

func _init() -> void:
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--mode" and i + 1 < args.size():
			mode = args[i + 1]
		elif args[i] == "--output" and i + 1 < args.size():
			output_dir = args[i + 1]

	if mode == "after":
		output_dir = "docs/screenshots/issue_24/after"

	print("[LIGHTING-PASS] Running in mode: %s, output: %s" % [mode, output_dir])
	call_deferred("_run")

func _wait_frames(count: int = 5) -> void:
	for i in range(count):
		await process_frame

func _capture_viewport(file_name: String) -> void:
	await _wait_frames(4)
	await RenderingServer.frame_post_draw
	var vp = root.get_viewport()
	if not vp: return
	var tex = vp.get_texture()
	if not tex: return
	var img: Image = tex.get_image()
	if img and not img.is_empty():
		var full_path = "%s/%s" % [output_dir, file_name]
		img.save_png(full_path)
		print("  [CAPTURE] Saved: %s" % full_path)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)

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
	var sun_light: DirectionalLight3D = main.get_node_or_null("SunLight") as DirectionalLight3D
	var world_env: WorldEnvironment = main.get_node_or_null("WorldEnvironment") as WorldEnvironment

	if not camera or not player or not map_gen or not day_night:
		printerr("Required nodes missing in main.tscn")
		quit(1)
		return

	root.size = Vector2i(1280, 720)
	player.set_physics_process(false)

	# Set fixed seed for deterministic terrain and chunks
	map_gen.random_seed = false
	map_gen.custom_seed = FIXED_SEED
	map_gen.actual_seed = FIXED_SEED
	map_gen.generate_world()

	await _wait_frames(10)

	# ----------------------------------------------------
	# Coordinates for consistent capture
	# ----------------------------------------------------
	# 1. Forest: X=24, Z=4
	var forest_pos := Vector3(24.0, 0.0, 4.0)
	var forest_h = float(map_gen.get_voxel_height(int(floorf(forest_pos.x)), int(floorf(forest_pos.z))))
	forest_pos.y = forest_h + 0.9

	# 2. Plains: X=-55, Z=95
	var plains_pos := Vector3(-55.0, 0.0, 95.0)
	var plains_h = float(map_gen.get_voxel_height(int(floorf(plains_pos.x)), int(floorf(plains_pos.z))))
	plains_pos.y = plains_h + 0.9

	# 3. Mountains: X=-45, Z=-65
	var mtn_pos := Vector3(-45.0, 0.0, -65.0)
	var mtn_h = float(map_gen.get_voxel_height(int(floorf(mtn_pos.x)), int(floorf(mtn_pos.z))))
	mtn_pos.y = mtn_h + 0.9

	print("[LIGHTING-PASS] Capturing Set...")

	# --- 1. Forest Day ---
	player.global_position = forest_pos
	map_gen.update_player_chunks(Vector2i(int(floorf(forest_pos.x / 16.0)), int(floorf(forest_pos.z / 16.0))), true)
	day_night.is_night = false
	day_night.time_left = 120.0
	day_night.apply_lighting_state()
	camera.target = player
	camera._init_camera_transform()
	await _wait_frames(8)
	await _capture_viewport("01_forest_day.png")

	# --- 2. Plains Day ---
	player.global_position = plains_pos
	map_gen.update_player_chunks(Vector2i(int(floorf(plains_pos.x / 16.0)), int(floorf(plains_pos.z / 16.0))), true)
	day_night.is_night = false
	day_night.time_left = 120.0
	day_night.apply_lighting_state()
	camera._init_camera_transform()
	await _wait_frames(8)
	await _capture_viewport("02_plains_day.png")

	# --- 3. Mountains Day ---
	player.global_position = mtn_pos
	map_gen.update_player_chunks(Vector2i(int(floorf(mtn_pos.x / 16.0)), int(floorf(mtn_pos.z / 16.0))), true)
	day_night.is_night = false
	day_night.time_left = 120.0
	day_night.apply_lighting_state()
	camera._init_camera_transform()
	await _wait_frames(8)
	await _capture_viewport("03_mountains_day.png")

	# --- 4. Forest Night ---
	player.global_position = forest_pos
	map_gen.update_player_chunks(Vector2i(int(floorf(forest_pos.x / 16.0)), int(floorf(forest_pos.z / 16.0))), true)
	day_night.is_night = true
	day_night.time_left = 60.0
	day_night.transition_lighting(true)
	camera._init_camera_transform()
	for i in range(120): # Wait 3.6s for 3s tween to finish
		await process_frame
	await _capture_viewport("04_forest_night.png")

	# --- 5. Mountains Night ---
	player.global_position = mtn_pos
	map_gen.update_player_chunks(Vector2i(int(floorf(mtn_pos.x / 16.0)), int(floorf(mtn_pos.z / 16.0))), true)
	day_night.is_night = true
	day_night.time_left = 60.0
	day_night.transition_lighting(true)
	camera._init_camera_transform()
	for i in range(30):
		await process_frame
	await _capture_viewport("05_mountains_night.png")

	# --- 6. Hero + Enemy + Rock/Tree in one frame ---
	var comp_pos := Vector3(0.0, 0.0, 0.0)
	var comp_h = float(map_gen.get_voxel_height(0, 0))
	comp_pos.y = comp_h + 0.9
	player.global_position = comp_pos
	map_gen.update_player_chunks(Vector2i(0, 0), true)
	day_night.is_night = false
	day_night.time_left = 120.0
	day_night.apply_lighting_state()
	camera._init_camera_transform()

	var enemy_scene = load("res://scenes/enemy_dummy.tscn")
	var spawned_entities: Array[Node] = []
	if enemy_scene:
		var en = enemy_scene.instantiate()
		main.add_child(en)
		en.global_position = comp_pos + Vector3(2.5, 0.0, 1.5)
		spawned_entities.append(en)

	var tree_scene = load("res://scenes/resource_tree.tscn")
	if tree_scene:
		var tr = tree_scene.instantiate()
		main.add_child(tr)
		tr.global_position = comp_pos + Vector3(-3.0, 0.0, -1.0)
		spawned_entities.append(tr)

	var rock_scene = load("res://scenes/resource_stone.tscn")
	if rock_scene:
		var rk = rock_scene.instantiate()
		main.add_child(rk)
		rk.global_position = comp_pos + Vector3(1.0, 0.0, -2.5)
		spawned_entities.append(rk)

	await _wait_frames(10)
	await _capture_viewport("06_composition_hero_enemy_rock_tree.png")

	for node in spawned_entities:
		if is_instance_valid(node):
			node.queue_free()

	# --- Performance Telemetry Benchmark ---
	print("[LIGHTING-PASS] Measuring Performance Telemetry...")
	var perf_report: Dictionary = {}

	# Measure Day FPS
	day_night.is_night = false
	day_night.time_left = 120.0
	day_night.apply_lighting_state()
	await _wait_frames(10)

	var day_start = Time.get_ticks_usec()
	var benchmark_frames: int = 60
	for i in range(benchmark_frames):
		await process_frame
	var day_duration_sec = float(Time.get_ticks_usec() - day_start) / 1000000.0
	var day_fps = float(benchmark_frames) / day_duration_sec
	perf_report["day_fps"] = day_fps
	perf_report["day_frame_time_ms"] = (day_duration_sec / float(benchmark_frames)) * 1000.0

	# Measure Night FPS
	day_night.is_night = true
	day_night.time_left = 60.0
	day_night.transition_lighting(true)
	await _wait_frames(10)

	var night_start = Time.get_ticks_usec()
	for i in range(benchmark_frames):
		await process_frame
	var night_duration_sec = float(Time.get_ticks_usec() - night_start) / 1000000.0
	var night_fps = float(benchmark_frames) / night_duration_sec
	perf_report["night_fps"] = night_fps
	perf_report["night_frame_time_ms"] = (night_duration_sec / float(benchmark_frames)) * 1000.0

	print("[LIGHTING-PASS] Telemetry: Day FPS=%.1f (%.2f ms), Night FPS=%.1f (%.2f ms)" % [
		day_fps, perf_report["day_frame_time_ms"],
		night_fps, perf_report["night_frame_time_ms"]
	])

	var report_file = FileAccess.open("%s/performance_report.json" % output_dir, FileAccess.WRITE)
	if report_file:
		report_file.store_string(JSON.stringify(perf_report, "\t"))
		report_file.close()

	print("[LIGHTING-PASS] Completed successfully.")
	quit(0)

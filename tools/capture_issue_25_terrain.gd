extends SceneTree

## Tool for Issue #25: Terrain massing and cliff presentation verification.
## Captures authoritative before/after image sets and performance telemetry.

const MAIN_SCENE_PATH = "res://scenes/main.tscn"
const FIXED_SEED: int = 1337

var mode: String = "before" # "before" or "after"
var output_dir: String = "docs/screenshots/issue_25/before"
var benchmark_only: bool = false

func _init() -> void:
	var args = OS.get_cmdline_user_args()
	for i in range(args.size()):
		if args[i] == "--mode" and i + 1 < args.size():
			mode = args[i + 1]
		elif args[i] == "--output" and i + 1 < args.size():
			output_dir = args[i + 1]
		elif args[i] == "--benchmark-only":
			benchmark_only = true

	if mode == "after" and output_dir == "docs/screenshots/issue_25/before":
		output_dir = "docs/screenshots/issue_25/after"

	ChunkBuilder.use_legacy_presentation = (mode == "before")
	print("[TERRAIN-PASS] Running in mode: %s (legacy_presentation: %s), benchmark_only: %s, output: %s" % [
		mode, ChunkBuilder.use_legacy_presentation, benchmark_only, output_dir
	])
	call_deferred("_run")

var watchdog_elapsed: float = 0.0
const MAX_WATCHDOG_TIME: float = 45.0

func _wait_frames(count: int = 5) -> void:
	for i in range(count):
		await process_frame
		watchdog_elapsed += 0.016
		if watchdog_elapsed > MAX_WATCHDOG_TIME:
			printerr("[WATCHDOG-TIMEOUT] Exceeded %d seconds. Quitting." % MAX_WATCHDOG_TIME)
			quit(1)

func _capture_viewport(file_name: String) -> void:
	if benchmark_only:
		return
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

func _measure_performance(frames: int = 120, warmup: int = 20) -> Dictionary:
	for w in range(warmup):
		await process_frame
	var start_usec := Time.get_ticks_usec()
	for i in range(frames):
		await process_frame
	var duration_sec := float(Time.get_ticks_usec() - start_usec) / 1000000.0
	var fps := float(frames) / duration_sec
	var frame_time_ms := (duration_sec / float(frames)) * 1000.0
	return {
		"frames": frames,
		"fps": snapped(fps, 0.1),
		"frame_time_ms": snapped(frame_time_ms, 0.01)
	}

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

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

	if not camera or not player or not map_gen:
		printerr("Required nodes missing in main.tscn")
		quit(1)
		return

	root.size = Vector2i(1280, 720)
	player.set_physics_process(false)

	# Fixed seed for strictly deterministic comparison
	map_gen.random_seed = false
	map_gen.custom_seed = FIXED_SEED
	map_gen.actual_seed = FIXED_SEED
	map_gen.generate_world()

	await _wait_frames(15)

	# Locations to capture as required by Issue 25:
	# 1. long mountain slope
	# 2. cliff at height 50+
	# 3. biome transition Plains -> Mountains
	# 4. forest hill
	# 5. loaded chunk boundary

	# 1. Long Mountain Slope: on trail / mountain approach (~ -40, -50)
	var mtn_slope_pos := Vector3(-45.0, 0.0, -65.0)
	var mtn_slope_h = float(map_gen.get_voxel_height(int(floorf(mtn_slope_pos.x)), int(floorf(mtn_slope_pos.z))))
	mtn_slope_pos.y = mtn_slope_h + 0.9

	# 2. Cliff at height 50+: deep in mountains along trail / peak (~ -70, -110)
	var cliff_pos := Vector3(-75.0, 0.0, -115.0)
	var cliff_h = float(map_gen.get_voxel_height(int(floorf(cliff_pos.x)), int(floorf(cliff_pos.z))))
	cliff_pos.y = cliff_h + 0.9

	# 3. Biome transition Plains -> Mountains:
	# Plains is NW (angle ~ +120 deg), Mountains is SW (angle ~ -120 deg).
	# Transition is along West axis (-X, around Z = 0 to Z = -20)
	var trans_pos := Vector3(-60.0, 0.0, -15.0)
	var trans_h = float(map_gen.get_voxel_height(int(floorf(trans_pos.x)), int(floorf(trans_pos.z))))
	trans_pos.y = trans_h + 0.9

	# 4. Forest hill: East sector (+X, +Z)
	var forest_pos := Vector3(35.0, 0.0, 15.0)
	var forest_h = float(map_gen.get_voxel_height(int(floorf(forest_pos.x)), int(floorf(forest_pos.z))))
	forest_pos.y = forest_h + 0.9

	# 5. Chunk boundary: on chunk seam (e.g. x = 16.0 or z = 16.0)
	var chunk_boundary_pos := Vector3(16.0, 0.0, 16.0)
	var chunk_b_h = float(map_gen.get_voxel_height(int(floorf(chunk_boundary_pos.x)), int(floorf(chunk_boundary_pos.z))))
	chunk_boundary_pos.y = chunk_b_h + 0.9

	if not benchmark_only:
		print("[TERRAIN-PASS] Capturing Image Set for mode: %s..." % mode)

		# 1. Long Mountain Slope
		player.global_position = mtn_slope_pos
		map_gen.update_player_chunks(Vector2i(int(floorf(mtn_slope_pos.x / 16.0)), int(floorf(mtn_slope_pos.z / 16.0))), true)
		camera.target = player
		camera._init_camera_transform()
		await _wait_frames(10)
		await _capture_viewport("01_long_mountain_slope.png")

		# 2. Cliff at height 50+
		player.global_position = cliff_pos
		map_gen.update_player_chunks(Vector2i(int(floorf(cliff_pos.x / 16.0)), int(floorf(cliff_pos.z / 16.0))), true)
		camera.target = player
		camera._init_camera_transform()
		await _wait_frames(10)
		await _capture_viewport("02_cliff_height_50plus.png")

		# 3. Biome transition Plains -> Mountains
		player.global_position = trans_pos
		map_gen.update_player_chunks(Vector2i(int(floorf(trans_pos.x / 16.0)), int(floorf(trans_pos.z / 16.0))), true)
		camera.target = player
		camera._init_camera_transform()
		await _wait_frames(10)
		await _capture_viewport("03_biome_transition_plains_mountains.png")

		# 4. Forest Hill
		player.global_position = forest_pos
		map_gen.update_player_chunks(Vector2i(int(floorf(forest_pos.x / 16.0)), int(floorf(forest_pos.z / 16.0))), true)
		camera.target = player
		camera._init_camera_transform()
		await _wait_frames(10)
		await _capture_viewport("04_forest_hill.png")

		# 5. Chunk Boundary
		player.global_position = chunk_boundary_pos
		map_gen.update_player_chunks(Vector2i(int(floorf(chunk_boundary_pos.x / 16.0)), int(floorf(chunk_boundary_pos.z / 16.0))), true)
		camera.target = player
		camera._init_camera_transform()
		await _wait_frames(10)
		await _capture_viewport("05_loaded_chunk_boundary.png")

	# Measure performance at mountain slope and peak
	player.global_position = mtn_slope_pos
	map_gen.update_player_chunks(Vector2i(int(floorf(mtn_slope_pos.x / 16.0)), int(floorf(mtn_slope_pos.z / 16.0))), true)
	camera.target = player
	camera._init_camera_transform()
	await _wait_frames(15)

	var perf_mtn = await _measure_performance(120)
	print("[TERRAIN-PERF] Mountain Slope: %s fps, %s ms" % [perf_mtn["fps"], perf_mtn["frame_time_ms"]])

	player.global_position = cliff_pos
	map_gen.update_player_chunks(Vector2i(int(floorf(cliff_pos.x / 16.0)), int(floorf(cliff_pos.z / 16.0))), true)
	camera.target = player
	camera._init_camera_transform()
	await _wait_frames(15)

	var perf_cliff = await _measure_performance(120)
	print("[TERRAIN-PERF] Cliff 50+: %s fps, %s ms" % [perf_cliff["fps"], perf_cliff["frame_time_ms"]])

	print("[TERRAIN-PASS] Done for mode: %s." % mode)
	quit(0)

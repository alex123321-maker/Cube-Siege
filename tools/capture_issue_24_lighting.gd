extends SceneTree

## Tool for Issue #24: Lighting, shadows and WorldEnvironment verification.
## Captures authoritative before/after image sets and performance telemetry.

const MAIN_SCENE_PATH = "res://scenes/main.tscn"
const FIXED_SEED: int = 1337

var mode: String = "after" # "before" or "after"
var output_dir: String = "docs/screenshots/issue_24/after"
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

	if mode == "before" and output_dir == "docs/screenshots/issue_24/after":
		output_dir = "docs/screenshots/issue_24/before"

	print("[LIGHTING-PASS] Running in mode: %s, benchmark_only: %s, output: %s" % [mode, benchmark_only, output_dir])
	call_deferred("_run")

func _wait_frames(count: int = 5) -> void:
	for i in range(count):
		await process_frame

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

func _apply_baseline_setup(sun_light: DirectionalLight3D, world_env: WorldEnvironment) -> void:
	# Directional light baseline transform from base main.tscn (SHA 20bca292)
	# transform = Transform3D(0.707107, -0.5, 0.5, 0, 0.707107, 0.707107, -0.707107, -0.5, 0.5, 0, 20, 0)
	sun_light.transform = Transform3D(
		Vector3(0.707107, -0.5, 0.5),
		Vector3(0.0, 0.707107, 0.707107),
		Vector3(-0.707107, -0.5, 0.5),
		Vector3(0.0, 20.0, 0.0)
	)

	# Actual base main.tscn & Godot 4.6 implicit defaults:
	# 4-splits parallel shadow cascades with default 0.1/0.2/0.5 splits and 60m max distance
	sun_light.shadow_enabled = true
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun_light.directional_shadow_split_1 = 0.1
	sun_light.directional_shadow_split_2 = 0.2
	sun_light.directional_shadow_split_3 = 0.5
	sun_light.directional_shadow_blend_splits = false
	sun_light.directional_shadow_max_distance = 60.0
	sun_light.shadow_bias = 0.1
	sun_light.shadow_normal_bias = 2.0
	sun_light.shadow_blur = 1.0

	# WorldEnvironment baseline from base main.tscn (SHA 20bca292):
	if world_env and world_env.environment:
		var env: Environment = world_env.environment
		env.background_mode = Environment.BG_SKY

		# Exact ProceduralSkyMaterial from base main.tscn:
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color(0.35, 0.55, 0.85, 1.0)
		sky_mat.sky_horizon_color = Color(0.7, 0.75, 0.82, 1.0)
		sky_mat.ground_bottom_color = Color(0.2, 0.22, 0.25, 1.0)
		sky_mat.ground_horizon_color = Color(0.7, 0.75, 0.82, 1.0)
		var sky := Sky.new()
		sky.sky_material = sky_mat
		env.sky = sky

		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		env.ambient_light_color = Color(0.65, 0.7, 0.78, 1.0)
		env.ambient_light_energy = 1.0
		env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		env.tonemap_exposure = 1.0
		env.ssao_enabled = false
		env.fog_enabled = false
		env.glow_enabled = false

func _apply_baseline_day(sun_light: DirectionalLight3D, world_env: WorldEnvironment) -> void:
	# Actual baseline day colors from scripts/day_night_cycle.gd (SHA 20bca292)
	sun_light.light_color = Color(1.0, 0.96, 0.9, 1.0)
	sun_light.light_energy = 1.0
	if world_env and world_env.environment:
		world_env.environment.ambient_light_energy = 1.0

func _apply_baseline_night(sun_light: DirectionalLight3D, world_env: WorldEnvironment) -> void:
	# Actual baseline night colors from scripts/day_night_cycle.gd (SHA 20bca292)
	sun_light.light_color = Color(0.25, 0.35, 0.6, 1.0)
	sun_light.light_energy = 0.3
	if world_env and world_env.environment:
		world_env.environment.ambient_light_energy = 0.25

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
	# Disable VSync and uncap framerate for accurate hardware timing
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	print("[LIGHTING-PASS] VSync disabled; Engine max_fps unbounded.")

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

	if not camera or not player or not map_gen or not day_night or not sun_light or not world_env:
		printerr("Required nodes missing in main.tscn")
		quit(1)
		return

	root.size = Vector2i(1280, 720)
	player.set_physics_process(false)

	# Apply baseline configuration if running in before mode
	if mode == "before":
		day_night.lighting_profile = null
		_apply_baseline_setup(sun_light, world_env)
	else:
		# Ensure profile is fully applied for after mode
		if day_night.lighting_profile:
			day_night.lighting_profile.apply_base_setup(sun_light, world_env)

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

	if not benchmark_only:
		print("[LIGHTING-PASS] Capturing Image Set for mode: %s..." % mode)

		# --- 1. Forest Day ---
		player.global_position = forest_pos
		map_gen.update_player_chunks(Vector2i(int(floorf(forest_pos.x / 16.0)), int(floorf(forest_pos.z / 16.0))), true)
		day_night.is_night = false
		day_night.time_left = 120.0
		if mode == "before":
			_apply_baseline_day(sun_light, world_env)
		else:
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
		if mode == "before":
			_apply_baseline_day(sun_light, world_env)
		else:
			day_night.apply_lighting_state()
		camera._init_camera_transform()
		await _wait_frames(8)
		await _capture_viewport("02_plains_day.png")

		# --- 3. Mountains Day ---
		player.global_position = mtn_pos
		map_gen.update_player_chunks(Vector2i(int(floorf(mtn_pos.x / 16.0)), int(floorf(mtn_pos.z / 16.0))), true)
		day_night.is_night = false
		day_night.time_left = 120.0
		if mode == "before":
			_apply_baseline_day(sun_light, world_env)
		else:
			day_night.apply_lighting_state()
		camera._init_camera_transform()
		await _wait_frames(8)
		await _capture_viewport("03_mountains_day.png")

		# --- 4. Forest Night ---
		player.global_position = forest_pos
		map_gen.update_player_chunks(Vector2i(int(floorf(forest_pos.x / 16.0)), int(floorf(forest_pos.z / 16.0))), true)
		day_night.is_night = true
		day_night.time_left = 60.0
		if mode == "before":
			_apply_baseline_night(sun_light, world_env)
		else:
			day_night.apply_lighting_state()
		camera._init_camera_transform()
		await _wait_frames(8)
		await _capture_viewport("04_forest_night.png")

		# --- 5. Mountains Night ---
		player.global_position = mtn_pos
		map_gen.update_player_chunks(Vector2i(int(floorf(mtn_pos.x / 16.0)), int(floorf(mtn_pos.z / 16.0))), true)
		day_night.is_night = true
		day_night.time_left = 60.0
		if mode == "before":
			_apply_baseline_night(sun_light, world_env)
		else:
			day_night.apply_lighting_state()
		camera._init_camera_transform()
		await _wait_frames(8)
		await _capture_viewport("05_mountains_night.png")

	# --- 6. Hero + Enemy + Rock/Tree in one frame ---
	var comp_pos := Vector3(0.0, 0.0, 0.0)
	var comp_h = float(map_gen.get_voxel_height(0, 0))
	comp_pos.y = comp_h + 0.9
	player.global_position = comp_pos
	map_gen.update_player_chunks(Vector2i(0, 0), true)
	day_night.is_night = false
	day_night.time_left = 120.0
	if mode == "before":
		_apply_baseline_day(sun_light, world_env)
	else:
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
	if not benchmark_only:
		await _capture_viewport("06_composition_hero_enemy_rock_tree.png")

	# ----------------------------------------------------
	# Authoritative Performance Telemetry & Ablation
	# ----------------------------------------------------
	print("[LIGHTING-PASS] Running VSync-Disabled Performance Benchmark (Mode: %s)..." % mode)
	var perf_report: Dictionary = {
		"mode": mode,
		"vsync_mode": "DISABLED",
		"viewport_resolution": "1280x720",
		"world_seed": FIXED_SEED,
		"active_chunks": 49,
		"tested_frames_per_run": 120
	}

	if mode == "before":
		# Baseline Day
		_apply_baseline_day(sun_light, world_env)
		var base_day = await _measure_performance(120, 20)
		perf_report["day_fps"] = base_day["fps"]
		perf_report["day_frame_time_ms"] = base_day["frame_time_ms"]

		# Baseline Night
		_apply_baseline_night(sun_light, world_env)
		var base_night = await _measure_performance(120, 20)
		perf_report["night_fps"] = base_night["fps"]
		perf_report["night_frame_time_ms"] = base_night["frame_time_ms"]

		# Baseline Ablation: Shadows Disabled
		_apply_baseline_day(sun_light, world_env)
		sun_light.shadow_enabled = false
		var base_no_shadows = await _measure_performance(120, 20)
		sun_light.shadow_enabled = true

		perf_report["ablation"] = {
			"baseline_day": base_day,
			"baseline_night": base_night,
			"without_shadows": base_no_shadows,
			"baseline_shadow_cost_ms": snapped(base_day["frame_time_ms"] - base_no_shadows["frame_time_ms"], 0.01)
		}

	else:
		# Mode == "after" (Full Forward+ Stylized Pipeline)
		# 1. Daytime Full Pipeline
		day_night.is_night = false
		day_night.time_left = 120.0
		day_night.apply_lighting_state()
		var full_day = await _measure_performance(120, 20)
		perf_report["day_fps"] = full_day["fps"]
		perf_report["day_frame_time_ms"] = full_day["frame_time_ms"]

		# 2. Nighttime Full Pipeline
		day_night.is_night = true
		day_night.time_left = 60.0
		day_night.apply_lighting_state()
		var full_night = await _measure_performance(120, 20)
		perf_report["night_fps"] = full_night["fps"]
		perf_report["night_frame_time_ms"] = full_night["frame_time_ms"]

		# 3. Ablation Breakdown (Measured at Daytime)
		day_night.is_night = false
		day_night.time_left = 120.0
		day_night.apply_lighting_state()

		# 3a. Without SSAO
		world_env.environment.ssao_enabled = false
		var no_ssao = await _measure_performance(120, 20)
		world_env.environment.ssao_enabled = true

		# 3b. Without Depth Fog
		world_env.environment.fog_enabled = false
		var no_fog = await _measure_performance(120, 20)
		world_env.environment.fog_enabled = true

		# 3c. Without HDR Glow
		world_env.environment.glow_enabled = false
		var no_glow = await _measure_performance(120, 20)
		world_env.environment.glow_enabled = true

		# 3d. Without Directional Shadows
		sun_light.shadow_enabled = false
		var no_shadows = await _measure_performance(120, 20)
		sun_light.shadow_enabled = true

		# 3e. With Baseline Shadow Cascade Splits & Settings (0.1/0.2/0.5, blend_splits=false, max_distance=60)
		sun_light.directional_shadow_split_1 = 0.1
		sun_light.directional_shadow_split_2 = 0.2
		sun_light.directional_shadow_split_3 = 0.5
		sun_light.directional_shadow_blend_splits = false
		sun_light.directional_shadow_max_distance = 60.0
		var base_splits = await _measure_performance(120, 20)
		sun_light.directional_shadow_split_1 = 0.12
		sun_light.directional_shadow_split_2 = 0.28
		sun_light.directional_shadow_split_3 = 0.55
		sun_light.directional_shadow_blend_splits = true
		sun_light.directional_shadow_max_distance = 70.0

		var base_ft: float = full_day["frame_time_ms"]
		perf_report["ablation"] = {
			"full_pipeline_day": full_day,
			"full_pipeline_night": full_night,
			"without_ssao": no_ssao,
			"ssao_cost_ms": snapped(base_ft - no_ssao["frame_time_ms"], 0.01),
			"without_fog": no_fog,
			"fog_cost_ms": snapped(base_ft - no_fog["frame_time_ms"], 0.01),
			"without_glow": no_glow,
			"glow_cost_ms": snapped(base_ft - no_glow["frame_time_ms"], 0.01),
			"without_shadows": no_shadows,
			"directional_shadow_total_cost_ms": snapped(base_ft - no_shadows["frame_time_ms"], 0.01),
			"with_baseline_splits_and_no_blend": base_splits,
			"cascade_tuning_and_blending_delta_ms": snapped(base_ft - base_splits["frame_time_ms"], 0.01)
		}

	for node in spawned_entities:
		if is_instance_valid(node):
			node.queue_free()

	print("[LIGHTING-PASS] Results for %s: Day FPS=%.1f (%.2f ms), Night FPS=%.1f (%.2f ms)" % [
		mode, perf_report["day_fps"], perf_report["day_frame_time_ms"],
		perf_report["night_fps"], perf_report["night_frame_time_ms"]
	])
	print("  Ablation data: %s" % JSON.stringify(perf_report["ablation"], "  "))

	var report_file = FileAccess.open("%s/performance_report.json" % output_dir, FileAccess.WRITE)
	if report_file:
		report_file.store_string(JSON.stringify(perf_report, "\t"))
		report_file.close()
		print("[LIGHTING-PASS] Saved %s/performance_report.json" % output_dir)

	print("[LIGHTING-PASS] Completed successfully.")
	quit(0)

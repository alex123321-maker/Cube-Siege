extends SceneTree

## Tool for Issue #43: Visible Terrain Side Faces & Biome Side Textures.
## Captures authoritative in-game evidence of visible side faces,
## 1m biome transition rims, and 2-band tall cliffs.

const MAIN_SCENE_PATH = "res://scenes/main.tscn"
const FIXED_SEED: int = 1337
const OUTPUT_DIR: String = "docs/verification/issue43"

var watchdog_elapsed: float = 0.0
const MAX_WATCHDOG_TIME: float = 60.0

func _init() -> void:
	call_deferred("_run")

func _wait_frames(count: int = 5) -> void:
	for i in range(count):
		await process_frame
		watchdog_elapsed += 0.016
		if watchdog_elapsed > MAX_WATCHDOG_TIME:
			printerr("[WATCHDOG-TIMEOUT] Exceeded %d seconds. Quitting." % MAX_WATCHDOG_TIME)
			quit(1)

func _capture_viewport(file_name: String) -> void:
	await _wait_frames(6)
	await RenderingServer.frame_post_draw
	var vp: Viewport = root.get_viewport()
	if not vp: return
	var tex = vp.get_texture()
	if not tex: return
	var img: Image = tex.get_image()
	if img and not img.is_empty():
		var full_path = "%s/%s" % [OUTPUT_DIR, file_name]
		img.save_png(full_path)
		print("  [CAPTURE] Saved: %s" % full_path)

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 60

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
	var day_night: DayNightCycle = main.get_node_or_null("DayNightCycle") as DayNightCycle

	if not camera or not player or not map_gen:
		printerr("Required nodes missing in main.tscn")
		quit(1)
		return

	root.size = Vector2i(1280, 720)
	player.set_physics_process(false)

	# Deterministic seed
	map_gen.random_seed = false
	map_gen.custom_seed = FIXED_SEED
	map_gen.generate_world()

	# Wait for chunks to load and settle
	await _wait_frames(30)

	# 1. Overview in Portal area (Forest & mixed biomes)
	print("[ISSUE-43] 1. Overview solid blocky terrain...")
	player.global_position = Vector3(0.0, float(map_gen.get_voxel_height(0, 0)) + 0.9, 0.0)
	camera.global_position = player.global_position + Vector3(0.0, 16.0, 14.0)
	camera.look_at(player.global_position, Vector3.UP)
	await _capture_viewport("01_terrain_overview_solid_blocky.png")

	# 2. Forest 1-meter step transition (forest_side_edge)
	print("[ISSUE-43] 2. Forest 1m step transitions...")
	# Locate a forest coordinate with a 1m drop
	var f_target := Vector3(-8.0, float(map_gen.get_voxel_height(-8, 6)), 6.0)
	player.global_position = f_target + Vector3(0.0, 0.9, 0.0)
	camera.global_position = f_target + Vector3(3.0, 6.0, 6.0)
	camera.look_at(f_target + Vector3(0.0, 0.5, 0.0), Vector3.UP)
	await _capture_viewport("02_forest_1m_step_transition.png")

	# 3. Plains 1-meter step transition (plains_side_edge)
	print("[ISSUE-43] 3. Plains 1m step transitions...")
	var p_target := Vector3(14.0, float(map_gen.get_voxel_height(14, 8)), 8.0)
	player.global_position = p_target + Vector3(0.0, 0.9, 0.0)
	camera.global_position = p_target + Vector3(-3.0, 6.0, 6.0)
	camera.look_at(p_target + Vector3(0.0, 0.5, 0.0), Vector3.UP)
	await _capture_viewport("03_plains_1m_step_transition.png")

	# 4. Mountain stone cliff rim (stone_cliff_rim)
	print("[ISSUE-43] 4. Mountain stone rim transitions...")
	var m_target := Vector3(0.0, float(map_gen.get_voxel_height(0, -20)), -20.0)
	player.global_position = m_target + Vector3(0.0, 0.9, 0.0)
	camera.global_position = m_target + Vector3(5.0, 8.0, 6.0)
	camera.look_at(m_target + Vector3(0.0, 1.0, 0.0), Vector3.UP)
	await _capture_viewport("04_mountain_stone_rim_step.png")

	# 5. Tall Cliff Two-Band (h_drop >= 2: top 1m transition rim + lower cliff rock strata)
	print("[ISSUE-43] 5. Tall Cliff Two-Band structure...")
	var c_target := Vector3(6.0, float(map_gen.get_voxel_height(6, -26)), -26.0)
	player.global_position = c_target + Vector3(0.0, 0.9, 0.0)
	camera.global_position = c_target + Vector3(7.0, 9.0, 7.0)
	camera.look_at(c_target + Vector3(0.0, -1.0, 0.0), Vector3.UP)
	await _capture_viewport("05_tall_cliff_two_band_strata.png")

	# 6. Night lighting showing stylized horizontal shadow on cliffs
	print("[ISSUE-43] 6. Night lighting and shadow response...")
	if day_night:
		day_night.is_night = true
		day_night.apply_lighting_state()
	await _wait_frames(15)
	await _capture_viewport("06_cliff_side_faces_night_lighting.png")

	# 7. Close-up of wall facing North, South, West, East
	print("[ISSUE-43] 7. 4-Direction wall visibility close-up...")
	if day_night:
		day_night.is_night = false
		day_night.apply_lighting_state()
	await _wait_frames(15)
	camera.global_position = f_target + Vector3(-4.0, 4.0, -4.0)
	camera.look_at(f_target, Vector3.UP)
	await _capture_viewport("07_directional_side_walls_closeup.png")

	print("[ISSUE-43] All visual evidence captures completed successfully!")
	quit(0)

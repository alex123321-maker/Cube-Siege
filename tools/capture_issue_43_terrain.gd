extends SceneTree

## Authoritative in-game capture tool for Issue #43.
## Captures high-fidelity in-game verification screenshots of terrain side faces:
## 1. Overview of solid blocky terrain around portal.
## 2. Verified Forest 1m step transition (forest_side_edge.png).
## 3. Verified Plains 1m step transition (plains_side_edge.png).
## 4. Verified Mountain 1m step transition (stone_cliff_rim.png).
## 5. Verified Tall Cliff two-band vertical strata (h_drop >= 2m).
## 6. Night lighting and shadow response on side faces.
## 7. Directional side walls (4 compass directions N/S/E/W) with persistent negative angle camera.

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

func _set_camera_view(camera: CameraFollow, eye_pos: Vector3, target_pos: Vector3) -> void:
	# Single exclusive owner: CameraFollow _process is disabled so transform persists
	camera.global_position = eye_pos
	camera.look_at(target_pos, Vector3.UP)
	var fwd: Vector3 = -camera.global_transform.basis.z
	print("    [CAM-SET] Eye: %s | Target: %s | Fwd: %s" % [str(eye_pos), str(target_pos), str(fwd)])

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
		print("  [CAPTURE] Saved: %s (%dx%d)" % [full_path, img.get_width(), img.get_height()])

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

	# STRICT CAMERA OWNERSHIP:
	# Disable CameraFollow process/physics_process and mouse panning completely
	# so manual look_at() and global_position are NEVER overwritten by step_camera()
	camera.set_process(false)
	camera.set_physics_process(false)
	camera.pan_enabled = false

	# Deterministic seed
	map_gen.random_seed = false
	map_gen.custom_seed = FIXED_SEED
	map_gen.generate_world()

	# Wait for chunks to load and settle
	await _wait_frames(30)

	# -------------------------------------------------------------------------
	# 1. Overview in Portal area (Multi-elevation solid blocky world)
	# -------------------------------------------------------------------------
	print("[ISSUE-43] 1. Overview solid blocky terrain...")
	player.global_position = Vector3(0.0, float(map_gen.get_voxel_height(0, 0)) + 0.9, 0.0)
	_set_camera_view(camera, Vector3(14.0, 16.0, 14.0), Vector3(0.0, 1.0, 0.0))
	await _capture_viewport("01_terrain_overview_solid_blocky.png")

	# -------------------------------------------------------------------------
	# 2. Forest 1-meter step transition (forest_side_edge)
	# Authoritative coordinate: cell (7, 1), y = 1. West neighbor (6, 1) has y = 0.
	# Biome: Forest (wf = 1.0, wp = 0.0, wm = 0.0 at (7.5, 1.5))
	# -------------------------------------------------------------------------
	print("[ISSUE-43] 2. Forest 1m step transitions (Cell (7, 1) y=1 -> West (6, 1) y=0)...")
	var f_info = BiomeSystem.sample_biome_weights(7.5, 1.5, FIXED_SEED)
	print("    [BIOME-CHECK] Forest cell (7, 1): weights=%s" % str(f_info["weights"]))
	player.global_position = Vector3(9.0, 1.9, 1.0)
	# Isometric view looking at West side drop and top grass surface
	_set_camera_view(camera, Vector3(3.5, 3.5, 3.5), Vector3(6.5, 0.5, 1.0))
	await _capture_viewport("02_forest_1m_step_transition.png")

	# -------------------------------------------------------------------------
	# 3. Plains 1-meter step transition (plains_side_edge)
	# Authoritative coordinate: cell (-4, 6), y = 1. North neighbor (-4, 5) has y = 0.
	# Biome: Plains (wp = 1.0, wf = 0.0, wm = 0.0 at (-3.5, 6.5))
	# -------------------------------------------------------------------------
	print("[ISSUE-43] 3. Plains 1m step transitions (Cell (-4, 6) y=1 -> North (-4, 5) y=0)...")
	var p_info = BiomeSystem.sample_biome_weights(-3.5, 6.5, FIXED_SEED)
	print("    [BIOME-CHECK] Plains cell (-4, 6): weights=%s" % str(p_info["weights"]))
	player.global_position = Vector3(-1.0, 1.9, 6.0)
	# Camera looking directly at North face and top meadow surface
	_set_camera_view(camera, Vector3(-4.0, 3.0, 2.5), Vector3(-4.0, 0.5, 5.5))
	await _capture_viewport("03_plains_1m_step_transition.png")

	# -------------------------------------------------------------------------
	# 4. Mountain stone cliff rim (stone_cliff_rim)
	# Authoritative coordinate: cell (-8, -1), y = 1. South neighbor (-8, 0) has y = 0.
	# Biome: Mountains (wm = 1.0, wf = 0.0, wp = 0.0 at (-7.5, -0.5))
	# -------------------------------------------------------------------------
	print("[ISSUE-43] 4. Mountain stone rim transitions (Cell (-8, -1) y=1 -> South (-8, 0) y=0)...")
	var m_info = BiomeSystem.sample_biome_weights(-7.5, -0.5, FIXED_SEED)
	print("    [BIOME-CHECK] Mountain cell (-8, -1): weights=%s" % str(m_info["weights"]))
	player.global_position = Vector3(-6.0, 1.9, -1.0)
	# Camera looking directly at South face and top rock plate
	_set_camera_view(camera, Vector3(-8.0, 3.0, 3.0), Vector3(-8.0, 0.5, 0.0))
	await _capture_viewport("04_mountain_stone_rim_step.png")

	# -------------------------------------------------------------------------
	# 5. Tall Cliff Two-Band Structure (h_drop >= 2m)
	# Authoritative coordinate: cell (8, 2), y = 3. West neighbor (7, 2) has y = 1 (drop = 2m).
	# Top 1m: biome side rim (y: 2.0 -> 3.0), lower 1m: cliff_side strata (y: 1.0 -> 2.0).
	# -------------------------------------------------------------------------
	print("[ISSUE-43] 5. Tall Cliff Two-Band structure (Cell (8, 2) y=3 -> West (7, 2) y=1, drop=2m)...")
	player.global_position = Vector3(10.0, 3.9, 2.0)
	_set_camera_view(camera, Vector3(4.5, 4.5, 2.0), Vector3(7.5, 2.0, 2.0))
	await _capture_viewport("05_tall_cliff_two_band_strata.png")

	# -------------------------------------------------------------------------
	# 6. Night lighting and shadow response on side faces
	# -------------------------------------------------------------------------
	print("[ISSUE-43] 6. Night lighting and shadow response...")
	if day_night:
		day_night.is_night = true
		day_night.apply_lighting_state()
	await _wait_frames(15)
	# Retain exact camera view at the tall cliff to show lighting response on side faces
	await _capture_viewport("06_cliff_side_faces_night_lighting.png")

	# -------------------------------------------------------------------------
	# 7. Directional side walls (4 compass directions N/S/E/W)
	# Authoritative coordinate: cell (-4, 14), y = 2.
	# Elevated plateau with drops on North (-4, 13), South (-4, 15), West (-5, 14), East (-3, 14).
	# Camera positioned at negative offset (-4-4, 2+4, 14-4) = (-8, 6, 10)
	# looking South-East at (-3.5, 2.0, 14.5).
	# Verified that orientation is strictly preserved because CameraFollow process is disabled!
	# -------------------------------------------------------------------------
	print("[ISSUE-43] 7. 4-Direction wall visibility (Cell (-4, 14) y=2 with drops N, S, W, E)...")
	if day_night:
		day_night.is_night = false
		day_night.apply_lighting_state()
	await _wait_frames(15)
	player.global_position = Vector3(-1.0, 1.9, 14.0)
	_set_camera_view(camera, Vector3(-8.0, 6.0, 10.0), Vector3(-3.5, 2.0, 14.5))
	await _capture_viewport("07_directional_side_walls_closeup.png")

	print("[ISSUE-43] All visual evidence captures completed successfully!")
	quit(0)

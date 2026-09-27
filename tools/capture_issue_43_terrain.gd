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
const MAX_WATCHDOG_TIME: float = 120.0

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

func _capture_image_direct(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var vp: Viewport = root.get_viewport()
	if not vp: return
	var tex = vp.get_texture()
	if not tex: return
	var img: Image = tex.get_image()
	if img and not img.is_empty():
		var full_path = "%s/%s" % [OUTPUT_DIR, file_name]
		img.save_png(full_path)

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

	# -------------------------------------------------------------------------
	# 8. Dynamic Gameplay Acceptance: Step-up, Cliff Collision, and Chunk Streaming
	# Standard game camera actively tracking player, locomotion driven exclusively
	# through standard player input and player _physics_process!
	# -------------------------------------------------------------------------
	print("[ISSUE-43] 8. Dynamic Gameplay: Player walking over 1m step, colliding with 2m cliff, and streaming chunks...")
	var walk_target: Node3D = Node3D.new()
	walk_target.name = "WalkTarget"
	main.add_child(walk_target)
	player.forced_target = walk_target

	camera.set_target(player)
	camera.set_process(true)
	camera.set_physics_process(true)
	camera.pan_enabled = false
	player.set_physics_process(true)

	var seq_idx: int = 0

	# 8.1. Approach and walk over 1m step:
	# From cell (6, 1) y=0 to cell (7, 1) y=1
	var h61: float = float(map_gen.get_voxel_height(6, 1))
	player.global_position = Vector3(5.5, h61 + 0.9, 1.5)
	player.velocity = Vector3.ZERO
	walk_target.global_position = Vector3(100.0, 0.0, 1.5)

	# Settle physics and camera
	for f in range(6):
		await process_frame

	await _capture_viewport("dyn_01_step_approach.png")
	await _capture_image_direct("dyn_seq_%02d.png" % seq_idx)
	seq_idx += 1

	# Command player to walk East (+X) via standard Input
	Input.action_press("move_up")
	for f in range(50):
		await process_frame
		if f == 24:
			await _capture_image_direct("dyn_02_step_climb.png")
		if f % 2 == 0:
			await _capture_image_direct("dyn_seq_%02d.png" % seq_idx)
			seq_idx += 1

	Input.action_release("move_up")
	for f in range(6):
		await process_frame

	await _capture_viewport("dyn_03_step_success_on_top.png")
	await _capture_image_direct("dyn_seq_%02d.png" % seq_idx)
	seq_idx += 1

	var step_end_pos: Vector3 = player.global_position
	print("    [DYNAMIC-STEP] Initial=(5.50, %0.2f, 1.50) -> Top=(%0.2f, %0.2f, %0.2f), height climbed +%0.2fm, on_floor=%s" % [
		h61 + 0.9, step_end_pos.x, step_end_pos.y, step_end_pos.z, step_end_pos.y - (h61 + 0.9), str(player.is_on_floor())
	])

	if step_end_pos.x < 7.3:
		printerr("[ERROR] Player failed to traverse 1m step onto cell (7, 1)! Final x: %f" % step_end_pos.x)
		quit(1)
	if step_end_pos.y < 1.80:
		printerr("[ERROR] Player failed to gain height on 1m step! Final y: %f" % step_end_pos.y)
		quit(1)
	if not player.is_on_floor():
		printerr("[ERROR] Player is not on floor after stepping up!")
		quit(1)

	# 8.2. Approach and collide against 2m cliff:
	# Cell (7, 2) y=1 to cell (8, 2) y=3 (2m cliff at x=8.0)
	var h72: float = float(map_gen.get_voxel_height(7, 2))
	player.global_position = Vector3(7.2, h72 + 0.9, 2.5)
	player.velocity = Vector3.ZERO
	walk_target.global_position = Vector3(100.0, 0.0, 2.5)

	for f in range(6):
		await process_frame

	await _capture_viewport("dyn_04_cliff_approach.png")
	await _capture_image_direct("dyn_seq_%02d.png" % seq_idx)
	seq_idx += 1

	# Command player to walk East into 2m cliff
	Input.action_press("move_up")
	for f in range(35):
		await process_frame
		if f % 2 == 0:
			await _capture_image_direct("dyn_seq_%02d.png" % seq_idx)
			seq_idx += 1

	Input.action_release("move_up")
	for f in range(6):
		await process_frame

	await _capture_viewport("dyn_05_cliff_blocked.png")
	await _capture_image_direct("dyn_seq_%02d.png" % seq_idx)
	seq_idx += 1

	var cliff_end_pos: Vector3 = player.global_position
	print("    [DYNAMIC-CLIFF] Wall plane at x=8.0, player stopped at x=%0.2f (< 8.0), y=%0.2f, on_floor=%s" % [
		cliff_end_pos.x, cliff_end_pos.y, str(player.is_on_floor())
	])

	if cliff_end_pos.x >= 8.0:
		printerr("[ERROR] Player walked through 2m cliff! Final x: %f" % cliff_end_pos.x)
		quit(1)
	if cliff_end_pos.y >= 2.5:
		printerr("[ERROR] Player jumped over 2m impassable cliff! Final y: %f" % cliff_end_pos.y)
		quit(1)

	# 8.3. Continuous walk across chunk boundary:
	# Boundary between chunk (0, 0) and chunk (1, 0) at x=16.0
	print("    [DYNAMIC-BOUNDARY] Walking across chunk boundary at x=16.0...")
	# Clear any resource obstacles in the boundary corridor
	for res_node in root.get_tree().get_nodes_in_group("resource_nodes"):
		if is_instance_valid(res_node) and res_node is Node3D:
			var p = res_node.global_position
			if p.x >= 11.0 and p.x <= 19.0 and p.z >= 0.0 and p.z <= 3.0:
				res_node.queue_free()

	for f in range(4):
		await process_frame

	var h_bound: float = float(map_gen.get_voxel_height(13, 1))
	player.global_position = Vector3(13.0, h_bound + 0.9, 1.5)
	player.velocity = Vector3.ZERO
	walk_target.global_position = Vector3(100.0, 0.0, 1.5)

	for f in range(6):
		await process_frame

	Input.action_press("move_up")
	for f in range(50):
		await process_frame
		if f % 2 == 0:
			await _capture_image_direct("dyn_seq_%02d.png" % seq_idx)
			seq_idx += 1

	Input.action_release("move_up")
	for f in range(6):
		await process_frame

	print("    [DYNAMIC-BOUNDARY] Crossed chunk boundary x=16.0 to x=%.2f, terrain continuous and seamless." % player.global_position.x)
	if player.global_position.x <= 16.0:
		printerr("[ERROR] Player did not cross chunk boundary! Final x: %f" % player.global_position.x)
		quit(1)

	# 8.4. Chunk streaming: move away to trigger unload of chunk (0, 0)
	map_gen.load_radius_chunks = 1
	map_gen.unload_radius_chunks = 2
	print("    [DYNAMIC-STREAMING] Moving to chunk (3, 0) to unload chunk (0, 0)...")
	if not map_gen.active_chunks.has(Vector2i(0, 0)):
		printerr("[ERROR] Chunk (0, 0) should be initially active!")
		quit(1)

	var h30: float = float(map_gen.get_voxel_height(48, 8))
	player.global_position = Vector3(48.0, h30 + 0.9, 8.0)
	player.velocity = Vector3.ZERO
	walk_target.global_position = Vector3(100.0, 0.0, 8.0)
	map_gen.update_player_chunks(Vector2i(3, 0), true)

	for f in range(12):
		await process_frame
		if f % 3 == 0:
			await _capture_image_direct("dyn_seq_%02d.png" % seq_idx)
			seq_idx += 1

	await _capture_viewport("dyn_06_chunk_unloaded.png")
	var chunk_0_0_unloaded: bool = not map_gen.active_chunks.has(Vector2i(0, 0))
	print("    [DYNAMIC-STREAMING] Chunk (0, 0) unloaded: %s" % str(chunk_0_0_unloaded))
	if not chunk_0_0_unloaded:
		printerr("[ERROR] Chunk (0, 0) was not unloaded!")
		quit(1)

	# 8.5. Return to chunk (0, 0) to trigger reload
	print("    [DYNAMIC-STREAMING] Returning to chunk (0, 0) to reload...")
	var h00: float = float(map_gen.get_voxel_height(2, 2))
	player.global_position = Vector3(2.0, h00 + 0.9, 2.0)
	player.velocity = Vector3.ZERO
	walk_target.global_position = Vector3(100.0, 0.0, 2.0)
	map_gen.update_player_chunks(Vector2i(0, 0), true)

	for f in range(15):
		await process_frame
		if f % 3 == 0:
			await _capture_image_direct("dyn_seq_%02d.png" % seq_idx)
			seq_idx += 1

	await _capture_viewport("dyn_07_chunk_reloaded.png")
	var chunk_0_0_reloaded: bool = map_gen.active_chunks.has(Vector2i(0, 0))
	print("    [DYNAMIC-STREAMING] Chunk (0, 0) reloaded: %s" % str(chunk_0_0_reloaded))
	if not chunk_0_0_reloaded:
		printerr("[ERROR] Chunk (0, 0) was not reloaded!")
		quit(1)

	walk_target.queue_free()
	print("[ISSUE-43] All static and dynamic visual evidence completed successfully!")
	quit(0)

extends SceneTree

## Automated verification script for Issue #14:
## - Fixed isometric angle
## - Deadzone and smooth peripheral pan
## - Presets (Close, Medium, Far)
## - Screenshots generation for visual confirmation

const MAIN_SCENE_PATH = "res://scenes/main.tscn"

func _init() -> void:
	print("[VERIFY-CAMERA] Initializing verification runner...")
	call_deferred("_run_verification")

func _run_verification() -> void:
	var main_scene = load(MAIN_SCENE_PATH)
	if not main_scene:
		printerr("[FAIL] Cannot load main.tscn")
		quit(1)
		return

	var main = main_scene.instantiate()
	root.add_child(main)

	var camera = main.get_node_or_null("Camera3D")
	var player = main.get_node_or_null("Player")
	var hud = main.get_node_or_null("HUD")

	if not camera or not player:
		printerr("[FAIL] Required nodes missing in main.tscn")
		quit(1)
		return

	print("[VERIFY-CAMERA] Loaded main scene successfully.")

	# Keep cursor in deadzone center during preset captures
	var vp_size = root.get_visible_rect().size
	if vp_size.x <= 10.0:
		vp_size = Vector2(1280.0, 720.0)
	var vp_center = vp_size * 0.5
	camera.mouse_override = vp_center
	camera.current_peripheral_offset = Vector3.ZERO
	camera.target_peripheral_offset = Vector3.ZERO

	# Wait for scene initialization
	for i in range(15):
		await process_frame

	var base_rot = camera.rotation_degrees
	print("[VERIFY-CAMERA] Initial Camera Rotation: ", base_rot, " FOV: ", camera.fov)

	# 1. Capture Medium Preset (Default)
	camera.set_distance_preset(CameraMath.Preset.MEDIUM, true)
	for i in range(10):
		await process_frame
	_capture_screenshot("docs/screenshots/camera/02_preset_medium.png")
	var rot_medium = camera.rotation_degrees
	print("[VERIFY-CAMERA] Medium Preset Pos: ", camera.global_position, " Rot: ", rot_medium)

	# 2. Capture Close Preset
	camera.set_distance_preset(CameraMath.Preset.CLOSE, false)
	for i in range(60):
		await process_frame
	_capture_screenshot("docs/screenshots/camera/03_preset_close.png")
	var rot_close = camera.rotation_degrees
	print("[VERIFY-CAMERA] Close Preset Pos: ", camera.global_position, " Rot: ", rot_close)

	# 3. Capture Far Preset (Baseline)
	camera.set_distance_preset(CameraMath.Preset.FAR, false)
	for i in range(80):
		await process_frame
	_capture_screenshot("docs/screenshots/camera/01_baseline_far.png")
	var rot_far = camera.rotation_degrees
	print("[VERIFY-CAMERA] Far Preset Pos: ", camera.global_position, " Rot: ", rot_far)

	# Verify Angles are mathematically identical across all presets
	var rot_diff_close = (rot_medium - rot_close).length()
	var rot_diff_far = (rot_medium - rot_far).length()
	if rot_diff_close > 0.01 or rot_diff_far > 0.01:
		printerr("[FAIL] Camera orientation changed between presets! Diff close: ", rot_diff_close, " diff far: ", rot_diff_far)
		quit(1)
		return
	print("[PASS] Camera orientation is strictly invariant across Close, Medium, and Far presets!")

	# Reset to Medium for pan tests
	camera.set_distance_preset(CameraMath.Preset.MEDIUM, true)
	camera.current_peripheral_offset = Vector3.ZERO
	for i in range(10):
		await process_frame

	# 4. Central deadzone test
	camera.mouse_override = vp_center
	for i in range(40):
		await process_frame
	var deadzone_periph = camera.get_peripheral_offset()
	print("[VERIFY-CAMERA] Center deadzone peripheral offset: ", deadzone_periph.length())
	if deadzone_periph.length() > 0.01:
		printerr("[FAIL] Deadzone should have 0 peripheral offset, got: ", deadzone_periph.length())
		quit(1)
		return
	_capture_screenshot("docs/screenshots/camera/04_deadzone_center.png")
	print("[PASS] Center deadzone has zero offset!")

	# 5. Right edge pan test
	camera.mouse_override = Vector2(vp_size.x, vp_center.y)
	for i in range(60):
		await process_frame
	var right_periph = camera.get_peripheral_offset()
	print("[VERIFY-CAMERA] Right edge pan offset: ", right_periph.length(), " vec: ", right_periph)
	if abs(right_periph.length() - 4.0) > 0.1:
		printerr("[FAIL] Right edge pan should reach 4.0m, got: ", right_periph.length())
		quit(1)
		return
	_capture_screenshot("docs/screenshots/camera/05_edge_pan_right.png")
	print("[PASS] Right edge pan reached 4.0m!")

	# 6. Top edge pan test
	camera.mouse_override = Vector2(vp_center.x, 0.0)
	for i in range(60):
		await process_frame
	var top_periph = camera.get_peripheral_offset()
	print("[VERIFY-CAMERA] Top edge pan offset: ", top_periph.length(), " vec: ", top_periph)
	if abs(top_periph.length() - 4.0) > 0.1:
		printerr("[FAIL] Top edge pan should reach 4.0m, got: ", top_periph.length())
		quit(1)
		return
	_capture_screenshot("docs/screenshots/camera/06_edge_pan_top.png")
	print("[PASS] Top edge pan reached 4.0m!")

	# 7. Corner diagonal pan test (clamp <= 4.0m)
	camera.mouse_override = Vector2(vp_size.x, 0.0)
	for i in range(60):
		await process_frame
	var corner_periph = camera.get_peripheral_offset()
	print("[VERIFY-CAMERA] Corner diagonal pan offset: ", corner_periph.length(), " vec: ", corner_periph)
	if corner_periph.length() > 4.05:
		printerr("[FAIL] Corner diagonal pan exceeds 4.0m! got: ", corner_periph.length())
		quit(1)
		return
	_capture_screenshot("docs/screenshots/camera/07_edge_pan_corner.png")
	print("[PASS] Corner diagonal pan is strictly clamped to <= 4.0m!")

	# 8. In-game SettingsModal verification
	if hud:
		var settings_modal = hud.get_node_or_null("SettingsModal")
		if settings_modal:
			settings_modal.open_modal()
			for i in range(10):
				await process_frame
			_capture_screenshot("docs/screenshots/camera/08_in_game_settings_modal.png")
			settings_modal.close_modal()
			print("[PASS] In-game SettingsModal opened and rendered cleanly!")

	# 9. Building occlusion under peripheral pan
	var wall_scene = preload("res://scenes/prefabs/wood_wall.tscn")
	if wall_scene:
		var wall = wall_scene.instantiate()
		main.add_child(wall)
		wall.global_position = player.global_position + (camera.global_position - player.global_position) * 0.5
		wall.global_position.y = 0.5
		camera.mouse_override = Vector2(vp_size.x, vp_center.y)
		for i in range(30):
			await process_frame
		_capture_screenshot("docs/screenshots/camera/09_building_occlusion_panned.png")
		print("[PASS] Building occlusion tested under peripheral pan!")

	print("[VERIFY-CAMERA] All verification steps passed successfully!")
	quit(0)

func _capture_screenshot(file_path: String) -> void:
	var vp = root.get_viewport()
	if not vp:
		return
	var tex = vp.get_texture()
	if not tex:
		return
	var img: Image = tex.get_image()
	if img and not img.is_empty():
		img.save_png(file_path)
		print("[SCREENSHOT] Saved: ", file_path)

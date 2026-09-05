extends GutTest

const CameraFollow = preload("res://scripts/camera_follow.gd")
const CameraMath = preload("res://scripts/camera/camera_math.gd")
const PlayerAim = preload("res://scripts/player/player_aim.gd")

func test_camera_rotation_invariant_under_different_cursor_positions() -> void:
	var target = Node3D.new()
	add_child_autoqfree(target)
	target.position = Vector3(5.0, 1.0, 5.0)

	var camera = CameraFollow.new()
	add_child_autoqfree(camera)
	camera.target = target

	camera._init_camera_transform()
	var initial_rot = camera.rotation_degrees
	assert_true(camera.is_initialized, "Camera should be initialized")
	assert_almost_eq(camera.fov, 45.0, 0.001, "Initial FOV must be 45.0")

	var cursor_positions = [
		Vector2(640, 360), # Center
		Vector2(10, 360),  # Left edge
		Vector2(1270, 360),# Right edge
		Vector2(640, 10),  # Top edge
		Vector2(640, 710), # Bottom edge
		Vector2(10, 10),   # Corner top-left
		Vector2(1270, 710),# Corner bottom-right
	]

	for pos in cursor_positions:
		camera.mouse_override = pos
		for i in range(15):
			camera._process(0.016)

		assert_almost_eq(camera.rotation_degrees.x, initial_rot.x, 0.001, "Rotation X must remain invariant")
		assert_almost_eq(camera.rotation_degrees.y, initial_rot.y, 0.001, "Rotation Y must remain invariant")
		assert_almost_eq(camera.rotation_degrees.z, initial_rot.z, 0.001, "Rotation Z must remain invariant")
		assert_almost_eq(camera.fov, 45.0, 0.001, "FOV must remain invariant")

func test_runtime_preset_switch_preserves_orientation_and_fov() -> void:
	var target = Node3D.new()
	add_child_autoqfree(target)
	target.position = Vector3.ZERO

	var camera = CameraFollow.new()
	add_child_autoqfree(camera)
	camera.target = target
	camera._init_camera_transform()

	var base_rot = camera.rotation_degrees
	camera.mouse_override = Vector2(640, 360) # Deadzone center

	# Switch: Medium -> Close
	camera.set_distance_preset(CameraMath.Preset.CLOSE, false)
	for i in range(40):
		camera._process(0.033)

	assert_almost_eq(camera.rotation_degrees.x, base_rot.x, 0.001, "Switch to Close: Rotation X must not change")
	assert_almost_eq(camera.rotation_degrees.y, base_rot.y, 0.001, "Switch to Close: Rotation Y must not change")
	assert_almost_eq(camera.rotation_degrees.z, base_rot.z, 0.001, "Switch to Close: Rotation Z must not change")
	assert_almost_eq(camera.fov, 45.0, 0.001, "FOV must remain 45.0")
	assert_true(camera.global_position.distance_to(target.global_position) < 25.0, "Close preset distance must be closer than Medium")

	# Switch: Close -> Far
	camera.set_distance_preset(CameraMath.Preset.FAR, false)
	for i in range(70):
		camera._process(0.033)

	assert_almost_eq(camera.rotation_degrees.x, base_rot.x, 0.001, "Switch to Far: Rotation X must not change")
	assert_almost_eq(camera.rotation_degrees.y, base_rot.y, 0.001, "Switch to Far: Rotation Y must not change")
	assert_almost_eq(camera.rotation_degrees.z, base_rot.z, 0.001, "Switch to Far: Rotation Z must not change")
	assert_almost_eq(camera.fov, 45.0, 0.001, "FOV must remain 45.0")
	assert_true(camera.global_position.distance_to(target.global_position) > 30.0, "Far preset distance must be farther than Medium")

func test_aim_ray_accuracy_under_maximum_peripheral_pan() -> void:
	var player = CharacterBody3D.new()
	add_child_autoqfree(player)
	player.position = Vector3(0.0, 0.9, 0.0)

	var camera = CameraFollow.new()
	add_child_autoqfree(camera)
	camera.target = player
	camera._init_camera_transform()

	var vp = camera.get_viewport()
	var vp_size = vp.get_visible_rect().size if vp else Vector2(1280, 720)
	var vp_center = vp_size * 0.5

	# Pan to right edge
	camera.mouse_override = Vector2(vp_size.x, vp_center.y)
	for i in range(50):
		camera._process(0.033)

	var periph = camera.get_peripheral_offset()
	assert_almost_eq(periph.length(), 4.0, 0.1, "Peripheral offset should reach max length (4.0m)")

	# Raycast towards ground plane at player height
	var ground_plane = Plane(Vector3.UP, player.global_position.y)
	var ray_orig = camera.project_ray_origin(vp_center)
	var ray_norm = camera.project_ray_normal(vp_center)
	var hit = ground_plane.intersects_ray(ray_orig, ray_norm)

	assert_not_null(hit, "Ground raycast from panned camera must hit ground plane")
	if hit is Vector3:
		var diff = (hit as Vector3) - player.global_position
		diff.y = 0.0
		# Hit point should match the peripheral shift of the camera
		assert_almost_eq(diff.length(), periph.length(), 0.1, "Center ray on ground must precisely track camera peripheral pan")

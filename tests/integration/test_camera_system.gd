extends GutTest

const CameraFollow = preload("res://scripts/camera_follow.gd")
const CameraMath = preload("res://scripts/camera/camera_math.gd")
const PlayerAim = preload("res://scripts/player/player_aim.gd")
const BuildingSystem = preload("res://scripts/building_system.gd")
const PlayerInteraction = preload("res://scripts/player/player_interaction.gd")
const WoodWallScene = preload("res://scenes/prefabs/wood_wall.tscn")

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

func test_player_aim_under_panned_camera() -> void:
	var player = CharacterBody3D.new()
	add_child_autoqfree(player)
	player.position = Vector3(0.0, 0.9, 0.0)

	var camera = CameraFollow.new()
	add_child_autoqfree(camera)
	camera.target = player
	camera.current = true
	camera._init_camera_transform()

	var vp = camera.get_viewport()
	var vp_size = vp.get_visible_rect().size if vp else Vector2(1280, 720)
	var vp_center = vp_size * 0.5

	# Pan to right edge
	camera.mouse_override = Vector2(vp_size.x, vp_center.y)
	for i in range(50):
		camera._process(0.033)

	var aim = PlayerAim.new()
	aim.last_aim_dir = Vector3(0.0, 0.0, -1.0)

	# Aim at a world position ahead of player (East: Vector3(5, 0.9, 0))
	var target_world = player.global_position + Vector3(5.0, 0.0, 0.0)
	var ground_plane = Plane(Vector3.UP, player.global_position.y)

	# Raycast from camera towards target's screen projection
	var screen_pt = camera.unproject_position(target_world)
	var ray_o = camera.project_ray_origin(screen_pt)
	var ray_n = camera.project_ray_normal(screen_pt)
	var hit = ground_plane.intersects_ray(ray_o, ray_n)
	assert_not_null(hit, "Ray from unprojected screen coordinate must hit ground")

	if hit is Vector3:
		var aim_dir = aim.resolve_cursor_aim(player.global_position, hit as Vector3, 0.6)
		assert_almost_eq(aim_dir.x, 1.0, 0.05, "Aim direction under panned camera should point towards target in East")
		assert_almost_eq(aim_dir.z, 0.0, 0.05, "Aim direction Z should be near zero")
		assert_eq(aim.last_aim_dir, aim_dir, "last_aim_dir must be updated")

	# Test deadzone preservation under panned camera
	var deadzone_world = player.global_position + Vector3(0.2, 0.0, 0.0) # Within 0.6m deadzone
	var deadzone_screen = camera.unproject_position(deadzone_world)
	var dz_ray_o = camera.project_ray_origin(deadzone_screen)
	var dz_ray_n = camera.project_ray_normal(deadzone_screen)
	var dz_hit = ground_plane.intersects_ray(dz_ray_o, dz_ray_n)
	if dz_hit is Vector3:
		var preserved_aim = aim.resolve_cursor_aim(player.global_position, dz_hit as Vector3, 0.6)
		assert_almost_eq(preserved_aim.x, 1.0, 0.05, "Aim direction should be preserved when cursor is inside deadzone")

func test_building_system_placement_under_panned_camera() -> void:
	var player = CharacterBody3D.new()
	add_child_autoqfree(player)
	player.position = Vector3(0.0, 0.0, 0.0)

	var camera = CameraFollow.new()
	add_child_autoqfree(camera)
	camera.target = player
	camera.current = true
	camera._init_camera_transform()

	var vp = camera.get_viewport()
	var vp_size = vp.get_visible_rect().size if vp else Vector2(1280, 720)
	var vp_center = vp_size * 0.5

	# Pan to right edge
	camera.mouse_override = Vector2(vp_size.x, vp_center.y)
	for i in range(50):
		camera._process(0.033)

	var building_system = BuildingSystem.new()
	add_child_autoqfree(building_system)

	# Control screen-space cursor input targeting an exact known grid cell (Vector3(6, 0, 4))
	var target_grid = Vector3(6.0, 0.0, 4.0)
	var screen_pos = camera.unproject_position(target_grid)
	building_system.mouse_override = screen_pos

	# Verify grid positioning calculates the exact target cell from camera ray
	var aimed_pos = building_system.get_aimed_grid_position()
	assert_eq(aimed_pos, target_grid, "BuildingSystem must aim at the exact target cell under panned camera")
	assert_eq(int(aimed_pos.x), 6, "Aimed cell X must match 6")
	assert_eq(int(aimed_pos.z), 4, "Aimed cell Z must match 4")

	# Select prefab and verify preview position tracks correctly under cursor
	building_system.select_prefab(BuildingSystem.PrefabType.WOOD_WALL)
	building_system._process(0.016)
	assert_true(building_system.preview_node.visible, "Preview hologram must be visible during prefab placement")
	assert_eq(building_system.preview_node.global_position, target_grid, "Hologram preview must snap to aimed grid under cursor")

	# Execute real building placement under panned camera
	var cell = Vector2i(int(aimed_pos.x), int(aimed_pos.z))
	building_system.place_building(aimed_pos, cell, BuildingSystem.PrefabType.WOOD_WALL)
	assert_true(building_system.placed_buildings.has(cell), "Building must be registered in placed_buildings")
	var placed_node = building_system.placed_buildings[cell]
	assert_not_null(placed_node, "Placed building instance must not be null")
	assert_eq(placed_node.global_position, target_grid, "Placed building world position must match target grid")
	assert_eq(placed_node.grid_coord, cell, "Placed building grid_coord must match cell")

	building_system.cancel_build_mode()
	assert_false(building_system.preview_node.visible, "Preview hologram must hide on cancel")

func test_player_interaction_under_panned_camera() -> void:
	var player = CharacterBody3D.new()
	add_child_autoqfree(player)
	player.position = Vector3(0.0, 0.0, 0.0)

	var camera = CameraFollow.new()
	add_child_autoqfree(camera)
	camera.target = player
	camera.current = true
	camera._init_camera_transform()

	var vp = camera.get_viewport()
	var vp_size = vp.get_visible_rect().size if vp else Vector2(1280, 720)
	var vp_center = vp_size * 0.5

	# Pan camera to right edge
	camera.mouse_override = Vector2(vp_size.x, vp_center.y)
	for i in range(50):
		camera._process(0.033)

	var wall = WoodWallScene.instantiate()
	add_child_autoqfree(wall)
	# Place wall 3.0m in front of player (within 4.5m interaction range)
	wall.global_position = Vector3(0.0, 0.0, -3.0)

	var interaction = PlayerInteraction.new()
	interaction.add_candidate(wall)
	interaction.process_interaction(player, 0.016)

	assert_not_null(interaction.focused_interactable, "Interactable within range must be focused under panned camera")
	assert_eq(interaction.focused_interactable, wall, "Focused interactable must be the wall candidate")

func test_building_occlusion_and_restoration() -> void:
	var player = CharacterBody3D.new()
	add_child_autoqfree(player)
	player.position = Vector3(0.0, 0.0, 0.0)

	var camera = CameraFollow.new()
	add_child_autoqfree(camera)
	camera.target = player
	camera._init_camera_transform()

	var wall = WoodWallScene.instantiate()
	add_child_autoqfree(wall)
	# Position wall directly on the line between camera and player head where ray passes through wall volume
	var ray_start = camera.global_position
	var ray_end = player.global_position + Vector3(0.0, 0.9, 0.0)
	var occlude_pt = ray_end + (ray_start - ray_end) * 0.1
	wall.global_position = occlude_pt - Vector3(0.0, 1.0, 0.0)

	# Wait for physics update
	for i in range(5):
		await get_tree().physics_frame
		camera.check_occlusion()

	# Assert occlusion sets transparency to 0.6
	assert_almost_eq(wall.current_transparency, 0.6, 0.05, "Occluding building transparency must be set to 0.6")

	# Move wall away so it is no longer occluding
	wall.global_position = Vector3(100.0, 0.0, 100.0)
	for i in range(5):
		await get_tree().physics_frame
		camera.check_occlusion()

	# Assert transparency is restored to 0.0
	assert_almost_eq(wall.current_transparency, 0.0, 0.05, "Non-occluding building transparency must be restored to 0.0")

func test_narrow_viewport_screen_space_safety() -> void:
	var sub_vp = SubViewport.new()
	sub_vp.size = Vector2i(360, 800)
	add_child_autoqfree(sub_vp)

	var player = CharacterBody3D.new()
	sub_vp.add_child(player)
	player.position = Vector3(0.0, 0.9, 0.0)

	var camera = CameraFollow.new()
	sub_vp.add_child(camera)
	camera.target = player
	camera.current = true
	camera._init_camera_transform()

	# Simulate extreme edge pan in narrow viewport
	camera.mouse_override = Vector2(360.0, 400.0) # Far right edge
	for i in range(60):
		camera._process(0.033)

	# Verify player screen projection
	var screen_pos = camera.unproject_position(player.global_position)
	assert_true(screen_pos.x >= 0.0, "Player screen X must be >= 0 (on screen)")
	assert_true(screen_pos.x <= 360.0, "Player screen X must be <= 360 (on screen)")
	assert_true(screen_pos.y >= 0.0, "Player screen Y must be >= 0 (on screen)")
	assert_true(screen_pos.y <= 800.0, "Player screen Y must be <= 800 (on screen)")

	# Check screen half-extent margin (player within safe margin)
	var half_w = 360.0 * 0.5
	var center_dist_x = absf(screen_pos.x - half_w)
	assert_true(center_dist_x / half_w <= 0.85, "Player must remain within 85% safe screen-space half-extent on narrow viewport")

func test_viewport_resize_transition_guarantees_player_remains_on_screen_every_frame() -> void:
	var sub_vp = SubViewport.new()
	# Start with standard 16:9 viewport
	sub_vp.size = Vector2i(1280, 720)
	add_child_autoqfree(sub_vp)

	var player = CharacterBody3D.new()
	sub_vp.add_child(player)
	player.position = Vector3(0.0, 0.9, 0.0)

	var camera = CameraFollow.new()
	sub_vp.add_child(camera)
	camera.target = player
	camera.current = true
	camera._init_camera_transform()

	# Establish full 4.0m pan on 16:9
	camera.mouse_override = Vector2(1280.0, 360.0)
	for i in range(80):
		camera._process(0.016)

	assert_almost_eq(camera.get_peripheral_offset().length(), 4.0, 0.15, "Initial pan on 16:9 should reach ~4.0m")

	# Suddenly resize viewport to extreme narrow portrait aspect ratio (320 x 800)
	sub_vp.size = Vector2i(320, 800)
	camera.mouse_override = Vector2(320.0, 400.0)

	# Verify on EVERY SINGLE FRAME of the resize transition that the player never leaves the safe screen margin
	var half_w = 320.0 * 0.5
	var half_h = 800.0 * 0.5
	for frame in range(60):
		camera._process(0.016)
		var screen_pos = camera.unproject_position(player.global_position)
		assert_true(screen_pos.x >= 0.0, "Frame %d: Player X must be >= 0 (on screen)" % frame)
		assert_true(screen_pos.x <= 320.0, "Frame %d: Player X must be <= 320 (on screen)" % frame)
		assert_true(screen_pos.y >= 0.0, "Frame %d: Player Y must be >= 0 (on screen)" % frame)
		assert_true(screen_pos.y <= 800.0, "Frame %d: Player Y must be <= 800 (on screen)" % frame)

		var nx = absf(screen_pos.x - half_w) / half_w
		var ny = absf(screen_pos.y - half_h) / half_h
		assert_true(nx <= 0.85, "Frame %d: Player NDC X must remain within safe margin 0.85, got: %f" % [frame, nx])
		assert_true(ny <= 0.85, "Frame %d: Player NDC Y must remain within safe margin 0.85, got: %f" % [frame, ny])


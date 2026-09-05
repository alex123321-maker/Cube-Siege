extends GutTest

const CameraMath = preload("res://scripts/camera/camera_math.gd")

func test_dead_zone_mapping_inside_70_percent() -> void:
	var vp_size = Vector2(1000.0, 1000.0)
	# Central 70% is between 150.0 and 850.0 on both X and Y
	
	# Center of screen
	var center_factors = CameraMath.calculate_deadzone_factors(Vector2(500.0, 500.0), vp_size, 0.70)
	assert_eq(center_factors, Vector2.ZERO, "Screen center must produce ZERO peripheral offset")
	
	# Small offsets inside deadzone
	var near_center = CameraMath.calculate_deadzone_factors(Vector2(400.0, 600.0), vp_size, 0.70)
	assert_eq(near_center, Vector2.ZERO, "Points inside deadzone must produce ZERO offset")

	# Boundary points at 15% and 85%
	var left_bound = CameraMath.calculate_deadzone_factors(Vector2(150.0, 500.0), vp_size, 0.70)
	assert_almost_eq(left_bound.x, 0.0, 0.001, "Inner boundary at 15% must be 0% offset")

	var right_bound = CameraMath.calculate_deadzone_factors(Vector2(850.0, 500.0), vp_size, 0.70)
	assert_almost_eq(right_bound.x, 0.0, 0.001, "Inner boundary at 85% must be 0% offset")

	var top_bound = CameraMath.calculate_deadzone_factors(Vector2(500.0, 150.0), vp_size, 0.70)
	assert_almost_eq(top_bound.y, 0.0, 0.001, "Inner boundary at top 15% must be 0% offset")

	var bottom_bound = CameraMath.calculate_deadzone_factors(Vector2(500.0, 850.0), vp_size, 0.70)
	assert_almost_eq(bottom_bound.y, 0.0, 0.001, "Inner boundary at bottom 85% must be 0% offset")

func test_smooth_and_continuous_peripheral_ramp() -> void:
	var vp_size = Vector2(1000.0, 1000.0)
	# Halfway through peripheral zone: 75 px from left edge (t = 0.5)
	var left_mid = CameraMath.calculate_deadzone_factors(Vector2(75.0, 500.0), vp_size, 0.70)
	# Hermite smoothstep at 0.5: 0.5 * 0.5 * (3 - 1) = 0.5
	assert_almost_eq(left_mid.x, -0.5, 0.01, "Midway in left peripheral zone must equal -0.5 smoothly")
	assert_eq(left_mid.y, 0.0, "Y offset should be 0 when Y is in deadzone")

	# Right halfway (850 + 75 = 925 px)
	var right_mid = CameraMath.calculate_deadzone_factors(Vector2(925.0, 500.0), vp_size, 0.70)
	assert_almost_eq(right_mid.x, 0.5, 0.01, "Midway in right peripheral zone must equal +0.5 smoothly")

	# At exact screen edges (0 and 1000 px)
	var left_edge = CameraMath.calculate_deadzone_factors(Vector2(0.0, 500.0), vp_size, 0.70)
	assert_almost_eq(left_edge.x, -1.0, 0.001, "Left edge must be maximum -1.0")

	var right_edge = CameraMath.calculate_deadzone_factors(Vector2(1000.0, 500.0), vp_size, 0.70)
	assert_almost_eq(right_edge.x, 1.0, 0.001, "Right edge must be maximum +1.0")

	var top_edge = CameraMath.calculate_deadzone_factors(Vector2(500.0, 0.0), vp_size, 0.70)
	assert_almost_eq(top_edge.y, 1.0, 0.001, "Top edge must be maximum +1.0 (forward)")

	var bottom_edge = CameraMath.calculate_deadzone_factors(Vector2(500.0, 1000.0), vp_size, 0.70)
	assert_almost_eq(bottom_edge.y, -1.0, 0.001, "Bottom edge must be maximum -1.0 (backward)")

func test_clamp_max_offset_including_diagonals() -> void:
	var vp_size = Vector2(1000.0, 1000.0)
	var dummy_basis = Basis.looking_at(Vector3(-1.0, -1.333333, -1.0).normalized(), Vector3.UP)
	var max_offset = 4.0

	# Four screen corners
	var corners = [
		Vector2(0.0, 0.0),       # Top-Left
		Vector2(1000.0, 0.0),    # Top-Right
		Vector2(0.0, 1000.0),    # Bottom-Left
		Vector2(1000.0, 1000.0)  # Bottom-Right
	]

	for corner in corners:
		var dir_2d = CameraMath.calculate_peripheral_offset_2d(corner, vp_size, 0.70)
		assert_true(dir_2d.length() <= 1.0001, "2D corner direction must be clamped to <= 1.0, got: %f" % dir_2d.length())
		
		var offset_3d = CameraMath.calculate_target_peripheral_offset(corner, vp_size, dummy_basis, max_offset, 0.70)
		assert_true(offset_3d.length() <= max_offset + 0.0001, "Corner 3D offset must be clamped to <= 4.0, got: %f" % offset_3d.length())
		assert_almost_eq(offset_3d.y, 0.0, 0.0001, "Offset must strictly remain on ground plane (Y = 0)")

	# Out of bounds mouse coordinates (e.g. mouse moved outside window)
	var out_of_bounds = Vector2(-200.0, 1500.0)
	var oob_offset = CameraMath.calculate_target_peripheral_offset(out_of_bounds, vp_size, dummy_basis, max_offset, 0.70)
	assert_true(oob_offset.length() <= max_offset + 0.0001, "Out-of-bounds mouse must never exceed max_offset")

func test_camera_presets_exact_values() -> void:
	# Contract specifications:
	# Близко = Vector3(12, 16, 12)
	# Средне = Vector3(15, 20, 15)
	# Далеко = Vector3(18, 24, 18)
	var close_offset = CameraMath.get_preset_offset(CameraMath.Preset.CLOSE)
	var medium_offset = CameraMath.get_preset_offset(CameraMath.Preset.MEDIUM)
	var far_offset = CameraMath.get_preset_offset(CameraMath.Preset.FAR)

	assert_eq(close_offset, Vector3(12.0, 16.0, 12.0), "Close preset must be Vector3(12, 16, 12)")
	assert_eq(medium_offset, Vector3(15.0, 20.0, 15.0), "Medium preset must be Vector3(15, 20, 15)")
	assert_eq(far_offset, Vector3(18.0, 24.0, 18.0), "Far preset must be Vector3(18, 24, 18)")

	# Default preset is Medium
	assert_eq(CameraMath.DEFAULT_PRESET, CameraMath.Preset.MEDIUM, "Default preset must be Medium")
	assert_eq(CameraMath.get_preset_offset(-1), Vector3(15.0, 20.0, 15.0), "Fallback must return Medium preset")

	# Preset names
	assert_eq(CameraMath.get_preset_name(CameraMath.Preset.CLOSE), "Близко")
	assert_eq(CameraMath.get_preset_name(CameraMath.Preset.MEDIUM), "Средне")
	assert_eq(CameraMath.get_preset_name(CameraMath.Preset.FAR), "Далеко")

	# Orientation invariant: all three presets share identical normalized direction vector
	var dir_close = close_offset.normalized()
	var dir_med = medium_offset.normalized()
	var dir_far = far_offset.normalized()

	assert_almost_eq(dir_close.x, dir_med.x, 0.0001, "Direction X must match between Close and Medium")
	assert_almost_eq(dir_close.y, dir_med.y, 0.0001, "Direction Y must match between Close and Medium")
	assert_almost_eq(dir_close.z, dir_med.z, 0.0001, "Direction Z must match between Close and Medium")

	assert_almost_eq(dir_med.x, dir_far.x, 0.0001, "Direction X must match between Medium and Far")
	assert_almost_eq(dir_med.y, dir_far.y, 0.0001, "Direction Y must match between Medium and Far")
	assert_almost_eq(dir_med.z, dir_far.z, 0.0001, "Direction Z must match between Medium and Far")

func test_viewport_aspect_ratios_16_9_and_21_9() -> void:
	# 16:9 viewport (1920 x 1080)
	var vp_16_9 = Vector2(1920.0, 1080.0)
	# Center must be zero
	var center_16_9 = CameraMath.calculate_deadzone_factors(vp_16_9 * 0.5, vp_16_9, 0.70)
	assert_eq(center_16_9, Vector2.ZERO, "16:9 center must be zero offset")
	# Point at 50% width and 50% height is in deadzone
	# Boundary check: 15% width = 288 px, 85% width = 1632 px
	var in_deadzone_16_9 = CameraMath.calculate_deadzone_factors(Vector2(300.0, 540.0), vp_16_9, 0.70)
	assert_eq(in_deadzone_16_9, Vector2.ZERO, "Inside 16:9 deadzone must be zero")
	# Outer 15% check: 100 px from left is in peripheral
	var left_16_9 = CameraMath.calculate_deadzone_factors(Vector2(100.0, 540.0), vp_16_9, 0.70)
	assert_true(left_16_9.x < 0.0, "Left peripheral in 16:9 must produce negative X offset")

	# 21:9 ultrawide viewport (2560 x 1080)
	var vp_21_9 = Vector2(2560.0, 1080.0)
	var center_21_9 = CameraMath.calculate_deadzone_factors(vp_21_9 * 0.5, vp_21_9, 0.70)
	assert_eq(center_21_9, Vector2.ZERO, "21:9 ultrawide center must be zero offset")
	# In 21:9, 15% width is 384 px. Point at 400 px is deadzone
	var in_deadzone_21_9 = CameraMath.calculate_deadzone_factors(Vector2(400.0, 540.0), vp_21_9, 0.70)
	assert_eq(in_deadzone_21_9, Vector2.ZERO, "Inside 21:9 deadzone must be zero")
	# Point at 200 px is peripheral
	var left_21_9 = CameraMath.calculate_deadzone_factors(Vector2(200.0, 540.0), vp_21_9, 0.70)
	assert_true(left_21_9.x < 0.0, "Left peripheral in 21:9 must produce negative X offset")

func test_clamp_offset_to_safe_frustum_keeps_target_visible_on_narrow_viewport() -> void:
	var base_offset = Vector3(15.0, 20.0, 15.0)
	var cam_basis = Basis.looking_at(-base_offset.normalized(), Vector3.UP)
	var max_offset = 4.0
	var safe_margin = 0.80

	# 1. Standard 16:9 viewport (1280 x 720) - 4.0m pan is well within 80% safe margin, not clamped
	var vp_standard = Vector2(1280.0, 720.0)
	var raw_offset = Vector3(max_offset, 0.0, 0.0)
	var clamped_standard = CameraMath.clamp_offset_to_safe_frustum(raw_offset, base_offset, cam_basis, vp_standard, 45.0, safe_margin)
	assert_almost_eq(clamped_standard.length(), max_offset, 0.01, "On standard 16:9 viewport, 4.0m pan should remain full")

	# 2. Narrow vertical viewport (300 x 900) - 4.0m lateral pan would push player close to edge
	var vp_narrow = Vector2(300.0, 900.0)
	var ground_dirs = CameraMath.get_ground_plane_directions(cam_basis)
	var lateral_offset = ground_dirs["right"] * max_offset
	var clamped_narrow = CameraMath.clamp_offset_to_safe_frustum(lateral_offset, base_offset, cam_basis, vp_narrow, 45.0, safe_margin)

	# Clamped offset must be scaled down
	assert_true(clamped_narrow.length() < max_offset, "On narrow viewport (300x900), lateral offset should be scaled down")
	assert_true(clamped_narrow.length() > 1.0, "Clamped offset should still allow non-zero pan")

	# Verify projection of player with clamped offset is strictly within safe margin
	var p_world = -(base_offset + clamped_narrow)
	var p_cam = cam_basis.inverse() * p_world
	var half_h = (-p_cam.z) * tan(deg_to_rad(45.0) * 0.5)
	var half_w = half_h * (vp_narrow.x / vp_narrow.y)
	var nx = absf(p_cam.x) / half_w
	var ny = absf(p_cam.y) / half_h
	assert_true(nx <= safe_margin + 0.01, "Projected X must be within safe margin 0.80, got: %f" % nx)
	assert_true(ny <= safe_margin + 0.01, "Projected Y must be within safe margin 0.80, got: %f" % ny)

	# 3. Extreme narrow viewport (200 x 800)
	var vp_extreme = Vector2(200.0, 800.0)
	var clamped_extreme = CameraMath.clamp_offset_to_safe_frustum(lateral_offset, base_offset, cam_basis, vp_extreme, 45.0, safe_margin)
	assert_true(clamped_extreme.length() < clamped_narrow.length(), "More extreme aspect ratio should scale down offset further")

	var p_world_ext = -(base_offset + clamped_extreme)
	var p_cam_ext = cam_basis.inverse() * p_world_ext
	var half_h_ext = (-p_cam_ext.z) * tan(deg_to_rad(45.0) * 0.5)
	var half_w_ext = half_h_ext * (vp_extreme.x / vp_extreme.y)
	var nx_ext = absf(p_cam_ext.x) / half_w_ext
	assert_true(nx_ext <= safe_margin + 0.01, "Projected X in extreme viewport must be within safe margin, got: %f" % nx_ext)

func test_calculate_target_peripheral_offset_integrates_safe_frustum_clamp() -> void:
	var base_offset = Vector3(15.0, 20.0, 15.0)
	var cam_basis = Basis.looking_at(-base_offset.normalized(), Vector3.UP)
	var vp_narrow = Vector2(300.0, 900.0)

	# Right edge cursor on narrow viewport
	var edge_pos = Vector2(vp_narrow.x, vp_narrow.y * 0.5)
	var offset = CameraMath.calculate_target_peripheral_offset(edge_pos, vp_narrow, cam_basis, 4.0, 0.70, base_offset)

	# Check that offset was computed and clamped safely
	assert_true(offset.length() > 0.5, "Should have non-zero peripheral offset")
	assert_true(offset.length() <= 4.0, "Should not exceed max offset 4.0")

	# Target remains inside safe frustum
	var p_world = -(base_offset + offset)
	var p_cam = cam_basis.inverse() * p_world
	var half_h = (-p_cam.z) * tan(deg_to_rad(45.0) * 0.5)
	var half_w = half_h * (vp_narrow.x / vp_narrow.y)
	var nx = absf(p_cam.x) / half_w
	assert_true(nx <= 0.81, "Calculated offset must keep target within safe frustum")

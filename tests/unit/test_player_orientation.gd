extends GutTest

## Unit tests for PlayerOrientation: kinematics, shortest turn, facing tolerance, deadzone, and speed curve (Issue #11).

const PlayerOrientation = preload("res://scripts/player/player_orientation.gd")
const PlayerOrientationSettings = preload("res://scripts/resources/player_orientation_settings.gd")
const PlayerAim = preload("res://scripts/player/player_aim.gd")

func test_orientation_initialization_defaults() -> void:
	var orientation = PlayerOrientation.new()
	orientation.setup(Vector3(0.0, 0.0, -1.0))

	assert_almost_eq(orientation.body_facing_direction.x, 0.0, 0.01)
	assert_almost_eq(orientation.body_facing_direction.z, -1.0, 0.01)
	assert_almost_eq(orientation.aim_direction.z, -1.0, 0.01)
	assert_eq(orientation.is_turning, false)
	assert_almost_eq(orientation.directional_speed_multiplier, 1.0, 0.01)
	assert_almost_eq(orientation.angular_velocity, 0.0, 0.001)

func test_angle_calculations_and_shortest_turn() -> void:
	var orientation = PlayerOrientation.new()
	orientation.setup(Vector3(0.0, 0.0, -1.0))

	# 90 degrees right (East)
	var right_target: Vector3 = Vector3(1.0, 0.0, 0.0)
	var angle_to_right: float = orientation.get_angle_to_direction(right_target)
	assert_almost_eq(angle_to_right, PI * 0.5, 0.01, "Angle to right should be ~90 degrees")

	# 90 degrees left (West)
	var left_target: Vector3 = Vector3(-1.0, 0.0, 0.0)
	var angle_to_left: float = orientation.get_angle_to_direction(left_target)
	assert_almost_eq(angle_to_left, PI * 0.5, 0.01, "Angle to left should be ~90 degrees")

	# 180 degrees backward (South)
	var back_target: Vector3 = Vector3(0.0, 0.0, 1.0)
	var angle_to_back: float = orientation.get_angle_to_direction(back_target)
	assert_almost_eq(angle_to_back, PI, 0.01, "Angle to back should be ~180 degrees")

	# Shortest turn across ±180° seam
	# Near South: (0.1, 0, 0.99) to (-0.1, 0, 0.99)
	var v_a: Vector3 = Vector3(0.1, 0.0, 0.99).normalized()
	var v_b: Vector3 = Vector3(-0.1, 0.0, 0.99).normalized()
	orientation.setup(v_a)
	var delta_angle: float = orientation.get_angle_to_direction(v_b)
	assert_lt(delta_angle, 0.3, "Turn across ±180° boundary should take shortest arc, not 360 spin")

func test_angular_acceleration_and_deceleration_kinematics() -> void:
	var orientation = PlayerOrientation.new()
	orientation.setup(Vector3(0.0, 0.0, -1.0))

	var target: Vector3 = Vector3(0.0, 0.0, 1.0) # 180 deg turn

	# Step 1: initial acceleration
	orientation.step_rotation(0.016, target)
	assert_true(orientation.is_turning, "Should be turning")
	assert_gt(absf(orientation.angular_velocity), 0.0, "Angular velocity should accelerate from zero")
	assert_lt(absf(orientation.angular_velocity), orientation.settings.max_turn_rate, "Angular velocity should ramp up gradually")

	# Simulate full rotation until completion
	var total_time: float = 0.0
	var max_iterations: int = 200
	while orientation.is_turning and max_iterations > 0:
		orientation.step_rotation(0.016, target)
		total_time += 0.016
		max_iterations -= 1

	assert_false(orientation.is_turning, "Should complete rotation")
	assert_almost_eq(orientation.angular_velocity, 0.0, 0.001, "Angular velocity should stop at zero")
	assert_almost_eq(orientation.body_facing_direction.x, target.x, 0.01, "Should cleanly reach target X")
	assert_almost_eq(orientation.body_facing_direction.z, target.z, 0.01, "Should cleanly reach target Z")
	# Full 180° turn should complete in reasonable gameplay range (0.15s - 0.40s)
	assert_gt(total_time, 0.10, "Turn should not be instantaneous")
	assert_lt(total_time, 0.45, "Turn should not be sluggish")

func test_facing_tolerance_and_is_facing() -> void:
	var orientation = PlayerOrientation.new()
	orientation.setup(Vector3(0.0, 0.0, -1.0))

	var within_tol: Vector3 = Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, deg_to_rad(10.0))
	var outside_tol: Vector3 = Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, deg_to_rad(25.0))

	assert_true(orientation.is_facing(within_tol, deg_to_rad(15.0)), "10° should be within 15° tolerance")
	assert_false(orientation.is_facing(outside_tol, deg_to_rad(15.0)), "25° should be outside 15° tolerance")
	assert_true(orientation.is_facing(outside_tol, deg_to_rad(30.0)), "25° should be within 30° tolerance")

func test_directional_speed_multiplier_curve_sampling() -> void:
	var orientation = PlayerOrientation.new()
	orientation.setup(Vector3(0.0, 0.0, -1.0))

	var dummy_body = CharacterBody3D.new()
	add_child_autoqfree(dummy_body)

	# 0° (Forward) -> 1.00
	orientation.process_orientation(dummy_body, 0.016, Vector3(0, 0, -1), Vector3(0, 0, -1))
	assert_almost_eq(orientation.directional_speed_multiplier, 1.00, 0.02, "Forward speed should be 1.0")

	# 45° -> ~0.90
	var move_45: Vector3 = Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(45.0))
	orientation.process_orientation(dummy_body, 0.016, Vector3(0, 0, -1), move_45)
	assert_almost_eq(orientation.directional_speed_multiplier, 0.90, 0.05, "45° speed should be ~0.90")

	# 90° (Strafe) -> ~0.75
	var move_90: Vector3 = Vector3(1, 0, 0)
	orientation.process_orientation(dummy_body, 0.016, Vector3(0, 0, -1), move_90)
	assert_almost_eq(orientation.directional_speed_multiplier, 0.75, 0.05, "Strafe speed should be ~0.75")

	# 135° -> ~0.62
	var move_135: Vector3 = Vector3(0, 0, -1).rotated(Vector3.UP, deg_to_rad(135.0))
	orientation.process_orientation(dummy_body, 0.016, Vector3(0, 0, -1), move_135)
	assert_almost_eq(orientation.directional_speed_multiplier, 0.62, 0.05, "135° speed should be ~0.62")

	# 180° (Backward) -> ~0.50
	var move_180: Vector3 = Vector3(0, 0, 1)
	orientation.process_orientation(dummy_body, 0.016, Vector3(0, 0, -1), move_180)
	assert_almost_eq(orientation.directional_speed_multiplier, 0.50, 0.03, "Backward speed should be ~0.50")

func test_aim_deadzone_preserves_last_valid_aim() -> void:
	var aim = PlayerAim.new()
	var dummy_body = CharacterBody3D.new()
	add_child_autoqfree(dummy_body)
	dummy_body.global_position = Vector3(10.0, 0.0, 10.0)

	aim.last_aim_dir = Vector3(0.0, 0.0, -1.0)

	# Forced target outside deadzone
	var target_outside = Node3D.new()
	add_child_autoqfree(target_outside)
	target_outside.global_position = dummy_body.global_position + Vector3(2.0, 0.0, 0.0)

	var res_outside = aim.handle_aim(dummy_body, target_outside, 0.6)
	assert_almost_eq(res_outside.x, 1.0, 0.01, "Should aim towards target outside deadzone")

	# Forced target inside deadzone (distance < 0.6)
	var target_inside = Node3D.new()
	add_child_autoqfree(target_inside)
	target_inside.global_position = dummy_body.global_position + Vector3(0.01, 0.0, 0.01) # length ~0.014

	# If forced_target length is very small, handle_aim preserves last_aim_dir
	var res_inside = aim.handle_aim(dummy_body, target_inside, 0.6)
	assert_almost_eq(res_inside.x, 1.0, 0.01, "Should preserve previous valid aim inside deadzone")

func test_smooth_redirection_mid_turn() -> void:
	var orientation = PlayerOrientation.new()
	orientation.setup(Vector3(0.0, 0.0, -1.0))

	# Start turning right towards (1, 0, 0)
	for i in range(5):
		orientation.step_rotation(0.016, Vector3(1.0, 0.0, 0.0))

	assert_gt(orientation.angular_velocity * signf(orientation.body_facing_direction.signed_angle_to(Vector3(1, 0, 0), Vector3.UP)), 0.0)

	# Suddenly change target to left (-1, 0, 0)
	var old_facing: Vector3 = orientation.body_facing_direction
	orientation.step_rotation(0.016, Vector3(-1.0, 0.0, 0.0))

	# Should not crash, should not NaN, and should adjust rotation continuously
	assert_true(orientation.body_facing_direction.is_finite())
	assert_almost_eq(orientation.body_facing_direction.length(), 1.0, 0.01)

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
	var player_pos: Vector3 = Vector3(10.0, 0.0, 10.0)

	# Initial valid aim direction: North (0, 0, -1)
	aim.last_aim_dir = Vector3(0.0, 0.0, -1.0)

	# Test 1: With deadzone = 1.0
	var deadzone_1: float = 1.0

	# Cursor inside deadzone (distance 0.6 < 1.0 towards East)
	var cursor_inside_1: Vector3 = player_pos + Vector3(0.6, 0.0, 0.0)
	var res_inside_1: Vector3 = aim.resolve_cursor_aim(player_pos, cursor_inside_1, deadzone_1)
	assert_almost_eq(res_inside_1.z, -1.0, 0.01, "Cursor inside deadzone (dist 0.6 < 1.0) must preserve previous aim (North)")
	assert_almost_eq(res_inside_1.x, 0.0, 0.01, "Cursor inside deadzone must not update to East")

	# Cursor outside deadzone (distance 1.5 >= 1.0 towards East)
	var cursor_outside_1: Vector3 = player_pos + Vector3(1.5, 0.0, 0.0)
	var res_outside_1: Vector3 = aim.resolve_cursor_aim(player_pos, cursor_outside_1, deadzone_1)
	assert_almost_eq(res_outside_1.x, 1.0, 0.01, "Cursor outside deadzone (dist 1.5 >= 1.0) must update aim to East")
	assert_almost_eq(res_outside_1.z, 0.0, 0.01)

	# Test 2: Prove that changing aim_deadzone dynamically changes the behavior boundary
	# Increase deadzone to 2.0. The previous cursor position (dist 1.5) is now INSIDE deadzone!
	var deadzone_2: float = 2.0

	# Aim is currently East (1, 0, 0).
	# Move cursor towards South (+Z) at distance 1.5.
	# At deadzone 1.0 this would update to South, but at deadzone 2.0 (1.5 < 2.0) it must preserve East!
	var cursor_at_1_5_south: Vector3 = player_pos + Vector3(0.0, 0.0, 1.5)
	var res_inside_2: Vector3 = aim.resolve_cursor_aim(player_pos, cursor_at_1_5_south, deadzone_2)
	assert_almost_eq(res_inside_2.x, 1.0, 0.01, "At deadzone 2.0, dist 1.5 is inside deadzone and must preserve previous aim (East)")
	assert_almost_eq(res_inside_2.z, 0.0, 0.01, "At deadzone 2.0, dist 1.5 must not update to South")

	# Move cursor beyond deadzone 2.0 (distance 2.5 towards South)
	var cursor_outside_2: Vector3 = player_pos + Vector3(0.0, 0.0, 2.5)
	var res_outside_2: Vector3 = aim.resolve_cursor_aim(player_pos, cursor_outside_2, deadzone_2)
	assert_almost_eq(res_outside_2.z, 1.0, 0.01, "At deadzone 2.0, dist 2.5 >= 2.0 must update aim to South")
	assert_almost_eq(res_outside_2.x, 0.0, 0.01)

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

func test_kinematic_reversal_direction_continuity() -> void:
	var orientation = PlayerOrientation.new()
	orientation.setup(Vector3(0.0, 0.0, -1.0))

	# Turn towards (1, 0, 0) for 6 frames to establish non-zero angular velocity
	for i in range(6):
		orientation.step_rotation(0.016, Vector3(1.0, 0.0, 0.0))

	var initial_vel: float = orientation.angular_velocity
	var initial_sign: float = signf(initial_vel)
	assert_ne(initial_sign, 0.0, "Angular velocity should be non-zero while rotating")

	# Suddenly reverse target direction to opposite side (-1, 0, 0)
	var facing_before: Vector3 = orientation.body_facing_direction
	orientation.step_rotation(0.016, Vector3(-1.0, 0.0, 0.0))

	# Velocity must keep its original sign (braking) and rotation delta must continue in velocity direction
	assert_eq(signf(orientation.angular_velocity), initial_sign, "Velocity sign must be preserved during initial braking step")
	assert_lt(absf(orientation.angular_velocity), absf(initial_vel), "Velocity magnitude should decelerate toward zero")
	var angle_delta: float = facing_before.signed_angle_to(orientation.body_facing_direction, Vector3.UP)
	assert_eq(signf(angle_delta), initial_sign, "Body must continue turning in the direction of angular_velocity during reversal brake")

	# Step until velocity reaches zero
	var max_steps: int = 50
	while absf(orientation.angular_velocity) > 0.001 and max_steps > 0:
		orientation.step_rotation(0.016, Vector3(-1.0, 0.0, 0.0))
		max_steps -= 1

	assert_almost_eq(orientation.angular_velocity, 0.0, 0.01, "Velocity should reach zero before reversing")

	# Next step must accelerate in the new target direction (opposite sign)
	orientation.step_rotation(0.016, Vector3(-1.0, 0.0, 0.0))
	assert_eq(signf(orientation.angular_velocity), -initial_sign, "After braking to zero, angular velocity must accelerate toward new target")

extends GutTest

func test_world_to_body_local_cardinals_and_rotated_body() -> void:
	for yaw: float in [0.0, 0.7, PI, -2.9]:
		var facing: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, yaw)
		var right: Vector3 = facing.cross(Vector3.UP)
		assert_almost_eq(CharacterAnimationMath.local_movement(facing, facing), Vector2(0, 1), Vector2.ONE * 0.0001)
		assert_almost_eq(CharacterAnimationMath.local_movement(-facing, facing), Vector2(0, -1), Vector2.ONE * 0.0001)
		assert_almost_eq(CharacterAnimationMath.local_movement(right, facing), Vector2(1, 0), Vector2.ONE * 0.0001)
		assert_almost_eq(CharacterAnimationMath.local_movement(-right, facing), Vector2(-1, 0), Vector2.ONE * 0.0001)

func test_diagonals_remain_continuous_and_normalized() -> void:
	for degrees: float in [35.0, 70.0, 135.0, 179.0, -135.0]:
		var angle: float = deg_to_rad(degrees)
		var direction: Vector3 = Vector3(sin(angle), 0, -cos(angle))
		var local: Vector2 = CharacterAnimationMath.local_movement(direction, Vector3.FORWARD)
		assert_almost_eq(local, Vector2(sin(angle), cos(angle)), Vector2.ONE * 0.0001)
		var weights: Vector4 = CharacterAnimationMath.direction_weights(local)
		assert_almost_eq(weights.x + weights.y + weights.z + weights.w, 1.0, 0.0001)
		var nearby: Vector4 = CharacterAnimationMath.direction_weights(local.rotated(0.001))
		assert_lt((weights - nearby).length(), 0.005, "No direction quantization")

func test_aim_clamps_and_shortest_angle_at_wrap() -> void:
	var profile: CharacterAnimationProfile = PlayerPresentation.ARCHER_PROFILE
	for angle: float in [-PI, -2.0, 2.0, PI]:
		var offsets: Vector3 = CharacterAnimationMath.aim_offsets(Vector3.FORWARD, Vector3.FORWARD.rotated(Vector3.UP, angle), profile)
		assert_lte(absf(offsets.x), profile.torso_limit)
		assert_lte(absf(offsets.y), profile.head_limit)
		assert_lt(absf(offsets.x + offsets.y), PI / 2)
	var facing: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(179))
	var aim: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(-179))
	var result: Vector3 = CharacterAnimationMath.aim_offsets(facing, aim, profile)
	assert_gt(result.x, 0.0)
	assert_lt(result.x + result.y, deg_to_rad(3))

func test_backward_is_authored_gait_and_shared_phase_wraps() -> void:
	var profile: CharacterAnimationProfile = PlayerPresentation.WARRIOR_PROFILE
	assert_gt(profile.forward.sample_rotation(0).x, 0.0)
	assert_lt(profile.backward.sample_rotation(0).x, 0.0)
	assert_gt(profile.strafe_right.sample_rotation(0).z, 0.0)
	assert_lt(profile.strafe_left.sample_rotation(0).z, 0.0)
	assert_ne(profile.backward.sample_rotation(0.2), profile.forward.sample_rotation(0.8), "Backward is not reverse playback")
	for gait: CharacterGait in [profile.forward, profile.backward, profile.strafe_left, profile.strafe_right]:
		assert_lt((gait.sample_rotation(0.9999) - gait.sample_rotation(0.0001)).length(), 0.005)

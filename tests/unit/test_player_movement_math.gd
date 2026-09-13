extends GutTest

## Unit tests for PlayerMovementMath (Issue #22):
## Screen-relative locomotion basis, forced target basis, cardinal directions,
## diagonal normalization, and fallback handling.

const PlayerMovementMath = preload("res://scripts/player/player_movement_math.gd")

func test_screen_relative_basis_invariant_to_aim() -> void:
	var player_pos: Vector3 = Vector3.ZERO
	var test_aims: Array[Vector3] = [
		Vector3(0.0, 0.0, -1.0), # North
		Vector3(1.0, 0.0, 0.0),  # East
		Vector3(0.0, 0.0, 1.0),  # South
		Vector3(-1.0, 0.0, 0.0), # West
		Vector3(0.707, 0.0, -0.707),
		Vector3.ZERO
	]

	for aim in test_aims:
		var basis: Dictionary = PlayerMovementMath.calculate_movement_basis(player_pos, aim)
		var fwd: Vector3 = basis["forward"]
		var right: Vector3 = basis["right"]

		assert_almost_eq(fwd.x, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.x, 0.001, "Forward basis must remain Screen-Relative")
		assert_almost_eq(fwd.z, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.z, 0.001)
		assert_almost_eq(right.x, PlayerMovementMath.DEFAULT_SCREEN_RIGHT.x, 0.001, "Right basis must remain Screen-Relative")
		assert_almost_eq(right.z, PlayerMovementMath.DEFAULT_SCREEN_RIGHT.z, 0.001)

func test_cardinal_screen_relative_movement() -> void:
	var basis: Dictionary = PlayerMovementMath.calculate_movement_basis(Vector3.ZERO, Vector3.ZERO)
	var fwd: Vector3 = basis["forward"]
	var right: Vector3 = basis["right"]

	# W (0, -1) -> Screen-Up (-0.707, 0, -0.707)
	var move_w: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(0.0, -1.0), fwd, right)
	assert_almost_eq(move_w.x, fwd.x, 0.001)
	assert_almost_eq(move_w.z, fwd.z, 0.001, "W must move Screen-Up")
	assert_almost_eq(move_w.length(), 1.0, 0.001)

	# S (0, 1) -> Screen-Down (0.707, 0, 0.707)
	var move_s: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(0.0, 1.0), fwd, right)
	assert_almost_eq(move_s.x, -fwd.x, 0.001)
	assert_almost_eq(move_s.z, -fwd.z, 0.001, "S must move Screen-Down")
	assert_almost_eq(move_s.length(), 1.0, 0.001)

	# A (-1, 0) -> Screen-Left (-0.707, 0, 0.707)
	var move_a: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(-1.0, 0.0), fwd, right)
	assert_almost_eq(move_a.x, -right.x, 0.001)
	assert_almost_eq(move_a.z, -right.z, 0.001, "A must move Screen-Left")
	assert_almost_eq(move_a.length(), 1.0, 0.001)

	# D (1, 0) -> Screen-Right (0.707, 0, -0.707)
	var move_d: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(1.0, 0.0), fwd, right)
	assert_almost_eq(move_d.x, right.x, 0.001)
	assert_almost_eq(move_d.z, right.z, 0.001, "D must move Screen-Right")
	assert_almost_eq(move_d.length(), 1.0, 0.001)

func test_diagonal_inputs_and_normalization() -> void:
	var basis: Dictionary = PlayerMovementMath.calculate_movement_basis(Vector3.ZERO, Vector3.ZERO)
	var fwd: Vector3 = basis["forward"]
	var right: Vector3 = basis["right"]

	# W + D (input: Vector2(1, -1)) -> North (0, 0, -1) in world coordinates
	var wd: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(1.0, -1.0), fwd, right)
	assert_almost_eq(wd.length(), 1.0, 0.001, "W+D must be strictly normalized to length 1.0")
	assert_almost_eq(wd.x, 0.0, 0.001)
	assert_almost_eq(wd.z, -1.0, 0.001, "W+D in isometric basis points North (0, 0, -1)")

	# W + A (input: Vector2(-1, -1)) -> West (-1, 0, 0) in world coordinates
	var wa: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(-1.0, -1.0), fwd, right)
	assert_almost_eq(wa.length(), 1.0, 0.001, "W+A must be strictly normalized to length 1.0")
	assert_almost_eq(wa.x, -1.0, 0.001, "W+A in isometric basis points West (-1, 0, 0)")
	assert_almost_eq(wa.z, 0.0, 0.001)

	# S + D (input: Vector2(1, 1)) -> East (1, 0, 0) in world coordinates
	var sd: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(1.0, 1.0), fwd, right)
	assert_almost_eq(sd.length(), 1.0, 0.001, "S+D must be strictly normalized to length 1.0")
	assert_almost_eq(sd.x, 1.0, 0.001, "S+D in isometric basis points East (1, 0, 0)")
	assert_almost_eq(sd.z, 0.0, 0.001)

	# S + A (input: Vector2(-1, 1)) -> South (0, 0, 1) in world coordinates
	var sa: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(-1.0, 1.0), fwd, right)
	assert_almost_eq(sa.length(), 1.0, 0.001, "S+A must be strictly normalized to length 1.0")
	assert_almost_eq(sa.x, 0.0, 0.001)
	assert_almost_eq(sa.z, 1.0, 0.001, "S+A in isometric basis points South (0, 0, 1)")

func test_near_zero_aim_and_safe_fallback() -> void:
	var player_pos: Vector3 = Vector3.ZERO
	# Zero aim direction: should safely fall back without NaN or zero-division
	var basis_zero: Dictionary = PlayerMovementMath.calculate_movement_basis(player_pos, Vector3.ZERO)
	assert_almost_eq(basis_zero["forward"].x, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.x, 0.001)
	assert_almost_eq(basis_zero["forward"].z, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.z, 0.001)
	assert_true(basis_zero["forward"].is_finite(), "Forward basis must be finite")
	assert_true(basis_zero["right"].is_finite(), "Right basis must be finite")

	# Tiny vertical aim (no horizontal component)
	var basis_vertical: Dictionary = PlayerMovementMath.calculate_movement_basis(player_pos, Vector3(0.0, 10.0, 0.0))
	assert_almost_eq(basis_vertical["forward"].length(), 1.0, 0.001, "Forward basis must be unit length")
	assert_false(basis_vertical["forward"].is_zero_approx(), "Forward basis must never be Vector3.ZERO")

	# Custom fallback direction
	var custom_fb: Vector3 = Vector3(1.0, 0.0, 0.0)
	var basis_custom: Dictionary = PlayerMovementMath.calculate_movement_basis(player_pos, Vector3.ZERO, null, custom_fb)
	assert_almost_eq(basis_custom["forward"].x, 1.0, 0.001, "Must respect custom fallback forward")

func test_forced_target_basis() -> void:
	var player_pos: Vector3 = Vector3(0.0, 0.0, 0.0)
	var target: Node3D = Node3D.new()
	add_child_autoqfree(target)
	target.global_position = Vector3(10.0, 0.0, 0.0) # East (+X)

	# Even if aim_dir is North, forced_target has priority 1
	var aim_north: Vector3 = Vector3(0.0, 0.0, -1.0)
	var basis: Dictionary = PlayerMovementMath.calculate_movement_basis(player_pos, aim_north, target)

	assert_almost_eq(basis["forward"].x, 1.0, 0.001, "Forced target forward must point to target (East)")
	assert_almost_eq(basis["forward"].z, 0.0, 0.001)

	# W moves toward target (East)
	var move_w: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(0.0, -1.0), basis["forward"], basis["right"])
	assert_almost_eq(move_w.x, 1.0, 0.001, "W must move toward forced target")

	# S moves away from target (West)
	var move_s: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(0.0, 1.0), basis["forward"], basis["right"])
	assert_almost_eq(move_s.x, -1.0, 0.001, "S must move away from forced target")

	# D strafes right around target (South)
	var move_d: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(1.0, 0.0), basis["forward"], basis["right"])
	assert_almost_eq(move_d.z, 1.0, 0.001, "D must strafe right around target")

func test_moving_forced_target() -> void:
	var player_pos: Vector3 = Vector3(0.0, 0.0, 0.0)
	var target: Node3D = Node3D.new()
	add_child_autoqfree(target)
	target.global_position = Vector3(10.0, 0.0, 0.0) # Initially East

	var basis1: Dictionary = PlayerMovementMath.calculate_movement_basis(player_pos, Vector3(0, 0, -1), target)
	assert_almost_eq(basis1["forward"].x, 1.0, 0.001)

	# Target moves to South (+Z)
	target.global_position = Vector3(0.0, 0.0, 10.0)
	var basis2: Dictionary = PlayerMovementMath.calculate_movement_basis(player_pos, Vector3(0, 0, -1), target)
	assert_almost_eq(basis2["forward"].z, 1.0, 0.001, "Movement basis must dynamically update when target moves")

func test_fallback_after_invalid_or_freed_target() -> void:
	var player_pos: Vector3 = Vector3(0.0, 0.0, 0.0)
	var aim_east: Vector3 = Vector3(1.0, 0.0, 0.0)
	var target: Node3D = Node3D.new()
	target.free() # Freed target

	# Should safely detect freed target and fallback to screen-relative
	var basis: Dictionary = PlayerMovementMath.calculate_movement_basis(player_pos, aim_east, target)
	assert_almost_eq(basis["forward"].x, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.x, 0.001, "Must fallback to screen-relative when target is freed")
	assert_true(basis["forward"].is_finite())

func test_forced_target_at_same_position_as_player() -> void:
	var player_pos: Vector3 = Vector3(5.0, 0.0, 5.0)
	var target: Node3D = Node3D.new()
	add_child_autoqfree(target)
	target.global_position = player_pos # Coincident with player

	var aim_north: Vector3 = Vector3(0.0, 0.0, -1.0)
	var basis: Dictionary = PlayerMovementMath.calculate_movement_basis(player_pos, aim_north, target)
	assert_almost_eq(basis["forward"].x, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.x, 0.001, "Must fallback to screen-relative when target is coincident with player")
	assert_true(basis["forward"].is_finite())

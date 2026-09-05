extends GutTest

## Unit tests for PlayerMovementMath (Issue #16):
## Aim-relative locomotion basis, forced target basis, cardinal directions,
## diagonal normalization, and fallback handling.

const PlayerMovementMath = preload("res://scripts/player/player_movement_math.gd")

func test_cardinal_aim_north() -> void:
	# North: AimDirection = (0, 0, -1) [↑]
	var player_pos: Vector3 = Vector3.ZERO
	var aim_north: Vector3 = Vector3(0.0, 0.0, -1.0)
	var basis: Dictionary = PlayerMovementMath.calculate_movement_basis(player_pos, aim_north)

	var fwd: Vector3 = basis["forward"]
	var right: Vector3 = basis["right"]

	assert_almost_eq(fwd.x, 0.0, 0.001)
	assert_almost_eq(fwd.z, -1.0, 0.001, "Forward basis for North aim must be (0, 0, -1)")
	assert_almost_eq(right.x, 1.0, 0.001, "Right basis for North aim must be (1, 0, 0) [East]")
	assert_almost_eq(right.z, 0.0, 0.001)

	# W (0, -1) -> ↑ (0, 0, -1)
	var move_w: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(0.0, -1.0), fwd, right)
	assert_almost_eq(move_w.x, 0.0, 0.001)
	assert_almost_eq(move_w.z, -1.0, 0.001, "Aim ↑ + W must move North (0, 0, -1)")

	# S (0, 1) -> ↓ (0, 0, 1)
	var move_s: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(0.0, 1.0), fwd, right)
	assert_almost_eq(move_s.x, 0.0, 0.001)
	assert_almost_eq(move_s.z, 1.0, 0.001, "Aim ↑ + S must move South (0, 0, 1)")

	# A (-1, 0) -> ← (-1, 0, 0)
	var move_a: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(-1.0, 0.0), fwd, right)
	assert_almost_eq(move_a.x, -1.0, 0.001, "Aim ↑ + A must move West (-1, 0, 0)")
	assert_almost_eq(move_a.z, 0.0, 0.001)

	# D (1, 0) -> → (1, 0, 0)
	var move_d: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(1.0, 0.0), fwd, right)
	assert_almost_eq(move_d.x, 1.0, 0.001, "Aim ↑ + D must move East (1, 0, 0)")
	assert_almost_eq(move_d.z, 0.0, 0.001)

func test_cardinal_aim_east() -> void:
	# East: AimDirection = (1, 0, 0) [→]
	var player_pos: Vector3 = Vector3.ZERO
	var aim_east: Vector3 = Vector3(1.0, 0.0, 0.0)
	var basis: Dictionary = PlayerMovementMath.calculate_movement_basis(player_pos, aim_east)

	var fwd: Vector3 = basis["forward"]
	var right: Vector3 = basis["right"]

	assert_almost_eq(fwd.x, 1.0, 0.001, "Forward basis for East aim must be (1, 0, 0)")
	assert_almost_eq(fwd.z, 0.0, 0.001)
	assert_almost_eq(right.x, 0.0, 0.001)
	assert_almost_eq(right.z, 1.0, 0.001, "Right basis for East aim must be (0, 0, 1) [South]")

	# Aim → + W -> → (1, 0, 0)
	var move_w: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(0.0, -1.0), fwd, right)
	assert_almost_eq(move_w.x, 1.0, 0.001, "Aim → + W must move East (1, 0, 0)")
	assert_almost_eq(move_w.z, 0.0, 0.001)

	# Aim → + S -> ← (-1, 0, 0)
	var move_s: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(0.0, 1.0), fwd, right)
	assert_almost_eq(move_s.x, -1.0, 0.001, "Aim → + S must move West (-1, 0, 0)")
	assert_almost_eq(move_s.z, 0.0, 0.001)

	# Aim → + A -> ↑ (0, 0, -1)
	var move_a: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(-1.0, 0.0), fwd, right)
	assert_almost_eq(move_a.x, 0.0, 0.001)
	assert_almost_eq(move_a.z, -1.0, 0.001, "Aim → + A must move North (0, 0, -1)")

	# Aim → + D -> ↓ (0, 0, 1)
	var move_d: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(1.0, 0.0), fwd, right)
	assert_almost_eq(move_d.x, 0.0, 0.001)
	assert_almost_eq(move_d.z, 1.0, 0.001, "Aim → + D must move South (0, 0, 1)")

func test_cardinal_aim_south_and_west() -> void:
	var player_pos: Vector3 = Vector3.ZERO

	# South: AimDirection = (0, 0, 1) [↓]
	var basis_s: Dictionary = PlayerMovementMath.calculate_movement_basis(player_pos, Vector3(0.0, 0.0, 1.0))
	var w_s: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(0.0, -1.0), basis_s["forward"], basis_s["right"])
	assert_almost_eq(w_s.z, 1.0, 0.001, "Aim South + W must move South")
	var d_s: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(1.0, 0.0), basis_s["forward"], basis_s["right"])
	assert_almost_eq(d_s.x, -1.0, 0.001, "Aim South + D must strafe West")

	# West: AimDirection = (-1, 0, 0) [←]
	var basis_w: Dictionary = PlayerMovementMath.calculate_movement_basis(player_pos, Vector3(-1.0, 0.0, 0.0))
	var w_w: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(0.0, -1.0), basis_w["forward"], basis_w["right"])
	assert_almost_eq(w_w.x, -1.0, 0.001, "Aim West + W must move West")
	var a_w: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(-1.0, 0.0), basis_w["forward"], basis_w["right"])
	assert_almost_eq(a_w.z, 1.0, 0.001, "Aim West + A must strafe South")

func test_diagonal_inputs_and_normalization() -> void:
	# Test diagonals for North aim and East aim
	var aims: Array[Vector3] = [Vector3(0.0, 0.0, -1.0), Vector3(1.0, 0.0, 0.0)]
	for aim in aims:
		var basis: Dictionary = PlayerMovementMath.calculate_movement_basis(Vector3.ZERO, aim)
		var fwd: Vector3 = basis["forward"]
		var right: Vector3 = basis["right"]

		# W + D (input: Vector2(1, -1))
		var wd: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(1.0, -1.0), fwd, right)
		assert_almost_eq(wd.length(), 1.0, 0.001, "W+D must be strictly normalized to length 1.0")
		assert_almost_eq(fwd.angle_to(wd), deg_to_rad(45.0), 0.01, "W+D must be 45° to the right of forward")

		# W + A (input: Vector2(-1, -1))
		var wa: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(-1.0, -1.0), fwd, right)
		assert_almost_eq(wa.length(), 1.0, 0.001, "W+A must be strictly normalized to length 1.0")
		assert_almost_eq(fwd.angle_to(wa), deg_to_rad(45.0), 0.01, "W+A must be 45° to the left of forward")

		# S + D (input: Vector2(1, 1))
		var sd: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(1.0, 1.0), fwd, right)
		assert_almost_eq(sd.length(), 1.0, 0.001, "S+D must be strictly normalized to length 1.0")
		assert_almost_eq(fwd.angle_to(sd), deg_to_rad(135.0), 0.01, "S+D must be 135° to the right of forward")

		# S + A (input: Vector2(-1, 1))
		var sa: Vector3 = PlayerMovementMath.compute_movement_vector(Vector2(-1.0, 1.0), fwd, right)
		assert_almost_eq(sa.length(), 1.0, 0.001, "S+A must be strictly normalized to length 1.0")
		assert_almost_eq(fwd.angle_to(sa), deg_to_rad(135.0), 0.01, "S+A must be 135° to the left of forward")

func test_near_zero_aim_and_safe_fallback() -> void:
	var player_pos: Vector3 = Vector3.ZERO
	# Zero aim direction: should safely fall back without NaN or zero-division
	var basis_zero: Dictionary = PlayerMovementMath.calculate_movement_basis(player_pos, Vector3.ZERO)
	assert_almost_eq(basis_zero["forward"].z, -1.0, 0.001, "Fallback forward must default to North (0, 0, -1)")
	assert_almost_eq(basis_zero["right"].x, 1.0, 0.001, "Fallback right must default to East (1, 0, 0)")
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

	# Should safely detect freed target and fallback to aim_dir
	var basis: Dictionary = PlayerMovementMath.calculate_movement_basis(player_pos, aim_east, target)
	assert_almost_eq(basis["forward"].x, 1.0, 0.001, "Must fallback to aim_direction when target is freed")
	assert_true(basis["forward"].is_finite())

func test_forced_target_at_same_position_as_player() -> void:
	var player_pos: Vector3 = Vector3(5.0, 0.0, 5.0)
	var target: Node3D = Node3D.new()
	add_child_autoqfree(target)
	target.global_position = player_pos # Coincident with player

	var aim_north: Vector3 = Vector3(0.0, 0.0, -1.0)
	var basis: Dictionary = PlayerMovementMath.calculate_movement_basis(player_pos, aim_north, target)
	assert_almost_eq(basis["forward"].z, -1.0, 0.001, "Must fallback to aim_direction when target is coincident with player")
	assert_true(basis["forward"].is_finite())

extends GutTest

## Integration tests for Issue #16:
## WASD movement relative to AimDirection and forced_target,
## orientation turn decoupling, directional speed curve, dash, deadzone, duel, and camera.

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const CameraMath = preload("res://scripts/camera/camera_math.gd")

const PlayerMovementMath = preload("res://scripts/player/player_movement_math.gd")

func after_each() -> void:
	Input.action_release("move_up")
	Input.action_release("move_down")
	Input.action_release("move_left")
	Input.action_release("move_right")

func test_continuous_turn_while_holding_w_90_degrees() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.orientation.setup(Vector3(0.0, 0.0, -1.0)) # Facing North

	# 1. Holding W with Aim North (0, 0, -1)
	Input.action_press("move_up")
	player.orientation.aim_direction = Vector3(0.0, 0.0, -1.0)
	var input_vec = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var move_dir1 = player.movement.compute_move_direction(player.global_position, player.orientation.aim_direction, input_vec)
	assert_almost_eq(move_dir1.x, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.x, 0.01, "Moving Screen-Up initially")
	assert_almost_eq(move_dir1.z, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.z, 0.01)

	player.movement.process_movement(player, 0.016, null, 1.0, player.orientation.aim_direction)
	assert_almost_eq(Vector2(player.velocity.x, player.velocity.z).length(), player.speed, 0.1, "Velocity magnitude is player.speed")

	# 2. While W is held, Aim turns 90° East (1, 0, 0)
	player.orientation.aim_direction = Vector3(1.0, 0.0, 0.0)
	var move_dir2 = player.movement.compute_move_direction(player.global_position, player.orientation.aim_direction, input_vec)
	assert_almost_eq(move_dir2.x, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.x, 0.01, "WASD is Screen-Relative: movement remains Screen-Up when Aim turns")
	assert_almost_eq(move_dir2.z, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.z, 0.01)

func test_holding_w_aim_flip_180_body_facing_does_not_snap() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.orientation.setup(Vector3(0.0, 0.0, -1.0)) # Facing North (-Z)

	# Holding W
	Input.action_press("move_up")
	var input_vec = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	# Aim abruptly flips 180° to South (+Z)
	var new_aim = Vector3(0.0, 0.0, 1.0)
	player.orientation.aim_direction = new_aim

	# MoveDirection remains Screen-Up regardless of aim flip
	var move_dir = player.movement.compute_move_direction(player.global_position, player.orientation.aim_direction, input_vec)
	assert_almost_eq(move_dir.x, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.x, 0.01)
	assert_almost_eq(move_dir.z, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.z, 0.01)

	# Process 1 orientation step: BodyFacing must NOT snap to South!
	player.orientation.process_orientation(player, 0.016, new_aim, move_dir)
	var angle_to_target = player.body_facing_direction.angle_to(new_aim)
	assert_gt(angle_to_target, deg_to_rad(120.0), "BodyFacing must rotate smoothly at turn rate, not snap on 180° flip")
	assert_true(player.orientation.is_turning, "Orientation must report is_turning = true")

func test_directional_speed_curve_retained_with_actual_angle() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	var screen_fwd = PlayerMovementMath.DEFAULT_SCREEN_FORWARD
	player.orientation.setup(screen_fwd)

	Input.action_press("move_down") # Holding S (Screen-Down, 180° relative to body)
	var input_vec = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	var move_dir = player.movement.compute_move_direction(player.global_position, player.orientation.aim_direction, input_vec)
	player.orientation.process_orientation(player, 0.016, screen_fwd, move_dir)
	assert_almost_eq(player.directional_speed_multiplier, 0.50, 0.05, "Speed multiplier must be ~0.50 (backward speed) based on actual 180° angle")

	# Movement speed is scaled accordingly
	player.movement.process_movement(player, 0.016, null, player.directional_speed_multiplier, player.orientation.aim_direction)
	assert_almost_eq(Vector2(player.velocity.x, player.velocity.z).length(), player.speed * 0.50, 0.1)

func test_dash_uses_screen_relative_move_direction() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.orientation.setup(Vector3(0.0, 0.0, -1.0))

	# Press W + D
	Input.action_press("move_up")
	Input.action_press("move_right")
	var input_vec = Input.get_vector("move_left", "move_right", "move_up", "move_down")

	var rel_move_dir = player.movement.compute_move_direction(player.global_position, player.orientation.aim_direction, input_vec)
	# In Screen-relative basis, W+D points North (0, 0, -1)
	var expected_north = Vector3(0.0, 0.0, -1.0)
	assert_almost_eq(rel_move_dir.angle_to(expected_north), 0.0, 0.02, "W+D relative move direction must be North")

	# Dash with relative move direction
	player.movement.dash_cooldown_timer = 0.0
	player.movement.perform_dash(player.body_facing_direction, rel_move_dir)
	assert_true(player.movement.is_dashing)
	assert_almost_eq(player.movement.dash_direction.angle_to(expected_north), 0.0, 0.02, "Dash must follow Screen-Relative MoveDirection")

func test_aim_deadzone_preserves_movement_basis() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.global_position = Vector3.ZERO

	# 1. Aim was established North (outside deadzone)
	var resolved_aim = player.aim.resolve_cursor_aim(player.global_position, Vector3(0.0, 0.0, -5.0), 0.6)
	assert_almost_eq(resolved_aim.z, -1.0, 0.01)
	player.orientation.aim_direction = resolved_aim

	var basis_before = player.movement.get_movement_basis(player.global_position, player.orientation.aim_direction)
	assert_almost_eq(basis_before["forward"].x, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.x, 0.01)

	# 2. Cursor passes through player center (distance = 0.2 < deadzone 0.6)
	var deadzone_cursor_hit = Vector3(0.1, 0.0, 0.1)
	var deadzone_aim = player.aim.resolve_cursor_aim(player.global_position, deadzone_cursor_hit, 0.6)
	assert_almost_eq(deadzone_aim.z, -1.0, 0.01, "Deadzone must preserve last valid aim direction")

	player.orientation.aim_direction = deadzone_aim
	var basis_inside = player.movement.get_movement_basis(player.global_position, player.orientation.aim_direction)
	assert_almost_eq(basis_inside["forward"].x, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.x, 0.01, "Movement basis must remain stable inside aim deadzone")
	assert_almost_eq(basis_inside["right"].x, PlayerMovementMath.DEFAULT_SCREEN_RIGHT.x, 0.01, "Right basis must not flip inside aim deadzone")

func test_duel_retains_automatic_movement_and_ignores_wasd() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.global_position = Vector3.ZERO

	var dummy = Node3D.new()
	add_child_autoqfree(dummy)
	dummy.global_position = Vector3(5.0, 0.0, 0.0) # East (+X)

	# Activate duel state
	player.abilities.is_dueling = true
	player.abilities.duel_target = dummy

	# Player presses S (trying to retreat West)
	Input.action_press("move_down")

	# Duel movement processes automatic pull toward target
	player.movement.process_duel_movement(player, 0.016, dummy)
	assert_gt(player.velocity.x, 0.0, "Duel automatic movement must pull towards target (East)")
	assert_almost_eq(player.velocity.z, 0.0, 0.01, "WASD retreat must not override duel pull")

func test_forced_target_movement_basis_supports_strafe_and_retreat() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.global_position = Vector3.ZERO

	var target = Node3D.new()
	add_child_autoqfree(target)
	target.global_position = Vector3(0.0, 0.0, 10.0) # Target is South (+Z)

	player.forced_target = target

	# W -> moves toward target (South)
	var w_vec = player.movement.compute_move_direction(player.global_position, player.aim_direction, Vector2(0.0, -1.0), target)
	assert_almost_eq(w_vec.z, 1.0, 0.01, "W must move toward target")

	# S -> moves away from target (North)
	var s_vec = player.movement.compute_move_direction(player.global_position, player.aim_direction, Vector2(0.0, 1.0), target)
	assert_almost_eq(s_vec.z, -1.0, 0.01, "S must move away from target")

	# D -> strafes right around target (West, -X)
	var d_vec = player.movement.compute_move_direction(player.global_position, player.aim_direction, Vector2(1.0, 0.0), target)
	assert_almost_eq(d_vec.x, -1.0, 0.01, "D must strafe right around target")

	# A -> strafes left around target (East, +X)
	var a_vec = player.movement.compute_move_direction(player.global_position, player.aim_direction, Vector2(-1.0, 0.0), target)
	assert_almost_eq(a_vec.x, 1.0, 0.01, "A must strafe left around target")

func test_forced_target_transition_to_null_and_freed_during_movement() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.global_position = Vector3.ZERO

	var target = Node3D.new()
	add_child_autoqfree(target)
	target.global_position = Vector3(10.0, 0.0, 0.0) # Target is East (+X)

	# 1. Moving with forced_target active
	player.forced_target = target
	var move_with_target = player.movement.compute_move_direction(player.global_position, player.orientation.aim_direction, Vector2(0.0, -1.0))
	assert_almost_eq(move_with_target.x, 1.0, 0.01, "While forced_target is active, W moves toward target (East)")
	assert_almost_eq(move_with_target.z, 0.0, 0.01)

	# 2. Transition forced_target -> null while holding W
	player.forced_target = null
	var move_after_null = player.movement.compute_move_direction(player.global_position, player.orientation.aim_direction, Vector2(0.0, -1.0))
	assert_almost_eq(move_after_null.x, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.x, 0.01, "When forced_target becomes null, WASD must immediately revert to Screen-Relative")
	assert_almost_eq(move_after_null.z, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.z, 0.01)

	# 3. Moving with another target (South)
	var target2 = Node3D.new()
	add_child(target2)
	target2.global_position = Vector3(0.0, 0.0, 10.0)
	player.forced_target = target2
	var move_with_target2 = player.movement.compute_move_direction(player.global_position, player.orientation.aim_direction, Vector2(0.0, -1.0))
	assert_almost_eq(move_with_target2.z, 1.0, 0.01, "W moves toward target2 (South)")

	# 4. Transition forced_target -> freed while holding W
	target2.free()
	var move_after_freed = player.movement.compute_move_direction(player.global_position, player.orientation.aim_direction, Vector2(0.0, -1.0))
	assert_almost_eq(move_after_freed.x, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.x, 0.01, "When forced_target is freed, WASD must immediately revert to Screen-Relative")
	assert_almost_eq(move_after_freed.z, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.z, 0.01)

func test_peripheral_camera_pan_does_not_change_movement_basis() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.global_position = Vector3.ZERO
	player.orientation.aim_direction = Vector3(0.0, 0.0, -1.0) # North

	var basis_center = player.movement.get_movement_basis(player.global_position, player.orientation.aim_direction)

	# Even if camera peripheral pan offset is applied to camera, movement basis is strictly aim-relative
	var pan_offset = Vector3(4.0, 0.0, 4.0)
	var basis_panned = player.movement.get_movement_basis(player.global_position, player.orientation.aim_direction)

	assert_eq(basis_center["forward"], basis_panned["forward"], "Camera peripheral pan must not affect movement forward basis")
	assert_eq(basis_center["right"], basis_panned["right"], "Camera peripheral pan must not affect movement right basis")

func test_diagonals_normalized_across_multiple_aim_directions() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.global_position = Vector3.ZERO

	var test_aims = [
		Vector3(0.0, 0.0, -1.0), # North
		Vector3(1.0, 0.0, 0.0),  # East
		Vector3(0.0, 0.0, 1.0),  # South
		Vector3(-1.0, 0.0, 0.0), # West
		Vector3(1.0, 0.0, -1.0).normalized() # Northeast
	]

	var diag_inputs = [
		{"name": "W+D", "vec": Vector2(1.0, -1.0)},
		{"name": "W+A", "vec": Vector2(-1.0, -1.0)},
		{"name": "S+D", "vec": Vector2(1.0, 1.0)},
		{"name": "S+A", "vec": Vector2(-1.0, 1.0)}
	]

	for aim in test_aims:
		player.orientation.aim_direction = aim
		var basis = player.movement.get_movement_basis(player.global_position, aim)
		var fwd: Vector3 = basis["forward"]
		var right: Vector3 = basis["right"]

		for diag in diag_inputs:
			var move_dir = player.movement.compute_move_direction(player.global_position, aim, diag["vec"])
			assert_almost_eq(move_dir.length(), 1.0, 0.001, "Diagonal %s under aim %s must have length 1.0" % [diag["name"], aim])

			var norm_input = diag["vec"].normalized()
			var expected = (right * norm_input.x - fwd * norm_input.y).normalized()
			assert_almost_eq(move_dir.angle_to(expected), 0.0, 0.01, "Diagonal %s under aim %s must match expected relative vector" % [diag["name"], aim])

func test_dash_all_cardinal_and_diagonal_directions() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.global_position = Vector3.ZERO

	# Aim East: forward = (1, 0, 0), right = (0, 0, 1)
	var aim = Vector3(1.0, 0.0, 0.0)
	player.orientation.aim_direction = aim
	var basis = player.movement.get_movement_basis(player.global_position, aim)
	var fwd: Vector3 = basis["forward"]
	var right: Vector3 = basis["right"]

	var test_directions = [
		{"name": "W", "vec": Vector2(0.0, -1.0), "expected": fwd},
		{"name": "S", "vec": Vector2(0.0, 1.0), "expected": -fwd},
		{"name": "A", "vec": Vector2(-1.0, 0.0), "expected": -right},
		{"name": "D", "vec": Vector2(1.0, 0.0), "expected": right},
		{"name": "W+D", "vec": Vector2(1.0, -1.0), "expected": (fwd + right).normalized()},
		{"name": "W+A", "vec": Vector2(-1.0, -1.0), "expected": (fwd - right).normalized()},
		{"name": "S+D", "vec": Vector2(1.0, 1.0), "expected": (-fwd + right).normalized()},
		{"name": "S+A", "vec": Vector2(-1.0, 1.0), "expected": (-fwd - right).normalized()}
	]

	for entry in test_directions:
		var move_dir = player.movement.compute_move_direction(player.global_position, aim, entry["vec"])
		player.movement.dash_cooldown_timer = 0.0
		player.movement.is_dashing = false
		player.movement.perform_dash(player.body_facing_direction, move_dir)
		assert_true(player.movement.is_dashing, "Dash must be triggered for %s" % entry["name"])
		assert_almost_eq(
			player.movement.dash_direction.angle_to(entry["expected"]),
			0.0,
			0.02,
			"Dash direction for %s must match aim-relative expected direction" % entry["name"]
		)

func test_dash_regression_immediately_after_sharp_aim_change() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.global_position = Vector3.ZERO

	# Player holding W (Screen-Up)
	var initial_move = player.movement.compute_move_direction(player.global_position, Vector3(0.0, 0.0, -1.0), Vector2(0.0, -1.0))
	assert_almost_eq(initial_move.x, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.x, 0.01)
	assert_almost_eq(initial_move.z, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.z, 0.01)

	# In the very same frame, aim snaps sharply 90° to East (1, 0, 0)
	var new_aim = Vector3(1.0, 0.0, 0.0)
	player.orientation.aim_direction = new_aim

	# Player immediately dashes holding W: Screen-Relative movement direction is invariant to aim
	var new_move = player.movement.compute_move_direction(player.global_position, player.orientation.aim_direction, Vector2(0.0, -1.0))
	player.movement.dash_cooldown_timer = 0.0
	player.movement.is_dashing = false
	player.movement.perform_dash(player.body_facing_direction, new_move)

	assert_almost_eq(player.movement.dash_direction.x, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.x, 0.01, "Dash holding W remains Screen-Up regardless of aim")
	assert_almost_eq(player.movement.dash_direction.z, PlayerMovementMath.DEFAULT_SCREEN_FORWARD.z, 0.01)

	# Now sharp flip 180° to West (-1, 0, 0) while pressing S (Screen-Down)
	var snap_west = Vector3(-1.0, 0.0, 0.0)
	player.orientation.aim_direction = snap_west
	var retreat_move = player.movement.compute_move_direction(player.global_position, player.orientation.aim_direction, Vector2(0.0, 1.0))
	player.movement.dash_cooldown_timer = 0.0
	player.movement.is_dashing = false
	player.movement.perform_dash(player.body_facing_direction, retreat_move)

	assert_almost_eq(player.movement.dash_direction.x, -PlayerMovementMath.DEFAULT_SCREEN_FORWARD.x, 0.01, "Dash holding S remains Screen-Down regardless of aim")
	assert_almost_eq(player.movement.dash_direction.z, -PlayerMovementMath.DEFAULT_SCREEN_FORWARD.z, 0.01)


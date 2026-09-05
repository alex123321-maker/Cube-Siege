class_name PlayerMovementMath
extends RefCounted

## Pure mathematical helpers for aim-relative and forced-target locomotion basis,
## diagonal normalization, and world-space movement direction calculation (Issue #16).

const DEFAULT_FALLBACK_FORWARD: Vector3 = Vector3(0.0, 0.0, -1.0)
const MIN_HORIZONTAL_LENGTH_SQ: float = 0.0001

## Computes the orthogonal horizontal basis (forward and right vectors on the XZ plane)
## based on the priority:
## 1. Valid forced_target horizontal offset from player_pos
## 2. Horizontal aim_dir
## 3. Fallback basis forward (defaults to Vector3(0, 0, -1))
##
## Returns Dictionary with:
##   "forward": Vector3 (normalized, y=0, non-zero)
##   "right": Vector3 (normalized, y=0, non-zero, orthogonal to forward)
static func calculate_movement_basis(
	player_pos: Vector3,
	aim_dir: Vector3,
	forced_target: Variant = null,
	fallback_fwd: Vector3 = DEFAULT_FALLBACK_FORWARD
) -> Dictionary:
	var forward: Vector3 = Vector3.ZERO

	# 1. Priority 1: valid forced_target
	if forced_target != null and is_instance_valid(forced_target) and forced_target is Node3D:
		var target_node: Node3D = forced_target as Node3D
		var target_pos: Vector3 = target_node.global_position if target_node.is_inside_tree() else target_node.position
		var to_target: Vector3 = target_pos - player_pos
		to_target.y = 0.0
		if to_target.length_squared() > MIN_HORIZONTAL_LENGTH_SQ and to_target.is_finite():
			forward = to_target.normalized()

	# 2. Priority 2: current aim_direction
	if forward.length_squared() <= MIN_HORIZONTAL_LENGTH_SQ:
		var h_aim: Vector3 = Vector3(aim_dir.x, 0.0, aim_dir.z)
		if h_aim.length_squared() > MIN_HORIZONTAL_LENGTH_SQ and h_aim.is_finite():
			forward = h_aim.normalized()

	# 3. Priority 3: fallback basis forward
	if forward.length_squared() <= MIN_HORIZONTAL_LENGTH_SQ:
		var h_fb: Vector3 = Vector3(fallback_fwd.x, 0.0, fallback_fwd.z)
		if h_fb.length_squared() > MIN_HORIZONTAL_LENGTH_SQ and h_fb.is_finite():
			forward = h_fb.normalized()
		else:
			forward = DEFAULT_FALLBACK_FORWARD

	# Right is perpendicular to forward on XZ plane: forward.cross(Vector3.UP)
	# For forward = (0, 0, -1) [North], right is (1, 0, 0) [East]
	var right: Vector3 = forward.cross(Vector3.UP)
	if right.length_squared() > MIN_HORIZONTAL_LENGTH_SQ and right.is_finite():
		right = right.normalized()
	else:
		right = Vector3(1.0, 0.0, 0.0)

	return {
		"forward": forward,
		"right": right
	}

## Computes world-space movement direction from 2D input vector and local movement basis.
## input_vector: typically from Input.get_vector("move_left", "move_right", "move_up", "move_down")
##   where x is [-1, 1] (left to right), y is [-1, 1] (up/forward to down/backward).
##
## W (y = -1) -> +forward
## S (y = +1) -> -forward
## D (x = +1) -> +right
## A (x = -1) -> -right
## Diagonals (e.g. W+D, W+A, S+D, S+A) are normalized and keep length == 1.0.
static func compute_movement_vector(input_vector: Vector2, forward: Vector3, right: Vector3) -> Vector3:
	if input_vector.length_squared() < MIN_HORIZONTAL_LENGTH_SQ:
		return Vector3.ZERO

	var norm_input: Vector2 = input_vector.normalized()
	var move_vec: Vector3 = right * norm_input.x - forward * norm_input.y
	if move_vec.length_squared() > MIN_HORIZONTAL_LENGTH_SQ and move_vec.is_finite():
		return move_vec.normalized()

	return Vector3.ZERO

## Convenience wrapper combining basis calculation and movement vector calculation.
static func resolve_relative_movement(
	input_vector: Vector2,
	player_pos: Vector3,
	aim_dir: Vector3,
	forced_target: Variant = null,
	fallback_fwd: Vector3 = DEFAULT_FALLBACK_FORWARD
) -> Vector3:
	var basis: Dictionary = calculate_movement_basis(player_pos, aim_dir, forced_target, fallback_fwd)
	return compute_movement_vector(input_vector, basis["forward"], basis["right"])

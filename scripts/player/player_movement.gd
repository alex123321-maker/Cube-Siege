extends RefCounted
class_name PlayerMovement

## Handles locomotion, dashing, gravity, and voxel step-up assist for the Player.
## Locomotion direction is computed relative to aim_direction or forced_target (Issue #16).

signal dash_performed()

var speed: float = 7.0
var dash_speed: float = 18.0
var dash_duration: float = 0.15
var dash_cooldown: float = 3.0

var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO

var forced_target: Variant = null
var last_movement_basis_forward: Vector3 = Vector3(0.0, 0.0, -1.0)
var current_move_direction: Vector3 = Vector3.ZERO

func update_timers(delta: float) -> void:
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0.0:
			is_dashing = false

## Resolves the current movement basis (forward and right vectors on XZ plane).
func get_movement_basis(player_pos: Vector3, aim_dir: Vector3, target: Variant = null) -> Dictionary:
	var effective_target: Variant = target if (target != null and is_instance_valid(target)) else forced_target
	var basis: Dictionary = PlayerMovementMath.calculate_movement_basis(
		player_pos,
		aim_dir,
		effective_target,
		last_movement_basis_forward
	)
	last_movement_basis_forward = basis["forward"]
	return basis

## Computes world-space movement direction from 2D input vector relative to aim or forced_target.
func compute_move_direction(player_pos: Vector3, aim_dir: Vector3, input_dir: Vector2, target: Variant = null) -> Vector3:
	var basis: Dictionary = get_movement_basis(player_pos, aim_dir, target)
	return PlayerMovementMath.compute_movement_vector(input_dir, basis["forward"], basis["right"])

func perform_dash(facing_dir: Vector3, explicit_move_dir: Vector3 = Vector3.ZERO) -> bool:
	if dash_cooldown_timer > 0.0 or is_dashing:
		return false

	if explicit_move_dir.length_squared() > 0.01:
		dash_direction = explicit_move_dir.normalized()
	else:
		var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if input_dir.length_squared() > 0.01:
			var basis_fwd: Vector3 = last_movement_basis_forward
			if basis_fwd.length_squared() < 0.01:
				basis_fwd = facing_dir if facing_dir.length_squared() > 0.01 else Vector3(0.0, 0.0, -1.0)
			var basis_right: Vector3 = basis_fwd.cross(Vector3.UP).normalized()
			dash_direction = PlayerMovementMath.compute_movement_vector(input_dir, basis_fwd, basis_right)
		elif facing_dir.length_squared() > 0.01:
			dash_direction = facing_dir.normalized()
		else:
			dash_direction = Vector3(0.0, 0.0, -1.0)

	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	dash_performed.emit()
	return true

## Dedicated automatic motion handler for Warrior ultimate Duel.
func process_duel_movement(body: CharacterBody3D, delta: float, target: Variant) -> Vector3:
	var move_dir: Vector3 = Vector3.ZERO
	if target != null and is_instance_valid(target) and target is Node3D:
		var target_node: Node3D = target as Node3D
		var target_pos: Vector3 = target_node.global_position if target_node.is_inside_tree() else target_node.position
		var to_target: Vector3 = target_pos - body.global_position
		to_target.y = 0.0
		if to_target.length() > 1.2:
			move_dir = to_target.normalized()
			body.velocity.x = move_dir.x * (speed * 1.15)
			body.velocity.z = move_dir.z * (speed * 1.15)
		else:
			body.velocity.x = 0.0
			body.velocity.z = 0.0

	_apply_gravity_and_step_up(body, delta, move_dir)
	current_move_direction = move_dir
	return move_dir

## Main locomotion processing function.
## When target is provided, it acts as forced_target defining the relative WASD basis.
## If is_duel_override is true, executes automatic duel pull instead of WASD locomotion.
func process_movement(
	body: CharacterBody3D,
	delta: float,
	target: Variant = null,
	speed_multiplier: float = 1.0,
	aim_dir: Vector3 = Vector3.ZERO,
	is_duel_override: bool = false
) -> Vector3:
	if is_duel_override:
		return process_duel_movement(body, delta, target)

	var move_dir: Vector3 = Vector3.ZERO

	if is_dashing:
		body.velocity.x = dash_direction.x * dash_speed
		body.velocity.z = dash_direction.z * dash_speed
		move_dir = dash_direction
	else:
		var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		if input_dir.length_squared() > 0.001:
			var effective_target: Variant = target if (target != null and is_instance_valid(target)) else forced_target
			var effective_aim: Vector3 = aim_dir
			if effective_aim.length_squared() < 0.001 and body and "orientation" in body and body.orientation:
				effective_aim = body.orientation.aim_direction
			move_dir = compute_move_direction(body.global_position, effective_aim, input_dir, effective_target)
			var effective_speed: float = speed * speed_multiplier
			body.velocity.x = move_dir.x * effective_speed
			body.velocity.z = move_dir.z * effective_speed
		else:
			body.velocity.x = move_toward(body.velocity.x, 0.0, speed)
			body.velocity.z = move_toward(body.velocity.z, 0.0, speed)

	_apply_gravity_and_step_up(body, delta, move_dir)
	current_move_direction = move_dir
	return move_dir

func _apply_gravity_and_step_up(body: CharacterBody3D, delta: float, move_dir: Vector3) -> void:
	# Gravity
	if not body.is_on_floor():
		body.velocity.y -= 25.0 * delta
	else:
		if body.velocity.y < 0.0:
			body.velocity.y = 0.0

	body.move_and_slide()

	# Voxel Step-Up Assist (only on terrain cubes, NEVER on resources, trees, or buildings)
	if move_dir.length_squared() > 0.01:
		for i in range(body.get_slide_collision_count()):
			var col: KinematicCollision3D = body.get_slide_collision(i)
			var collider: Object = col.get_collider()
			if collider and collider is Node:
				var node: Node = collider as Node
				if node.is_in_group("resource_nodes") or node.is_in_group("buildings") or node.is_in_group("interactables"):
					continue
			if col.get_normal().y < 0.3 and col.get_normal().y > -0.3:
				var step_transform: Transform3D = Transform3D(body.global_transform.basis, body.global_position + Vector3(0, 1.05, 0))
				if not body.test_move(step_transform, move_dir * 0.35):
					body.global_position.y += 1.05
					break

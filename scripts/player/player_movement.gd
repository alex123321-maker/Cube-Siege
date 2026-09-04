extends RefCounted
class_name PlayerMovement

## Handles locomotion, dashing, gravity, and voxel step-up assist for the Player.

signal dash_performed()

var speed: float = 7.0
var dash_speed: float = 18.0
var dash_duration: float = 0.15
var dash_cooldown: float = 3.0

var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0
var dash_direction: Vector3 = Vector3.ZERO

func update_timers(delta: float) -> void:
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta
	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0.0:
			is_dashing = false

func perform_dash(facing_dir: Vector3) -> bool:
	if dash_cooldown_timer > 0.0 or is_dashing:
		return false

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir.length_squared() > 0.01:
		dash_direction = Vector3(input_dir.x, 0.0, input_dir.y).normalized()
	elif facing_dir.length_squared() > 0.01:
		dash_direction = facing_dir.normalized()
	else:
		dash_direction = Vector3.FORWARD

	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	dash_performed.emit()
	return true

func process_movement(body: CharacterBody3D, delta: float, forced_target: Node3D = null) -> Vector3:
	var move_dir: Vector3 = Vector3.ZERO

	if forced_target and is_instance_valid(forced_target):
		var to_target: Vector3 = forced_target.global_position - body.global_position
		to_target.y = 0.0
		if to_target.length() > 1.2:
			move_dir = to_target.normalized()
			body.velocity.x = move_dir.x * (speed * 1.15)
			body.velocity.z = move_dir.z * (speed * 1.15)
		else:
			body.velocity.x = 0.0
			body.velocity.z = 0.0
	elif is_dashing:
		body.velocity.x = dash_direction.x * dash_speed
		body.velocity.z = dash_direction.z * dash_speed
		move_dir = dash_direction
	else:
		var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var direction: Vector3 = Vector3(input_dir.x, 0.0, input_dir.y)

		if direction.length_squared() > 0.001:
			move_dir = direction.normalized()
			body.velocity.x = move_dir.x * speed
			body.velocity.z = move_dir.z * speed
		else:
			body.velocity.x = move_toward(body.velocity.x, 0.0, speed)
			body.velocity.z = move_toward(body.velocity.z, 0.0, speed)

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

	return move_dir

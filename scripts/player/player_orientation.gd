extends RefCounted
class_name PlayerOrientation

## Subsystem managing player spatial orientation, rotation kinematics, directional speed scaling, and action buffering.

const PlayerOrientationSettings = preload("res://scripts/resources/player_orientation_settings.gd")

var settings: PlayerOrientationSettings = null

# Core orientation vectors (horizontal XZ plane, normalized)
var aim_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
var body_facing_direction: Vector3 = Vector3(0.0, 0.0, -1.0)
var move_direction: Vector3 = Vector3.ZERO

# Kinematic rotation state
var angular_velocity: float = 0.0 # signed rad/s around Vector3.UP
var is_turning: bool = false

# Continuous spatial angles (radians, [0, PI])
var body_aim_angle: float = 0.0
var body_move_angle: float = 0.0

# Directional speed multiplier evaluated from Curve
var directional_speed_multiplier: float = 1.0

# Action buffering (stores single pending directional action)
var pending_action: Dictionary = {}

# Debugging
var debug_enabled: bool = false
var debug_node: Node3D = null
var _facing_line: MeshInstance3D = null
var _aim_line: MeshInstance3D = null
var _move_line: MeshInstance3D = null
var _debug_label: Label3D = null

func _init(custom_settings: PlayerOrientationSettings = null) -> void:
	if custom_settings:
		settings = custom_settings
	else:
		settings = PlayerOrientationSettings.new()

func setup(initial_facing: Vector3 = Vector3(0.0, 0.0, -1.0)) -> void:
	var h_facing: Vector3 = Vector3(initial_facing.x, 0.0, initial_facing.z)
	if h_facing.length_squared() > 0.01:
		body_facing_direction = h_facing.normalized()
		aim_direction = body_facing_direction
	else:
		body_facing_direction = Vector3(0.0, 0.0, -1.0)
		aim_direction = Vector3(0.0, 0.0, -1.0)

func step_rotation(delta: float, target_direction: Vector3) -> void:
	if delta <= 0.0:
		return

	var h_target: Vector3 = Vector3(target_direction.x, 0.0, target_direction.z)
	if h_target.length_squared() < 0.0001:
		h_target = aim_direction

	if h_target.length_squared() < 0.0001:
		h_target = Vector3(0.0, 0.0, -1.0)

	var target_norm: Vector3 = h_target.normalized()
	if body_facing_direction.length_squared() < 0.0001:
		body_facing_direction = Vector3(0.0, 0.0, -1.0)
	else:
		body_facing_direction = Vector3(body_facing_direction.x, 0.0, body_facing_direction.z).normalized()

	# Shortest signed angle from body_facing_direction to target_norm around UP (range [-PI, PI])
	var angle_diff: float = body_facing_direction.signed_angle_to(target_norm, Vector3.UP)
	var abs_diff: float = absf(angle_diff)

	# Deadband: if practically zero, snap cleanly to avoid tiny jitter
	if abs_diff < 0.0005:
		body_facing_direction = target_norm
		angular_velocity = 0.0
		is_turning = false
		return

	var turn_sign: float = signf(angle_diff)
	var max_rate: float = settings.max_turn_rate if settings else 14.0
	var accel: float = settings.angular_acceleration if settings else 70.0
	var decel: float = settings.angular_deceleration if settings else 90.0

	var cur_speed: float = absf(angular_velocity)
	var cur_sign: float = signf(angular_velocity)

	# If currently rotating in the opposite direction from target, brake first!
	if cur_speed > 0.001 and cur_sign != 0.0 and cur_sign != turn_sign:
		cur_speed = maxf(0.0, cur_speed - decel * delta)
		if cur_speed <= 0.0:
			angular_velocity = 0.0
		else:
			angular_velocity = cur_sign * cur_speed
	else:
		# Kinematic braking distance check: d_stop = v^2 / (2 * decel)
		# Desired speed profile: decelerate smoothly as target approaches
		var desired_speed: float = max_rate
		var stopping_dist: float = (max_rate * max_rate) / (2.0 * decel)
		if abs_diff <= stopping_dist:
			desired_speed = sqrt(maxf(0.0, 2.0 * decel * abs_diff))

		if cur_speed < desired_speed:
			cur_speed = minf(desired_speed, cur_speed + accel * delta)
		else:
			cur_speed = maxf(desired_speed, cur_speed - decel * delta)

		angular_velocity = turn_sign * cur_speed

	var step_angle: float = absf(angular_velocity) * delta
	if step_angle >= abs_diff:
		# Reached target this tick: snap cleanly to target
		body_facing_direction = target_norm
		angular_velocity = 0.0
		is_turning = false
	else:
		body_facing_direction = body_facing_direction.rotated(Vector3.UP, turn_sign * step_angle).normalized()
		is_turning = true

func process_orientation(body: CharacterBody3D, delta: float, target_aim_dir: Vector3, current_move_dir: Vector3) -> void:
	# 1. Update aim direction
	var h_aim: Vector3 = Vector3(target_aim_dir.x, 0.0, target_aim_dir.z)
	if h_aim.length_squared() > 0.001:
		aim_direction = h_aim.normalized()

	# 2. Update move direction
	var h_move: Vector3 = Vector3(current_move_dir.x, 0.0, current_move_dir.z)
	if h_move.length_squared() > 0.001:
		move_direction = h_move.normalized()
	else:
		move_direction = Vector3.ZERO

	# 3. Determine desired facing target
	var desired_target: Vector3 = aim_direction
	if not pending_action.is_empty():
		var act_target: Vector3 = pending_action.get("target_direction", Vector3.ZERO)
		if act_target.length_squared() > 0.001:
			desired_target = act_target.normalized()

	# 4. Step rotation kinematics
	step_rotation(delta, desired_target)

	# 5. Apply gameplay orientation to CharacterBody3D node
	if body and is_instance_valid(body) and body_facing_direction.length_squared() > 0.001:
		body.look_at(body.global_position + body_facing_direction, Vector3.UP)

	# 6. Calculate spatial angles
	body_aim_angle = body_facing_direction.angle_to(aim_direction)
	if move_direction.length_squared() > 0.001:
		body_move_angle = body_facing_direction.angle_to(move_direction)
		var curve_t: float = clampf(body_move_angle / PI, 0.0, 1.0)
		if settings and settings.directional_speed_curve:
			directional_speed_multiplier = settings.directional_speed_curve.sample(curve_t)
		else:
			directional_speed_multiplier = lerpf(1.0, 0.5, curve_t)
	else:
		body_move_angle = 0.0
		directional_speed_multiplier = 1.0

	# 7. Evaluate pending action buffer
	_evaluate_pending_action()

	# 8. Debug visualization if enabled
	if debug_enabled and body and is_instance_valid(body):
		_update_debug_visuals(body)

func _evaluate_pending_action() -> void:
	if pending_action.is_empty():
		return

	var target: Vector3 = pending_action.get("target_direction", Vector3.ZERO)
	if target.length_squared() < 0.001:
		target = aim_direction

	var angle: float = body_facing_direction.angle_to(target.normalized())
	var tol: float = pending_action.get("tolerance", settings.base_facing_tolerance if settings else 0.2618)
	if tol <= 0.0:
		tol = settings.base_facing_tolerance if settings else 0.2618

	if angle <= tol:
		var act = pending_action
		pending_action = {}
		var cb: Callable = act.get("callable", Callable())
		if cb.is_valid():
			cb.call()

func request_action(
	action_id: String,
	action_callable: Callable,
	requires_facing: bool = true,
	tolerance: float = -1.0,
	custom_target_dir: Vector3 = Vector3.ZERO
) -> bool:
	if not requires_facing:
		if action_callable.is_valid():
			action_callable.call()
		return true

	var tol: float = tolerance if tolerance > 0.0 else (settings.base_facing_tolerance if settings else 0.2618)
	var target: Vector3 = custom_target_dir if custom_target_dir.length_squared() > 0.001 else aim_direction
	target = Vector3(target.x, 0.0, target.z).normalized()

	var angle: float = body_facing_direction.angle_to(target)
	if angle <= tol:
		pending_action = {}
		if action_callable.is_valid():
			action_callable.call()
		return true

	# Target is outside tolerance: buffer action and turn toward it
	pending_action = {
		"action_id": action_id,
		"callable": action_callable,
		"requires_facing": true,
		"tolerance": tol,
		"target_direction": target
	}
	return false

func cancel_pending_action(action_id: String = "") -> void:
	if action_id.is_empty() or pending_action.get("action_id", "") == action_id:
		pending_action = {}

func is_action_pending() -> bool:
	return not pending_action.is_empty()

func get_angle_to_direction(target_dir: Vector3) -> float:
	var h_dir: Vector3 = Vector3(target_dir.x, 0.0, target_dir.z)
	if h_dir.length_squared() < 0.0001:
		return 0.0
	return body_facing_direction.angle_to(h_dir.normalized())

func is_facing(target_dir: Vector3, tolerance: float = -1.0) -> bool:
	var tol: float = tolerance if tolerance > 0.0 else (settings.base_facing_tolerance if settings else 0.2618)
	return get_angle_to_direction(target_dir) <= tol

func get_telemetry() -> Dictionary:
	return {
		"aim_direction": aim_direction,
		"body_facing_direction": body_facing_direction,
		"move_direction": move_direction,
		"body_aim_angle": body_aim_angle,
		"body_move_angle": body_move_angle,
		"angular_velocity": angular_velocity,
		"max_turn_rate": settings.max_turn_rate if settings else 14.0,
		"directional_speed_multiplier": directional_speed_multiplier,
		"is_turning": is_turning,
		"is_action_pending": not pending_action.is_empty()
	}

# Debug visualization implementation
func set_debug_enabled(enabled: bool, body: Node3D = null) -> void:
	debug_enabled = enabled
	if not debug_enabled and debug_node and is_instance_valid(debug_node):
		debug_node.queue_free()
		debug_node = null
		_facing_line = null
		_aim_line = null
		_move_line = null
		_debug_label = null
	elif debug_enabled and body and not debug_node:
		_create_debug_node(body)

func _create_debug_node(body: Node3D) -> void:
	debug_node = Node3D.new()
	debug_node.name = "OrientationDebug"
	body.add_child(debug_node)
	debug_node.top_level = true

	_facing_line = _create_line_mesh(Color(0.2, 0.5, 1.0)) # Blue for body facing
	debug_node.add_child(_facing_line)

	_aim_line = _create_line_mesh(Color(1.0, 0.2, 0.2)) # Red for aim direction
	debug_node.add_child(_aim_line)

	_move_line = _create_line_mesh(Color(0.2, 1.0, 0.3)) # Green for move direction
	debug_node.add_child(_move_line)

	_debug_label = Label3D.new()
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_label.no_depth_test = true
	_debug_label.font_size = 18
	_debug_label.outline_size = 4
	_debug_label.outline_color = Color(0, 0, 0, 1)
	_debug_label.position = Vector3(0, 2.5, 0)
	debug_node.add_child(_debug_label)

func _create_line_mesh(color: Color) -> MeshInstance3D:
	var mi: MeshInstance3D = MeshInstance3D.new()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	mi.material_override = mat
	return mi

func _update_debug_line(mi: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	if not mi:
		return
	var im: ImmediateMesh = ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_add_vertex(from)
	im.surface_add_vertex(to)
	im.surface_end()
	mi.mesh = im

func _update_debug_visuals(body: CharacterBody3D) -> void:
	if not debug_node or not is_instance_valid(debug_node):
		_create_debug_node(body)
		if not debug_node:
			return

	var origin: Vector3 = body.global_position + Vector3(0, 0.2, 0)
	debug_node.global_position = origin

	_update_debug_line(_facing_line, Vector3.ZERO, body_facing_direction * 2.0)
	_update_debug_line(_aim_line, Vector3.ZERO, aim_direction * 2.5)
	if move_direction.length_squared() > 0.01:
		_update_debug_line(_move_line, Vector3.ZERO, move_direction * 1.5)
		_move_line.visible = true
	else:
		_move_line.visible = false

	if _debug_label:
		_debug_label.text = "Body↔Aim: %.1f° | Body↔Move: %.1f°\nSpdMult: %.2f | AngVel: %.1f rad/s\nPending: %s" % [
			rad_to_deg(body_aim_angle),
			rad_to_deg(body_move_angle),
			directional_speed_multiplier,
			angular_velocity,
			pending_action.get("action_id", "none")
		]

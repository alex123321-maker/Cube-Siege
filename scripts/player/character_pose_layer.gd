extends RefCounted
class_name CharacterPoseLayer

## Rigid-node equivalent of an additive skeleton modifier. Bind once; restore the
## authored pose before AnimationPlayer advances, then apply masked corrections.
enum Joint { ROOT, TORSO, HEAD, RIGHT_ARM, LEFT_ARM, RIGHT_LEG, LEFT_LEG }

var profile: CharacterAnimationProfile
var nodes: Array[Node3D] = []
var rest: Array[Transform3D] = []
var authored: Array[Transform3D] = []
var knees: Array[Node3D] = []
var knee_rest: Array[Transform3D] = []
var knee_authored: Array[Transform3D] = []
var foot_plant: CharacterFootPlant
var local_move: Vector2 = Vector2.ZERO
var blend: Vector4 = Vector4(1, 0, 0, 0)
var phase: float = 0.0
var playback_rate: float = 0.0
var aim_yaw: Vector3 = Vector3.ZERO
var aim_weight: float = 1.0
var layer_weight: float = 1.0
var move_weight: float = 0.0
var turn_amount: float = 0.0
var turn_phase: float = 0.0
var movement_lean: Vector2 = Vector2.ZERO
var enabled: bool = true
var action: StringName = &""
var body_aim_angle: float = 0.0
var left_foot_height: float = 0.0
var right_foot_height: float = 0.0
var left_contact: bool = false
var right_contact: bool = false
var _facing_basis: Basis = Basis.IDENTITY
var _movement_lean_world: Vector3 = Vector3.ZERO

func bind(model: Node3D, animation_profile: CharacterAnimationProfile) -> void:
	profile = animation_profile
	var paths: Array[NodePath] = [profile.root_path, profile.torso_path, profile.head_path,
		profile.right_arm_path, profile.left_arm_path, profile.right_leg_path, profile.left_leg_path]
	for path: NodePath in paths:
		var node: Node3D = model.get_node_or_null(path) as Node3D if not path.is_empty() else null
		nodes.append(node)
		var pose: Transform3D = node.transform if node else Transform3D.IDENTITY
		rest.append(pose)
		authored.append(pose)
	for path: NodePath in [profile.right_knee_path, profile.left_knee_path]:
		var knee: Node3D = model.get_node_or_null(path) as Node3D if not path.is_empty() else null
		knees.append(knee)
		var pose: Transform3D = knee.transform if knee else Transform3D.IDENTITY
		knee_rest.append(pose)
		knee_authored.append(pose)
	foot_plant = CharacterFootPlant.new()
	foot_plant.bind(model, self)

func restore_authored() -> void:
	for i: int in nodes.size():
		if is_instance_valid(nodes[i]):
			nodes[i].transform = authored[i]
	for i: int in knees.size():
		if is_instance_valid(knees[i]):
			knees[i].transform = knee_authored[i]

func reset() -> void:
	for i: int in nodes.size():
		if is_instance_valid(nodes[i]):
			nodes[i].transform = rest[i]
	for i: int in knees.size():
		if is_instance_valid(knees[i]):
			knees[i].transform = knee_rest[i]

func update(delta: float, facing: Vector3, aim: Vector3, move: Vector3,
		actual_velocity: Vector3, angular_velocity: float, is_dashing: bool,
		active_action: StringName, blocking: bool) -> void:
	if not profile or delta <= 0:
		return
	for i: int in nodes.size():
		if is_instance_valid(nodes[i]):
			authored[i] = nodes[i].transform
	for i: int in knees.size():
		if is_instance_valid(knees[i]):
			knee_authored[i] = knees[i].transform
	if not enabled and layer_weight < 0.0001 and aim_yaw.length_squared() < 0.000001 and _movement_lean_world.length_squared() < 0.000001:
		layer_weight = 0.0
		aim_yaw = Vector3.ZERO
		movement_lean = Vector2.ZERO
		_movement_lean_world = Vector3.ZERO
		return
	action = active_action
	var response: float = 1.0 - exp(-profile.blend_response * delta)
	layer_weight = lerpf(layer_weight, 1.0 if enabled else 0.0, response)
	var planar: Vector3 = Vector3(actual_velocity.x, 0, actual_velocity.z)
	var speed: float = planar.length()
	# Dash, collision response and forced movement use their actual trajectory.
	var direction: Vector3 = planar.normalized() if speed > 0.01 else move
	local_move = CharacterAnimationMath.local_movement(direction, facing)
	var desired_blend: Vector4 = CharacterAnimationMath.direction_weights(local_move)
	if speed > 0.01:
		blend = blend.lerp(desired_blend, response)
	move_weight = lerpf(move_weight, clampf(speed / profile.full_stride_speed, 0, 1), response)
	var reference_speed: float = profile.gait_reference_speed
	if profile.foot_plant_enabled:
		reference_speed = 2.0 * profile.leg_length * profile.plant_stride_fraction / (CharacterFootPlant.STANCE_FRACTION * profile.cycle_seconds)
	playback_rate = clampf(speed / reference_speed, 0, profile.max_playback_rate)
	phase = fposmod(phase + delta * playback_rate / profile.cycle_seconds, 1.0)
	var turn_target: float = 0.0
	if absf(angular_velocity) > profile.turn_deadzone:
		turn_target = clampf(angular_velocity / profile.turn_rate_reference, -1, 1)
	turn_amount = lerpf(turn_amount, turn_target, response)
	turn_phase = fposmod(turn_phase + delta * profile.turn_step_rate * absf(turn_amount), 1.0)
	var target_weight: float = profile.action_aim_weight if not action.is_empty() else 1.0
	if blocking:
		target_weight = profile.block_aim_weight
	aim_weight = lerpf(aim_weight, target_weight, response)
	var target: Vector3 = CharacterAnimationMath.aim_offsets(facing, aim, profile)
	body_aim_angle = facing.signed_angle_to(aim, Vector3.UP)
	# Scalar interpolation cannot take a 360-degree detour across the antipode.
	aim_yaw.x = lerpf(aim_yaw.x, target.x * aim_weight * layer_weight, 1.0 - exp(-profile.aim_response * delta))
	aim_yaw.y = lerpf(aim_yaw.y, target.y * aim_weight * layer_weight, 1.0 - exp(-profile.head_response * delta))
	aim_yaw.z = lerpf(aim_yaw.z, target.z * aim_weight * layer_weight, response)
	_facing_basis = Basis(Vector3.UP, atan2(-facing.x, -facing.z))
	var lean_weight: float = profile.action_movement_lean_weight if not action.is_empty() else 1.0
	if blocking:
		lean_weight = profile.block_movement_lean_weight
	var lean_target: Vector3 = (planar / profile.movement_lean_reference_speed).limit_length() * profile.movement_lean_limit * lean_weight * layer_weight
	# Smooth in world space so rotating the body never rotates the inertia away
	# from actual travel. No input fallback: pushing into a wall must settle upright.
	_movement_lean_world = _movement_lean_world.lerp(lean_target, 1.0 - exp(-profile.movement_lean_response * delta))
	movement_lean = CharacterAnimationMath.local_movement(_movement_lean_world, facing)
	var idle_turn: float = turn_amount * (1.0 - move_weight) * layer_weight
	_rotate(Joint.ROOT, Vector3(0, -idle_turn * profile.turn_hip_yaw, 0))
	_rotate(Joint.TORSO, Vector3(0, aim_yaw.x, -turn_amount * profile.turn_lean * aim_weight * layer_weight))
	_rotate(Joint.TORSO, Vector3(-movement_lean.y, 0, -movement_lean.x))
	_rotate(Joint.HEAD, Vector3(0, aim_yaw.y, 0))
	_rotate(Joint.RIGHT_ARM, Vector3(0, aim_yaw.z * profile.right_arm_weight, 0))
	_rotate(Joint.LEFT_ARM, Vector3(0, aim_yaw.z * profile.left_arm_weight, 0))
	var stride: float = profile.stride_weight * (profile.dash_stride_weight if is_dashing else 1.0)
	_leg(Joint.RIGHT_LEG, phase, turn_phase, stride, idle_turn)
	_leg(Joint.LEFT_LEG, fposmod(phase + 0.5, 1.0), fposmod(turn_phase + 0.5, 1.0), stride, idle_turn)
	if profile.foot_plant_enabled and not is_dashing:
		foot_plant.update(self, planar, _facing_basis)
	else:
		foot_plant.reset()

func _rotate(joint: int, angles: Vector3) -> void:
	var node: Node3D = nodes[joint]
	if not is_instance_valid(node):
		return
	var mapping: Basis = node.get_parent_node_3d().global_basis.orthonormalized().inverse() * _facing_basis
	node.basis = mapping * Basis.from_euler(angles) * mapping.inverse() * node.basis

func _leg(joint: int, leg_phase: float, step_phase: float, stride: float, idle_turn: float) -> void:
	var node: Node3D = nodes[joint]
	if not is_instance_valid(node) or not profile.forward or not profile.backward or not profile.strafe_left or not profile.strafe_right:
		return
	var angles: Vector3 = (profile.forward.sample_rotation(leg_phase) * blend.x
		+ profile.backward.sample_rotation(leg_phase) * blend.y
		+ profile.strafe_right.sample_rotation(leg_phase) * blend.z
		+ profile.strafe_left.sample_rotation(leg_phase) * blend.w) * stride
	var lift: float = (profile.forward.sample_lift(leg_phase) * blend.x
		+ profile.backward.sample_lift(leg_phase) * blend.y
		+ profile.strafe_right.sample_lift(leg_phase) * blend.z
		+ profile.strafe_left.sample_lift(leg_phase) * blend.w) * stride
	var weight: float = move_weight * layer_weight
	var turn_weight: float = absf(idle_turn)
	var lateral: float = (_facing_basis.inverse() * node.get_parent_node_3d().global_basis * rest[joint].origin).x
	if lateral > 0:
		angles.z = maxf(angles.z, -profile.max_inward_leg_angle)
	else:
		angles.z = minf(angles.z, profile.max_inward_leg_angle)
	var leg_pose: Transform3D = rest[joint]
	# Rigid segments rotate at the hip; no scaling or imaginary knee stretching.
	node.transform = authored[joint].interpolate_with(leg_pose, maxf(weight, turn_weight))
	angles *= weight
	angles.y += sin(step_phase * TAU) * idle_turn * profile.turn_leg_yaw
	_rotate(joint, angles)
	var swing: float = maxf(0, sin(step_phase * TAU))
	# Lower the hip by the geometric shortening, then add deliberate swing clearance.
	node.position.y += lift * weight - profile.leg_length * (1.0 - cos(angles.x) * cos(angles.z))
	node.position.y += swing * turn_weight * profile.turn_lift
	# The lower segment follows the SAME blended gait phase as its hip. Letting
	# the authored forward-walk knee run independently makes it bend on a planted
	# backward/strafe foot, and previously changed the apparent leg length.
	var knee_index: int = 0 if joint == Joint.RIGHT_LEG else 1
	var knee: Node3D = knees[knee_index]
	if is_instance_valid(knee):
		var knee_weight: float = maxf(weight, turn_weight)
		knee.transform = knee_authored[knee_index].interpolate_with(knee_rest[knee_index], knee_weight)
		var bend: float = -profile.knee_swing_angle * clampf(lift / profile.knee_lift_reference, 0.0, 1.0) * weight
		bend -= profile.knee_swing_angle * swing * turn_weight
		var mapping: Basis = knee.get_parent_node_3d().global_basis.orthonormalized().inverse() * _facing_basis
		knee.basis = mapping * Basis(Vector3.RIGHT, bend) * mapping.inverse() * knee.basis
		# Additional vertical shortening introduced by a bent lower segment.
		node.position.y -= profile.leg_length * 0.5 * (cos(angles.x) - cos(angles.x + bend)) * cos(angles.z)

func debug_text() -> String:
	return "ANIMATION | local %.2f, %.2f / %.0f deg\nF %.2f B %.2f R %.2f L %.2f | phase %.2f x%.2f\nAim %.0f | torso %.0f head %.0f | weight %.2f / %.2f\nTurn %.2f | action %s | lean side %.1f forward %.1f deg\nFeet R %.2f (%s) L %.2f (%s)" % [
		local_move.x, local_move.y, rad_to_deg(atan2(local_move.x, local_move.y)),
		blend.x, blend.y, blend.z, blend.w, phase, playback_rate,
		rad_to_deg(body_aim_angle), rad_to_deg(aim_yaw.x), rad_to_deg(aim_yaw.y), aim_weight, layer_weight,
		turn_amount, action, rad_to_deg(movement_lean.x), rad_to_deg(movement_lean.y), right_foot_height, right_contact, left_foot_height, left_contact]

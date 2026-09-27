extends RefCounted
class_name CharacterFootPlant

## Two rigid segments, fixed world-space stance contacts. All transforms are
## presentation-owned; the CharacterBody velocity/orientation is never written.
const STANCE_FRACTION: float = 0.4
var model: Node3D
var root: Node3D
var legs: Array[Node3D] = []
var knees: Array[Node3D] = []
var leg_rest: Array[Transform3D] = []
var knee_rest: Array[Transform3D] = []
var anchors: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
var swing_starts: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO])
var contacts: Array[bool] = [false, false]
var initialized: bool = false
var previous_model_position: Vector3 = Vector3.ZERO
var feet: Array[Foot] = []

class Foot extends RefCounted:
	var parts: Array[MeshInstance3D] = []
	var rest: Array[Transform3D] = []
	var model_basis: Basis = Basis.IDENTITY
	var ankle: Vector3
	var contact_offset: Vector3
	var last_leg: Transform3D
	var last_knee: Transform3D
	var pose_valid: bool = false

	func bind(active_model: Node3D, knee: Node3D, paths: Array[NodePath], lower: float) -> void:
		ankle = Vector3.DOWN * lower
		if not is_instance_valid(knee):
			return
		model_basis = active_model.global_basis.inverse() * knee.global_basis
		var minimum: Vector3 = Vector3(INF, INF, INF)
		var maximum: Vector3 = Vector3(-INF, -INF, -INF)
		for path: NodePath in paths:
			var part: MeshInstance3D = knee.get_node_or_null(path) as MeshInstance3D
			if not part or not part.mesh:
				continue
			parts.append(part)
			rest.append(part.transform)
			for surface: int in part.mesh.get_surface_count():
				for vertex: Vector3 in part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					var point: Vector3 = part.transform * vertex
					minimum = minimum.min(point)
					maximum = maximum.max(point)
		if not parts.is_empty():
			contact_offset = Vector3((minimum.x + maximum.x) * .5, minimum.y, (minimum.z + maximum.z) * .5) - ankle

	func restore() -> void:
		for index: int in parts.size():
			if is_instance_valid(parts[index]):
				parts[index].transform = rest[index]

	func orient(knee: Node3D, flat_basis: Basis, weight: float) -> void:
		# A virtual ankle rotates the existing rigid boot pieces together. Geometry
		# and leg lengths stay unchanged; no helper nodes or gameplay state are added.
		var flat: Transform3D = Transform3D(flat_basis, knee.to_global(ankle))
		var local_flat: Transform3D = knee.global_transform.affine_inverse() * flat
		for index: int in parts.size():
			if not is_instance_valid(parts[index]):
				continue
			var relative: Transform3D = rest[index]
			relative.origin -= ankle
			parts[index].transform = rest[index].interpolate_with(local_flat * relative, weight)

func bind(active_model: Node3D, pose: CharacterPoseLayer) -> void:
	model = active_model
	root = pose.nodes[CharacterPoseLayer.Joint.ROOT]
	legs.assign([pose.nodes[CharacterPoseLayer.Joint.RIGHT_LEG], pose.nodes[CharacterPoseLayer.Joint.LEFT_LEG]])
	knees.assign(pose.knees)
	leg_rest.assign([pose.rest[CharacterPoseLayer.Joint.RIGHT_LEG], pose.rest[CharacterPoseLayer.Joint.LEFT_LEG]])
	knee_rest.assign(pose.knee_rest)
	for i: int in 2:
		var foot := Foot.new()
		foot.bind(model, knees[i], pose.profile.right_foot_parts if i == 0 else pose.profile.left_foot_parts,
			maxf(.05, pose.profile.leg_length - knee_rest[i].origin.length()))
		feet.append(foot)

func restore_feet() -> void:
	for foot: Foot in feet:
		foot.restore()

func reset() -> void:
	initialized = false
	contacts[0] = false
	contacts[1] = false
	for foot: Foot in feet:
		foot.pose_valid = false

func update(pose: CharacterPoseLayer, velocity: Vector3, facing: Basis, influence: float = 1.0,
		release_contacts: bool = false, delta: float = 1.0 / 60) -> void:
	var weight: float = pose.move_weight * pose.layer_weight * influence
	if weight < .001 or not is_instance_valid(root) or not is_instance_valid(model):
		reset()
		return
	for i: int in 2:
		if not is_instance_valid(legs[i]) or not is_instance_valid(knees[i]) or feet[i].parts.is_empty():
			return
	var profile: CharacterAnimationProfile = pose.profile
	# During the fade into dash, release world anchoring without discarding the
	# pose. Carry the targets with the body so a rapid dash cannot pull the knees
	# straight before their visual contribution has faded out.
	if initialized and release_contacts:
		var travel: Vector3 = model.global_position - previous_model_position
		for i: int in 2:
			anchors[i] += travel
			swing_starts[i] += travel
	previous_model_position = model.global_position
	var direction: Vector3 = Vector3(velocity.x, 0, velocity.z).normalized()
	if direction.is_zero_approx():
		direction = -facing.z
	var half_step: float = profile.leg_length * profile.plant_stride_fraction
	var floor_y: float = model.global_position.y
	# Crouch creates reach for the planted forward/back foot without stretching.
	root.position.y -= profile.plant_crouch * weight
	for i: int in 2:
		var leg: Node3D = legs[i]
		var knee: Node3D = knees[i]
		var phase: float = fposmod(pose.phase + float(i) * .5, 1.0)
		var contact: bool = phase < STANCE_FRACTION
		var hip_rest: Vector3 = leg.get_parent_node_3d().to_global(leg_rest[i].origin)
		var forward_target: Vector3 = hip_rest + direction * half_step
		forward_target.y = floor_y
		if not initialized or anchors[i].distance_to(hip_rest) > profile.leg_length * 3.0:
			anchors[i] = forward_target if contact else hip_rest
			anchors[i].y = floor_y
			swing_starts[i] = anchors[i]
			contacts[i] = contact
		if contact and not contacts[i]:
			anchors[i] = forward_target
		elif not contact and contacts[i]:
			swing_starts[i] = anchors[i]
		contacts[i] = contact
		var target: Vector3 = anchors[i]
		if not contact:
			var swing: float = (phase - STANCE_FRACTION) / (1.0 - STANCE_FRACTION)
			var ease: float = swing * swing * (3.0 - 2.0 * swing)
			target = swing_starts[i].lerp(forward_target, ease)
			target.y += sin(swing * PI) * profile.plant_swing_height
			anchors[i] = target
		# A terrain step follows the body's actual new floor height, without a ray
		# claiming that an untested surface contact exists.
		target.y = maxf(target.y, floor_y - profile.foot_placement_max_height)
		var flat_basis: Basis = model.global_basis.orthonormalized() * feet[i].model_basis
		# The target is the REAL sole centre, not an imaginary end of the shin.
		var ankle_target: Vector3 = target - flat_basis * feet[i].contact_offset
		var transition_strength: float = 1.0 if release_contacts else 1.0 - influence
		var follow: float = lerpf(1.0, 1.0 - exp(-profile.plant_transition_response * 2.0 * delta), transition_strength)
		_solve(i, ankle_target, hip_rest, -facing.z, profile, weight, follow)
		feet[i].orient(knee, flat_basis, weight)
		if i == 0:
			pose.right_contact = contact
			pose.right_foot_height = target.y
		else:
			pose.left_contact = contact
			pose.left_foot_height = target.y
	initialized = true

func _solve(i: int, target: Vector3, hip: Vector3, pole: Vector3,
		profile: CharacterAnimationProfile, weight: float, follow: float) -> void:
	var leg: Node3D = legs[i]
	var knee: Node3D = knees[i]
	var upper: float = knee_rest[i].origin.length()
	var lower: float = maxf(.05, profile.leg_length - upper)
	var offset: Vector3 = target - hip
	var distance: float = clampf(offset.length(), absf(upper - lower) + .001, upper + lower - .001)
	var direction: Vector3 = offset.normalized()
	var along: float = (upper * upper - lower * lower + distance * distance) / (2.0 * distance)
	var height: float = sqrt(maxf(0, upper * upper - along * along))
	var bend: Vector3 = (pole - direction * pole.dot(direction)).normalized()
	if bend.is_zero_approx():
		bend = Vector3.RIGHT
	var middle: Vector3 = hip + direction * along + bend * height
	var parent_basis: Basis = leg.get_parent_node_3d().global_basis.orthonormalized()
	var upper_basis: Basis = parent_basis * leg_rest[i].basis
	var rest_axis: Vector3 = (upper_basis * knee_rest[i].origin).normalized()
	var desired_upper: Basis = Basis(Quaternion(rest_axis, (middle - hip).normalized())) * upper_basis
	var local_upper: Basis = parent_basis.inverse() * desired_upper
	leg.transform = leg.transform.interpolate_with(Transform3D(local_upper, leg_rest[i].origin), weight)
	var lower_basis: Basis = desired_upper * knee_rest[i].basis
	var desired_lower: Basis = Basis(Quaternion((lower_basis * Vector3.DOWN).normalized(),
		(hip + direction * distance - middle).normalized())) * lower_basis
	var local_lower: Basis = leg.global_basis.orthonormalized().inverse() * desired_lower
	knee.transform = knee.transform.interpolate_with(Transform3D(local_lower, knee_rest[i].origin), weight)
	# Root height near maximum reach can amplify a small weight change into a
	# large knee-angle change. Inertialize the rigid joint poses during release;
	# return continuously to the exact contact solve as influence reaches one.
	if feet[i].pose_valid:
		leg.transform = feet[i].last_leg.interpolate_with(leg.transform, follow)
		knee.transform = feet[i].last_knee.interpolate_with(knee.transform, follow)
	feet[i].last_leg = leg.transform
	feet[i].last_knee = knee.transform
	feet[i].pose_valid = true

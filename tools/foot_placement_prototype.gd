extends RefCounted
## Evaluation only. Production does not load or instantiate this prototype:
## lifting a one-segment leg at the hip also disconnects it from the pelvis.

var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()

func update(layer: CharacterPoseLayer, delta: float) -> void:
	var profile: CharacterAnimationProfile = layer.profile
	if not profile.foot_placement_enabled:
		return
	query.collision_mask = profile.foot_collision_mask
	for joint: int in [CharacterPoseLayer.Joint.RIGHT_LEG, CharacterPoseLayer.Joint.LEFT_LEG]:
		var node: Node3D = layer.nodes[joint]
		if not is_instance_valid(node) or not node.is_inside_tree():
			continue
		var sole: Vector3 = node.global_position - Vector3.UP * profile.leg_length
		query.from = sole + Vector3.UP * profile.foot_ray_height
		query.to = sole - Vector3.UP * profile.foot_ray_height
		var hit: Dictionary = node.get_world_3d().direct_space_state.intersect_ray(query)
		var height: float = 0.0
		if not hit.is_empty():
			height = clampf(hit.position.y - sole.y, -profile.foot_placement_max_height, profile.foot_placement_max_height)
		var previous: float = layer.right_foot_height if joint == CharacterPoseLayer.Joint.RIGHT_LEG else layer.left_foot_height
		height = lerpf(previous, height, 1.0 - exp(-profile.blend_response * delta))
		if joint == CharacterPoseLayer.Joint.RIGHT_LEG:
			layer.right_foot_height = height
			layer.right_contact = not hit.is_empty()
		else:
			layer.left_foot_height = height
			layer.left_contact = not hit.is_empty()
		node.global_position += Vector3.UP * height * profile.foot_placement_weight * layer.layer_weight

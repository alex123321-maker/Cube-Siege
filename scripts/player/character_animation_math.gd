extends RefCounted
class_name CharacterAnimationMath

static func local_movement(move: Vector3, facing: Vector3) -> Vector2:
	var forward: Vector3 = Vector3(facing.x, 0, facing.z).normalized()
	return Vector2(move.dot(forward.cross(Vector3.UP)), move.dot(forward))

## Continuous convex weights: forward, backward, right, left. No quadrant snaps.
static func direction_weights(local: Vector2) -> Vector4:
	var total: float = absf(local.x) + absf(local.y)
	if total < 0.0001:
		return Vector4(1, 0, 0, 0)
	return Vector4(maxf(local.y, 0), maxf(-local.y, 0), maxf(local.x, 0), maxf(-local.x, 0)) / total

static func aim_offsets(facing: Vector3, aim: Vector3, profile: CharacterAnimationProfile) -> Vector3:
	var angle: float = facing.signed_angle_to(aim, Vector3.UP)
	var torso: float = clampf(angle * profile.torso_share, -profile.torso_limit, profile.torso_limit)
	var head: float = clampf((angle - torso) * profile.head_share, -profile.head_limit, profile.head_limit)
	var arms: float = clampf((angle - torso) * profile.arm_share, -profile.arm_limit, profile.arm_limit)
	return Vector3(torso, head, arms)

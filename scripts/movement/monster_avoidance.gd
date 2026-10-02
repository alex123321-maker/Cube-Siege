extends RefCounted
class_name MonsterAvoidance

## Authoritative local crowd avoidance and steering for monsters.
## Prevents mutual penetration before physical contact, provides stable
## time-consistent passing (right-hand rule for head-on encounters),
## handles stationary queues without pushing, and respects vertical tiers.

## Computes crowd-avoided horizontal velocity given desired path velocity and nearby neighbors.
static func compute_avoidance_velocity(
	self_node: CharacterBody3D,
	desired_velocity_h: Vector3,
	max_speed: float,
	self_radius: float,
	neighbors: Array[Node3D]
) -> Vector3:
	if neighbors.is_empty():
		return desired_velocity_h

	var self_pos: Vector3 = self_node.global_position
	var self_pos_2d: Vector2 = Vector2(self_pos.x, self_pos.z)
	var desired_speed: float = desired_velocity_h.length()
	var desired_dir_2d: Vector2 = Vector2.ZERO
	if desired_speed > 0.001:
		desired_dir_2d = Vector2(desired_velocity_h.x, desired_velocity_h.z).normalized()

	var avoidance_force: Vector2 = Vector2.ZERO
	var front_blocked: bool = false
	var nearest_front_dist: float = INF

	for other in neighbors:
		if not is_instance_valid(other) or other == self_node:
			continue

		var other_pos: Vector3 = other.global_position
		# Enforce vertical separation: monsters on different height tiers do not push each other
		if absf(other_pos.y - self_pos.y) > 1.8:
			continue

		var other_radius: float = float(other.get("radius")) if other.get("radius") != null else 0.4
		var combined_radius: float = self_radius + other_radius
		var avoid_zone: float = combined_radius + 0.65

		var diff_2d: Vector2 = self_pos_2d - Vector2(other_pos.x, other_pos.z)
		var dist: float = diff_2d.length()

		if dist < 0.001:
			# Degenerate exact overlap: push apart based on instance IDs deterministically
			var sign_val: float = 1.0 if self_node.get_instance_id() > other.get_instance_id() else -1.0
			diff_2d = Vector2(sign_val, 0.0)
			dist = 0.01

		if dist < avoid_zone:
			var away_dir: Vector2 = diff_2d / dist
			var penetration_weight: float = clampf((avoid_zone - dist) / avoid_zone, 0.0, 1.0)
			# Strong exponential repulsion as distance approaches combined radius
			var rep_strength: float = penetration_weight * penetration_weight * 2.5
			avoidance_force += away_dir * rep_strength

			# Time-consistent passing convention for approaching encounters (Right-hand rule):
			var other_vel_2d: Vector2 = Vector2.ZERO
			if other is CharacterBody3D:
				var other_body = other as CharacterBody3D
				other_vel_2d = Vector2(other_body.velocity.x, other_body.velocity.z)

			if desired_speed > 0.1 and other_vel_2d.length_squared() > 0.01:
				var other_dir: Vector2 = other_vel_2d.normalized()
				# If approaching roughly head-on
				if desired_dir_2d.dot(other_dir) < -0.35:
					# Steer to the right of our desired direction
					var right_tangent: Vector2 = Vector2(desired_dir_2d.y, -desired_dir_2d.x)
					avoidance_force += right_tangent * 1.5

			# Stationary neighbor detection in front sector:
			var to_other_dir: Vector2 = -away_dir
			var is_other_stationary: bool = other_vel_2d.length_squared() < 0.04
			if desired_speed > 0.1 and desired_dir_2d.dot(to_other_dir) > 0.6:
				if dist < combined_radius + 0.35:
					front_blocked = true
					nearest_front_dist = minf(nearest_front_dist, dist)
					if is_other_stationary:
						# Steer around stationary obstacle
						var tangent: Vector2 = Vector2(-to_other_dir.y, to_other_dir.x)
						avoidance_force += tangent * 1.2

	# Combine desired velocity with avoidance force
	var final_dir_2d: Vector2 = desired_dir_2d + avoidance_force
	var final_speed: float = desired_speed

	# If directly blocked by a stationary neighbor or queue ahead with nowhere to go, decelerate
	if front_blocked and final_dir_2d.dot(desired_dir_2d) < 0.1:
		final_speed = 0.0

	if final_dir_2d.length_squared() > 0.001:
		final_dir_2d = final_dir_2d.normalized()
		var target_vel: Vector2 = final_dir_2d * minf(final_speed, max_speed)
		return Vector3(target_vel.x, 0.0, target_vel.y)
	else:
		return Vector3.ZERO

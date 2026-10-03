extends RefCounted
class_name MonsterLocomotion

## Authoritative physical locomotion and voxel step-up / step-down for monsters.
## Handles CharacterBody3D move_and_slide, step climbing (<= 1.0 block height),
## ground follow (step down <= 1.0 block), cliff rejection (>= 2.0 blocks),
## and visual offset smoothing without accumulating height or horizontal speed.

const MAX_STEP_HEIGHT: float = 1.05
const MIN_STEP_HEIGHT: float = 0.05
const MAX_CLIFF_DROP: float = 1.95
const GRAVITY: float = 25.0
const SMOOTH_SPEED: float = 9.0

## Returns global Vector2(bottom_y, top_y) for the body's actual collision shape.
static func get_body_vertical_bounds(body: CharacterBody3D, fallback_half_height: float = 0.9) -> Vector2:
	if not body or not is_instance_valid(body):
		return Vector2.ZERO
	var col_node: CollisionShape3D = body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_node and col_node.shape:
		var center_y: float = col_node.global_position.y
		var hh: float = fallback_half_height
		if col_node.shape is BoxShape3D:
			hh = (col_node.shape as BoxShape3D).size.y * 0.5
		elif col_node.shape is CapsuleShape3D:
			hh = (col_node.shape as CapsuleShape3D).height * 0.5
		elif col_node.shape is CylinderShape3D:
			hh = (col_node.shape as CylinderShape3D).height * 0.5
		return Vector2(center_y - hh, center_y + hh)
	return Vector2(body.global_position.y - fallback_half_height, body.global_position.y + fallback_half_height)

## Returns the local Y offset from body root to the feet (bottom of collision shape).
static func get_root_to_feet_offset(body: CharacterBody3D, fallback_half_height: float = 0.9) -> float:
	if not body or not is_instance_valid(body):
		return -fallback_half_height
	var col_node: CollisionShape3D = body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_node and col_node.shape:
		var hh: float = fallback_half_height
		if col_node.shape is BoxShape3D:
			hh = (col_node.shape as BoxShape3D).size.y * 0.5
		elif col_node.shape is CapsuleShape3D:
			hh = (col_node.shape as CapsuleShape3D).height * 0.5
		elif col_node.shape is CylinderShape3D:
			hh = (col_node.shape as CylinderShape3D).height * 0.5
		return col_node.position.y - hh
	return -fallback_half_height

## Returns horizontal collision radius of body.
static func get_body_radius(body: CharacterBody3D, fallback_radius: float = 0.4) -> float:
	if not body or not is_instance_valid(body):
		return fallback_radius
	var col_node: CollisionShape3D = body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col_node and col_node.shape is BoxShape3D:
		var box: BoxShape3D = col_node.shape as BoxShape3D
		return maxf(box.size.x, box.size.z) * 0.5
	elif col_node and col_node.shape is CapsuleShape3D:
		return (col_node.shape as CapsuleShape3D).radius
	elif col_node and col_node.shape is CylinderShape3D:
		return (col_node.shape as CylinderShape3D).radius
	return fallback_radius

## Main locomotion processing function for CharacterBody3D monsters.
## Preserves external 3D knockback (including vertical impulses from spikes/skills),
## enforces cliff rejection strictly on voluntary walking, executes authoritative
## step-up assist on terrain when obstructed on the floor, and updates visual smoothing.
static func process_locomotion(
	body: CharacterBody3D,
	delta: float,
	desired_velocity_h: Vector3,
	knockback: Vector3,
	half_height: float,
	radius: float,
	current_smooth_offset_y: float
) -> Dictionary:
	# Returns {"smooth_offset_y": float, "knockback": Vector3}
	if not body or not is_instance_valid(body) or not body.is_inside_tree():
		return {"smooth_offset_y": current_smooth_offset_y, "knockback": knockback}

	# Configure body floor and snapping parameters
	body.floor_snap_length = 1.1
	body.floor_constant_speed = true
	body.floor_max_angle = deg_to_rad(46.0)

	var current_kb: Vector3 = knockback

	# 1. Gravity and vertical impulse handling
	if not body.is_on_floor():
		body.velocity.y -= GRAVITY * delta
	else:
		if body.velocity.y < 0.0:
			body.velocity.y = 0.0

	# Apply upward vertical knockback (e.g. from floor spikes or knockup attacks)
	if current_kb.y > 0.01:
		body.velocity.y += current_kb.y
		current_kb.y = 0.0

	# 2. Voluntary walking vs External Knockback
	# Cliff rejection applies ONLY to voluntary walking (monsters don't voluntarily step off cliffs)
	# External knockback pushes freely over edges as per design.
	var voluntary_h: Vector3 = Vector3(desired_velocity_h.x, 0.0, desired_velocity_h.z)
	var voluntary_speed: float = voluntary_h.length()
	var new_smooth_offset_y: float = current_smooth_offset_y

	if voluntary_speed > 0.01 and body.is_on_floor():
		var intended_dir: Vector3 = voluntary_h / voluntary_speed
		var probe_dist: float = maxf(radius + 0.1, voluntary_speed * delta * 2.0)
		if is_cliff_ahead(body, intended_dir, probe_dist):
			voluntary_h = Vector3.ZERO
			voluntary_speed = 0.0

	# Combine voluntary walk with horizontal knockback
	body.velocity.x = voluntary_h.x + current_kb.x
	body.velocity.z = voluntary_h.z + current_kb.z

	# Decay horizontal knockback
	if current_kb.length_squared() > 0.001:
		current_kb = current_kb.lerp(Vector3.ZERO, 10.0 * delta)

	# 3. Physical movement
	var pos_before: Vector3 = body.global_position
	body.move_and_slide()
	var pos_after: Vector3 = body.global_position

	var moved_h: float = Vector2(pos_after.x - pos_before.x, pos_after.z - pos_before.z).length()
	var total_budget_h: float = voluntary_speed * delta
	var remaining_budget_h: float = maxf(0.0, total_budget_h - moved_h)

	# 4. Voxel Step-Up Assist
	# Only triggers when on floor and moving voluntarily into an obstacle (forbidden while airborne / knocked back)
	if voluntary_speed > 0.01 and body.is_on_floor() and current_kb.length_squared() < 0.1 and remaining_budget_h > 0.0001:
		var intended_dir: Vector3 = voluntary_h / voluntary_speed
		var collision_count: int = body.get_slide_collision_count()
		for i in range(collision_count):
			var col: KinematicCollision3D = body.get_slide_collision(i)
			if not col:
				continue

			var collider: Object = col.get_collider()
			if collider and collider is Node:
				var node: Node = collider as Node
				# Step-up is strictly forbidden on buildings, walls, traps, resources, enemies, or player
				if node.is_in_group("buildings") or node.is_in_group("walls") or \
				   node.is_in_group("traps") or node.is_in_group("resource_nodes") or \
				   node.is_in_group("enemies") or node.is_in_group("player") or \
				   node.is_in_group("boss"):
					continue

			var normal: Vector3 = col.get_normal()
			# Check if collision face is near-vertical and opposing our movement
			if absf(normal.y) < 0.35 and normal.dot(intended_dir) < -0.2:
				var step_result: Dictionary = try_step_up(body, intended_dir, remaining_budget_h, half_height, radius)
				if step_result.get("success", false):
					new_smooth_offset_y -= float(step_result.get("step_delta", 0.0))
					break

	# 5. Visual smoothing interpolation
	if absf(new_smooth_offset_y) > 0.001:
		new_smooth_offset_y = move_toward(new_smooth_offset_y, 0.0, SMOOTH_SPEED * delta)
	else:
		new_smooth_offset_y = 0.0

	return {"smooth_offset_y": new_smooth_offset_y, "knockback": current_kb}

## Attempts to climb an authoritative <= 1.0 block voxel step.
## Performs full physical volume sweep:
## 1. Upward head clearance test_move.
## 2. Solid ground support probe on top surface (<= 1.05m).
## 3. Forward passage sweep at elevated height (strictly clamped to frame budget).
## 4. Final landing volume test_move.
## Returns Dictionary {"success": bool, "step_delta": float}.
static func try_step_up(
	body: CharacterBody3D,
	move_dir: Vector3,
	frame_budget_dist: float,
	fallback_half_height: float = 0.9,
	radius: float = 0.4
) -> Dictionary:
	var space_state: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	if not space_state or not body.is_on_floor():
		return {"success": false, "step_delta": 0.0}

	# 1. Sweep test upward for vertical head clearance from current position
	if body.test_move(body.global_transform, Vector3(0.0, MAX_STEP_HEIGHT, 0.0)):
		# Low ceiling or blocked overhead
		return {"success": false, "step_delta": 0.0}

	var bounds: Vector2 = get_body_vertical_bounds(body, fallback_half_height)
	var current_feet_y: float = bounds.x
	var actual_radius: float = get_body_radius(body, radius)

	# 2. Check ground support on top of the step: probe forward across obstacle face
	var probe_offset: Vector3 = move_dir.normalized() * (actual_radius + 0.15)
	var ray_down_start: Vector3 = Vector3(
		body.global_position.x + probe_offset.x,
		current_feet_y + MAX_STEP_HEIGHT + 0.2,
		body.global_position.z + probe_offset.z
	)
	var ray_down_end: Vector3 = Vector3(
		ray_down_start.x,
		current_feet_y - 0.2,
		ray_down_start.z
	)

	var ray_params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_down_start,
		ray_down_end,
		1 # Layer 1: World terrain
	)
	ray_params.exclude = [body.get_rid()]
	var hit: Dictionary = space_state.intersect_ray(ray_params)

	if hit.is_empty():
		return {"success": false, "step_delta": 0.0}

	var floor_pos: Vector3 = hit.position
	var floor_normal: Vector3 = hit.normal

	# Surface must be walkable slope
	if floor_normal.y < 0.65:
		return {"success": false, "step_delta": 0.0}

	# Verify collider is world terrain, not dynamic object
	var collider: Object = hit.get("collider", null)
	if collider and collider is Node:
		var node: Node = collider as Node
		if node.is_in_group("buildings") or node.is_in_group("walls") or \
		   node.is_in_group("traps") or node.is_in_group("resource_nodes") or \
		   node.is_in_group("enemies") or node.is_in_group("player") or \
		   node.is_in_group("boss"):
			return {"success": false, "step_delta": 0.0}

	var step_delta: float = floor_pos.y - current_feet_y
	if step_delta < MIN_STEP_HEIGHT or step_delta > MAX_STEP_HEIGHT:
		return {"success": false, "step_delta": 0.0}

	# 3. Test forward sweep at the elevated height
	# Advance horizontally by at most the frame's remaining movement budget (prevent horizontal speed boost)
	if frame_budget_dist <= 0.0001:
		return {"success": false, "step_delta": 0.0}

	var advance_dist: float = frame_budget_dist
	var forward_motion: Vector3 = move_dir.normalized() * advance_dist

	# Provide a slight vertical clearance (+0.03m) so horizontal test_move does not scrape against floor surface
	var elevated_xform: Transform3D = Transform3D(
		body.global_transform.basis,
		body.global_position + Vector3(0.0, step_delta + 0.03, 0.0)
	)
	if body.test_move(elevated_xform, forward_motion):
		# Forward passage at step height is blocked (e.g. wall is >= 2 blocks high)
		return {"success": false, "step_delta": 0.0}

	# 4. Test final landing volume (with recovery_as_collision = true)
	var target_xform: Transform3D = Transform3D(
		body.global_transform.basis,
		elevated_xform.origin + forward_motion
	)
	if body.test_move(target_xform, Vector3.ZERO, null, 0.001, true):
		# Final landing space occupied
		return {"success": false, "step_delta": 0.0}

	# 5. Execute step: elevate and advance by allowed frame motion
	body.global_position = target_xform.origin

	return {"success": true, "step_delta": step_delta}


## Checks if there is an impassable cliff (>= 2 blocks drop) in the direction of movement.
static func is_cliff_ahead(
	body: CharacterBody3D,
	move_dir: Vector3,
	check_dist: float,
	fallback_half_height: float = 0.9
) -> bool:
	var space_state: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	if not space_state:
		return false

	var current_feet_y: float = get_body_vertical_bounds(body, fallback_half_height).x
	var probe_xz: Vector3 = body.global_position + move_dir * check_dist
	var ray_start: Vector3 = Vector3(probe_xz.x, current_feet_y + 0.3, probe_xz.z)
	var ray_end: Vector3 = Vector3(probe_xz.x, current_feet_y - MAX_CLIFF_DROP - 0.2, probe_xz.z)

	var ray_params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_start,
		ray_end,
		1 # Layer 1: World
	)
	ray_params.exclude = [body.get_rid()]
	var hit: Dictionary = space_state.intersect_ray(ray_params)

	if hit.is_empty():
		# Ray cast reached bottom without finding ground: drop is >= MAX_CLIFF_DROP (cliff / abyss)
		return true

	var drop_amount: float = current_feet_y - hit.position.y
	return drop_amount >= MAX_CLIFF_DROP

## Calculates the required spawn position Y coordinate for a given archetype
## to align its bottom exactly with the terrain surface height.
static func calculate_spawn_y(terrain_surface_y: float, archetype: Variant) -> float:
	if archetype is float or archetype is int:
		return terrain_surface_y + float(archetype)
	if archetype is CharacterBody3D:
		var root_to_feet: float = get_root_to_feet_offset(archetype as CharacterBody3D)
		return terrain_surface_y - root_to_feet
	return terrain_surface_y + 0.9

## Validates whether a candidate spawn position has a clear physical volume
## and solid ground support directly beneath the archetype body.
static func validate_safe_spawn_point(
	space_state: PhysicsDirectSpaceState3D,
	body: CharacterBody3D,
	candidate_pos: Vector3,
	fallback_half_height: float = 0.9
) -> bool:
	if not space_state or not body:
		return false

	var root_to_feet: float = get_root_to_feet_offset(body, fallback_half_height)
	var feet_y: float = candidate_pos.y + root_to_feet

	# 1. Ground support check directly underneath candidate feet
	var ray_start: Vector3 = Vector3(candidate_pos.x, feet_y + 0.3, candidate_pos.z)
	var ray_end: Vector3 = Vector3(candidate_pos.x, feet_y - 0.5, candidate_pos.z)
	var ray_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, ray_end, 1)
	ray_query.exclude = [body.get_rid()]
	var hit: Dictionary = space_state.intersect_ray(ray_query)
	if hit.is_empty():
		return false
	var floor_normal: Vector3 = hit.normal
	if floor_normal.y < 0.65:
		return false

	# 2. Physical volume clearance check: query space state using actual collision shape
	var col_node: CollisionShape3D = body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var shape: Shape3D = null
	var local_shape_pos: Vector3 = Vector3(0.0, fallback_half_height, 0.0)
	if col_node and col_node.shape:
		shape = col_node.shape
		local_shape_pos = col_node.position
	else:
		var capsule: CapsuleShape3D = CapsuleShape3D.new()
		capsule.radius = get_body_radius(body, 0.4)
		capsule.height = fallback_half_height * 2.0
		shape = capsule

	var shape_query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	shape_query.shape = shape
	# Provide 0.04m lift so shape does not intersect the supporting floor block directly beneath feet
	shape_query.transform = Transform3D(Basis.IDENTITY, candidate_pos + local_shape_pos + Vector3(0.0, 0.04, 0.0))
	shape_query.collision_mask = 0xFFFFFFFF # All layers: terrain, buildings, resources, enemies, player
	shape_query.collide_with_bodies = true
	shape_query.collide_with_areas = false
	if body.is_inside_tree():
		shape_query.exclude = [body.get_rid()]

	var intersections: Array[Dictionary] = space_state.intersect_shape(shape_query, 1)
	if not intersections.is_empty():
		return false

	return true


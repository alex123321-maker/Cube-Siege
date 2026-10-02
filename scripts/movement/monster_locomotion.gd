extends RefCounted
class_name MonsterLocomotion

## Authoritative physical locomotion and voxel step-up / step-down for monsters.
## Handles CharacterBody3D move_and_slide, step climbing (<= 1.0 block height),
## ground follow (step down <= 1.0 block), cliff rejection (>= 2.0 blocks),
## and visual offset smoothing without accumulating height.

const MAX_STEP_HEIGHT: float = 1.05
const MIN_STEP_HEIGHT: float = 0.05
const MAX_CLIFF_DROP: float = 1.95
const GRAVITY: float = 25.0
const SMOOTH_SPEED: float = 9.0

## Main locomotion processing function for CharacterBody3D monsters.
## Applies gravity, sets intended horizontal velocity, performs move_and_slide(),
## checks and executes voxel step-up assist on terrain when obstructed,
## and updates visual smoothing offset.
static func process_locomotion(
	body: CharacterBody3D,
	delta: float,
	desired_velocity_h: Vector3,
	half_height: float,
	radius: float,
	current_smooth_offset_y: float
) -> float:
	if not body or not is_instance_valid(body) or not body.is_inside_tree():
		return current_smooth_offset_y

	# Configure body floor and snapping parameters
	body.floor_snap_length = 1.1
	body.floor_constant_speed = true
	body.floor_max_angle = deg_to_rad(46.0)

	# 1. Gravity handling
	if not body.is_on_floor():
		body.velocity.y -= GRAVITY * delta
	else:
		if body.velocity.y < 0.0:
			body.velocity.y = 0.0

	# 2. Check cliff in front: walking cannot voluntarily step over >= 2 block drop
	var intended_h: Vector3 = Vector3(desired_velocity_h.x, 0.0, desired_velocity_h.z)
	var intended_speed: float = intended_h.length()
	var new_smooth_offset_y: float = current_smooth_offset_y

	if intended_speed > 0.01 and body.is_on_floor():
		var intended_dir: Vector3 = intended_h / intended_speed
		var probe_dist: float = maxf(radius + 0.1, intended_speed * delta * 2.0)
		if is_cliff_ahead(body, intended_dir, probe_dist, half_height):
			# Stop forward motion towards cliff
			intended_h = Vector3.ZERO
			desired_velocity_h = Vector3.ZERO

	body.velocity.x = intended_h.x
	body.velocity.z = intended_h.z

	var start_pos: Vector3 = body.global_position

	# 3. Physical movement
	body.move_and_slide()

	# 4. Voxel Step-Up Assist
	# If we intended to move horizontally and collided with an obstacle, check if it's a climbable step.
	if intended_speed > 0.01:
		var intended_dir: Vector3 = intended_h / intended_speed
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
				var forward_dist: float = maxf(0.25, intended_speed * delta)
				var step_result: Dictionary = try_step_up(body, intended_dir, forward_dist, half_height, radius)
				if step_result.get("success", false):
					new_smooth_offset_y -= float(step_result.get("step_delta", 0.0))
					break

	# 5. Visual smoothing interpolation
	if absf(new_smooth_offset_y) > 0.001:
		new_smooth_offset_y = move_toward(new_smooth_offset_y, 0.0, SMOOTH_SPEED * delta)
	else:
		new_smooth_offset_y = 0.0

	return new_smooth_offset_y

## Attempts to climb an authoritative <= 1.0 block voxel step.
## Performs full physical volume check (head clearance, horizontal passage, solid ground support).
## Returns Dictionary {"success": bool, "step_delta": float}.
static func try_step_up(
	body: CharacterBody3D,
	move_dir: Vector3,
	forward_dist: float,
	half_height: float,
	radius: float = 0.4
) -> Dictionary:
	var space_state: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	if not space_state:
		return {"success": false, "step_delta": 0.0}

	# 1. Check vertical clearance directly above current body:
	# Test if body shape fits at +MAX_STEP_HEIGHT
	var elevated_transform: Transform3D = Transform3D(
		body.global_transform.basis,
		body.global_position + Vector3(0.0, MAX_STEP_HEIGHT, 0.0)
	)
	if body.test_move(elevated_transform, Vector3.ZERO):
		# Head clearance blocked (ceiling or >1m wall directly in face)
		return {"success": false, "step_delta": 0.0}

	# 2. Check horizontal clearance forward at the elevated height:
	var forward_motion: Vector3 = move_dir * maxf(forward_dist, 0.2)
	if body.test_move(elevated_transform, forward_motion):
		# Forward passage blocked at elevated height (e.g. wall is >= 2 blocks high)
		return {"success": false, "step_delta": 0.0}

	# 3. Check ground support at target position on top of the step:
	# Probe across the step face into the top surface (radius + 0.15m)
	var probe_offset: Vector3 = move_dir * (radius + 0.15)
	var ray_down_start: Vector3 = elevated_transform.origin + probe_offset
	var ray_down_end: Vector3 = ray_down_start - Vector3(0.0, MAX_STEP_HEIGHT + 0.4, 0.0)

	var ray_params: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		ray_down_start,
		ray_down_end,
		1 # Layer 1: World terrain
	)
	ray_params.exclude = [body.get_rid()]
	var hit: Dictionary = space_state.intersect_ray(ray_params)

	if hit.is_empty():
		# No solid floor found below step top
		return {"success": false, "step_delta": 0.0}

	var floor_pos: Vector3 = hit.position
	var floor_normal: Vector3 = hit.normal

	# Surface must be sufficiently horizontal to stand on (walkable slope)
	if floor_normal.y < 0.65:
		return {"success": false, "step_delta": 0.0}

	# Verify collider is world terrain, not dynamic object
	var collider: Object = hit.get("collider", null)
	if collider and collider is Node:
		var node: Node = collider as Node
		if node.is_in_group("buildings") or node.is_in_group("walls") or \
		   node.is_in_group("traps") or node.is_in_group("resource_nodes") or \
		   node.is_in_group("enemies") or node.is_in_group("player"):
			return {"success": false, "step_delta": 0.0}

	# Calculate actual step height
	var current_feet_y: float = body.global_position.y - half_height
	var step_delta: float = floor_pos.y - current_feet_y

	# Enforce exact <= 1 block rule with small numerical tolerance
	if step_delta < MIN_STEP_HEIGHT or step_delta > MAX_STEP_HEIGHT:
		return {"success": false, "step_delta": 0.0}

	# 4. Successful climb: place body feet firmly on the new surface and advance
	body.global_position.y = floor_pos.y + half_height
	body.global_position.x += forward_motion.x
	body.global_position.z += forward_motion.z

	return {"success": true, "step_delta": step_delta}

## Checks if there is an impassable cliff (>= 2 blocks drop) in the direction of movement.
static func is_cliff_ahead(
	body: CharacterBody3D,
	move_dir: Vector3,
	check_dist: float,
	half_height: float
) -> bool:
	var space_state: PhysicsDirectSpaceState3D = body.get_world_3d().direct_space_state
	if not space_state:
		return false

	var current_feet_y: float = body.global_position.y - half_height
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
		# Ray cast reached bottom without finding ground: drop is > MAX_CLIFF_DROP (cliff / abyss)
		return true

	var drop_amount: float = current_feet_y - hit.position.y
	return drop_amount >= MAX_CLIFF_DROP

## Calculates the required spawn position Y coordinate for a given archetype shape
## to align its bottom exactly with the terrain surface height.
static func calculate_spawn_y(terrain_surface_y: float, half_height: float) -> float:
	return terrain_surface_y + half_height

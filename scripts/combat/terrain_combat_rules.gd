extends RefCounted
class_name TerrainCombatRules

## TerrainCombatRules: Authoritative checks for vertical combat interaction,
## height connectivity between attacker and target, and ability terrain modes.

enum TerrainMode {
	TERRAIN_DEPENDENT = 0,
	TERRAIN_INDEPENDENT = 1
}

## Evaluates whether a melee attack from source_pos can reach target_pos given discrete terrain steps.
## A direct melee hit requires |target_y - source_y| <= 1.0.
## For extended ranges, all intermediate voxel height transitions along the 2D ray must have |delta_y| <= 1.0.
static func is_melee_connected(
	source_pos: Vector3,
	target_pos: Vector3,
	height_lookup: Callable = Callable()
) -> bool:
	var delta_y: float = target_pos.y - source_pos.y
	var rounded_delta_y: int = int(roundf(delta_y))

	# Immediate 1-step direct range
	var horizontal_dist: float = Vector2(target_pos.x - source_pos.x, target_pos.z - source_pos.z).length()
	if horizontal_dist <= 1.5:
		return absi(rounded_delta_y) <= 1

	# Extended range: if height_lookup is provided, trace intermediate discrete steps
	if height_lookup.is_valid():
		var steps: int = maxi(1, int(ceilf(horizontal_dist)))
		var prev_y: int = int(roundf(source_pos.y))

		for i in range(1, steps + 1):
			var t: float = float(i) / float(steps)
			var sample_x: int = int(roundf(lerpf(source_pos.x, target_pos.x, t)))
			var sample_z: int = int(roundf(lerpf(source_pos.z, target_pos.z, t)))
			var cur_y: int = int(height_lookup.call(sample_x, sample_z))

			if absi(cur_y - prev_y) >= 2:
				return false # Blocked by >= 2 block cliff / step
			prev_y = cur_y

		return true

	# Fallback if no map lookup: simple delta check between endpoints
	return absi(rounded_delta_y) <= 1

## Checks whether an attack or ability can hit the target under the specified terrain mode.
static func can_ability_hit_target(
	source_pos: Vector3,
	target_pos: Vector3,
	mode: TerrainMode,
	max_range: float = 100.0,
	height_lookup: Callable = Callable()
) -> bool:
	if mode == TerrainMode.TERRAIN_INDEPENDENT:
		# Aerial strikes / independent attacks check only horizontal XZ area
		var dist_h: float = Vector2(target_pos.x - source_pos.x, target_pos.z - source_pos.z).length()
		return dist_h <= max_range

	# Terrain dependent
	var dist_h: float = Vector2(target_pos.x - source_pos.x, target_pos.z - source_pos.z).length()
	if dist_h > max_range:
		return false

	return is_melee_connected(source_pos, target_pos, height_lookup)

## Evaluates projectile movement step over terrain.
## Returns Dictionary:
## {
##   "collided": bool (true if wall >= 2 blocks in front),
##   "new_y": float (adjusted height),
##   "is_diving": bool (false: continues straight if drop >= 2)
## }
static func update_projectile_height(
	current_pos: Vector3,
	next_pos: Vector3,
	current_terrain_y: float,
	next_terrain_y: float,
	projectile_base_offset: float = 0.8
) -> Dictionary:
	var step_diff: float = next_terrain_y - current_terrain_y
	var int_step: int = int(roundf(step_diff))

	# 1. Rising wall >= 2 blocks: collision!
	if int_step >= 2:
		return {
			"collided": true,
			"new_y": current_pos.y,
			"is_diving": false
		}

	# 2. Rising step of +1 block: smoothly climb
	if int_step == 1:
		var target_y: float = next_terrain_y + projectile_base_offset
		return {
			"collided": false,
			"new_y": maxf(current_pos.y, target_y),
			"is_diving": false
		}

	# 3. Descending step of -1 block: smoothly follow down
	if int_step == -1:
		var target_y: float = next_terrain_y + projectile_base_offset
		return {
			"collided": false,
			"new_y": minf(current_pos.y, target_y),
			"is_diving": false
		}

	# 4. Sudden drop/cliff <= -2 blocks: do NOT dive down to ground, continue on current trajectory
	if int_step <= -2:
		return {
			"collided": false,
			"new_y": current_pos.y, # maintain current height without snapping downward
			"is_diving": false
		}

	# Same level (0 step): maintain height
	return {
		"collided": false,
		"new_y": next_terrain_y + projectile_base_offset,
		"is_diving": false
	}

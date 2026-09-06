extends RefCounted
class_name TerrainCombatRules

## TerrainCombatRules: Authoritative checks for vertical combat interaction,
## height connectivity between attacker and target, and ability terrain modes.

enum TerrainMode {
	TERRAIN_DEPENDENT = 0,
	TERRAIN_INDEPENDENT = 1
}

## Authoritative mapping from world coordinate to integer voxel cell index.
## ChunkBuilder builds voxel cell (wx, wz) on [wx, wx + 1) and [wz, wz + 1).
## Therefore, the authoritative mapping is strictly floorf.
static func world_to_voxel(coord: float) -> int:
	return int(floorf(coord))

static func world_pos_to_voxel(pos: Vector3) -> Vector2i:
	return Vector2i(int(floorf(pos.x)), int(floorf(pos.z)))

## Evaluates whether a melee attack from source_pos can reach target_pos given discrete terrain steps.
## A direct melee hit requires |target_y - source_y| <= 1.0.
## For extended ranges, all intermediate voxel height transitions along the 2D ray must have |delta_y| <= 1.0.
static func is_melee_connected(
	source_pos: Vector3,
	target_pos: Vector3,
	height_lookup: Callable = Callable()
) -> bool:
	var horizontal_dist: float = Vector2(target_pos.x - source_pos.x, target_pos.z - source_pos.z).length()

	# If authoritative height lookup is available, evaluate using terrain surface heights
	if height_lookup.is_valid():
		var src_x: int = int(floorf(source_pos.x))
		var src_z: int = int(floorf(source_pos.z))
		var tgt_x: int = int(floorf(target_pos.x))
		var tgt_z: int = int(floorf(target_pos.z))

		var src_y: int = int(height_lookup.call(src_x, src_z))
		var tgt_y: int = int(height_lookup.call(tgt_x, tgt_z))

		# Immediate 1-step direct range
		if horizontal_dist <= 1.5:
			return absi(tgt_y - src_y) <= 1

		# Extended range: trace intermediate discrete steps along line at sub-voxel resolution
		var steps: int = maxi(1, int(ceilf(horizontal_dist * 2.0)))
		var prev_y: int = src_y

		for i in range(1, steps + 1):
			var t: float = float(i) / float(steps)
			var sample_x: int = int(floorf(lerpf(source_pos.x, target_pos.x, t)))
			var sample_z: int = int(floorf(lerpf(source_pos.z, target_pos.z, t)))
			var cur_y: int = int(height_lookup.call(sample_x, sample_z))

			if absi(cur_y - prev_y) >= 2:
				return false # Blocked by >= 2 block cliff / step
			prev_y = cur_y

		return true

	# Fallback if no map lookup provided (isolated unit tests)
	var delta_y: float = target_pos.y - source_pos.y
	var rounded_delta_y: int = int(roundf(delta_y))
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
##   "collided": bool (true if projectile collides with wall/ground face),
##   "new_y": float (adjusted height),
##   "is_diving": bool (false: continues straight if drop >= 2),
##   "is_over_drop": bool (true if flying above a drop/canyon)
## }
static func update_projectile_height(
	current_pos: Vector3,
	next_pos: Vector3,
	current_terrain_y: float,
	next_terrain_y: float,
	projectile_base_offset: float = 0.8,
	is_over_drop: bool = false
) -> Dictionary:
	var step_diff: float = next_terrain_y - current_terrain_y
	var int_step: int = int(roundf(step_diff))
	var clearance: float = current_pos.y - next_terrain_y

	# Detect if entering or currently inside over-drop state
	var currently_over_drop: bool = is_over_drop or int_step <= -2 or (clearance >= projectile_base_offset + 1.2)

	# 1. Rising wall >= 2 blocks when ground-following (near ground):
	if int_step >= 2 and not currently_over_drop:
		return {
			"collided": true,
			"new_y": current_pos.y,
			"is_diving": false,
			"is_over_drop": false
		}

	# 2. Collision with terrain face when over drop or penetrating below ground:
	if currently_over_drop and (current_pos.y <= next_terrain_y or next_pos.y <= next_terrain_y):
		return {
			"collided": true,
			"new_y": current_pos.y,
			"is_diving": false,
			"is_over_drop": false
		}

	# 2. Over drop: maintain straight horizontal altitude across multiple frames
	if currently_over_drop:
		if clearance > projectile_base_offset:
			return {
				"collided": false,
				"new_y": current_pos.y,
				"is_diving": false,
				"is_over_drop": true
			}
		else:
			# Ground has risen back to meet arrow trajectory: transition back to ground-following
			currently_over_drop = false

	# 3. Ground-following: check for wall in front (+2 or more blocks)
	# When near ground (not over drop), rising wall of >= 2 blocks stops projectile
	if int_step >= 2 and clearance < projectile_base_offset + 0.4:
		return {
			"collided": true,
			"new_y": current_pos.y,
			"is_diving": false,
			"is_over_drop": false
		}

	# 4. Climbing gentle step (+1 block): smoothly adjust upward without harsh jump
	if int_step == 1:
		var target_y: float = next_terrain_y + projectile_base_offset
		var smooth_y: float = current_pos.y + clampf(target_y - current_pos.y, 0.0, 0.5)
		return {
			"collided": false,
			"new_y": maxf(smooth_y, target_y * 0.5 + current_pos.y * 0.5),
			"is_diving": false,
			"is_over_drop": false
		}

	# 5. Descending gentle step (-1 block): smoothly adjust downward
	if int_step == -1:
		var target_y: float = next_terrain_y + projectile_base_offset
		var smooth_y: float = current_pos.y + clampf(target_y - current_pos.y, -0.5, 0.0)
		return {
			"collided": false,
			"new_y": minf(smooth_y, target_y * 0.5 + current_pos.y * 0.5),
			"is_diving": false,
			"is_over_drop": false
		}

	# 6. Flat terrain (0 step): maintain natural projectile flight altitude without snapping
	var target_flat_y: float = next_terrain_y + projectile_base_offset
	var adjusted_y: float = current_pos.y
	if absf(current_pos.y - target_flat_y) > 0.3:
		# Gently drift toward base offset over several frames instead of instant teleport
		adjusted_y = move_toward(current_pos.y, target_flat_y, 0.1)

	return {
		"collided": false,
		"new_y": adjusted_y,
		"is_diving": false,
		"is_over_drop": false
	}



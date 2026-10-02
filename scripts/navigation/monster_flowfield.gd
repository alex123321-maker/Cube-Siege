extends RefCounted
class_name MonsterFlowfield

## Authoritative 2D Flowfield and pathfinding for monsters on the discrete voxel grid.
## Computes shared integration field from target (Player / Building), respects the <= 1 block
## height transition rule, forbids diagonal corner-cutting through walls/cliffs, accounts for
## dynamic walls and static obstacles, and provides O(1) directional queries with clearance support.

const DEFAULT_RADIUS: int = 24
const CELL_SIZE: float = 1.0

var target_position: Vector3 = Vector3.INF
var target_cell: Vector2i = Vector2i(2147483647, 2147483647)
var world_seed: int = 0
var height_lookup: Callable = Callable()

# Flowfield grid: Vector2i -> Vector2 (normalized horizontal direction towards target)
var flow_directions: Dictionary = {}
var distance_field: Dictionary = {} # Vector2i -> float

# Blocked building cells: Vector2i -> bool
var blocked_cells: Dictionary = {}

var last_update_time_sec: float = -999.0
const RECALC_INTERVAL_SEC: float = 0.25
const TARGET_MOVE_THRESHOLD_SQ: float = 2.25 # 1.5m squared

func _init(seed_val: int = 0, custom_height_lookup: Callable = Callable()) -> void:
	world_seed = seed_val
	height_lookup = custom_height_lookup

## Sets or updates custom height lookup (e.g. from MapGenerator or BiomeSystem).
func set_height_lookup(lookup: Callable) -> void:
	height_lookup = lookup

## Marks a cell as blocked by a building or wall.
func set_cell_blocked(cell: Vector2i, is_blocked: bool) -> void:
	if is_blocked:
		blocked_cells[cell] = true
	else:
		blocked_cells.erase(cell)
	invalidate()

## Invalidates current flowfield, forcing recompute on next query.
func invalidate() -> void:
	target_cell = Vector2i(2147483647, 2147483647)
	flow_directions.clear()
	distance_field.clear()

## Resolves the voxel height at cell (x, z).
func get_cell_height(x: int, z: int) -> int:
	if height_lookup.is_valid():
		return int(height_lookup.call(x, z))
	return BiomeSystem.get_voxel_height(x, z, world_seed)

## Checks whether movement from (from_cell) to (to_cell) is traversable.
## Enforces:
## 1. to_cell is not blocked by wall/solid obstacle.
## 2. Discrete height difference |h_to - h_from| <= 1.
## 3. For diagonal steps, both orthogonal adjacent cells must be passable and within height bounds (no corner cutting).
func is_step_passable(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if blocked_cells.has(to_cell):
		return false

	var h_from: int = get_cell_height(from_cell.x, from_cell.y)
	var h_to: int = get_cell_height(to_cell.x, to_cell.y)

	if absi(h_to - h_from) > 1:
		return false # Blocked by >= 2 block cliff or step

	var dx: int = to_cell.x - from_cell.x
	var dz: int = to_cell.y - from_cell.y

	# Diagonal movement check: prevent cutting through diagonal wall corners or steps
	if dx != 0 and dz != 0:
		var side1 = Vector2i(from_cell.x + dx, from_cell.y)
		var side2 = Vector2i(from_cell.x, from_cell.y + dz)

		if blocked_cells.has(side1) or blocked_cells.has(side2):
			return false # Cannot cut through corner touching a wall

		var h_s1: int = get_cell_height(side1.x, side1.y)
		var h_s2: int = get_cell_height(side2.x, side2.y)

		if absi(h_s1 - h_from) > 1 or absi(h_s2 - h_from) > 1:
			return false # Cannot cut through corner touching a cliff

	return true

## Computes or updates the flowfield towards target_pos if needed.
func update_field_if_needed(target_pos: Vector3, max_radius: int = DEFAULT_RADIUS) -> void:
	var new_target_cell: Vector2i = Vector2i(int(floorf(target_pos.x)), int(floorf(target_pos.z)))
	var now: float = float(Time.get_ticks_msec()) / 1000.0

	var cell_changed: bool = new_target_cell != target_cell
	var dist_sq: float = target_position.distance_squared_to(target_pos) if target_position.x != INF else INF
	var time_elapsed: bool = (now - last_update_time_sec) >= RECALC_INTERVAL_SEC

	if not cell_changed and dist_sq < TARGET_MOVE_THRESHOLD_SQ and not time_elapsed:
		return

	target_position = target_pos
	target_cell = new_target_cell
	last_update_time_sec = now
	_compute_flowfield(new_target_cell, max_radius)

func _get_cached_height(x: int, z: int, cache: Dictionary) -> int:
	var key: Vector2i = Vector2i(x, z)
	if cache.has(key):
		return cache[key]
	var h: int = get_cell_height(x, z)
	cache[key] = h
	return h

func _is_step_passable_cached(from_cell: Vector2i, to_cell: Vector2i, cache: Dictionary) -> bool:
	if blocked_cells.has(to_cell):
		return false

	var h_from: int = _get_cached_height(from_cell.x, from_cell.y, cache)
	var h_to: int = _get_cached_height(to_cell.x, to_cell.y, cache)

	if absi(h_to - h_from) > 1:
		return false

	var dx: int = to_cell.x - from_cell.x
	var dz: int = to_cell.y - from_cell.y

	if dx != 0 and dz != 0:
		var side1 = Vector2i(from_cell.x + dx, from_cell.y)
		var side2 = Vector2i(from_cell.x, from_cell.y + dz)

		if blocked_cells.has(side1) or blocked_cells.has(side2):
			return false

		var h_s1: int = _get_cached_height(side1.x, side1.y, cache)
		var h_s2: int = _get_cached_height(side2.x, side2.y, cache)

		if absi(h_s1 - h_from) > 1 or absi(h_s2 - h_from) > 1:
			return false

	return true

func _compute_flowfield(goal_cell: Vector2i, radius: int) -> void:
	flow_directions.clear()
	distance_field.clear()

	var min_x: int = goal_cell.x - radius
	var max_x: int = goal_cell.x + radius
	var min_z: int = goal_cell.y - radius
	var max_z: int = goal_cell.y + radius

	var height_cache: Dictionary = {}

	# Wavefront integration field using queue BFS (visited set guaranteed by distance_field)
	distance_field[goal_cell] = 0.0
	var queue: Array[Vector2i] = [goal_cell]
	var head: int = 0

	var neighbors_8: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]

	while head < queue.size():
		var curr: Vector2i = queue[head]
		head += 1
		var curr_dist: float = distance_field[curr]

		for d in neighbors_8:
			var n: Vector2i = curr + d
			if n.x < min_x or n.x > max_x or n.y < min_z or n.y > max_z:
				continue

			if distance_field.has(n):
				continue

			# Note: we are propagating from goal outward, so step is from n to curr
			if not _is_step_passable_cached(n, curr, height_cache):
				continue

			var step_cost: float = 1.414 if (d.x != 0 and d.y != 0) else 1.0
			distance_field[n] = curr_dist + step_cost
			queue.append(n)

	# Derive flow vectors pointing from each cell towards lowest distance neighbor
	for cell: Vector2i in distance_field.keys():
		if cell == goal_cell:
			flow_directions[cell] = Vector2.ZERO
			continue

		var min_neighbor_dist: float = distance_field[cell]
		var best_dir: Vector2 = Vector2.ZERO

		for d in neighbors_8:
			var n: Vector2i = cell + d
			if distance_field.has(n):
				var n_dist: float = distance_field[n]
				if _is_step_passable_cached(cell, n, height_cache) and n_dist < min_neighbor_dist:
					min_neighbor_dist = n_dist
					best_dir = Vector2(d.x, d.y).normalized()

		if best_dir.length_squared() > 0.001:
			flow_directions[cell] = best_dir

## Queries the flowfield for the desired horizontal move direction from from_pos towards target_pos.
## Returns normalized Vector3 on the XZ plane.
func get_flow_direction(
	from_pos: Vector3,
	target_pos: Vector3,
	clearance_radius: float = 0.4
) -> Vector3:
	update_field_if_needed(target_pos)

	var from_cell: Vector2i = Vector2i(int(floorf(from_pos.x)), int(floorf(from_pos.z)))

	# 1. Line-of-sight shortcut: if direct horizontal path is short and connected, use direct vector
	var diff: Vector3 = target_pos - from_pos
	diff.y = 0.0
	var dist: float = diff.length()

	if dist > 0.1 and dist < 8.0:
		if TerrainCombatRules.is_melee_connected(from_pos, target_pos, height_lookup):
			var direct_clear: bool = true
			# Verify no blocked buildings in cells directly along line
			var steps: int = maxi(1, int(ceilf(dist)))
			for i in range(1, steps + 1):
				var t: float = float(i) / float(steps)
				var pt = from_pos.lerp(target_pos, t)
				var c = Vector2i(int(floorf(pt.x)), int(floorf(pt.z)))
				if blocked_cells.has(c):
					direct_clear = false
					break
			if direct_clear:
				return diff.normalized()

	# 2. Flowfield lookup:
	if flow_directions.has(from_cell):
		var dir_2d: Vector2 = flow_directions[from_cell]
		if dir_2d.length_squared() > 0.001:
			# For larger entities (e.g. Siege Breaker / Boss), verify lateral clearance
			if clearance_radius > 0.5:
				var perp = Vector2(-dir_2d.y, dir_2d.x)
				var side_cell_1 = Vector2i(int(floorf(from_pos.x + perp.x * 0.7)), int(floorf(from_pos.z + perp.y * 0.7)))
				var side_cell_2 = Vector2i(int(floorf(from_pos.x - perp.x * 0.7)), int(floorf(from_pos.z - perp.y * 0.7)))
				if blocked_cells.has(side_cell_1) or blocked_cells.has(side_cell_2):
					# Lateral side is blocked by wall: try to slide along available open side
					if not blocked_cells.has(side_cell_1):
						dir_2d = (dir_2d + perp * 0.5).normalized()
					elif not blocked_cells.has(side_cell_2):
						dir_2d = (dir_2d - perp * 0.5).normalized()

			return Vector3(dir_2d.x, 0.0, dir_2d.y)

	# 3. Fallback: if cell is outside flowfield or blocked, head directly towards target
	if dist > 0.01:
		return diff.normalized()
	return Vector3.ZERO

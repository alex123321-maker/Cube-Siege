extends RefCounted
class_name MonsterFlowfield

## Authoritative 2D Flowfield and pathfinding for monsters on the discrete voxel grid.
## Computes shared integration fields from targets (Player / Buildings / Points), respects the <= 1 block
## height transition rule, forbids diagonal corner-cutting through walls/cliffs, accounts for
## dynamic walls, loaded chunk boundaries, and static resources, and provides O(1) directional
## queries with multi-target caching, building perimeter seeding, and clearance support.

const DEFAULT_RADIUS: int = 36
const CELL_SIZE: float = 1.0
const RECALC_INTERVAL_SEC: float = 0.25
const TARGET_MOVE_THRESHOLD_SQ: float = 2.25 # 1.5m squared
const MAX_CACHED_FIELDS: int = 16
const MAX_CACHED_HEIGHTS: int = 16384
const MAX_PENDING_REQUESTS: int = 256

class FieldCache extends RefCounted:
	var goal_cell: Vector2i = Vector2i.ZERO
	var target_pos: Vector3 = Vector3.ZERO
	var last_update_sec: float = -999.0
	var last_access_sec: float = 0.0
	var is_goal_blocked: bool = false
	var clearance_radius: float = 0.4
	var flow_directions: Dictionary = {} # Vector2i -> Vector2
	var distance_field: Dictionary = {} # Vector2i -> float

class PendingRequest extends RefCounted:
	var target_pos: Vector3
	var max_radius: int
	var clearance_radius: float
	var clearance_class: int

var world_seed: int = 0
var height_lookup: Callable = Callable()
var chunk_loaded_lookup: Callable = Callable()

# Multi-target cache: Vector3i(goal_cell.x, goal_cell.y, clearance_class) -> FieldCache
var _target_fields: Dictionary = {}
var _rebuild_count: int = 0
var _profile_update_sec: Dictionary[int, float] = {}
var _simulation_time: float = 0.0
var _build_used_this_tick: bool = false
var _height_cache: Dictionary[Vector2i, int] = {}
var _native_solver: MonsterFieldSolver = MonsterFieldSolver.new()
var _compute_time_us: int = 0
var _pending_order: Array[String] = []
var _pending_requests: Dictionary[String, PendingRequest] = {}

## Called once by the registry per physics tick. Pauses do not advance the cadence.
func advance(delta: float) -> void:
	_simulation_time += maxf(delta, 0.0)
	_build_used_this_tick = false

func get_compute_time_us() -> int:
	return _compute_time_us

func get_pending_request_count() -> int:
	return _pending_order.size()

func get_simulation_time() -> float:
	return _simulation_time

## Pending work is distinct from a completed field that establishes no route.
func is_query_pending(goal: Vector3, clearance_radius: float = 0.4) -> bool:
	var cell: Vector2i = Vector2i(int(floorf(goal.x)), int(floorf(goal.z)))
	return not _target_fields.has(Vector3i(cell.x, cell.y, _get_clearance_class(clearance_radius)))

# Backward compatibility / active field inspectability
var target_position: Vector3 = Vector3.INF
var target_cell: Vector2i = Vector2i(2147483647, 2147483647)
var flow_directions: Dictionary = {} # Vector2i -> Vector2
var distance_field: Dictionary = {} # Vector2i -> float

# Blocked building / resource cells: Vector2i -> bool
var blocked_cells: Dictionary = {}

func _init(seed_val: int = 0, custom_height_lookup: Callable = Callable()) -> void:
	world_seed = seed_val
	height_lookup = custom_height_lookup

## Sets or updates custom height lookup (e.g. from MapGenerator or BiomeSystem).
func set_height_lookup(lookup: Callable) -> void:
	height_lookup = lookup
	_height_cache.clear()
	invalidate()

## Sets or updates chunk loaded predicate lookup.
func set_chunk_loaded_lookup(lookup: Callable) -> void:
	chunk_loaded_lookup = lookup
	invalidate()

## Marks a cell as blocked by a building, wall, or resource node.
func set_cell_blocked(cell: Vector2i, is_blocked: bool) -> void:
	if is_blocked:
		blocked_cells[cell] = true
	else:
		blocked_cells.erase(cell)
	invalidate()

## Invalidates cached flowfields, forcing recompute on subsequent queries.
func invalidate() -> void:
	_target_fields.clear()
	flow_directions.clear()
	distance_field.clear()
	target_cell = Vector2i(2147483647, 2147483647)
	target_position = Vector3.INF

## Clears all state including blocked cells and cached fields, while preserving world lookups.
func clear_all() -> void:
	blocked_cells.clear()
	_height_cache.clear()
	_profile_update_sec.clear()
	_pending_order.clear()
	_pending_requests.clear()
	_build_used_this_tick = false
	invalidate()

## Explicitly clears custom lookups if needed.
func clear_lookups() -> void:
	height_lookup = Callable()
	chunk_loaded_lookup = Callable()
	_height_cache.clear()

func get_rebuild_count() -> int:
	return _rebuild_count

func reset_rebuild_count() -> void:
	_rebuild_count = 0
	_compute_time_us = 0

## Resolves the voxel height at cell (x, z).
func get_cell_height(x: int, z: int) -> int:
	if height_lookup.is_valid():
		return int(height_lookup.call(x, z))
	return BiomeSystem.get_voxel_height(x, z, world_seed)

## Checks whether movement from (from_cell) to (to_cell) is traversable.
## Enforces:
## 1. to_cell is loaded and not blocked by wall/solid obstacle.
## 2. Discrete height difference |h_to - h_from| <= 1.
## 3. For diagonal steps, both orthogonal adjacent cells must be passable and within height bounds (no corner cutting).
func is_step_passable(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if blocked_cells.has(to_cell):
		return false

	if chunk_loaded_lookup.is_valid() and not chunk_loaded_lookup.call(to_cell.x, to_cell.y):
		return false

	var h_from: int = get_cell_height(from_cell.x, from_cell.y)
	var h_to: int = get_cell_height(to_cell.x, to_cell.y)

	if absi(h_to - h_from) > 1:
		return false # Blocked by >= 2 block cliff or step

	var dx: int = to_cell.x - from_cell.x
	var dz: int = to_cell.y - from_cell.y

	# Diagonal movement check: prevent cutting through diagonal wall corners or steps
	if dx != 0 and dz != 0:
		var side1: Vector2i = Vector2i(from_cell.x + dx, from_cell.y)
		var side2: Vector2i = Vector2i(from_cell.x, from_cell.y + dz)

		if blocked_cells.has(side1) or blocked_cells.has(side2):
			return false # Cannot cut through corner touching a wall

		if chunk_loaded_lookup.is_valid():
			if not chunk_loaded_lookup.call(side1.x, side1.y) or not chunk_loaded_lookup.call(side2.x, side2.y):
				return false

		var h_s1: int = get_cell_height(side1.x, side1.y)
		var h_s2: int = get_cell_height(side2.x, side2.y)

		if absi(h_s1 - h_from) > 1 or absi(h_s2 - h_from) > 1:
			return false # Cannot cut through corner touching a cliff

	return true

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

	if chunk_loaded_lookup.is_valid() and not chunk_loaded_lookup.call(to_cell.x, to_cell.y):
		return false

	var h_from: int = _get_cached_height(from_cell.x, from_cell.y, cache)
	var h_to: int = _get_cached_height(to_cell.x, to_cell.y, cache)

	if absi(h_to - h_from) > 1:
		return false

	var dx: int = to_cell.x - from_cell.x
	var dz: int = to_cell.y - from_cell.y

	if dx != 0 and dz != 0:
		var side1: Vector2i = Vector2i(from_cell.x + dx, from_cell.y)
		var side2: Vector2i = Vector2i(from_cell.x, from_cell.y + dz)

		if blocked_cells.has(side1) or blocked_cells.has(side2):
			return false

		if chunk_loaded_lookup.is_valid():
			if not chunk_loaded_lookup.call(side1.x, side1.y) or not chunk_loaded_lookup.call(side2.x, side2.y):
				return false

		var h_s1: int = _get_cached_height(side1.x, side1.y, cache)
		var h_s2: int = _get_cached_height(side2.x, side2.y, cache)

		if absi(h_s1 - h_from) > 1 or absi(h_s2 - h_from) > 1:
			return false

	return true

func _get_clearance_class(clearance_radius: float) -> int:
	if clearance_radius > 0.8:
		return 2 # Huge body (Boss Gorgon 1.2m radius / 2.4m width, requires 3x3 clearance)
	elif clearance_radius > 0.5:
		return 1 # Medium / Wide body (Siege Breaker 0.7m radius / 1.4m width, requires 2-cell corridor)
	return 0 # Standard / Small body (Zombie 0.4m, Skirmisher 0.35m, fits 1-cell corridor)

## Retrieves an exact-cell field. A stable target_id coalesces moving requests
## without losing FIFO order; 0 keeps the legacy per-cell request identity.
func get_or_update_field(target_pos: Vector3, max_radius: int = DEFAULT_RADIUS, clearance_radius: float = 0.4, target_id: int = 0) -> FieldCache:
	var goal_cell: Vector2i = Vector2i(int(floorf(target_pos.x)), int(floorf(target_pos.z)))
	var clearance_class: int = _get_clearance_class(clearance_radius)
	var cache_key: Vector3i = Vector3i(goal_cell.x, goal_cell.y, clearance_class)
	var now: float = _simulation_time
	var request_key: String = _request_key(goal_cell, clearance_class, target_id)

	var cached_field: FieldCache = null
	if _target_fields.has(cache_key):
		cached_field = _target_fields[cache_key]

	if cached_field:
		cached_field.last_access_sec = now
		var dist_sq: float = cached_field.target_pos.distance_squared_to(target_pos)
		# Target stationary or within movement threshold: field is valid, no rebuild needed
		if dist_sq < TARGET_MOVE_THRESHOLD_SQ:
			_remove_pending(request_key)
			_serve_next_pending()
			_activate_field(cached_field)
			return cached_field

		# Target moved significantly: throttle rebuilds to at most once per RECALC_INTERVAL_SEC
		var time_elapsed: bool = (now - cached_field.last_update_sec) >= RECALC_INTERVAL_SEC
		if not time_elapsed:
			_remove_pending(request_key)
			_serve_next_pending()
			_activate_field(cached_field)
			return cached_field

	# Stable logical targets retain their FIFO place while their exact cell changes.
	# Serving the oldest eligible request prevents player-first callers starving walls.
	_enqueue_request(request_key, target_pos, max_radius, clearance_radius, clearance_class)
	_serve_next_pending()
	var result: FieldCache = _target_fields.get(cache_key, cached_field)
	if result:
		_activate_field(result)
	return result

func _request_key(cell: Vector2i, clearance_class: int, target_id: int) -> String:
	if target_id != 0:
		return "target:%d:%d" % [target_id, clearance_class]
	return "cell:%d:%d:%d" % [cell.x, cell.y, clearance_class]

func _remove_pending(key: String) -> void:
	if _pending_requests.erase(key):
		_pending_order.erase(key)

func _enqueue_request(key: String, target_pos: Vector3, max_radius: int, clearance_radius: float, clearance_class: int) -> void:
	var request: PendingRequest = _pending_requests.get(key)
	if not request:
		if _pending_order.size() >= MAX_PENDING_REQUESTS:
			return # Keep already waiting requests; callers may retry after service.
		request = PendingRequest.new()
		_pending_requests[key] = request
		_pending_order.append(key)
	request.target_pos = target_pos
	request.max_radius = max_radius
	request.clearance_radius = clearance_radius
	request.clearance_class = clearance_class

func _serve_next_pending() -> void:
	if _build_used_this_tick:
		return
	var index: int = 0
	while index < _pending_order.size():
		var key: String = _pending_order[index]
		var request: PendingRequest = _pending_requests[key]
		var cell: Vector2i = Vector2i(int(floorf(request.target_pos.x)), int(floorf(request.target_pos.z)))
		var cached: FieldCache = _target_fields.get(Vector3i(cell.x, cell.y, request.clearance_class))
		if cached and cached.target_pos.distance_squared_to(request.target_pos) < TARGET_MOVE_THRESHOLD_SQ:
			_remove_pending(key)
			continue
		if _simulation_time - _profile_update_sec.get(request.clearance_class, -999.0) < RECALC_INTERVAL_SEC:
			index += 1
			continue
		_remove_pending(key)
		_build_pending_field(request)
		return

func _activate_field(field: FieldCache) -> void:
	flow_directions = field.flow_directions
	distance_field = field.distance_field
	target_position = field.target_pos
	target_cell = field.goal_cell

func _build_pending_field(request: PendingRequest) -> void:
	var target_pos: Vector3 = request.target_pos
	var goal_cell: Vector2i = Vector2i(int(floorf(target_pos.x)), int(floorf(target_pos.z)))
	var clearance_class: int = request.clearance_class
	var cache_key: Vector3i = Vector3i(goal_cell.x, goal_cell.y, clearance_class)
	var now: float = _simulation_time
	_build_used_this_tick = true
	_profile_update_sec[clearance_class] = now

	# Evict LRU field if cache capacity reached
	if _target_fields.size() >= MAX_CACHED_FIELDS and not _target_fields.has(cache_key):
		var oldest_key = null
		var oldest_time: float = INF
		for k in _target_fields.keys():
			var f: FieldCache = _target_fields[k]
			if f.last_access_sec < oldest_time:
				oldest_time = f.last_access_sec
				oldest_key = k
		if oldest_key != null:
			_target_fields.erase(oldest_key)

	var new_field: FieldCache = FieldCache.new()
	new_field.goal_cell = goal_cell
	new_field.target_pos = target_pos
	new_field.last_update_sec = now
	new_field.last_access_sec = now
	new_field.clearance_radius = request.clearance_radius

	_rebuild_count += 1
	var compute_start_us: int = Time.get_ticks_usec()
	_compute_field_data(new_field, goal_cell, request.max_radius, request.clearance_radius)
	_compute_time_us += Time.get_ticks_usec() - compute_start_us
	_target_fields[cache_key] = new_field

	_activate_field(new_field)

## Force-recomputes and caches a fresh flowfield for target_pos.
func recompute_field(target_pos: Vector3, max_radius: int = DEFAULT_RADIUS, clearance_radius: float = 0.4, target_id: int = 0) -> FieldCache:
	var goal_cell: Vector2i = Vector2i(int(floorf(target_pos.x)), int(floorf(target_pos.z)))
	var clearance_class: int = _get_clearance_class(clearance_radius)
	var cache_key: Vector3i = Vector3i(goal_cell.x, goal_cell.y, clearance_class)
	_target_fields.erase(cache_key)
	return get_or_update_field(target_pos, max_radius, clearance_radius, target_id)

## Computes or updates the flowfield towards target_pos if needed (backward compatibility).
func update_field_if_needed(target_pos: Vector3, max_radius: int = DEFAULT_RADIUS) -> void:
	get_or_update_field(target_pos, max_radius)

func _get_fast_height(x: int, z: int, min_x: int, min_z: int, stride: int, h_cache: PackedInt32Array) -> int:
	if x < min_x or z < min_z or x >= min_x + stride:
		return get_cell_height(x, z)
	var idx: int = (x - min_x) + (z - min_z) * stride
	if idx < 0 or idx >= h_cache.size():
		return get_cell_height(x, z)
	var h: int = h_cache[idx]
	if h == -999999:
		h = get_cell_height(x, z)
		h_cache[idx] = h
	return h

func _is_step_passable_fast(
	from_cell: Vector2i,
	to_cell: Vector2i,
	min_x: int,
	min_z: int,
	stride: int,
	h_cache: PackedInt32Array
) -> bool:
	if blocked_cells.has(to_cell):
		return false

	if chunk_loaded_lookup.is_valid() and not chunk_loaded_lookup.call(to_cell.x, to_cell.y):
		return false

	var h_from: int = _get_fast_height(from_cell.x, from_cell.y, min_x, min_z, stride, h_cache)
	var h_to: int = _get_fast_height(to_cell.x, to_cell.y, min_x, min_z, stride, h_cache)

	if absi(h_to - h_from) > 1:
		return false

	var dx: int = to_cell.x - from_cell.x
	var dz: int = to_cell.y - from_cell.y

	if dx != 0 and dz != 0:
		var side1: Vector2i = Vector2i(from_cell.x + dx, from_cell.y)
		var side2: Vector2i = Vector2i(from_cell.x, from_cell.y + dz)

		if blocked_cells.has(side1) or blocked_cells.has(side2):
			return false

		if chunk_loaded_lookup.is_valid():
			if not chunk_loaded_lookup.call(side1.x, side1.y) or not chunk_loaded_lookup.call(side2.x, side2.y):
				return false

		var h_s1: int = _get_fast_height(side1.x, side1.y, min_x, min_z, stride, h_cache)
		var h_s2: int = _get_fast_height(side2.x, side2.y, min_x, min_z, stride, h_cache)

		if absi(h_s1 - h_from) > 1 or absi(h_s2 - h_from) > 1:
			return false

	return true

func _is_cell_walkable_fast(
	x: int,
	z: int,
	ref_height: int,
	min_x: int,
	min_z: int,
	stride: int,
	h_cache: PackedInt32Array,
	max_x: int,
	max_z: int
) -> bool:
	if x < min_x or x > max_x or z < min_z or z > max_z:
		return false
	var cell: Vector2i = Vector2i(x, z)
	if blocked_cells.has(cell):
		return false
	if chunk_loaded_lookup.is_valid() and not chunk_loaded_lookup.call(x, z):
		return false
	var h: int = _get_fast_height(x, z, min_x, min_z, stride, h_cache)
	return absi(h - ref_height) <= 1

func _has_2cell_corridor_clearance_fast(
	n: Vector2i,
	curr: Vector2i,
	min_x: int,
	min_z: int,
	stride: int,
	h_cache: PackedInt32Array,
	max_x: int,
	max_z: int
) -> bool:
	var step: Vector2i = curr - n
	var h_n: int = _get_fast_height(n.x, n.y, min_x, min_z, stride, h_cache)
	var h_curr: int = _get_fast_height(curr.x, curr.y, min_x, min_z, stride, h_cache)

	# If step is horizontal (along X): corridor must be at least 2 cells wide along Z
	if step.x != 0 and step.y == 0:
		var side_pos_ok: bool = _is_cell_walkable_fast(n.x, n.y + 1, h_n, min_x, min_z, stride, h_cache, max_x, max_z) \
			and _is_cell_walkable_fast(curr.x, curr.y + 1, h_curr, min_x, min_z, stride, h_cache, max_x, max_z)
		if side_pos_ok:
			return true
		var side_neg_ok: bool = _is_cell_walkable_fast(n.x, n.y - 1, h_n, min_x, min_z, stride, h_cache, max_x, max_z) \
			and _is_cell_walkable_fast(curr.x, curr.y - 1, h_curr, min_x, min_z, stride, h_cache, max_x, max_z)
		return side_neg_ok

	# If step is vertical (along Z): corridor must be at least 2 cells wide along X
	if step.x == 0 and step.y != 0:
		var side_pos_ok: bool = _is_cell_walkable_fast(n.x + 1, n.y, h_n, min_x, min_z, stride, h_cache, max_x, max_z) \
			and _is_cell_walkable_fast(curr.x + 1, curr.y, h_curr, min_x, min_z, stride, h_cache, max_x, max_z)
		if side_pos_ok:
			return true
		var side_neg_ok: bool = _is_cell_walkable_fast(n.x - 1, n.y, h_n, min_x, min_z, stride, h_cache, max_x, max_z) \
			and _is_cell_walkable_fast(curr.x - 1, curr.y, h_curr, min_x, min_z, stride, h_cache, max_x, max_z)
		return side_neg_ok

	# Diagonal step: _is_step_passable_fast already verified the 2x2 bounding square [n, curr, s1, s2]
	return true

func _has_cell_clearance_fast(
	cell: Vector2i,
	min_x: int,
	min_z: int,
	stride: int,
	h_cache: PackedInt32Array,
	max_x: int,
	max_z: int
) -> bool:
	var h_c: int = _get_fast_height(cell.x, cell.y, min_x, min_z, stride, h_cache)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			var nx: int = cell.x + dx
			var nz: int = cell.y + dz
			var n: Vector2i = Vector2i(nx, nz)
			if blocked_cells.has(n):
				return false
			if chunk_loaded_lookup.is_valid() and not chunk_loaded_lookup.call(nx, nz):
				return false
			if nx >= min_x and nx <= max_x and nz >= min_z and nz <= max_z:
				var h_n: int = _get_fast_height(nx, nz, min_x, min_z, stride, h_cache)
				if absi(h_n - h_c) > 1:
					return false
	return true

func _has_huge_body_perimeter_clearance_fast(
	p: Vector2i,
	goal_cell: Vector2i,
	min_x: int,
	min_z: int,
	stride: int,
	h_cache: PackedInt32Array,
	max_x: int,
	max_z: int
) -> bool:
	var d: Vector2i = p - goal_cell
	if d.x != 0 and d.y != 0:
		return false

	var h_p: int = _get_fast_height(p.x, p.y, min_x, min_z, stride, h_cache)
	var perp: Vector2i = Vector2i(-d.y, d.x)

	if not _is_cell_walkable_fast(p.x + perp.x, p.y + perp.y, h_p, min_x, min_z, stride, h_cache, max_x, max_z):
		return false
	if not _is_cell_walkable_fast(p.x - perp.x, p.y - perp.y, h_p, min_x, min_z, stride, h_cache, max_x, max_z):
		return false

	if not _is_cell_walkable_fast(p.x + d.x, p.y + d.y, h_p, min_x, min_z, stride, h_cache, max_x, max_z):
		return false
	if not _is_cell_walkable_fast(p.x + d.x + perp.x, p.y + d.y + perp.y, h_p, min_x, min_z, stride, h_cache, max_x, max_z):
		return false
	if not _is_cell_walkable_fast(p.x + d.x - perp.x, p.y + d.y - perp.y, h_p, min_x, min_z, stride, h_cache, max_x, max_z):
		return false

	return true

func _has_wide_body_perimeter_clearance_fast(
	p: Vector2i,
	goal_cell: Vector2i,
	min_x: int,
	min_z: int,
	stride: int,
	h_cache: PackedInt32Array,
	max_x: int,
	max_z: int
) -> bool:
	var d: Vector2i = p - goal_cell
	if d.x != 0 and d.y != 0:
		return true

	var h_p: int = _get_fast_height(p.x, p.y, min_x, min_z, stride, h_cache)
	var perp: Vector2i = Vector2i(-d.y, d.x)

	var side_pos_ok: bool = _is_cell_walkable_fast(p.x + perp.x, p.y + perp.y, h_p, min_x, min_z, stride, h_cache, max_x, max_z) \
		and _is_cell_walkable_fast(p.x + d.x, p.y + d.y, h_p, min_x, min_z, stride, h_cache, max_x, max_z) \
		and _is_cell_walkable_fast(p.x + d.x + perp.x, p.y + d.y + perp.y, h_p, min_x, min_z, stride, h_cache, max_x, max_z)
	if side_pos_ok:
		return true

	var side_neg_ok: bool = _is_cell_walkable_fast(p.x - perp.x, p.y - perp.y, h_p, min_x, min_z, stride, h_cache, max_x, max_z) \
		and _is_cell_walkable_fast(p.x + d.x, p.y + d.y, h_p, min_x, min_z, stride, h_cache, max_x, max_z) \
		and _is_cell_walkable_fast(p.x + d.x - perp.x, p.y + d.y - perp.y, h_p, min_x, min_z, stride, h_cache, max_x, max_z)
	return side_neg_ok

func _compute_field_data(field: FieldCache, goal_cell: Vector2i, radius: int, clearance_req: float = 0.0) -> void:
	# Only immutable compact cell snapshots cross the native boundary. Height/loaded
	# lookups, obstacle lifecycle and all target/attack decisions remain in GDScript.
	var width: int = radius * 2 + 3
	if _height_cache.size() > MAX_CACHED_HEIGHTS:
		_height_cache.clear()
	var min_cell: Vector2i = goal_cell - Vector2i(radius + 1, radius + 1)
	var heights: PackedInt32Array = PackedInt32Array()
	var blocked: PackedByteArray = PackedByteArray()
	var loaded: PackedByteArray = PackedByteArray()
	heights.resize(width * width)
	blocked.resize(width * width)
	loaded.resize(width * width)
	for z in range(width):
		for x in range(width):
			var cell: Vector2i = min_cell + Vector2i(x, z)
			var idx: int = z * width + x
			if not _height_cache.has(cell):
				_height_cache[cell] = get_cell_height(cell.x, cell.y)
			heights[idx] = _height_cache[cell]
			blocked[idx] = 1 if blocked_cells.has(cell) else 0
			loaded[idx] = 1 if not chunk_loaded_lookup.is_valid() or chunk_loaded_lookup.call(cell.x, cell.y) else 0
	var data: PackedFloat32Array = _native_solver.build(heights, blocked, loaded, width, _get_clearance_class(clearance_req), 1)
	field.is_goal_blocked = blocked_cells.has(goal_cell)
	field.flow_directions.clear()
	field.distance_field.clear()
	if data.size() != width * width * 3:
		return
	for z in range(1, width - 1):
		for x in range(1, width - 1):
			var idx: int = (z * width + x) * 3
			if data[idx] >= 0.0:
				var cell: Vector2i = min_cell + Vector2i(x, z)
				field.distance_field[cell] = data[idx]
				field.flow_directions[cell] = Vector2(data[idx + 1], data[idx + 2])

## Retained reference implementation for regression parity; production uses the batch solver.
func _compute_field_data_reference(field: FieldCache, goal_cell: Vector2i, radius: int, clearance_req: float = 0.0) -> void:
	field.flow_directions.clear()
	field.distance_field.clear()

	var min_x: int = goal_cell.x - radius
	var max_x: int = goal_cell.x + radius
	var min_z: int = goal_cell.y - radius
	var max_z: int = goal_cell.y + radius
	var stride: int = (max_x - min_x + 1)
	var total_cells: int = stride * (max_z - min_z + 1)

	var h_cache: PackedInt32Array = PackedInt32Array()
	h_cache.resize(total_cells)
	h_cache.fill(-999999)

	var dist_grid: PackedFloat32Array = PackedFloat32Array()
	dist_grid.resize(total_cells)
	dist_grid.fill(999999.0)

	var dir_x_grid: PackedFloat32Array = PackedFloat32Array()
	dir_x_grid.resize(total_cells)
	dir_x_grid.fill(0.0)

	var dir_z_grid: PackedFloat32Array = PackedFloat32Array()
	dir_z_grid.resize(total_cells)
	dir_z_grid.fill(0.0)

	var neighbors_8: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]

	var is_huge_body: bool = clearance_req > 0.8
	var is_wide_body: bool = clearance_req > 0.5 and clearance_req <= 0.8

	var queue: Array[Vector2i] = []
	var head: int = 0
	var is_goal_blocked: bool = blocked_cells.has(goal_cell)
	field.is_goal_blocked = is_goal_blocked

	if is_goal_blocked:
		# Target is inside an obstacle / building (e.g. wall targeted by siege unit).
		# Seed wavefront from all unblocked, height-connected perimeter neighbor cells.
		for d in neighbors_8:
			var p: Vector2i = goal_cell + d
			if p.x < min_x or p.x > max_x or p.y < min_z or p.y > max_z:
				continue
			if blocked_cells.has(p):
				continue
			if chunk_loaded_lookup.is_valid() and not chunk_loaded_lookup.call(p.x, p.y):
				continue
			var h_p: int = _get_fast_height(p.x, p.y, min_x, min_z, stride, h_cache)
			var h_goal: int = _get_fast_height(goal_cell.x, goal_cell.y, min_x, min_z, stride, h_cache)
			if absi(h_p - h_goal) > 1:
				continue

			# Diagonal perimeter seed anti-corner-cutting check:
			if d.x != 0 and d.y != 0:
				var s1: Vector2i = Vector2i(p.x, goal_cell.y)
				var s2: Vector2i = Vector2i(goal_cell.x, p.y)
				if blocked_cells.has(s1) or blocked_cells.has(s2):
					continue
				if chunk_loaded_lookup.is_valid() and (not chunk_loaded_lookup.call(s1.x, s1.y) or not chunk_loaded_lookup.call(s2.x, s2.y)):
					continue
				var h_s1: int = _get_fast_height(s1.x, s1.y, min_x, min_z, stride, h_cache)
				var h_s2: int = _get_fast_height(s2.x, s2.y, min_x, min_z, stride, h_cache)
				if absi(h_s1 - h_p) > 1 or absi(h_s2 - h_p) > 1:
					continue
				if absi(h_s1 - h_goal) > 1 or absi(h_s2 - h_goal) > 1:
					continue

			if is_huge_body and not _has_huge_body_perimeter_clearance_fast(p, goal_cell, min_x, min_z, stride, h_cache, max_x, max_z):
				continue
			if is_wide_body and not _has_wide_body_perimeter_clearance_fast(p, goal_cell, min_x, min_z, stride, h_cache, max_x, max_z):
				continue

			var p_idx: int = (p.y - min_z) * stride + (p.x - min_x)
			dist_grid[p_idx] = 0.0
			var to_goal: Vector2 = Vector2(goal_cell.x - p.x, goal_cell.y - p.y).normalized()
			dir_x_grid[p_idx] = to_goal.x
			dir_z_grid[p_idx] = to_goal.y
			queue.append(p)
	else:
		var goal_idx: int = (goal_cell.y - min_z) * stride + (goal_cell.x - min_x)
		dist_grid[goal_idx] = 0.0
		dir_x_grid[goal_idx] = 0.0
		dir_z_grid[goal_idx] = 0.0
		queue.append(goal_cell)

	while head < queue.size():
		var curr: Vector2i = queue[head]
		head += 1
		var curr_idx: int = (curr.y - min_z) * stride + (curr.x - min_x)
		var curr_dist: float = dist_grid[curr_idx]

		for d in neighbors_8:
			var n: Vector2i = curr + d
			if n.x < min_x or n.x > max_x or n.y < min_z or n.y > max_z:
				continue

			var step_cost: float = 1.414 if (d.x != 0 and d.y != 0) else 1.0
			var new_dist: float = curr_dist + step_cost
			var n_idx: int = (n.y - min_z) * stride + (n.x - min_x)
			var existing_dist: float = dist_grid[n_idx]

			if existing_dist < 999998.0:
				if new_dist < existing_dist:
					if _is_step_passable_fast(n, curr, min_x, min_z, stride, h_cache):
						var can_pass: bool = true
						if is_huge_body:
							can_pass = _has_cell_clearance_fast(n, min_x, min_z, stride, h_cache, max_x, max_z)
						elif is_wide_body:
							can_pass = _has_2cell_corridor_clearance_fast(n, curr, min_x, min_z, stride, h_cache, max_x, max_z)
						if can_pass:
							dist_grid[n_idx] = new_dist
							var flow: Vector2 = Vector2(curr.x - n.x, curr.y - n.y).normalized()
							dir_x_grid[n_idx] = flow.x
							dir_z_grid[n_idx] = flow.y
				continue

			# Wavefront propagates from goal/perimeter outward: step is from n to curr
			if not _is_step_passable_fast(n, curr, min_x, min_z, stride, h_cache):
				continue

			if is_huge_body and not _has_cell_clearance_fast(n, min_x, min_z, stride, h_cache, max_x, max_z):
				continue
			if is_wide_body and not _has_2cell_corridor_clearance_fast(n, curr, min_x, min_z, stride, h_cache, max_x, max_z):
				continue

			dist_grid[n_idx] = new_dist
			var flow: Vector2 = Vector2(curr.x - n.x, curr.y - n.y).normalized()
			dir_x_grid[n_idx] = flow.x
			dir_z_grid[n_idx] = flow.y
			queue.append(n)

	# Transfer visited cells into FieldCache Dictionary
	for cell in queue:
		var c_idx: int = (cell.y - min_z) * stride + (cell.x - min_x)
		field.distance_field[cell] = dist_grid[c_idx]
		field.flow_directions[cell] = Vector2(dir_x_grid[c_idx], dir_z_grid[c_idx])


## Queries the flowfield for desired horizontal movement direction towards target_pos.
## Returns normalized Vector3 on XZ plane, or Vector3.ZERO if unreachable / no valid path.
func get_flow_direction(
	from_pos: Vector3,
	target_pos: Vector3,
	clearance_radius: float = 0.4,
	target_id: int = 0
) -> Vector3:
	var diff: Vector3 = target_pos - from_pos
	diff.y = 0.0
	var dist: float = diff.length()
	if dist < 0.1:
		return Vector3.ZERO

	var from_cell: Vector2i = Vector2i(int(floorf(from_pos.x)), int(floorf(from_pos.z)))

	# Ensure origin cell is loaded and not blocked
	if chunk_loaded_lookup.is_valid() and not chunk_loaded_lookup.call(from_cell.x, from_cell.y):
		return Vector3.ZERO
	if blocked_cells.has(from_cell):
		return Vector3.ZERO
	# 1. Line-of-sight shortcut:
	# Requires unobstructed direct path, clearance width, and strict anti-corner-cutting.
	if dist < 8.0:
		if _check_line_of_sight(from_pos, target_pos, clearance_radius):
			return diff.normalized()
	var field: FieldCache = get_or_update_field(target_pos, DEFAULT_RADIUS, clearance_radius, target_id)
	if not field:
		return Vector3.ZERO

	# 2. Flowfield lookup:
	if field.flow_directions.has(from_cell):
		var dir_2d: Vector2 = field.flow_directions[from_cell]
		if dir_2d.length_squared() > 0.001:
			var step_x: int = int(roundf(dir_2d.x))
			var step_z: int = int(roundf(dir_2d.y))
			var next_cell: Vector2i = from_cell + Vector2i(step_x, step_z)
			var is_passable: bool = true
			if step_x != 0 or step_z != 0:
				if not is_step_passable(from_cell, next_cell):
					if field.is_goal_blocked and next_cell == field.goal_cell and _is_perimeter_goal_step_passable(from_cell, next_cell):
						is_passable = true
					else:
						is_passable = false

			if not is_passable:
				# Stale cached direction (chunk unloaded, wall placed, or cliff changed).
				field = recompute_field(target_pos, DEFAULT_RADIUS, clearance_radius, target_id)
				if not field or not field.flow_directions.has(from_cell):
					return Vector3.ZERO
				dir_2d = field.flow_directions[from_cell]
				step_x = int(roundf(dir_2d.x))
				step_z = int(roundf(dir_2d.y))
				next_cell = from_cell + Vector2i(step_x, step_z)
				if step_x != 0 or step_z != 0:
					var re_passable: bool = is_step_passable(from_cell, next_cell)
					if not re_passable and field.is_goal_blocked and next_cell == field.goal_cell and _is_perimeter_goal_step_passable(from_cell, next_cell):
						re_passable = true
					if not re_passable:
						return Vector3.ZERO

			if dir_2d.length_squared() > 0.001:
				if field.is_goal_blocked and next_cell == field.goal_cell:
					if _has_lateral_clearance(from_pos, dir_2d, clearance_radius):
						var advance_probe: Vector3 = from_pos + Vector3(dir_2d.x, 0.0, dir_2d.y) * 0.35
						if _has_lateral_clearance(advance_probe, dir_2d, clearance_radius):
							return Vector3(dir_2d.x, 0.0, dir_2d.y)
					return Vector3.ZERO

				if clearance_radius > 0.2:
					dir_2d = _resolve_clearance_direction(from_pos, dir_2d, clearance_radius, field)
					if dir_2d.length_squared() < 0.001:
						return Vector3.ZERO
				return Vector3(dir_2d.x, 0.0, dir_2d.y)

	# 3. Path unreachable / blocked:
	return Vector3.ZERO

func _is_perimeter_goal_step_passable(from_cell: Vector2i, goal_cell: Vector2i) -> bool:
	if chunk_loaded_lookup.is_valid() and not chunk_loaded_lookup.call(goal_cell.x, goal_cell.y):
		return false
	var h_from: int = get_cell_height(from_cell.x, from_cell.y)
	var h_goal: int = get_cell_height(goal_cell.x, goal_cell.y)
	if absi(h_goal - h_from) > 1:
		return false

	# Anti-corner-cutting check: if moving diagonally into goal cell,
	# the two orthogonal neighbor cells must be unblocked, loaded, and level.
	if goal_cell.x != from_cell.x and goal_cell.y != from_cell.y:
		var s1: Vector2i = Vector2i(goal_cell.x, from_cell.y)
		var s2: Vector2i = Vector2i(from_cell.x, goal_cell.y)
		if blocked_cells.has(s1) or blocked_cells.has(s2):
			return false
		if chunk_loaded_lookup.is_valid() and (not chunk_loaded_lookup.call(s1.x, s1.y) or not chunk_loaded_lookup.call(s2.x, s2.y)):
			return false
		var h_s1: int = get_cell_height(s1.x, s1.y)
		var h_s2: int = get_cell_height(s2.x, s2.y)
		if absi(h_s1 - h_from) > 1 or absi(h_s2 - h_from) > 1:
			return false
		if absi(h_s1 - h_goal) > 1 or absi(h_s2 - h_goal) > 1:
			return false

	return true

func _check_line_of_sight(from_pos: Vector3, target_pos: Vector3, clearance_radius: float) -> bool:
	if not _is_direct_line_passable(from_pos, target_pos):
		return false

	if clearance_radius > 0.05:
		var diff: Vector3 = target_pos - from_pos
		var dir_h: Vector2 = Vector2(diff.x, diff.z).normalized()
		var perp: Vector2 = Vector2(-dir_h.y, dir_h.x) * clearance_radius
		var perp_3d: Vector3 = Vector3(perp.x, 0.0, perp.y)
		if not _is_direct_line_passable(from_pos + perp_3d, target_pos + perp_3d):
			return false
		if not _is_direct_line_passable(from_pos - perp_3d, target_pos - perp_3d):
			return false
		if clearance_radius > 0.5:
			var half_perp_3d: Vector3 = perp_3d * 0.5
			if not _is_direct_line_passable(from_pos + half_perp_3d, target_pos + half_perp_3d):
				return false
			if not _is_direct_line_passable(from_pos - half_perp_3d, target_pos - half_perp_3d):
				return false

	return true

func _is_direct_line_passable(start_pos: Vector3, end_pos: Vector3) -> bool:
	var diff: Vector3 = end_pos - start_pos
	diff.y = 0.0
	var dist: float = diff.length()
	if dist < 0.05:
		return true

	var steps: int = maxi(2, int(ceilf(dist / 0.25)))
	var prev_cell: Vector2i = Vector2i(int(floorf(start_pos.x)), int(floorf(start_pos.z)))

	if blocked_cells.has(prev_cell):
		return false
	if chunk_loaded_lookup.is_valid() and not chunk_loaded_lookup.call(prev_cell.x, prev_cell.y):
		return false

	for i in range(1, steps + 1):
		var t: float = float(i) / float(steps)
		var pt: Vector3 = start_pos.lerp(end_pos, t)
		var curr_cell: Vector2i = Vector2i(int(floorf(pt.x)), int(floorf(pt.z)))
		if curr_cell != prev_cell:
			if not is_step_passable(prev_cell, curr_cell):
				return false
			prev_cell = curr_cell

	return true

func _resolve_clearance_direction(
	from_pos: Vector3,
	dir_2d: Vector2,
	clearance_radius: float,
	field: FieldCache
) -> Vector2:
	var from_cell: Vector2i = Vector2i(int(floorf(from_pos.x)), int(floorf(from_pos.z)))

	# Check whether proposed dir_2d has full lateral clearance currently and 1 step ahead
	if _has_lateral_clearance(from_pos, dir_2d, clearance_radius):
		var target_cell: Vector2i = from_cell + Vector2i(int(roundf(dir_2d.x)), int(roundf(dir_2d.y)))
		if field.is_goal_blocked and target_cell == field.goal_cell:
			return dir_2d
		var next_pos: Vector3 = from_pos + Vector3(dir_2d.x, 0.0, dir_2d.y) * 1.0
		if _has_lateral_clearance(next_pos, dir_2d, clearance_radius):
			return dir_2d

	# Proposed direction lacks clearance for body width (e.g. narrow corridor); search alternative neighbors
	var neighbors_8: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]
	var best_alt: Vector2 = Vector2.ZERO
	var best_dist: float = INF
	for d in neighbors_8:
		var n: Vector2i = from_cell + d
		if field.distance_field.has(n) and is_step_passable(from_cell, n):
			var d_val: float = field.distance_field[n]
			if d_val < best_dist:
				var alt_dir: Vector2 = Vector2(d.x, d.y).normalized()
				if _has_lateral_clearance(from_pos, alt_dir, clearance_radius):
					var next_alt_pos: Vector3 = from_pos + Vector3(alt_dir.x, 0.0, alt_dir.y) * 1.0
					if _has_lateral_clearance(next_alt_pos, alt_dir, clearance_radius):
						best_dist = d_val
						best_alt = alt_dir

	if best_alt.length_squared() < 0.001 and clearance_radius <= 0.8:
		var cell_center_2d: Vector2 = Vector2(float(from_cell.x) + 0.5, float(from_cell.y) + 0.5)
		var to_center: Vector2 = cell_center_2d - Vector2(from_pos.x, from_pos.z)
		var steer: Vector2 = (dir_2d + to_center * 2.0).normalized()
		var next_test: Vector3 = from_pos + Vector3(steer.x, 0.0, steer.y) * 0.5
		if _has_lateral_clearance(next_test, steer, clearance_radius * 0.75):
			return steer

	return best_alt

func _has_lateral_clearance(pos: Vector3, dir: Vector2, clearance_radius: float) -> bool:
	var center_cell: Vector2i = Vector2i(int(floorf(pos.x)), int(floorf(pos.z)))
	var h_center: int = get_cell_height(center_cell.x, center_cell.y)
	var perp: Vector2 = Vector2(-dir.y, dir.x) * clearance_radius
	var offsets: Array[Vector2] = [perp, -perp]
	if clearance_radius > 0.8:
		offsets.append(perp * 0.5)
		offsets.append(-perp * 0.5)

	for off in offsets:
		var check_cell: Vector2i = Vector2i(int(floorf(pos.x + off.x)), int(floorf(pos.z + off.y)))
		if blocked_cells.has(check_cell):
			return false
		if chunk_loaded_lookup.is_valid() and not chunk_loaded_lookup.call(check_cell.x, check_cell.y):
			return false
		var h_lateral: int = get_cell_height(check_cell.x, check_cell.y)
		if absi(h_lateral - h_center) > 1:
			return false
	return true

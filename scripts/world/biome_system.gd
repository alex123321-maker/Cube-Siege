extends RefCounted
class_name BiomeSystem

## BiomeSystem: Authoritative procedural calculation of macro-biomes,
## biome blend weights, and continuous/voxel physical terrain heights.
## Strictly deterministic given world coordinates (x, z) and world seed.

enum BiomeType {
	FOREST = 0,
	PLAINS = 1,
	MOUNTAINS = 2
}

const PORTAL_CLEAR_RADIUS: float = 6.5

# Center angles for each macro-biome around Portal (0, 0)
# Evenly distributed across 360 degrees (2*PI/3 radians each)
const ANGLE_FOREST: float = 0.0                 # ~0 rad (East / +X)
const ANGLE_PLAINS: float = 2.0943951023931953  # ~+120 deg (North-West)
const ANGLE_MOUNTAINS: float = -2.0943951023931953 # ~-120 deg (South-West)

const SECTOR_SPAN: float = 2.0943951023931953  # 120 degrees
const HALF_SECTOR: float = 1.0471975511965976  # 60 degrees
const BLEND_BAND: float = 0.40                 # ~23 degrees transition band
const TRAIL_WIDTH: float = 3.2
const TRAIL_VALLEY_WIDTH: float = 14.0
const MOUNTAIN_BASE_SLOPE: float = 0.68

static func get_trail_angle(r: float, seed_val: int) -> float:
	var phase: float = float(seed_val % 97) * 0.04
	return normalize_angle(ANGLE_MOUNTAINS + sin(r * 0.035 + phase) * 0.22)

## Returns true if integer coordinate falls within the authoritative mountain trail corridor.
static func is_mountain_trail(x: int, z: int, seed_val: int) -> bool:
	var r: float = Vector2(float(x), float(z)).length()
	if r <= PORTAL_CLEAR_RADIUS:
		return false
	var trail_ang: float = get_trail_angle(r, seed_val)
	var trail_x: float = r * cos(trail_ang)
	var trail_z: float = r * sin(trail_ang)
	var dist_to_trail: float = Vector2(float(x) - trail_x, float(z) - trail_z).length()
	return dist_to_trail <= TRAIL_WIDTH

static func normalize_angle(a: float) -> float:
	var res: float = fposmod(a + PI, TAU) - PI
	return res

static func angular_distance(a: float, b: float) -> float:
	return absf(normalize_angle(a - b))

static var _cached_warp_noise: FastNoiseLite = null
static var _cached_broad_noise: FastNoiseLite = null
static var _cached_hills_noise: FastNoiseLite = null

static func _get_warp_noise(seed_val: int) -> FastNoiseLite:
	if _cached_warp_noise == null:
		_cached_warp_noise = FastNoiseLite.new()
		_cached_warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_cached_warp_noise.frequency = 0.015
	if _cached_warp_noise.seed != seed_val + 777:
		_cached_warp_noise.seed = seed_val + 777
	return _cached_warp_noise

static func _get_broad_noise(seed_val: int) -> FastNoiseLite:
	if _cached_broad_noise == null:
		_cached_broad_noise = FastNoiseLite.new()
		_cached_broad_noise.noise_type = FastNoiseLite.TYPE_PERLIN
		_cached_broad_noise.frequency = 0.02
	if _cached_broad_noise.seed != seed_val + 101:
		_cached_broad_noise.seed = seed_val + 101
	return _cached_broad_noise

static func _get_hills_noise(seed_val: int) -> FastNoiseLite:
	if _cached_hills_noise == null:
		_cached_hills_noise = FastNoiseLite.new()
		_cached_hills_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
		_cached_hills_noise.frequency = 0.04
	if _cached_hills_noise.seed != seed_val + 202:
		_cached_hills_noise.seed = seed_val + 202
	return _cached_hills_noise

## Calculates warped direction angle and biome weights for world (x, z).
static func sample_biome_weights(x: float, z: float, seed_val: int) -> Dictionary:
	var dist: float = Vector2(x, z).length()
	if dist < 0.001:
		return {
			"primary": BiomeType.PLAINS,
			"weights": { BiomeType.FOREST: 0.333, BiomeType.PLAINS: 0.334, BiomeType.MOUNTAINS: 0.333 },
			"is_sanctuary": true
		}

	var base_angle: float = atan2(z, x)

	# Boundary warping noise to prevent straight ray boundaries
	var warp_noise: FastNoiseLite = _get_warp_noise(seed_val)
	var warp_offset: float = warp_noise.get_noise_2d(x, z) * 0.35
	var angle: float = normalize_angle(base_angle + warp_offset)

	var d_forest: float = angular_distance(angle, ANGLE_FOREST)
	var d_plains: float = angular_distance(angle, ANGLE_PLAINS)
	var d_mountains: float = angular_distance(angle, ANGLE_MOUNTAINS)

	# Raw inverse-distance weighting
	var w_f: float = maxf(0.0, HALF_SECTOR + BLEND_BAND * 0.5 - d_forest)
	var w_p: float = maxf(0.0, HALF_SECTOR + BLEND_BAND * 0.5 - d_plains)
	var w_m: float = maxf(0.0, HALF_SECTOR + BLEND_BAND * 0.5 - d_mountains)

	var total_w: float = w_f + w_p + w_m
	if total_w > 0.0001:
		w_f /= total_w
		w_p /= total_w
		w_m /= total_w
	else:
		w_f = 0.333
		w_p = 0.334
		w_m = 0.333

	var primary: BiomeType = BiomeType.FOREST
	if w_p >= w_f and w_p >= w_m:
		primary = BiomeType.PLAINS
	elif w_m >= w_f and w_m >= w_p:
		primary = BiomeType.MOUNTAINS

	return {
		"primary": primary,
		"weights": { BiomeType.FOREST: w_f, BiomeType.PLAINS: w_p, BiomeType.MOUNTAINS: w_m },
		"is_sanctuary": dist <= PORTAL_CLEAR_RADIUS,
		"warped_angle": angle
	}

## Calculates physical terrain elevation.
## Returns continuous height before block quantization.
static func sample_height(x: float, z: float, seed_val: int) -> float:
	var dist: float = Vector2(x, z).length()
	if dist <= PORTAL_CLEAR_RADIUS:
		return 0.0

	var weights_info: Dictionary = sample_biome_weights(x, z, seed_val)
	var w: Dictionary = weights_info["weights"]
	var wf: float = w[BiomeType.FOREST]
	var wp: float = w[BiomeType.PLAINS]
	var wm: float = w[BiomeType.MOUNTAINS]
	var warped_angle: float = weights_info.get("warped_angle", atan2(z, x))

	# Elevation noise generators (cached)
	var noise_broad: FastNoiseLite = _get_broad_noise(seed_val)
	var noise_hills: FastNoiseLite = _get_hills_noise(seed_val)

	var broad_val: float = (noise_broad.get_noise_2d(x, z) + 1.0) * 0.5  # 0..1
	var hills_val: float = (noise_hills.get_noise_2d(x, z) + 1.0) * 0.5  # 0..1

	# 1. Forest height: 0..10 blocks, broad rolling swells
	var h_forest: float = clampf((broad_val * 0.7 + hills_val * 0.3) * 9.5, 0.0, 9.5)

	# 2. Plains height: 0..4 blocks, local hills without continuous upward trend
	var h_plains: float = clampf(hills_val * 3.8, 0.0, 3.8)

	# 3. Mountains height:
	# Core mountain sector (central 60 deg) has edge_attenuation = 1.0 with zero lateral derivative.
	# Outer border bands smoothly attenuate to 0 at borders with neighboring biomes.
	var d_mountains: float = angular_distance(warped_angle, ANGLE_MOUNTAINS)
	var edge_t: float = clampf((HALF_SECTOR - d_mountains) / (HALF_SECTOR * 0.45), 0.0, 1.0)
	var edge_attenuation: float = edge_t * edge_t * (3.0 - 2.0 * edge_t)

	var dist_from_sanctuary: float = maxf(0.0, dist - PORTAL_CLEAR_RADIUS)
	# Base climb at ~0.70 blocks per meter, sharing exact base slope across trail and mountain core
	const MOUNTAIN_CLIMB_SLOPE: float = 0.70
	var mountain_growth: float = dist_from_sanctuary * MOUNTAIN_CLIMB_SLOPE * edge_attenuation

	# Natural ridge variations
	var raw_variation: float = (broad_val * 0.6 + hills_val * 0.4) * 3.5 * edge_attenuation

	# Mountain climbing trail pass:
	# The trail corridor smoothly attenuates local roughness towards the pass floor
	# across a wide 12m pass, sharing the exact same base elevation so lateral slope is <= 1 everywhere.
	var trail_factor: float = 1.0
	if dist > PORTAL_CLEAR_RADIUS:
		var trail_ang: float = get_trail_angle(dist, seed_val)
		var trail_x: float = dist * cos(trail_ang)
		var trail_z: float = dist * sin(trail_ang)
		var dist_to_trail: float = Vector2(x - trail_x, z - trail_z).length()

		if dist_to_trail <= TRAIL_WIDTH:
			trail_factor = 0.0
		elif dist_to_trail < TRAIL_VALLEY_WIDTH:
			var t: float = (dist_to_trail - TRAIL_WIDTH) / (TRAIL_VALLEY_WIDTH - TRAIL_WIDTH)
			trail_factor = t * t * (3.0 - 2.0 * t)

	var mountain_local_variation: float = raw_variation * trail_factor
	var h_mountains: float = mountain_growth + mountain_local_variation

	# Weighted blend across all 3 biomes
	var final_h: float = h_forest * wf + h_plains * wp + h_mountains * wm

	# Safe blend ramp from Portal sanctuary edge to avoid step right at 6.5m
	if dist < PORTAL_CLEAR_RADIUS + 3.0:
		var ramp: float = (dist - PORTAL_CLEAR_RADIUS) / 3.0
		final_h *= clampf(ramp, 0.0, 1.0)

	return final_h

## Returns discrete integer voxel height.
## Top surface of the ground block is at y = height.
static func get_voxel_height(x: int, z: int, seed_val: int) -> int:
	var raw_h: float = sample_height(float(x), float(z), seed_val)
	return int(roundf(raw_h))

## Returns true if vertical difference between two heights satisfies the <= 1 block rule.
static func is_height_step_walkable(h1: int, h2: int) -> bool:
	return absi(h2 - h1) <= 1

## Returns true if step between two adjacent coordinates satisfies the <= 1 block rule.
static func is_step_walkable(x1: int, z1: int, x2: int, z2: int, seed_val: int) -> bool:
	var h1: int = get_voxel_height(x1, z1, seed_val)
	var h2: int = get_voxel_height(x2, z2, seed_val)
	return is_height_step_walkable(h1, h2)

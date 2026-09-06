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

static func normalize_angle(a: float) -> float:
	var res: float = fposmod(a + PI, TAU) - PI
	return res

static func angular_distance(a: float, b: float) -> float:
	return absf(normalize_angle(a - b))

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
	var warp_noise: FastNoiseLite = FastNoiseLite.new()
	warp_noise.seed = seed_val + 777
	warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	warp_noise.frequency = 0.015

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

	# Elevation noise generators
	var noise_broad: FastNoiseLite = FastNoiseLite.new()
	noise_broad.seed = seed_val + 101
	noise_broad.noise_type = FastNoiseLite.TYPE_PERLIN
	noise_broad.frequency = 0.02

	var noise_hills: FastNoiseLite = FastNoiseLite.new()
	noise_hills.seed = seed_val + 202
	noise_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise_hills.frequency = 0.04

	var broad_val: float = (noise_broad.get_noise_2d(x, z) + 1.0) * 0.5  # 0..1
	var hills_val: float = (noise_hills.get_noise_2d(x, z) + 1.0) * 0.5  # 0..1

	# 1. Forest height: 0..10 blocks, broad rolling swells
	var h_forest: float = clampf((broad_val * 0.7 + hills_val * 0.3) * 9.5, 0.0, 9.5)

	# 2. Plains height: 0..4 blocks, local hills without continuous upward trend
	var h_plains: float = clampf(hills_val * 3.8, 0.0, 3.8)

	# 3. Mountains height:
	# Base potential height increases with distance into mountain sector.
	# Mountain cross-section smoothly attenuates to 0 at borders with neighboring biomes.
	var d_mountains: float = angular_distance(warped_angle, ANGLE_MOUNTAINS)
	var edge_attenuation: float = clampf(1.0 - (d_mountains / HALF_SECTOR), 0.0, 1.0)
	# Smooth cubic hermite curve to ensure 0 derivative at the border
	edge_attenuation = edge_attenuation * edge_attenuation * (3.0 - 2.0 * edge_attenuation)

	var dist_from_sanctuary: float = maxf(0.0, dist - PORTAL_CLEAR_RADIUS)
	# Climbs at ~0.72 blocks per meter away from portal, scaling smoothly with edge attenuation
	var mountain_growth: float = dist_from_sanctuary * 0.72 * edge_attenuation

	# Natural ridge variations
	var ridge_noise: FastNoiseLite = FastNoiseLite.new()
	ridge_noise.seed = seed_val + 303
	ridge_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	ridge_noise.frequency = 0.025
	var ridge_val: float = absf(ridge_noise.get_noise_2d(x, z)) * 2.0  # 0..2
	var mountain_local_variation: float = (broad_val * 0.5 + hills_val * 0.3 + ridge_val * 0.2) * (8.0 + dist_from_sanctuary * 0.15) * edge_attenuation

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

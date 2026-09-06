extends RefCounted
class_name ResourceDistribution

## ResourceDistribution: Authoritative tables and deterministic selection
## for resource types, attempt weights, and free pickup vs full deposit classification.

enum ResourceType {
	NONE = 0,
	WOOD = 1,
	STONE = 2,
	IRON = 3,
	MAGIC_STONE = 4
}

enum DepositForm {
	NONE = 0,
	FREE_PICKUP = 1,  # 1-3 units, non-solid, interact directly
	FULL_DEPOSIT = 2  # Solid obstacle, mined/chopped
}

# Weight tables per biome / height condition as specified in Issue #18
# Tables specify cumulative thresholds for a normalized roll in [0.0, 1.0)
const FOREST_WEIGHTS: Dictionary = {
	ResourceType.WOOD: 0.85,
	ResourceType.STONE: 0.14,
	ResourceType.IRON: 0.01,
	ResourceType.NONE: 0.00,
	ResourceType.MAGIC_STONE: 0.00
}

const PLAINS_WEIGHTS: Dictionary = {
	ResourceType.WOOD: 0.20,
	ResourceType.STONE: 0.10,
	ResourceType.MAGIC_STONE: 0.02,
	ResourceType.NONE: 0.68,
	ResourceType.IRON: 0.00
}

const LOW_MOUNTAINS_WEIGHTS: Dictionary = {
	ResourceType.STONE: 0.80,
	ResourceType.WOOD: 0.05,
	ResourceType.IRON: 0.03,
	ResourceType.NONE: 0.12,
	ResourceType.MAGIC_STONE: 0.00
}

const HIGH_MOUNTAINS_WEIGHTS: Dictionary = {
	ResourceType.STONE: 0.80,
	ResourceType.WOOD: 0.02,
	ResourceType.IRON: 0.15,
	ResourceType.NONE: 0.03,
	ResourceType.MAGIC_STONE: 0.00
}

## Returns the authoritative resource weight dictionary for the given biome and height.
static func get_weights(biome: BiomeSystem.BiomeType, height: float) -> Dictionary:
	match biome:
		BiomeSystem.BiomeType.FOREST:
			return FOREST_WEIGHTS
		BiomeSystem.BiomeType.PLAINS:
			return PLAINS_WEIGHTS
		BiomeSystem.BiomeType.MOUNTAINS:
			if height < 50.0:
				return LOW_MOUNTAINS_WEIGHTS
			else:
				return HIGH_MOUNTAINS_WEIGHTS
		_:
			return PLAINS_WEIGHTS

## Deterministically selects a ResourceType based on a roll in [0.0, 1.0).
static func roll_resource_type(biome: BiomeSystem.BiomeType, height: float, roll: float) -> ResourceType:
	var weights: Dictionary = get_weights(biome, height)
	var accumulated: float = 0.0
	var clamped_roll: float = clampf(roll, 0.0, 0.999999)

	for res_type: ResourceType in [
		ResourceType.WOOD,
		ResourceType.STONE,
		ResourceType.IRON,
		ResourceType.MAGIC_STONE,
		ResourceType.NONE
	]:
		var w: float = weights.get(res_type, 0.0)
		accumulated += w
		if clamped_roll < accumulated and w > 0.0:
			return res_type

	return ResourceType.NONE

## Blended roll across biome weights: P(res) = sum(w_b * P_b(res))
static func roll_blended_resource_type(biome_weights: Dictionary, height: float, roll: float) -> ResourceType:
	var accumulated: float = 0.0
	var clamped_roll: float = clampf(roll, 0.0, 0.999999)

	var res_order: Array[ResourceType] = [
		ResourceType.WOOD,
		ResourceType.STONE,
		ResourceType.IRON,
		ResourceType.MAGIC_STONE,
		ResourceType.NONE
	]

	for res_type: ResourceType in res_order:
		var p_res: float = 0.0
		for b: BiomeSystem.BiomeType in biome_weights.keys():
			var w_biome: float = biome_weights[b]
			if w_biome > 0.0:
				var table: Dictionary = get_weights(b, height)
				p_res += w_biome * table.get(res_type, 0.0)

		accumulated += p_res
		if clamped_roll < accumulated and p_res > 0.0:
			return res_type

	return ResourceType.NONE


## Resolves whether a rolled resource spawns as a free pickup or full deposit,
## its yield amount, and visual sub-type.
static func resolve_spawn_details(
	res_type: ResourceType,
	biome_or_weights,
	height: float,
	form_roll: float,
	variation_roll: float
) -> Dictionary:
	if res_type == ResourceType.NONE:
		return {
			"resource_type": ResourceType.NONE,
			"deposit_form": DepositForm.NONE,
			"yield_amount": 0,
			"variation_index": 0,
			"solid": false
		}

	var w_mountain: float = 0.0
	if biome_or_weights is Dictionary:
		w_mountain = biome_or_weights.get(BiomeSystem.BiomeType.MOUNTAINS, 0.0)
	elif biome_or_weights == BiomeSystem.BiomeType.MOUNTAINS:
		w_mountain = 1.0

	# Magic stones only exist as free pickups (1-3 units)
	if res_type == ResourceType.MAGIC_STONE:
		var amount: int = 1 + int(variation_roll * 3.0)
		amount = clampi(amount, 1, 3)
		return {
			"resource_type": ResourceType.MAGIC_STONE,
			"deposit_form": DepositForm.FREE_PICKUP,
			"yield_amount": amount,
			"variation_index": int(variation_roll * 3.0) % 3,
			"solid": false
		}

	# For Wood, Stone, and Iron: ~30% are free loose resources, ~70% are full deposits
	var is_free: bool = form_roll < 0.30

	if is_free:
		var free_amount: int = 1 + int(variation_roll * 3.0)
		free_amount = clampi(free_amount, 1, 3)
		return {
			"resource_type": res_type,
			"deposit_form": DepositForm.FREE_PICKUP,
			"yield_amount": free_amount,
			"variation_index": int(variation_roll * 4.0) % 4,
			"solid": false
		}

	# Full deposits (solid obstacles)
	var deposit_yield: int = 4
	var tier: int = 1 # 0: small, 1: medium, 2: large
	var var_idx: int = int(variation_roll * 4.0) % 4

	if res_type == ResourceType.WOOD:
		# In mountains: NO big trees allowed, only small/shrub variations!
		# In transition zone, chance of mountain shrub smoothly increases with w_mountain.
		var is_mountain_tree: bool = (variation_roll < w_mountain)
		if is_mountain_tree:
			var_idx = 3 + (int(variation_roll * 100.0) % 2) # 3: young oak, 4: shrub
			deposit_yield = 3
		else:
			var_idx = int(variation_roll * 5.0) % 5 # 0..4 oak variants
			deposit_yield = 4
	elif res_type == ResourceType.STONE:
		if variation_roll < 0.35:
			tier = 0 # small (yield 3)
			deposit_yield = 3
		elif variation_roll < 0.75:
			tier = 1 # medium (yield 5)
			deposit_yield = 5
		else:
			tier = 2 # large (yield 8)
			deposit_yield = 8
	elif res_type == ResourceType.IRON:
		if variation_roll < 0.40:
			tier = 0 # small (yield 2)
			deposit_yield = 2
		elif variation_roll < 0.80:
			tier = 1 # medium (yield 4)
			deposit_yield = 4
		else:
			tier = 2 # large (yield 6)
			deposit_yield = 6

	return {
		"resource_type": res_type,
		"deposit_form": DepositForm.FULL_DEPOSIT,
		"yield_amount": deposit_yield,
		"tier": tier,
		"variation_index": var_idx,
		"solid": true
	}

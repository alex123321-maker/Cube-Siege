extends GutTest

const ResourceDist = preload("res://scripts/world/resource_distribution.gd")
const BiomeSystem = preload("res://scripts/world/biome_system.gd")

func test_forest_resource_table_probabilities() -> void:
	var counts = {
		ResourceDist.ResourceType.WOOD: 0,
		ResourceDist.ResourceType.STONE: 0,
		ResourceDist.ResourceType.IRON: 0,
		ResourceDist.ResourceType.MAGIC_STONE: 0,
		ResourceDist.ResourceType.NONE: 0
	}
	var total: int = 1000
	for i in range(total):
		var roll: float = float(i) / float(total)
		var res: ResourceDist.ResourceType = ResourceDist.roll_resource_type(BiomeSystem.BiomeType.FOREST, 5.0, roll)
		counts[res] += 1

	# Forest weights: 85 Wood, 14 Stone, 1 Iron
	assert_true(counts[ResourceDist.ResourceType.WOOD] >= 800, "Forest must heavily prioritize Wood (~85%%), got %d" % counts[ResourceDist.ResourceType.WOOD])
	assert_true(counts[ResourceDist.ResourceType.STONE] >= 100, "Forest must have some Stone (~14%%), got %d" % counts[ResourceDist.ResourceType.STONE])
	assert_true(counts[ResourceDist.ResourceType.IRON] >= 5, "Forest must have rare Iron (~1%%), got %d" % counts[ResourceDist.ResourceType.IRON])
	assert_eq(counts[ResourceDist.ResourceType.MAGIC_STONE], 0, "Forest has no native Magic Stone deposits")

func test_plains_resource_table_probabilities() -> void:
	var counts = {
		ResourceDist.ResourceType.WOOD: 0,
		ResourceDist.ResourceType.STONE: 0,
		ResourceDist.ResourceType.IRON: 0,
		ResourceDist.ResourceType.MAGIC_STONE: 0,
		ResourceDist.ResourceType.NONE: 0
	}
	var total: int = 1000
	for i in range(total):
		var roll: float = float(i) / float(total)
		var res: ResourceDist.ResourceType = ResourceDist.roll_resource_type(BiomeSystem.BiomeType.PLAINS, 2.0, roll)
		counts[res] += 1

	# Plains weights: 20 Wood, 10 Stone, 2 Iron, 68 None/Magic
	assert_true(counts[ResourceDist.ResourceType.NONE] >= 600, "Plains has mostly open ground (~68%%), got %d" % counts[ResourceDist.ResourceType.NONE])
	assert_true(counts[ResourceDist.ResourceType.WOOD] >= 150, "Plains has scattered Wood (~20%%), got %d" % counts[ResourceDist.ResourceType.WOOD])
	assert_true(counts[ResourceDist.ResourceType.STONE] >= 80, "Plains has scattered Stone (~10%%), got %d" % counts[ResourceDist.ResourceType.STONE])

func test_mountains_low_vs_high_elevation_iron_increase() -> void:
	var total: int = 1000
	var low_iron: int = 0
	var high_iron: int = 0

	for i in range(total):
		var roll: float = float(i) / float(total)
		var res_low = ResourceDist.roll_resource_type(BiomeSystem.BiomeType.MOUNTAINS, 20.0, roll)
		if res_low == ResourceDist.ResourceType.IRON:
			low_iron += 1

		var res_high = ResourceDist.roll_resource_type(BiomeSystem.BiomeType.MOUNTAINS, 75.0, roll)
		if res_high == ResourceDist.ResourceType.IRON:
			high_iron += 1

	# Low Mountains: 5% Iron, High Mountains (>=50): 15% Iron
	assert_true(high_iron > low_iron * 2, "High mountains (>=50) should have significantly more Iron deposits (low=%d, high=%d)" % [low_iron, high_iron])

func test_magic_stone_is_exclusively_free_pickup() -> void:
	for i in range(20):
		var form_roll: float = float(i) / 20.0
		var var_roll: float = 0.5
		var details = ResourceDist.resolve_spawn_details(
			ResourceDist.ResourceType.MAGIC_STONE,
			BiomeSystem.BiomeType.MOUNTAINS,
			60.0,
			form_roll,
			var_roll
		)
		assert_eq(details["deposit_form"], ResourceDist.DepositForm.FREE_PICKUP, "Magic Stone must ALWAYS be a free pickup")
		assert_true(details["yield_amount"] >= 1 and details["yield_amount"] <= 3, "Magic Stone yield must be 1..3, got %d" % details["yield_amount"])

func test_mountain_wood_has_no_big_trees() -> void:
	# Mountains must only generate young or shrub trees (variations 3 or 4), no big trees (0, 1, 2)
	for i in range(50):
		var form_roll: float = 0.9 # Force full deposit
		var var_roll: float = float(i) / 50.0
		var details = ResourceDist.resolve_spawn_details(
			ResourceDist.ResourceType.WOOD,
			BiomeSystem.BiomeType.MOUNTAINS,
			45.0,
			form_roll,
			var_roll
		)
		if details["deposit_form"] == ResourceDist.DepositForm.FULL_DEPOSIT:
			var v: int = details["variation_index"]
			assert_true(v == 3 or v == 4, "Mountain trees must be small/young shrubs (variation 3 or 4), got %d" % v)

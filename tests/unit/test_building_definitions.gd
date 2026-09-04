extends GutTest

const BuildingDefinition = preload("res://scripts/resources/building_definition.gd")
const CharacterDefinition = preload("res://scripts/resources/character_definition.gd")

func test_building_catalog_costs_match_specification() -> void:
	var cat = BuildingDefinition.get_catalog()
	assert_true(cat.has(1), "Wood wall (id=1) must exist")
	assert_true(cat.has(2), "Floor spikes (id=2) must exist")
	assert_true(cat.has(3), "Archer tower (id=3) must exist")
	assert_true(cat.has(4), "Iron wall (id=4) must exist")
	assert_true(cat.has(5), "Ballista (id=5) must exist")

	var wood_wall: BuildingDefinition = cat[1]
	assert_eq(wood_wall.wood_cost, 4, "Wood wall cost 4 Wood")
	assert_eq(wood_wall.stone_cost, 0, "Wood wall cost 0 Stone")
	assert_eq(wood_wall.iron_cost, 0, "Wood wall cost 0 Iron")

	var spikes: BuildingDefinition = cat[2]
	assert_eq(spikes.wood_cost, 2, "Spikes cost 2 Wood")
	assert_eq(spikes.stone_cost, 1, "Spikes cost 1 Stone")

	var tower: BuildingDefinition = cat[3]
	assert_eq(tower.wood_cost, 6, "Archer tower cost 6 Wood")
	assert_eq(tower.stone_cost, 2, "Archer tower cost 2 Stone")

	var iron_wall: BuildingDefinition = cat[4]
	assert_eq(iron_wall.stone_cost, 2, "Iron wall cost 2 Stone")
	assert_eq(iron_wall.iron_cost, 2, "Iron wall cost 2 Iron")

	var ballista: BuildingDefinition = cat[5]
	assert_eq(ballista.stone_cost, 4, "Ballista cost 4 Stone")
	assert_eq(ballista.iron_cost, 4, "Ballista cost 4 Iron")

func test_character_catalog_classes_match_specification() -> void:
	var warrior = CharacterDefinition.get_definition(0)
	assert_not_null(warrior)
	assert_eq(warrior.class_id, 0)
	assert_eq(warrior.character_name, "Воин")
	assert_eq(warrior.base_health, 100.0)

	var archer = CharacterDefinition.get_definition(1)
	assert_not_null(archer)
	assert_eq(archer.class_id, 1)
	assert_eq(archer.character_name, "Лучник")
	assert_eq(archer.base_health, 80.0)

	var eng = CharacterDefinition.get_definition(2)
	assert_not_null(eng)
	assert_eq(eng.class_id, 2)
	assert_eq(eng.character_name, "Инженер")
	assert_eq(eng.base_health, 110.0)

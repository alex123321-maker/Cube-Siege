extends GutTest

const Scatter = preload("res://scripts/world/environment_scatter.gd")

func test_cell_placement_is_deterministic_for_world_seed() -> void:
	var weights: Dictionary = {
		BiomeSystem.BiomeType.FOREST: 0.1,
		BiomeSystem.BiomeType.PLAINS: 0.9,
		BiomeSystem.BiomeType.MOUNTAINS: 0.0,
	}
	var first: StringName = Scatter.choose_prop(41, 57, 1337, 91827, weights, 2.0, Scatter.DensityLevel.MEDIUM, false)
	var second: StringName = Scatter.choose_prop(41, 57, 1337, 91827, weights, 2.0, Scatter.DensityLevel.MEDIUM, false)
	assert_eq(first, second, "Same seed and cell must choose the same prop")
	assert_eq(
		Scatter.make_instance_transform(first, Vector3(41.5, 2.0, 57.5), 91827),
		Scatter.make_instance_transform(first, Vector3(41.5, 2.0, 57.5), 91827),
		"Rotation and scale variation must also be deterministic"
	)

func test_density_levels_are_ordered_and_medium_is_production_default() -> void:
	var weights: Dictionary = {
		BiomeSystem.BiomeType.FOREST: 0.0,
		BiomeSystem.BiomeType.PLAINS: 1.0,
		BiomeSystem.BiomeType.MOUNTAINS: 0.0,
	}
	var counts: Dictionary = {Scatter.DensityLevel.LOW: 0, Scatter.DensityLevel.MEDIUM: 0, Scatter.DensityLevel.HIGH: 0}
	for z: int in range(64):
		for x: int in range(64):
			for level: int in [Scatter.DensityLevel.LOW, Scatter.DensityLevel.MEDIUM, Scatter.DensityLevel.HIGH]:
				if not Scatter.choose_prop(x, z, 7123, x * 1009 ^ z * 9176, weights, 1.0, level, false).is_empty():
					counts[level] += 1
	assert_gt(counts[Scatter.DensityLevel.LOW], 0)
	assert_gt(counts[Scatter.DensityLevel.MEDIUM], counts[Scatter.DensityLevel.LOW])
	assert_gt(counts[Scatter.DensityLevel.HIGH], counts[Scatter.DensityLevel.MEDIUM])
	assert_eq(Scatter.PRODUCTION_DENSITY, Scatter.DensityLevel.MEDIUM)

func test_bare_high_mountains_never_receive_grass_or_flowers() -> void:
	var mountain_weights: Dictionary = {
		BiomeSystem.BiomeType.FOREST: 0.0,
		BiomeSystem.BiomeType.PLAINS: 0.0,
		BiomeSystem.BiomeType.MOUNTAINS: 1.0,
	}
	for z: int in range(32):
		for x: int in range(32):
			var prop_id: StringName = Scatter.choose_prop(x, z, 19, x * 31 ^ z * 79, mountain_weights, 30.0, Scatter.DensityLevel.HIGH, false)
			assert_false(String(prop_id).begins_with("grass_"), "Bare high cliffs should not receive grass")
			assert_false(String(prop_id).begins_with("flower_"), "Bare high cliffs should not receive flowers")

func test_biome_density_profiles_are_authored_resources() -> void:
	var forest: EnvironmentScatterProfile = Scatter.BIOME_PROFILES[BiomeSystem.BiomeType.FOREST]
	var plains: EnvironmentScatterProfile = Scatter.BIOME_PROFILES[BiomeSystem.BiomeType.PLAINS]
	var mountains: EnvironmentScatterProfile = Scatter.BIOME_PROFILES[BiomeSystem.BiomeType.MOUNTAINS]
	assert_gt(forest.grass_rate, 0.0)
	assert_gt(plains.flower_rate, forest.flower_rate)
	assert_gt(mountains.debris_rate, plains.debris_rate)
	assert_eq(mountains.flower_rate, 0.0)

func test_dressing_pack_contains_all_authored_props() -> void:
	assert_eq(Scatter.PROP_PATHS.size(), 19)
	for prop_path: String in Scatter.PROP_PATHS.values():
		assert_true(ResourceLoader.exists(prop_path), "Missing authored scatter asset: %s" % prop_path)

func test_scatter_batch_has_no_collision_nodes() -> void:
	var instances: Dictionary = {
		&"grass_tuft_small_01": [Transform3D(Basis.IDENTITY, Vector3(1.5, 0.0, 2.5))],
	}
	var nodes: Array[Node] = Scatter.create_multimesh_nodes(instances)
	assert_eq(nodes.size(), 1)
	assert_true(nodes[0] is MultiMeshInstance3D)
	assert_eq(nodes[0].find_children("*", "CollisionObject3D", true, false).size(), 0)
	assert_eq(nodes[0].find_children("*", "CollisionShape3D", true, false).size(), 0)
	nodes[0].free()

func test_chunk_unload_cleans_batches_and_reload_is_deterministic() -> void:
	var map_scene: PackedScene = load("res://scenes/map_generator.tscn") as PackedScene
	var generator: MapGenerator = map_scene.instantiate() as MapGenerator
	generator.random_seed = false
	generator.custom_seed = 1337
	add_child_autoqfree(generator)
	var target_coord: Vector2i = Vector2i.ZERO
	var initial_nodes: Array[Node] = []
	var initial_instances: int = 0
	for coord_value: Variant in generator.chunk_resources:
		var chunk_nodes: Array = generator.chunk_resources[coord_value]
		var chunk_instances: int = 0
		var batches: Array[Node] = []
		for node: Node in chunk_nodes:
			if node is MultiMeshInstance3D and String(node.name).begins_with("Scatter_"):
				batches.append(node)
				chunk_instances += (node as MultiMeshInstance3D).multimesh.instance_count
		if chunk_instances > 0:
			target_coord = coord_value
			initial_nodes = batches
			initial_instances = chunk_instances
			break
	assert_gt(initial_instances, 0, "Seeded map should have at least one scatter batch")
	generator.unload_chunk(target_coord.x, target_coord.y)
	await get_tree().process_frame
	for old_node: Node in initial_nodes:
		assert_false(is_instance_valid(old_node), "Chunk unload must free its MultiMesh nodes")
	generator.load_chunk(target_coord.x, target_coord.y)
	var reloaded_nodes: Array[Node] = generator.chunk_resources[target_coord]
	var reloaded_instances: int = 0
	for node: Node in reloaded_nodes:
		if node is MultiMeshInstance3D and String(node.name).begins_with("Scatter_"):
			reloaded_instances += (node as MultiMeshInstance3D).multimesh.instance_count
	assert_eq(reloaded_instances, initial_instances, "Reloading the same seed and chunk must restore the same scatter")

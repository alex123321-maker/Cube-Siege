extends GutTest

const RESOURCE_TREE_SCENE = preload("res://scenes/resource_tree.tscn")
const RESOURCE_STONE_SCENE = preload("res://scenes/resource_stone.tscn")
const RESOURCE_IRON_SCENE = preload("res://scenes/resource_iron.tscn")
const MAP_GENERATOR_SCRIPT = preload("res://scripts/map_generator.gd")

func test_all_tree_variations_use_authored_models_and_fit_bounds() -> void:
	assert_eq(ResourceTree.TREE_VARIANTS.size(), 5)
	for variation_index in range(ResourceTree.TREE_VARIANTS.size()):
		var tree: ResourceTree = RESOURCE_TREE_SCENE.instantiate() as ResourceTree
		tree.configure_tree(variation_index, 4)
		add_child_autoqfree(tree)

		assert_not_null(tree.trunk, "Tree variation %d must have an imported bark mesh" % variation_index)
		assert_eq(tree.foliage_meshes.size(), 2, "Tree variation %d must have both foliage layers" % variation_index)
		assert_true(tree.foliage_materials.size() >= 2, "Tree variation %d must have per-instance foliage materials" % variation_index)
		assert_not_null((tree.hurtbox as HurtboxArea).mesh_to_flash, "Tree variation %d must wire its damage flash target" % variation_index)
		assert_true(tree.trunk.name.begins_with("tree_oak_var_%d_" % variation_index))
		for foliage_mesh in tree.foliage_meshes:
			assert_true(foliage_mesh.name.begins_with("tree_oak_var_%d_" % variation_index))
		assert_almost_eq(tree.tree_hurtbox_shape.shape.size.x, tree._tree_bounds.size.x, 0.01)
		assert_almost_eq(tree.tree_hurtbox_shape.shape.size.y, tree._tree_bounds.size.y, 0.01)
		assert_almost_eq(tree.canopy_occlusion_shape.shape.size.x, tree._get_mesh_bounds(tree.foliage_meshes, tree.foliage).size.x, 0.01)
		var trunk_bounds: AABB = tree._get_mesh_bounds([tree.trunk], tree)
		assert_almost_eq(tree.body_collision_shape.shape.size.y, trunk_bounds.size.y, 0.01, "Tree %d solid collision must fit its trunk height" % variation_index)
		assert_almost_eq(tree.body_collision_shape.position.y, trunk_bounds.position.y + trunk_bounds.size.y * 0.5, 0.01)
		assert_eq(tree.max_health, 60.0, "Visual integration must preserve tree HP")
		assert_eq(tree.wood_yield, 4, "Visual integration must preserve configured tree yield")

func test_adult_canopies_are_fadeable_and_ray_occluders() -> void:
	for variation_index in range(3):
		var tree: ResourceTree = RESOURCE_TREE_SCENE.instantiate() as ResourceTree
		tree.configure_tree(variation_index)
		add_child_autoqfree(tree)
		tree.global_position = Vector3(variation_index * 8.0, 0.0, 0.0)
		await get_tree().physics_frame

		var bounds: AABB = tree._get_mesh_bounds(tree.foliage_meshes, tree.foliage)
		var center: Vector3 = tree.foliage.to_global(bounds.position + bounds.size * 0.5)
		var query := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 10.0, center - Vector3.UP * 10.0, 16)
		query.collide_with_areas = true
		query.collide_with_bodies = false
		var hit: Dictionary = get_viewport().world_3d.direct_space_state.intersect_ray(query)
		assert_eq(hit.get("collider"), tree.canopy_occlusion_area, "Adult tree %d must occlude the camera through its canopy bounds" % variation_index)

		tree.set_transparency(0.6)
		for material in tree.foliage_materials:
			assert_almost_eq(material.albedo_color.a, 0.4, 0.01)
		tree.set_transparency(0.0)

func test_six_rock_variations_use_distinct_authored_models_and_matching_shapes() -> void:
	assert_eq(ResourceRock.ROCK_VARIANTS.size(), 6)
	for variation_index in range(ResourceRock.ROCK_VARIANTS.size()):
		var rock: ResourceRock = RESOURCE_STONE_SCENE.instantiate() as ResourceRock
		rock.configure_rock(ResourceRock.RockType.STONE, 6, 1, variation_index)
		add_child_autoqfree(rock)

		assert_not_null(rock.rock_asset, "Rock variation %d must instantiate a production Stage 1 model" % variation_index)
		assert_eq(rock.rock_asset.name, "Stage1RockVariant%d" % variation_index)
		assert_eq(rock.rock_mesh_instances.size(), 4)
		assert_not_null((rock.hurtbox as HurtboxArea).mesh_to_flash, "Rock variation %d must wire its damage flash target" % variation_index)
		for mesh_instance in rock.rock_mesh_instances:
			assert_true(mesh_instance.name.begins_with("destructible_rock_stage_1_var_%d_" % (variation_index + 1)))
		var expected_bounds: AABB = rock._scale_aabb(rock.rock_bounds, rock.base_scale)
		assert_almost_eq(rock.body_collision_shape.shape.size.x, expected_bounds.size.x, 0.01)
		assert_almost_eq(rock.hurtbox_shape.shape.size.y, expected_bounds.size.y, 0.01)
		assert_eq(rock.max_health, 85.0, "Visual integration must preserve configured stone HP")
		assert_eq(rock.resource_yield, 6, "Visual integration must preserve configured stone yield")

func test_resource_collision_shapes_are_instance_local() -> void:
	var small_stone: ResourceRock = RESOURCE_STONE_SCENE.instantiate() as ResourceRock
	small_stone.configure_rock(ResourceRock.RockType.STONE, 4, 0, 1)
	add_child_autoqfree(small_stone)
	var original_stone_body_size: Vector3 = small_stone.body_collision_shape.shape.size
	var original_stone_body_position: Vector3 = small_stone.body_collision_shape.position
	var original_stone_hurt_size: Vector3 = small_stone.hurtbox_shape.shape.size
	var original_stone_hurt_position: Vector3 = small_stone.hurtbox_shape.position

	var large_stone: ResourceRock = RESOURCE_STONE_SCENE.instantiate() as ResourceRock
	large_stone.configure_rock(ResourceRock.RockType.STONE, 8, 2, 5)
	add_child_autoqfree(large_stone)
	assert_ne(small_stone.body_collision_shape.shape.get_instance_id(), large_stone.body_collision_shape.shape.get_instance_id())
	assert_ne(small_stone.hurtbox_shape.shape.get_instance_id(), large_stone.hurtbox_shape.shape.get_instance_id())
	assert_eq(small_stone.body_collision_shape.shape.size, original_stone_body_size)
	assert_eq(small_stone.body_collision_shape.position, original_stone_body_position)
	assert_eq(small_stone.hurtbox_shape.shape.size, original_stone_hurt_size)
	assert_eq(small_stone.hurtbox_shape.position, original_stone_hurt_position)

	var iron: ResourceRock = RESOURCE_IRON_SCENE.instantiate() as ResourceRock
	iron.configure_rock(ResourceRock.RockType.IRON, 2, 1, 3)
	add_child_autoqfree(iron)
	assert_ne(large_stone.body_collision_shape.shape.get_instance_id(), iron.body_collision_shape.shape.get_instance_id())
	assert_ne(large_stone.hurtbox_shape.shape.get_instance_id(), iron.hurtbox_shape.shape.get_instance_id())
	assert_eq(small_stone.body_collision_shape.shape.size, original_stone_body_size)
	assert_eq(small_stone.hurtbox_shape.shape.size, original_stone_hurt_size)

	var shrub: ResourceTree = RESOURCE_TREE_SCENE.instantiate() as ResourceTree
	shrub.configure_tree(4)
	add_child_autoqfree(shrub)
	var shrub_body_size: Vector3 = shrub.body_collision_shape.shape.size
	var shrub_body_position: Vector3 = shrub.body_collision_shape.position
	var shrub_hurt_size: Vector3 = shrub.tree_hurtbox_shape.shape.size
	var shrub_hurt_position: Vector3 = shrub.tree_hurtbox_shape.position

	var tall_tree: ResourceTree = RESOURCE_TREE_SCENE.instantiate() as ResourceTree
	tall_tree.configure_tree(1)
	add_child_autoqfree(tall_tree)
	assert_ne(shrub.body_collision_shape.shape.get_instance_id(), tall_tree.body_collision_shape.shape.get_instance_id())
	assert_ne(shrub.tree_hurtbox_shape.shape.get_instance_id(), tall_tree.tree_hurtbox_shape.shape.get_instance_id())
	assert_eq(shrub.body_collision_shape.shape.size, shrub_body_size)
	assert_eq(shrub.body_collision_shape.position, shrub_body_position)
	assert_eq(shrub.tree_hurtbox_shape.shape.size, shrub_hurt_size)
	assert_eq(shrub.tree_hurtbox_shape.position, shrub_hurt_position)

func test_generated_full_deposits_reach_all_rock_assets() -> void:
	var generator: MapGenerator = MAP_GENERATOR_SCRIPT.new() as MapGenerator
	generator.random_seed = false
	generator.custom_seed = 27
	generator.load_radius_chunks = 0
	generator.unload_radius_chunks = 0
	add_child_autoqfree(generator)
	var seen_variants: Dictionary = {}
	for spawned_node in generator.resources_container.get_children():
		var spawned_rock: ResourceRock = spawned_node as ResourceRock
		if spawned_rock:
			seen_variants[spawned_rock.variation_index] = true
			assert_not_null(spawned_rock.rock_asset, "Normally generated rocks must instantiate their authored visual")
	for chunk_z in range(-8, 9):
		for chunk_x in range(-8, 9):
			var spawned_nodes: Array[Node] = []
			generator._spawn_chunk_resources(chunk_x, chunk_z, spawned_nodes)
			for spawned_node in spawned_nodes:
				var rock: ResourceRock = spawned_node as ResourceRock
				if rock:
					seen_variants[rock.variation_index] = true
					assert_not_null(rock.rock_asset, "Normally generated rocks must instantiate their authored visual")
			if seen_variants.size() == ResourceRock.ROCK_VARIANTS.size():
				break
		if seen_variants.size() == ResourceRock.ROCK_VARIANTS.size():
			break
	assert_eq(seen_variants.size(), ResourceRock.ROCK_VARIANTS.size(), "Normal deterministic chunk generation must reach all six rock visuals")

func test_focused_broken_rock_keeps_its_broken_scale() -> void:
	var rock: ResourceRock = RESOURCE_STONE_SCENE.instantiate() as ResourceRock
	rock.configure_rock(ResourceRock.RockType.STONE, 4, 1, 0)
	add_child_autoqfree(rock)
	rock.break_rock()
	await get_tree().create_timer(0.2).timeout
	assert_eq(rock.rock_mesh.scale, rock.broken_scale, "Break animation must settle on the broken scale")
	rock.set_focused(true)
	assert_eq(rock.rock_mesh.scale, rock.broken_scale * 1.08, "Focusing must emphasize the broken pickup scale")
	rock.set_focused(false)
	assert_eq(rock.rock_mesh.scale, rock.broken_scale, "Unfocusing must restore the broken pickup scale")

func test_rock_health_maps_evenly_to_five_authored_stages() -> void:
	assert_eq(ResourceRock.visual_stage_for_health(100.0, 100.0), 1)
	assert_eq(ResourceRock.visual_stage_for_health(80.0, 100.0), 2)
	assert_eq(ResourceRock.visual_stage_for_health(60.0, 100.0), 3)
	assert_eq(ResourceRock.visual_stage_for_health(40.0, 100.0), 4)
	assert_eq(ResourceRock.visual_stage_for_health(20.0, 100.0), 5)
	assert_eq(ResourceRock.visual_stage_for_health(0.0, 100.0), 5)
	assert_eq(ResourceRock.visual_stage_for_health(10.0, 0.0), 5)

func test_rock_stage_pools_are_complete_and_seeded_selection_is_stable() -> void:
	var pools: Array[Array] = [ResourceRock.ROCK_STAGE1_VARIANTS, ResourceRock.ROCK_STAGE2_VARIANTS, ResourceRock.ROCK_STAGE3_VARIANTS, ResourceRock.ROCK_STAGE4_VARIANTS, ResourceRock.ROCK_STAGE5_VARIANTS]
	var expected_counts: Array[int] = [6, 3, 3, 2, 3]
	for stage_index in range(pools.size()):
		assert_eq(pools[stage_index].size(), expected_counts[stage_index])
		for seed_value in range(12):
			var selected: int = ResourceRock.visual_variant_for_seed(seed_value, stage_index + 1)
			assert_true(selected >= 0 and selected < expected_counts[stage_index])
			assert_eq(selected, ResourceRock.visual_variant_for_seed(seed_value, stage_index + 1), "Variant must repeat for a fixed cell seed")

func test_configured_rock_preserves_explicit_seeds_and_stage_one_variation() -> void:
	for seed_value in [12345, -6, 0]:
		var rock: ResourceRock = RESOURCE_STONE_SCENE.instantiate() as ResourceRock
		rock.configure_rock(ResourceRock.RockType.STONE, 6, 1, 2, seed_value)
		assert_eq(rock.visual_seed, seed_value, "Configured seed %d must be preserved" % seed_value)
		add_child_autoqfree(rock)
		assert_eq(rock.rock_asset.name, "Stage1RockVariant2", "Stage 1 must use the requested variation index")
		rock._set_visual_stage(2)
		assert_eq(rock.rock_asset.name, "Stage2RockVariant%d" % ResourceRock.visual_variant_for_seed(seed_value, 2), "Later stages must use the explicit visual seed")

func test_configure_rock_without_visual_seed_uses_variation_as_compatible_fallback() -> void:
	var rock: ResourceRock = RESOURCE_STONE_SCENE.instantiate() as ResourceRock
	rock.configure_rock(ResourceRock.RockType.STONE, 6, 1, 4)
	assert_eq(rock.visual_seed, 4)
	add_child_autoqfree(rock)
	assert_eq(rock.rock_asset.name, "Stage1RockVariant4")
	rock._set_visual_stage(2)
	assert_eq(rock.rock_asset.name, "Stage2RockVariant%d" % ResourceRock.visual_variant_for_seed(4, 2))

func test_rock_stage_swap_keeps_bottom_center_anchor_and_pickup_contract() -> void:
	var rock: ResourceRock = RESOURCE_STONE_SCENE.instantiate() as ResourceRock
	rock.configure_rock(ResourceRock.RockType.STONE, 6, 1, 2, 12345)
	var rock_container := Node3D.new()
	add_child_autoqfree(rock_container)
	rock_container.add_child(rock)
	var expected_health: float = rock.max_health
	var expected_yield: int = rock.resource_yield
	for stage in range(1, 6):
		rock._set_visual_stage(stage)
		assert_eq(rock.visual_stage, stage)
		assert_eq(rock.rock_mesh.scale, rock.base_scale, "Stage swaps must not scale the authored mesh")
		assert_almost_eq(rock.rock_bounds.position.x + rock.rock_bounds.size.x * 0.5, 0.0, 0.01)
		assert_almost_eq(rock.rock_bounds.position.z + rock.rock_bounds.size.z * 0.5, 0.0, 0.01)
		assert_almost_eq(rock.rock_bounds.position.y, 0.0, 0.01)
	rock._set_visual_stage(1)
	for damage_step in range(1, 5):
		rock._on_damaged(expected_health / 5.0, Vector3.ZERO, "test", null)
		assert_eq(rock.visual_stage, damage_step + 1, "Damage must advance through the health-mapped stage")
		assert_almost_eq(rock.current_health, expected_health * (1.0 - damage_step / 5.0), 0.01)
	assert_eq(rock.max_health, expected_health)
	assert_eq(rock.resource_yield, expected_yield)
	rock._on_damaged(expected_health / 5.0, Vector3.ZERO, "test", null)
	assert_true(rock.is_ready_for_pickup())
	assert_eq(rock.collision_layer, 8)
	assert_eq(rock.collision_mask, 0)
	assert_eq(rock.visual_stage, 5)

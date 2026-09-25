extends GutTest

const RESOURCE_TREE_SCENE = preload("res://scenes/resource_tree.tscn")
const RESOURCE_STONE_SCENE = preload("res://scenes/resource_stone.tscn")

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

extends GutTest

const MapGen = preload("res://scripts/map_generator.gd")
const FreePickup = preload("res://scripts/world/free_resource_pickup.gd")
const ResourceDist = preload("res://scripts/world/resource_distribution.gd")

var map_instance: MapGenerator = null

func before_each() -> void:
	map_instance = MapGen.new()
	map_instance.random_seed = false
	map_instance.custom_seed = 4242
	map_instance.load_radius_chunks = 2 # 5x5 = 25 chunks for fast integration testing
	map_instance.unload_radius_chunks = 3
	add_child_autoqfree(map_instance)

func test_initial_chunk_loading_is_bounded() -> void:
	# 5x5 chunks around center
	var expected_chunks: int = 25
	assert_eq(map_instance.active_chunks.size(), expected_chunks, "Must generate exactly 25 chunks for load_radius=2")
	assert_true(map_instance.active_chunks.has(Vector2i(0, 0)), "Center chunk (0, 0) must be loaded")

func test_chunk_streaming_unloads_distant_and_loads_new() -> void:
	# Move player to chunk (8, 0)
	var new_center: Vector2i = Vector2i(8, 0)
	map_instance.update_player_chunks(new_center)

	assert_false(map_instance.active_chunks.has(Vector2i(0, 0)), "Chunk (0, 0) must be unloaded when player is at (8, 0)")
	assert_true(map_instance.active_chunks.has(Vector2i(8, 0)), "Chunk (8, 0) must now be active")

	# Bounded memory: total active chunks should remain around (2*load_radius + 1)^2
	assert_true(map_instance.active_chunks.size() <= 25, "Active chunk count must remain bounded after movement")

func test_harvest_persistence_across_chunk_unload_and_reload() -> void:
	# Pick a test location in chunk (1, 1)
	var test_coord: Vector3 = Vector3(20, 0, 20)
	map_instance.record_harvest(test_coord)

	# Unload chunk (1, 1)
	map_instance.unload_chunk(1, 1)
	assert_false(map_instance.active_chunks.has(Vector2i(1, 1)), "Chunk (1, 1) should be unloaded")

	# Reload chunk (1, 1)
	map_instance.load_chunk(1, 1)
	assert_true(map_instance.active_chunks.has(Vector2i(1, 1)), "Chunk (1, 1) should be reloaded")

	# Verify harvested cell was remembered in map_instance.harvested_cells
	var voxel_y: int = map_instance.get_voxel_height(int(test_coord.x), int(test_coord.z))
	var key: Vector3i = Vector3i(int(test_coord.x), voxel_y, int(test_coord.z))
	assert_true(map_instance.harvested_cells.has(key), "Harvested cell must be persistently recorded in MapGenerator")

func test_free_resource_pickup_contract() -> void:
	var pickup = FreePickup.new()
	pickup.resource_type = ResourceDist.ResourceType.MAGIC_STONE
	pickup.yield_amount = 2
	add_child_autoqfree(pickup)

	# Layer 4 (Interactable sensor), mask 0 (no solid physics block)
	assert_eq(pickup.collision_layer, 4, "Pickup must be on layer 4 (interactable sensor)")
	assert_eq(pickup.collision_mask, 0, "Pickup must have collision_mask = 0 (non-solid)")
	assert_true(pickup.is_interactable(), "Pickup must be interactable initially")
	assert_true(pickup.is_ready_for_pickup(), "Pickup must be ready for pickup initially")

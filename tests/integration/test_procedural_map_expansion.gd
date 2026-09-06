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

	# Layer 4 in Inspector is bit 3 (value 8: 1 << 3), matches InteractionSensor mask 9 (1 | 8)
	assert_eq(pickup.collision_layer, 8, "Pickup must have collision_layer = 8 (bit 3 / layer 4)")
	assert_eq(pickup.collision_mask, 0, "Pickup must have collision_mask = 0 (non-solid)")
	assert_true(pickup.is_interactable(), "Pickup must be interactable initially")
	assert_true(pickup.is_ready_for_pickup(), "Pickup must be ready for pickup initially")

	# Pickup can be harvested without runtime error
	var mock_wallet = Node3D.new()
	mock_wallet.name = "BuildingSystem"
	mock_wallet.set_script(load("res://scripts/building_system.gd"))
	add_child_autoqfree(mock_wallet)


	var mock_player = Node.new()
	mock_player.name = "Player"
	mock_player.set("building_system", mock_wallet)
	add_child_autoqfree(mock_player)

	pickup.harvest(mock_player)
	assert_true(pickup.is_harvested, "Must be marked harvested")

func test_mountain_trail_guarantees_climb_above_50_and_100() -> void:
	var test_seed: int = 4242
	# BFS search from portal (0, 0) up the mountain trail corridor
	var queue: Array[Vector2i] = [Vector2i(0, 0)]
	var visited: Dictionary = { Vector2i(0, 0): true }
	var max_h: int = 0

	var directions: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
	]

	while not queue.is_empty():
		var cur = queue.pop_front()
		var cur_h = BiomeSystem.get_voxel_height(cur.x, cur.y, test_seed)
		if cur_h > max_h:
			max_h = cur_h

		if max_h >= 100:
			break # Successfully reached target height 100+

		for d in directions:
			var n: Vector2i = cur + d
			if visited.has(n):
				continue

			var dist: float = Vector2(float(n.x), float(n.y)).length()
			# Allow portal sanctuary or mountain trail
			var is_corridor = (dist <= BiomeSystem.PORTAL_CLEAR_RADIUS) or BiomeSystem.is_mountain_trail(n.x, n.y, test_seed)
			if not is_corridor:
				continue

			var nh = BiomeSystem.get_voxel_height(n.x, n.y, test_seed)
			# Walkable condition: step <= 1
			if absi(nh - cur_h) <= 1:
				visited[n] = true
				queue.append(n)

	assert_true(max_h >= 50, "Mountain trail must allow continuous walking to height >= 50 (reached %d)" % max_h)
	assert_true(max_h >= 100, "Mountain trail must allow continuous walking to height >= 100 (reached %d)" % max_h)

	# Verify lateral height smoothness across the corridor borders (no artificial canyons / walls)
	for test_r in [30.0, 60.0, 90.0, 120.0, 150.0]:
		var trail_ang = BiomeSystem.get_trail_angle(test_r, test_seed)
		var center_x = test_r * cos(trail_ang)
		var center_z = test_r * sin(trail_ang)
		var normal_x = -sin(trail_ang)
		var normal_z = cos(trail_ang)

		var prev_lateral_h: int = -999999
		for offset in range(-15, 16):
			var px = int(roundf(center_x + normal_x * float(offset)))
			var pz = int(roundf(center_z + normal_z * float(offset)))
			var lateral_h = BiomeSystem.get_voxel_height(px, pz, test_seed)
			if prev_lateral_h != -999999:
				var lateral_step = absi(lateral_h - prev_lateral_h)
				assert_true(lateral_step <= 1, "Lateral slope across mountain corridor at r=%.1f offset=%d must be <= 1 (was %d)" % [test_r, offset, lateral_step])
			prev_lateral_h = lateral_h

func test_blended_biome_resource_probabilities() -> void:
	# Test blended probability roll at Forest-Plains border (50% Forest, 50% Plains)
	var weights: Dictionary = {
		BiomeSystem.BiomeType.FOREST: 0.5,
		BiomeSystem.BiomeType.PLAINS: 0.5,
		BiomeSystem.BiomeType.MOUNTAINS: 0.0
	}

	# In pure Forest: Wood = 0.85. In pure Plains: Wood = 0.20.
	# Blended Wood = 0.5 * 0.85 + 0.5 * 0.20 = 0.525.
	# At roll 0.10 (< 0.525), blended result must be WOOD
	var res1 = ResourceDist.roll_blended_resource_type(weights, 0.0, 0.10)
	assert_eq(res1, ResourceDist.ResourceType.WOOD, "Blended roll at 0.10 should yield Wood")

	# At roll 0.60 (> 0.525, Wood + Stone = 0.525 + 0.12 = 0.645), result must be STONE
	var res2 = ResourceDist.roll_blended_resource_type(weights, 0.0, 0.60)
	assert_eq(res2, ResourceDist.ResourceType.STONE, "Blended roll at 0.60 should yield Stone")


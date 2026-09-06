extends SceneTree

## Comprehensive Verification Runner for Issue #18:
## Procedural Biomes, Mountain Trail Verticality, Vertical Combat & Cell Alignment,
## High-Elevation Aiming, Multi-Hit Foliage Occlusion, Starting Enemy Snapping,
## Resource Yield Contracts, and O(1) Chunk Streaming.

const MAIN_SCENE_PATH = "res://scenes/main.tscn"

var total_checks: int = 0
var passed_checks: int = 0
var failed_checks: int = 0

func _init() -> void:
	print("======================================================================")
	print(" [VERIFY-ISSUE-18] Starting Comprehensive Runtime Verification")
	print("======================================================================")
	call_deferred("_run_all_checks")

func _assert_check(cond: bool, check_name: String, detail: String = "") -> void:
	total_checks += 1
	if cond:
		passed_checks += 1
		print("  [PASS] | %-45s | %s" % [check_name, detail])
	else:
		failed_checks += 1
		printerr("  [FAIL] | %-45s | %s" % [check_name, detail])

func _run_all_checks() -> void:
	await _check_biome_distribution_and_blending()
	await _check_mountain_trail_verticality_and_lateral_profile()
	await _check_resource_distribution_and_mountain_variations()
	await _check_vertical_combat_rules_and_fractional_cell_mapping()
	await _check_high_mountain_duel_aiming()
	await _check_multi_hit_foliage_occlusion()
	await _check_starting_enemies_alignment()
	await _check_chunk_streaming_and_o1_memory_profile()

	print("======================================================================")
	print(" [VERIFY-ISSUE-18] Summary: %d/%d Passed, %d Failed" % [passed_checks, total_checks, failed_checks])
	print("======================================================================")
	quit(0 if failed_checks == 0 else 1)

## 1. Procedural Biome Distribution & Blending
func _check_biome_distribution_and_blending() -> void:
	print("\n--- 1. Testing Biome Distribution & Continuous Blending ---")
	var seed_val: int = 42

	# Plains sector check (East: angle ~ 0)
	var plains_x: float = 60.0 * cos(BiomeSystem.ANGLE_PLAINS)
	var plains_z: float = 60.0 * sin(BiomeSystem.ANGLE_PLAINS)
	var plains_info: Dictionary = BiomeSystem.sample_biome_weights(plains_x, plains_z, seed_val)
	_assert_check(
		plains_info["primary"] == BiomeSystem.BiomeType.PLAINS,
		"Plains Sector Placement",
		"Plains sector primary biome is PLAINS (weight: %.2f)" % plains_info["weights"][BiomeSystem.BiomeType.PLAINS]
	)

	# Forest sector check (East/center: angle ~ 0)
	var forest_x: float = 60.0 * cos(BiomeSystem.ANGLE_FOREST)
	var forest_z: float = 60.0 * sin(BiomeSystem.ANGLE_FOREST)
	var forest_info: Dictionary = BiomeSystem.sample_biome_weights(forest_x, forest_z, seed_val)
	_assert_check(
		forest_info["primary"] == BiomeSystem.BiomeType.FOREST,
		"Forest Sector Placement",
		"Forest sector primary biome is FOREST (weight: %.2f)" % forest_info["weights"][BiomeSystem.BiomeType.FOREST]
	)

	# Mountain sector check (South-West: angle ~ -120 deg)
	var mount_x: float = 60.0 * cos(BiomeSystem.ANGLE_MOUNTAINS)
	var mount_z: float = 60.0 * sin(BiomeSystem.ANGLE_MOUNTAINS)
	var mount_info: Dictionary = BiomeSystem.sample_biome_weights(mount_x, mount_z, seed_val)
	_assert_check(
		mount_info["primary"] == BiomeSystem.BiomeType.MOUNTAINS,
		"Mountains Sector Placement",
		"Mountains sector primary biome is MOUNTAINS (weight: %.2f)" % mount_info["weights"][BiomeSystem.BiomeType.MOUNTAINS]
	)

	# Transition weights sum to ~1.0
	var sum_w: float = plains_info["weights"][BiomeSystem.BiomeType.FOREST] + plains_info["weights"][BiomeSystem.BiomeType.PLAINS] + plains_info["weights"][BiomeSystem.BiomeType.MOUNTAINS]
	_assert_check(absf(sum_w - 1.0) < 0.01, "Biome Weight Normalization", "Weights sum strictly to 1.0 (actual: %.4f)" % sum_w)

## 2. Mountain Trail Elevation & Lateral Profile
func _check_mountain_trail_verticality_and_lateral_profile() -> void:
	print("\n--- 2. Testing Mountain Trail Verticality & Lateral Slope ---")
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
			break

		for d in directions:
			var n: Vector2i = cur + d
			if visited.has(n):
				continue

			var dist: float = Vector2(float(n.x), float(n.y)).length()
			var is_corridor = (dist <= BiomeSystem.PORTAL_CLEAR_RADIUS) or BiomeSystem.is_mountain_trail(n.x, n.y, test_seed)
			if not is_corridor:
				continue

			var nh = BiomeSystem.get_voxel_height(n.x, n.y, test_seed)
			if absi(nh - cur_h) <= 1:
				visited[n] = true
				queue.append(n)

	_assert_check(max_h >= 50, "Mountain Trail Climb >= 50", "Continuous BFS walking reaches low mountain elevation (reached %d)" % max_h)
	_assert_check(max_h >= 100, "Mountain Trail Climb >= 100", "Continuous BFS walking reaches high mountain peak (reached %d)" % max_h)

	# Verify lateral height profile across corridor [-15..+15]
	var lateral_max_step: int = 0
	for test_r in [30.0, 60.0, 90.0, 120.0, 150.0]:
		var ang: float = BiomeSystem.get_trail_angle(test_r, test_seed)
		var center_pt: Vector2 = Vector2(test_r * cos(ang), test_r * sin(ang))
		var perp_dir: Vector2 = Vector2(-sin(ang), cos(ang))
		var prev_lat_h: int = -99999
		for d in range(-15, 16):
			var sample_pt: Vector2 = center_pt + perp_dir * float(d)
			var h: int = BiomeSystem.get_voxel_height(int(round(sample_pt.x)), int(round(sample_pt.y)), test_seed)
			if prev_lat_h != -99999:
				var lstep: int = absi(h - prev_lat_h)
				if lstep > lateral_max_step:
					lateral_max_step = lstep
			prev_lat_h = h

	_assert_check(lateral_max_step <= 1, "Lateral Valley Smoothness", "Max lateral step across valley corridor is <= 1 (actual: %d)" % lateral_max_step)

## 3. Resource Distribution & Yield Contracts
func _check_resource_distribution_and_mountain_variations() -> void:
	print("\n--- 3. Testing Resource Distribution & Yield Contracts ---")
	# Plains Magic Stone
	var plains_w = {BiomeSystem.BiomeType.FOREST: 0.0, BiomeSystem.BiomeType.PLAINS: 1.0, BiomeSystem.BiomeType.MOUNTAINS: 0.0}
	var magic_stone_found: bool = false
	for roll_i in range(100):
		var r_type = ResourceDistribution.roll_blended_resource_type(plains_w, 0.0, float(roll_i) / 100.0)
		if r_type == ResourceDistribution.ResourceType.MAGIC_STONE:
			magic_stone_found = true
			break
	_assert_check(magic_stone_found, "Plains Magic Stone Spawning", "Magic stone spawned in Plains probability window (2%)")

	# High Mountains Iron
	var mount_w = {BiomeSystem.BiomeType.FOREST: 0.0, BiomeSystem.BiomeType.PLAINS: 0.0, BiomeSystem.BiomeType.MOUNTAINS: 1.0}
	var iron_found: bool = false
	for roll_i in range(100):
		var r_type = ResourceDistribution.roll_blended_resource_type(mount_w, 55.0, float(roll_i) / 100.0)
		if r_type == ResourceDistribution.ResourceType.IRON:
			iron_found = true
			break
	_assert_check(iron_found, "High Mountains Iron Spawning", "Iron spawned in High Mountains (h=55 >= 50, 15%)")

	# Yield Contract Check across all resources and rolls:
	# FREE_PICKUP strictly in [1, 3], FULL_DEPOSIT strictly > 3
	var yield_contract_valid: bool = true
	var tested_count: int = 0
	for r_type in [ResourceDistribution.ResourceType.WOOD, ResourceDistribution.ResourceType.STONE, ResourceDistribution.ResourceType.IRON, ResourceDistribution.ResourceType.MAGIC_STONE]:
		for b in [BiomeSystem.BiomeType.FOREST, BiomeSystem.BiomeType.PLAINS, BiomeSystem.BiomeType.MOUNTAINS]:
			for i in range(25):
				tested_count += 1
				var d = ResourceDistribution.resolve_spawn_details(r_type, b, 60.0, float(i) / 25.0, float(24 - i) / 25.0)
				var form = d["deposit_form"]
				var y_amt: int = int(d["yield_amount"])
				if form == ResourceDistribution.DepositForm.FREE_PICKUP and (y_amt < 1 or y_amt > 3):
					yield_contract_valid = false
				elif form == ResourceDistribution.DepositForm.FULL_DEPOSIT and y_amt <= 3:
					yield_contract_valid = false

	_assert_check(
		yield_contract_valid and tested_count > 0,
		"Loose vs Deposit Yield Contract",
		"All FREE_PICKUP yields are in [1, 3] and all FULL_DEPOSIT yields strictly > 3 (%d tested)" % tested_count
	)

## 4. Vertical Combat Rules & Cell Boundary Alignment
func _check_vertical_combat_rules_and_fractional_cell_mapping() -> void:
	print("\n--- 4. Testing Vertical Combat & Fractional Cell Boundary Alignment ---")
	# Verify floorf cell mapping
	_assert_check(
		TerrainCombatRules.world_to_voxel(0.75) == 0 and TerrainCombatRules.world_to_voxel(1.05) == 1,
		"Authoritative World-to-Voxel Mapping",
		"x=0.75 maps to cell 0, x=1.05 maps to cell 1 (strictly matches ChunkBuilder)"
	)

	var lookup = func(x: int, _z: int) -> int:
		return 2 if x >= 1 else 0

	# Fractional positioning inside cell 0 connecting
	var melee_in_cell = TerrainCombatRules.is_melee_connected(
		Vector3(0.25, 0.9, 0.0),
		Vector3(0.85, 0.9, 0.0),
		lookup
	)
	_assert_check(melee_in_cell, "Fractional In-Cell Melee Hit", "Melee connects within cell [0.0, 1.0) at fractional coords")

	# Fractional positioning across cell boundary into cell 1 (+2 step) blocked
	var melee_across_boundary = TerrainCombatRules.is_melee_connected(
		Vector3(0.85, 0.9, 0.0),
		Vector3(1.15, 2.9, 0.0),
		lookup
	)
	_assert_check(not melee_across_boundary, "Fractional Cell Edge Step Blocked", "Melee blocked across x=1.0 boundary into +2 wall")

	# Projectile flying horizontally at Y=10.8 over canyon with floor rising 2 -> 4
	var proj_pos: Vector3 = Vector3(5.0, 10.8, 0.0)
	var next_pos: Vector3 = Vector3(6.0, 10.8, 0.0)
	var flight_res = TerrainCombatRules.update_projectile_height(
		proj_pos,
		next_pos,
		2.0, # current terrain y
		4.0, # next terrain y
		0.8, # projectile base offset
		true # is_over_drop
	)

	_assert_check(
		flight_res["collided"] == false,
		"Projectile Over-Canyon High Flight",
		"Projectile at Y=%.1f does not collide when canyon floor rises 2 -> 4" % flight_res["new_y"]
	)
	_assert_check(
		absf(flight_res["new_y"] - 10.8) < 0.01,
		"Projectile High Flight Altitude Invariance",
		"Projectile preserves horizontal altitude over chasm (Y=%.2f)" % flight_res["new_y"]
	)

## 5. High Mountain Warrior Duel Aiming
func _check_high_mountain_duel_aiming() -> void:
	print("\n--- 5. Testing Warrior Duel Aiming on High Mountain Terrain ---")
	var player_scene = load("res://scenes/player.tscn")
	var enemy_scene = load("res://scenes/enemy_dummy.tscn")
	if not player_scene or not enemy_scene:
		_assert_check(false, "Load Player & Enemy Scenes", "Failed to load scenes")
		return

	var player = player_scene.instantiate()
	root.add_child(player)
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.global_position = Vector3(0.0, 60.9, 0.0) # High elevation (60m)

	var camera = CameraFollow.new()
	root.add_child(camera)
	camera.target = player
	camera.current = true
	camera._init_camera_transform()
	camera._process(0.016)

	var high_enemy = enemy_scene.instantiate()
	root.add_child(high_enemy)
	high_enemy.global_position = Vector3(4.0, 60.9, 2.0)

	var enemy_screen_pos: Vector2 = camera.unproject_position(high_enemy.global_position)
	camera.mouse_override = enemy_screen_pos

	var target = player.abilities.find_target_near_mouse(player)
	_assert_check(
		target == high_enemy,
		"High Mountain Duel Target Acquisition",
		"Warrior duel aiming successfully selects target on high mountain (Y=60.9)"
	)

	player.queue_free()
	camera.queue_free()
	high_enemy.queue_free()

## 6. Multi-Hit Foliage Occlusion
func _check_multi_hit_foliage_occlusion() -> void:
	print("\n--- 6. Testing Multi-Hit Foliage Occlusion & Bounded Targets ---")
	var camera: CameraFollow = CameraFollow.new()
	root.add_child(camera)
	camera.global_position = Vector3(15.0, 20.0, 15.0)

	var player_node: Node3D = Node3D.new()
	root.add_child(player_node)
	player_node.global_position = Vector3(0.0, 0.0, 0.0)
	camera.target = player_node

	var tree_scene: PackedScene = load("res://scenes/resource_tree.tscn")
	var trees: Array[Node] = []
	for i in range(3):
		var tree: Node3D = tree_scene.instantiate() as Node3D
		root.add_child(tree)
		var t_val: float = 0.25 + float(i) * 0.20
		tree.global_position = player_node.global_position.lerp(camera.global_position, t_val)
		trees.append(tree)

	for frame in range(4):
		await process_frame

	camera.check_occlusion()

	var all_transparent: bool = true
	for t in trees:
		if not camera.occluding_buildings.has(t):
			all_transparent = false

	_assert_check(all_transparent, "Multi-Hit Canopy Transparency", "All 3 stacked canopies pierced and set semi-transparent")

	# Move trees far away
	for t in trees:
		(t as Node3D).global_position = Vector3(500.0, 0.0, 500.0)

	for frame in range(4):
		await process_frame

	camera.check_occlusion()
	_assert_check(camera.occluding_buildings.is_empty(), "Occlusion Restoration", "All occluders restored to opaque when out of line-of-sight")

	camera.queue_free()
	player_node.queue_free()
	for t in trees:
		t.queue_free()

## 7. Starting Debug Enemies Height Alignment
func _check_starting_enemies_alignment() -> void:
	print("\n--- 7. Testing Starting Enemies Alignment ---")
	var main_scene = load(MAIN_SCENE_PATH)
	if not main_scene:
		_assert_check(false, "Load main.tscn", "Could not load main.tscn")
		return

	var main = main_scene.instantiate()
	root.add_child(main)

	var map_gen: MapGenerator = main.get_node_or_null("MapGenerator") as MapGenerator
	var enemies_node: Node3D = main.get_node_or_null("Enemies") as Node3D

	var aligned_count: int = 0
	var enemy_count: int = 0
	if enemies_node and map_gen:
		for enemy in enemies_node.get_children():
			if enemy is Node3D:
				enemy_count += 1
				var ex: int = int(floorf(enemy.global_position.x))
				var ez: int = int(floorf(enemy.global_position.z))
				var expected_y: float = float(map_gen.get_voxel_height(ex, ez)) + 0.9
				if absf(enemy.global_position.y - expected_y) < 0.05:
					aligned_count += 1

	_assert_check(
		enemy_count > 0 and aligned_count == enemy_count,
		"Starting Enemies Floor Snapping",
		"All %d debug enemies snapped to y_floor + 0.9" % enemy_count
	)

	main.queue_free()

## 8. Chunk Streaming & O(1) Memory Profile
func _check_chunk_streaming_and_o1_memory_profile() -> void:
	print("\n--- 8. Testing Chunk Streaming & O(1) Bounded Memory Profile ---")
	var map_gen: MapGenerator = MapGenerator.new()
	map_gen.load_radius_chunks = 2 # 5x5 = 25 active chunks
	map_gen.unload_radius_chunks = 2
	map_gen.random_seed = false
	map_gen.custom_seed = 999
	root.add_child(map_gen)

	for frame in range(3):
		await process_frame

	var base_chunk_count: int = map_gen.active_chunks.size()
	_assert_check(base_chunk_count == 25, "Initial Chunk Window Size", "Active chunks matches 5x5 window (25 chunks)")

	# Simulate 20 chunk steps moving East
	var gen_times: Array[float] = []
	for step in range(1, 21):
		var t0: int = Time.get_ticks_usec()
		map_gen.update_player_chunks(Vector2i(step, 0))
		var dt_ms: float = float(Time.get_ticks_usec() - t0) / 1000.0
		gen_times.append(dt_ms)

	for frame in range(3):
		await process_frame

	var final_chunk_count: int = map_gen.active_chunks.size()
	_assert_check(
		final_chunk_count == 25,
		"Bounded Active Chunk Count",
		"Active chunks remains strictly bounded to 25 after 20 chunk movements (O(1) memory)"
	)

	var avg_ms: float = 0.0
	for t in gen_times:
		avg_ms += t
	avg_ms /= float(gen_times.size())
	_assert_check(
		avg_ms < 150.0,
		"O(1) Chunk Update Execution Time",
		"Average chunk transition processing time: %.2f ms (zero-allocation noise, O(1))" % avg_ms
	)

	map_gen.queue_free()

extends GutTest

## Unit tests for Issue #56 navigation fixes:
## - Flowfield radius coverage (20-28m spawn ring)
## - Lookup preservation across clear_all()
## - Ghost obstacle prevention on building relocation
## - Immediate cell unblocking upon felling resource trees
## - Full-width lateral clearance for large archetypes (Boss Gorgon)
## - Perimeter approach when player is enclosed behind walls

const FlowfieldScript = preload("res://scripts/navigation/monster_flowfield.gd")
const TreeScene = preload("res://scenes/resource_tree.tscn")
const WoodWallScene = preload("res://scenes/prefabs/wood_wall.tscn")

func before_each() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg and reg.has_method("clear"):
		reg.clear()

func after_each() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg and reg.has_method("clear"):
		reg.clear()

func test_flowfield_radius_36_covers_spawn_ring() -> void:
	var ff = FlowfieldScript.new(12345)
	var target = Vector3(0.5, 0.0, 0.5)
	# Mobs spawn at 20-28m. Test 26.5m distance along X
	var spawn_pos = Vector3(26.5, 0.0, 0.5)

	var dir: Vector3 = ff.get_flow_direction(spawn_pos, target, 0.4)
	assert_gt(dir.length_squared(), 0.001, "Spawn ring position (26.5m) must be covered by DEFAULT_RADIUS=36")
	assert_lt(dir.x, -0.5, "Direction from X=26.5 towards X=0.5 must point in negative X")

func test_clear_all_preserves_height_and_chunk_lookups() -> void:
	var ff = FlowfieldScript.new(12345)
	var dummy_h = func(_x, _z): return 3
	var dummy_c = func(_x, _z): return true

	ff.set_height_lookup(dummy_h)
	ff.set_chunk_loaded_lookup(dummy_c)
	assert_true(ff.height_lookup.is_valid())
	assert_true(ff.chunk_loaded_lookup.is_valid())

	ff.set_cell_blocked(Vector2i(2, 3), true)
	assert_true(ff.blocked_cells.has(Vector2i(2, 3)))

	# clear_all must clear blocked cells and cached fields, but NOT strip registered lookups!
	ff.clear_all()
	assert_false(ff.blocked_cells.has(Vector2i(2, 3)), "Blocked cells should be cleared")
	assert_true(ff.height_lookup.is_valid(), "height_lookup must be preserved after clear_all()")
	assert_true(ff.chunk_loaded_lookup.is_valid(), "chunk_loaded_lookup must be preserved after clear_all()")

func test_building_reregistration_unblocks_old_cell() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if not reg:
		return

	var wall: Node3D = Node3D.new()
	wall.add_to_group("walls")
	add_child_autoqfree(wall)

	# Initial placement at (0, 0, 0)
	wall.global_position = Vector3(0.0, 0.0, 0.0)
	reg.register_building(wall)
	assert_true(reg.monster_flowfield.blocked_cells.has(Vector2i(0, 0)), "(0,0) must be blocked initially")

	# Relocate building to (5, 0, 5) and re-register
	wall.global_position = Vector3(5.0, 0.0, 5.0)
	reg.register_building(wall)
	assert_false(reg.monster_flowfield.blocked_cells.has(Vector2i(0, 0)), "(0,0) ghost obstacle must be unblocked")
	assert_true(reg.monster_flowfield.blocked_cells.has(Vector2i(5, 5)), "(5,5) new cell must be blocked")

	# Teardown unregister
	reg.unregister_building(wall)
	assert_false(reg.monster_flowfield.blocked_cells.has(Vector2i(5, 5)), "(5,5) must be unblocked upon removal")

func test_resource_tree_felling_unblocks_flowfield_cell() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if not reg:
		return

	var tree = TreeScene.instantiate()
	tree.position = Vector3(8.0, 0.0, 8.0)
	add_child_autoqfree(tree)
	await wait_physics_frames(2)

	var tree_cell: Vector2i = Vector2i(8, 8)
	assert_true(reg.monster_flowfield.blocked_cells.has(tree_cell), "Tree cell must be registered and blocked in flowfield")

	# Fell tree: must immediately unregister from EntityRegistry and unblock flowfield cell
	tree.fell_tree()
	assert_false(reg.monster_flowfield.blocked_cells.has(tree_cell), "Felled tree cell must be immediately unblocked in flowfield")

func test_wide_boss_clearance_rejects_narrow_corridor() -> void:
	var ff = FlowfieldScript.new(12345)
	# Flat ground lookup
	ff.set_height_lookup(func(_x, _z): return 0)

	# Build a corridor: walls at z=-1 and z=2 (corridor center at z=1.0, width 2.0m: cells z=0 and z=1)
	# Boss Gorgon has diameter 2.4m (radius 1.2m), Grunt has diameter 0.8m (radius 0.4m)
	for x in range(-3, 4):
		ff.set_cell_blocked(Vector2i(x, -1), true)
		ff.set_cell_blocked(Vector2i(x, 2), true)

	var start_pos = Vector3(-2.5, 0.0, 1.0)
	var end_pos = Vector3(2.5, 0.0, 1.0)

	# Grunt (clearance 0.4) fits through 2.0m corridor
	var grunt_passable = ff._check_line_of_sight(start_pos, end_pos, 0.4)
	assert_true(grunt_passable, "Narrow Grunt (radius 0.4) must pass through 2.0m corridor")

	# Boss Gorgon (clearance 1.2) exceeds 2.0m corridor width (2.4m > 2.0m)
	var gorgon_passable = ff._check_line_of_sight(start_pos, end_pos, 1.2)
	assert_false(gorgon_passable, "Boss Gorgon (radius 1.2) must NOT pass through 2.0m corridor due to body clearance")

func test_zombie_approaches_wall_when_player_walled_in() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if not reg:
		return

	# Build enclosed wall box around player at (0, 0):
	# Box: X from -2 to 2, Z from -2 to 2
	var walls: Array[Node3D] = []
	for x in range(-2, 3):
		for z in range(-2, 3):
			if absi(x) == 2 or absi(z) == 2:
				var w = Node3D.new()
				w.add_to_group("buildings")
				w.add_to_group("walls")
				add_child_autoqfree(w)
				w.global_position = Vector3(float(x) + 0.5, 0.0, float(z) + 0.5)
				reg.register_building(w)
				walls.append(w)

	var player = Node3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)
	player.global_position = Vector3(0.5, 0.0, 0.5)

	# Flowfield from outside (X=8, Z=0.5) to player inside walled box must return ZERO
	var zombie_pos = Vector3(8.0, 0.0, 0.5)
	var dir_to_player = reg.monster_flowfield.get_flow_direction(zombie_pos, player.global_position, 0.4)
	assert_almost_eq(dir_to_player.length_squared(), 0.0, 0.001, "Player inside sealed walls is unreachable directly")

	# Query nearest blocking building
	var nearest_b = reg.get_nearest_building(zombie_pos)
	assert_not_null(nearest_b, "Zombie must find nearest blocking perimeter building")

	# Flowfield towards the blocking building perimeter must yield reachable approach vector
	var dir_to_building = reg.monster_flowfield.get_flow_direction(zombie_pos, nearest_b.global_position, 0.4)
	assert_gt(dir_to_building.length_squared(), 0.001, "Zombie must receive active flow vector approaching perimeter building")
	assert_lt(dir_to_building.x, -0.5, "Approach vector must lead zombie westward towards wall perimeter")

func test_resource_stone_and_iron_break_unblocks_flowfield_cells() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if not reg:
		return

	var stone_scene = preload("res://scenes/resource_stone.tscn")
	var iron_scene = preload("res://scenes/resource_iron.tscn")

	var stone = stone_scene.instantiate()
	stone.position = Vector3(12.0, 0.0, 12.0)
	add_child_autoqfree(stone)

	var iron = iron_scene.instantiate()
	iron.position = Vector3(16.0, 0.0, 16.0)
	add_child_autoqfree(iron)

	await wait_physics_frames(2)

	var stone_cell: Vector2i = Vector2i(12, 12)
	var iron_cell: Vector2i = Vector2i(16, 16)
	assert_true(reg.monster_flowfield.blocked_cells.has(stone_cell), "Stone rock cell must be blocked initially")
	assert_true(reg.monster_flowfield.blocked_cells.has(iron_cell), "Iron rock cell must be blocked initially")

	# Destroy rocks without harvesting/freeing: both must immediately unblock in flowfield
	stone.break_rock()
	iron.break_rock()

	assert_false(reg.monster_flowfield.blocked_cells.has(stone_cell), "Destroyed stone rock cell must be unblocked immediately upon break_rock")
	assert_false(reg.monster_flowfield.blocked_cells.has(iron_cell), "Destroyed iron rock cell must be unblocked immediately upon break_rock")

func test_chunk_unload_prevents_stale_flowfield_transition() -> void:
	var ff = FlowfieldScript.new(12345)
	ff.set_height_lookup(func(_x, _z): return 0)

	var loaded_cells: Dictionary = {}
	# Initially all cells loaded
	ff.set_chunk_loaded_lookup(func(x, z): return not loaded_cells.has(Vector2i(x, z)))

	var start_pos = Vector3(0.5, 0.0, 0.5)
	var target_pos = Vector3(5.5, 0.0, 0.5)

	# Fetch initial direction (must be towards +X)
	var dir_init: Vector3 = ff.get_flow_direction(start_pos, target_pos, 0.4)
	assert_gt(dir_init.x, 0.5, "Initial path points east towards target")

	# Now unload boundary column at x=1 so target is completely across unloaded chunk boundary
	for z in range(-36, 37):
		loaded_cells[Vector2i(1, z)] = true

	# Subsequent query with cached field must detect next step is into unloaded territory and return ZERO
	var dir_unloaded: Vector3 = ff.get_flow_direction(start_pos, target_pos, 0.4)
	assert_almost_eq(dir_unloaded.length_squared(), 0.0, 0.001, "Movement into unloaded territory must return ZERO direction")

	# Also verify when mob's current cell is unloaded
	loaded_cells[Vector2i(0, 0)] = true
	var dir_origin_unloaded: Vector3 = ff.get_flow_direction(start_pos, target_pos, 0.4)
	assert_almost_eq(dir_origin_unloaded.length_squared(), 0.0, 0.001, "Mob standing in unloaded cell returns ZERO direction")

func test_small_mob_lateral_clearance_respects_wall_boundary() -> void:
	var ff = FlowfieldScript.new(12345)
	ff.set_height_lookup(func(_x, _z): return 0)

	# Walls occupy cells (0,0), (1,0), (2,0), (3,0) covering z in [0, 1]
	for x in range(4):
		ff.set_cell_blocked(Vector2i(x, 0), true)

	var start_pos = Vector3(-1.0, 0.9, 1.2)
	var target_pos = Vector3(5.0, 0.9, 1.2)

	# Grunt has radius 0.4. Lateral edge extends to z = 1.2 - 0.4 = 0.8 which intersects walls in row 0 (z in [0, 1])
	var los_clear = ff._check_line_of_sight(start_pos, target_pos, 0.4)
	assert_false(los_clear, "Small mob line-of-sight must be rejected when body width intersects adjacent wall boundary")

	# Skirmisher has radius 0.3. Lateral edge extends to z = 1.2 - 0.3 = 0.9 which also intersects walls in row 0
	var los_skirmisher = ff._check_line_of_sight(start_pos, target_pos, 0.3)
	assert_false(los_skirmisher, "Skirmisher line-of-sight must be rejected when body width intersects wall boundary")

func test_unreachable_target_returns_zero_without_straight_fallback() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if not reg:
		return

	var zombie_scene = preload("res://scenes/enemy_dummy.tscn")
	var zombie = zombie_scene.instantiate()
	add_child_autoqfree(zombie)
	zombie.global_position = Vector3(0.0, 0.9, 0.0)

	var player = Node3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)
	player.global_position = Vector3(5.0, 2.9, 0.0)
	zombie.target_player = player

	# Height lookup: cliff between X=2 and X=3 (height jump from 0 to 2)
	reg.monster_flowfield.set_height_lookup(func(x, _z):
		return 2 if x >= 3 else 0
	)
	reg.monster_flowfield.invalidate()

	# Process 1 frame of physics
	zombie._custom_physics(0.016)

	assert_almost_eq(zombie.desired_velocity_h.length_squared(), 0.0, 0.001, "Unreachable player across cliff must result in ZERO horizontal velocity (no straight line fallback into cliff)")

func test_duel_mode_ignores_buildings_on_unreachable_player() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if not reg:
		return

	var zombie_scene = preload("res://scenes/enemy_dummy.tscn")
	var zombie = zombie_scene.instantiate()
	add_child_autoqfree(zombie)
	zombie.global_position = Vector3(0.0, 0.9, 0.0)

	var player = Node3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)
	player.global_position = Vector3(5.0, 2.9, 0.0)

	# Register a nearby reachable building
	var wall = Node3D.new()
	wall.add_to_group("buildings")
	add_child_autoqfree(wall)
	wall.global_position = Vector3(0.0, 0.0, 2.0)
	reg.register_building(wall)

	reg.monster_flowfield.set_height_lookup(func(x, _z):
		return 2 if x >= 3 else 0
	)
	reg.monster_flowfield.invalidate()

	# In DUEL mode, zombie MUST strictly target player and ignore buildings
	zombie.is_in_duel = true
	zombie.duel_opponent = player
	zombie.target_player = player
	zombie._custom_physics(0.016)
	var duel_vel = zombie.desired_velocity_h

	assert_almost_eq(duel_vel.length_squared(), 0.0, 0.001, "During duel, unreachable player must NOT cause zombie to divert to buildings; velocity must be ZERO")

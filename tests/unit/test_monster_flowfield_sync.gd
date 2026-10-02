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

	# Build a corridor: walls at z=0 and z=2 (corridor center at z=1, width 2.0m)
	# Boss Gorgon has diameter 2.4m (radius 1.2m), Grunt has diameter 0.8m (radius 0.4m)
	for x in range(-3, 4):
		ff.set_cell_blocked(Vector2i(x, 0), true)
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

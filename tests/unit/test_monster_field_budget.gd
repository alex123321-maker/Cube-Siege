extends GutTest

func _field() -> MonsterFlowfield:
	return MonsterFlowfield.new(42, func(_x: int, _z: int) -> int: return 0)

func test_new_cell_keys_cannot_bypass_profile_cadence() -> void:
	var ff: MonsterFlowfield = _field()
	assert_not_null(ff.get_or_update_field(Vector3(0.99, 0.9, 0.99), 8, 0.4, 1))
	assert_null(ff.get_or_update_field(Vector3(1.01, 0.9, 0.99), 8, 0.4, 1))
	ff.advance(0.249)
	assert_null(ff.get_or_update_field(Vector3(1.01, 0.9, 1.01), 8, 0.4, 1))
	assert_eq(ff.get_rebuild_count(), 1)
	ff.advance(0.0011)
	var fresh: MonsterFlowfield.FieldCache = ff.get_or_update_field(Vector3(1.01, 0.9, 1.01), 8, 0.4, 1)
	assert_not_null(fresh)
	assert_eq(fresh.goal_cell, Vector2i(1, 1))
	assert_eq(ff.get_rebuild_count(), 2)

func test_multiple_profiles_share_one_build_per_tick() -> void:
	var ff: MonsterFlowfield = _field()
	var goal: Vector3 = Vector3(10.5, 0.0, 0.5)
	assert_not_null(ff.get_or_update_field(goal, 8, 0.4))
	assert_null(ff.get_or_update_field(goal, 8, 0.7))
	assert_null(ff.get_or_update_field(goal, 8, 1.2))
	ff.advance(1.0 / 60.0)
	assert_not_null(ff.get_or_update_field(goal, 8, 0.7))
	assert_null(ff.get_or_update_field(goal, 8, 1.2))
	ff.advance(1.0 / 60.0)
	assert_not_null(ff.get_or_update_field(goal, 8, 1.2))
	assert_eq(ff.get_rebuild_count(), 3)

func test_obstacle_invalidation_does_not_reset_cadence_or_reuse_other_goal() -> void:
	var ff: MonsterFlowfield = _field()
	var player: Vector3 = Vector3(10.5, 0.0, 0.5)
	assert_not_null(ff.get_or_update_field(player, 8))
	ff.set_cell_blocked(Vector2i(9, 0), true)
	assert_null(ff.get_or_update_field(player, 8))
	assert_null(ff.get_or_update_field(Vector3(9.5, 0.0, 0.5), 8))
	ff.advance(0.25)
	assert_null(ff.get_or_update_field(Vector3(9.5, 0.0, 0.5), 8), "Earlier player request retains its FIFO place after invalidation")
	assert_false(ff.is_query_pending(player))
	ff.advance(0.25)
	var wall: MonsterFlowfield.FieldCache = ff.get_or_update_field(Vector3(9.5, 0.0, 0.5), 8)
	assert_not_null(wall)
	assert_true(wall.is_goal_blocked)
	assert_eq(wall.goal_cell, Vector2i(9, 0))
	var player_field: MonsterFlowfield.FieldCache = ff.get_or_update_field(player, 8)
	assert_not_null(player_field)
	assert_eq(player_field.goal_cell, Vector2i(10, 0), "Wall cache never substitutes for the player")

func test_stationary_cached_target_never_rebuilds_and_pause_does_not_advance() -> void:
	var ff: MonsterFlowfield = _field()
	var goal: Vector3 = Vector3(10.5, 0.0, 0.5)
	var first: MonsterFlowfield.FieldCache = ff.get_or_update_field(goal, 8)
	for i in range(20):
		ff.advance(0.0)
		assert_same(ff.get_or_update_field(goal, 8), first)
		assert_null(ff.get_or_update_field(goal + Vector3.RIGHT, 8))
	assert_eq(ff.get_rebuild_count(), 1)

func test_native_batch_matches_reference_geometry_and_perimeter_for_each_profile() -> void:
	for radius in [0.4, 0.7, 1.2]:
		for wall_goal in [false, true]:
			var ff: MonsterFlowfield = MonsterFlowfield.new(42, func(x: int, z: int) -> int:
				return 1 if x >= 2 and z > -2 else 0)
			ff.set_chunk_loaded_lookup(func(x: int, z: int) -> bool: return x >= -7 and z <= 7)
			for z in range(-4, 5):
				if z != 2:
					ff.set_cell_blocked(Vector2i(3, z), true)
			var goal: Vector2i = Vector2i(5, 0)
			ff.set_cell_blocked(goal, wall_goal)
			var actual: MonsterFlowfield.FieldCache = MonsterFlowfield.FieldCache.new()
			var reference: MonsterFlowfield.FieldCache = MonsterFlowfield.FieldCache.new()
			ff._compute_field_data(actual, goal, 8, radius)
			ff._compute_field_data_reference(reference, goal, 8, radius)
			assert_eq(actual.distance_field.size(), reference.distance_field.size())
			for cell in reference.distance_field:
				assert_true(actual.distance_field.has(cell), "Reachable cell parity " + str(cell))
				assert_almost_eq(float(actual.distance_field.get(cell, -1.0)), float(reference.distance_field[cell]), 0.0001)
				assert_almost_eq(actual.flow_directions.get(cell, Vector2.INF), reference.flow_directions[cell], Vector2(0.0001, 0.0001))

func test_native_batch_rejects_malformed_inputs_and_keeps_border_outside_routes() -> void:
	var solver: MonsterFieldSolver = MonsterFieldSolver.new()
	assert_eq(solver.build(PackedInt32Array(), PackedByteArray(), PackedByteArray(), 3, 0, 1).size(), 0)
	var heights: PackedInt32Array = PackedInt32Array()
	var blocked: PackedByteArray = PackedByteArray()
	var loaded: PackedByteArray = PackedByteArray()
	heights.resize(9)
	blocked.resize(9)
	loaded.resize(9)
	loaded.fill(1)
	blocked[4] = 1
	var output: PackedFloat32Array = solver.build(heights, blocked, loaded, 3, 2, 1)
	assert_eq(output.size(), 27)
	for cell in range(9):
		assert_eq(output[cell * 3], -1.0, "One-cell border is never a perimeter seed")

func test_waiting_wall_is_served_while_unreachable_player_keeps_crossing_cells() -> void:
	var ff: MonsterFlowfield = MonsterFlowfield.new(42, func(_x: int, z: int) -> int: return 0 if z == 10 else 3)
	ff.set_chunk_loaded_lookup(func(_x: int, _z: int) -> bool: return true)
	ff.set_cell_blocked(Vector2i(10, 10), true)
	var origin: Vector3 = Vector3(7.5, 0.9, 10.5)
	var wall: Vector3 = Vector3(10.5, 0, 10.5)
	var first_wall_ready_step: int = -1
	var reachable_wall_queries: int = 0
	for step in range(240):
		ff.advance(1.0 / 60.0)
		var count_before: int = ff.get_rebuild_count()
		var player: Vector3 = Vector3(11.5 + 4.5 * float(step) / 60.0, 0.9, 10.5)
		var player_direction: Vector3 = ff.get_flow_direction(origin, player, 0.4, 1)
		# Exactly the production zombie's player-before-building request order.
		if player_direction.length_squared() < 0.001 and not ff.is_query_pending(player, 0.4):
			var wall_direction: Vector3 = ff.get_flow_direction(origin, wall, 0.4, 2)
			if wall_direction.length_squared() > 0.001:
				reachable_wall_queries += 1
		if first_wall_ready_step < 0 and not ff.is_query_pending(wall, 0.4):
			first_wall_ready_step = step
		assert_lte(ff.get_rebuild_count() - count_before, 1, "No multiple builds in one public clock tick")
		assert_lte(ff.get_pending_request_count(), 2, "Moving player coalesces its pending logical request")
	assert_between(first_wall_ready_step, 0, 30, "Fixed reachable wall is served within two intervals")
	assert_gt(reachable_wall_queries, 0, "Wall route is usable while player moves")
	assert_lte(ff.get_rebuild_count(), 17, "Per-profile .25s budget remains bounded over four seconds")

func test_pending_fifo_is_bounded_and_moving_target_keeps_place_and_latest_cell() -> void:
	var ff: MonsterFlowfield = _field()
	assert_not_null(ff.get_or_update_field(Vector3.ZERO, 2, 0.4, 1))
	for index in range(300):
		ff.get_or_update_field(Vector3(float(index + 10), 0, 0), 2, 0.4, index + 100)
	assert_eq(ff.get_pending_request_count(), MonsterFlowfield.MAX_PENDING_REQUESTS)
	# The earliest logical target moves while queued; its old cell must not be built.
	ff.get_or_update_field(Vector3(999, 0, 0), 2, 0.4, 100)
	ff.advance(0.25)
	assert_null(ff.get_or_update_field(Vector3(1000, 0, 0), 2, 0.4, 1))
	assert_false(ff.is_query_pending(Vector3(999, 0, 0)))
	assert_true(ff.is_query_pending(Vector3(10, 0, 0)))
	assert_true(ff.is_query_pending(Vector3(1000, 0, 0)), "Another target's computed field is never returned")
	assert_eq(ff.get_rebuild_count(), 2)
	ff.clear_all()
	assert_eq(ff.get_pending_request_count(), 0, "World cleanup clears pending logical targets")

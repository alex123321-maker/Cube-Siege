extends GutTest

func _field() -> MonsterFlowfield:
	return MonsterFlowfield.new(42, func(_x: int, _z: int) -> int: return 0)

func test_new_cell_keys_cannot_bypass_profile_cadence() -> void:
	var ff: MonsterFlowfield = _field()
	assert_not_null(ff.get_or_update_field(Vector3(0.99, 0.9, 0.99), 8))
	assert_null(ff.get_or_update_field(Vector3(1.01, 0.9, 0.99), 8))
	ff.advance(0.249)
	assert_null(ff.get_or_update_field(Vector3(1.01, 0.9, 1.01), 8))
	assert_eq(ff.get_rebuild_count(), 1)
	ff.advance(0.0011)
	var fresh: MonsterFlowfield.FieldCache = ff.get_or_update_field(Vector3(1.01, 0.9, 1.01), 8)
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
	var wall: MonsterFlowfield.FieldCache = ff.get_or_update_field(Vector3(9.5, 0.0, 0.5), 8)
	assert_not_null(wall)
	assert_true(wall.is_goal_blocked)
	assert_eq(wall.goal_cell, Vector2i(9, 0))
	assert_null(ff.get_or_update_field(player, 8))

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

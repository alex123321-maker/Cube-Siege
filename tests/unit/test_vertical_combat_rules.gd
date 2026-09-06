extends GutTest

const TerrainCombatRules = preload("res://scripts/combat/terrain_combat_rules.gd")

func test_melee_connectivity_direct_step() -> void:
	var p0: Vector3 = Vector3(0, 0, 0)
	var p_same: Vector3 = Vector3(1, 0, 0)
	var p_up_1: Vector3 = Vector3(1, 1, 0)
	var p_down_1: Vector3 = Vector3(1, -1, 0)
	var p_up_2: Vector3 = Vector3(1, 2, 0)
	var p_down_3: Vector3 = Vector3(1, -3, 0)

	assert_true(TerrainCombatRules.is_melee_connected(p0, p_same), "Melee hits at same height")
	assert_true(TerrainCombatRules.is_melee_connected(p0, p_up_1), "Melee hits at +1 block")
	assert_true(TerrainCombatRules.is_melee_connected(p0, p_down_1), "Melee hits at -1 block")
	assert_false(TerrainCombatRules.is_melee_connected(p0, p_up_2), "Melee fails against +2 block wall")
	assert_false(TerrainCombatRules.is_melee_connected(p0, p_down_3), "Melee fails against -3 block drop")

func test_melee_connectivity_stairs_propagation() -> void:
	var p0: Vector3 = Vector3(0, 0, 0)
	var p_target: Vector3 = Vector3(3, 3, 0)

	# 1. Connected stairs: step 1 is Y=1, step 2 is Y=2, step 3 is Y=3
	var valid_stairs_lookup = func(x: int, _z: int) -> int:
		return x

	assert_true(
		TerrainCombatRules.is_melee_connected(p0, p_target, valid_stairs_lookup),
		"Melee propagates along continuous stairs where each delta is <= 1"
	)

	# 2. Broken stairs: step 1 is Y=0, step 2 is Y=3 (jump of 3 blocks)
	var broken_stairs_lookup = func(x: int, _z: int) -> int:
		if x >= 2:
			return 3
		return 0

	assert_false(
		TerrainCombatRules.is_melee_connected(p0, p_target, broken_stairs_lookup),
		"Melee fails to propagate across stairs gap of >= 2 blocks"
	)

func test_terrain_mode_nuke_vs_standard_ability() -> void:
	var attacker_pos: Vector3 = Vector3(0, 0, 0)
	var target_high_mountain: Vector3 = Vector3(5, 45, 0) # 45 blocks high, 5m away horizontally

	# Terrain dependent ability (Warrior / Archer)
	var can_hit_standard: bool = TerrainCombatRules.can_ability_hit_target(
		attacker_pos,
		target_high_mountain,
		TerrainCombatRules.TerrainMode.TERRAIN_DEPENDENT,
		10.0
	)
	assert_false(can_hit_standard, "TERRAIN_DEPENDENT ability must not hit target 45 blocks above without stairs")

	# Terrain independent ability (Engineer Tactical Nuke)
	var can_hit_nuke: bool = TerrainCombatRules.can_ability_hit_target(
		attacker_pos,
		target_high_mountain,
		TerrainCombatRules.TerrainMode.TERRAIN_INDEPENDENT,
		10.0
	)
	assert_true(can_hit_nuke, "TERRAIN_INDEPENDENT nuke must hit targets in horizontal radius regardless of elevation")

func test_projectile_step_climb_and_descend() -> void:
	var cur_pos: Vector3 = Vector3(0, 0.8, 0)
	var next_pos: Vector3 = Vector3(1, 0.8, 0)

	# Ground climbs by +1 block (ground 0.0 -> 1.0)
	var res_climb: Dictionary = TerrainCombatRules.update_projectile_height(cur_pos, next_pos, 0.0, 1.0, 0.8)
	assert_false(res_climb["collided"], "Climbing +1 step should not collide with wall")
	assert_true(res_climb["new_y"] > 0.8, "Projectile must adjust upward to climb +1 step")

	# Ground descends by -1 block (ground 0.0 -> -1.0)
	var res_descend: Dictionary = TerrainCombatRules.update_projectile_height(cur_pos, next_pos, 0.0, -1.0, 0.8)
	assert_false(res_descend["collided"], "Descending -1 step should not collide")
	assert_true(res_descend["new_y"] < 0.8, "Projectile must adjust downward along slope")

func test_projectile_crashes_into_wall_and_skips_cliff_dive() -> void:
	var cur_pos: Vector3 = Vector3(0, 0.8, 0)
	var next_pos: Vector3 = Vector3(1, 0.8, 0)

	# Ground climbs by +2 blocks (wall / cliff face: 0.0 -> 2.0)
	var res_wall: Dictionary = TerrainCombatRules.update_projectile_height(cur_pos, next_pos, 0.0, 2.0, 0.8)
	assert_true(res_wall["collided"], "Projectile must collide with wall (delta >= 2 blocks)")

	# Ground drops by 5 blocks (cliff edge / drop: 0.0 -> -5.0)
	var res_drop: Dictionary = TerrainCombatRules.update_projectile_height(cur_pos, next_pos, 0.0, -5.0, 0.8)
	assert_false(res_drop["collided"], "Projectile does not collide when flying over drop")
	assert_false(res_drop["is_diving"], "Projectile must not dive down into drop")
	assert_almost_eq(res_drop["new_y"], 0.8, 0.05, "Projectile must continue straight over drop >= 2 rather than diving down")

func test_projectile_multi_frame_flight_over_chasm() -> void:
	# Simulate arrow flying from cliff (y=10) over a deep chasm (ground y=2) across 5 frames
	var arrow_pos: Vector3 = Vector3(0, 10.8, 0)
	var is_over_drop: bool = false

	# Frame 1: Cliff edge (ground 10.0 -> 2.0)
	var res1: Dictionary = TerrainCombatRules.update_projectile_height(arrow_pos, Vector3(1, 10.8, 0), 10.0, 2.0, 0.8, is_over_drop)
	assert_false(res1["collided"])
	assert_almost_eq(res1["new_y"], 10.8, 0.01, "Frame 1: must not drop down into chasm")
	is_over_drop = res1.get("is_over_drop", false)
	assert_true(is_over_drop, "Must flag is_over_drop = true")
	arrow_pos.x = 1.0
	arrow_pos.y = res1["new_y"]

	# Frame 2: Deep inside chasm (ground 2.0 -> 2.0, delta=0)
	var res2: Dictionary = TerrainCombatRules.update_projectile_height(arrow_pos, Vector3(2, 10.8, 0), 2.0, 2.0, 0.8, is_over_drop)
	assert_false(res2["collided"])
	assert_almost_eq(res2["new_y"], 10.8, 0.01, "Frame 2: must continue flying straight at 10.8, not plunge to ground+0.8 (2.8)")
	is_over_drop = res2.get("is_over_drop", false)
	assert_true(is_over_drop)
	arrow_pos.x = 2.0
	arrow_pos.y = res2["new_y"]

	# Frame 3: Still inside chasm (ground 2.0 -> 2.0)
	var res3: Dictionary = TerrainCombatRules.update_projectile_height(arrow_pos, Vector3(3, 10.8, 0), 2.0, 2.0, 0.8, is_over_drop)
	assert_almost_eq(res3["new_y"], 10.8, 0.01, "Frame 3: still maintains 10.8")
	is_over_drop = res3.get("is_over_drop", false)
	assert_true(is_over_drop)
	arrow_pos.x = 3.0
	arrow_pos.y = res3["new_y"]

	# Frame 4: Terrain rises up to wall (ground 2.0 -> 12.0)
	var res4: Dictionary = TerrainCombatRules.update_projectile_height(arrow_pos, Vector3(4, 10.8, 0), 2.0, 12.0, 0.8, is_over_drop)
	assert_true(res4["collided"], "Arrow must collide when rock wall rises above flight altitude")


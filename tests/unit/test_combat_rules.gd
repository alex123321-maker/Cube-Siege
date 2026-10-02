extends GutTest

const CombatRules = preload("res://scripts/combat/combat_rules.gd")
const BuildingBase = preload("res://scripts/building_base.gd")
const HitboxArea = preload("res://scripts/hitbox_area.gd")
const HurtboxArea = preload("res://scripts/hurtbox_area.gd")

func test_team_resolution() -> void:
	var player = Node3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)
	assert_eq(CombatRules.get_team(player), CombatRules.Team.PLAYER, "Player node must resolve to Team.PLAYER")

	var wall = BuildingBase.new()
	add_child_autoqfree(wall)
	assert_eq(CombatRules.get_team(wall), CombatRules.Team.PLAYER, "BuildingBase must resolve to Team.PLAYER")

	var enemy = Node3D.new()
	enemy.add_to_group("enemies")
	add_child_autoqfree(enemy)
	assert_eq(CombatRules.get_team(enemy), CombatRules.Team.ENEMY, "Enemy node must resolve to Team.ENEMY")

	var resource_node = Node3D.new()
	resource_node.add_to_group("resources")
	add_child_autoqfree(resource_node)
	assert_eq(CombatRules.get_team(resource_node), CombatRules.Team.NEUTRAL, "Resource node must resolve to Team.NEUTRAL")

func test_is_friendly_building() -> void:
	var bldg = BuildingBase.new()
	add_child_autoqfree(bldg)
	assert_true(CombatRules.is_friendly_building(bldg), "BuildingBase is a friendly building")

	var wall = Node3D.new()
	wall.add_to_group("walls")
	add_child_autoqfree(wall)
	assert_true(CombatRules.is_friendly_building(wall), "Node in walls group is a friendly building")

	var tower = Node3D.new()
	tower.add_to_group("towers")
	add_child_autoqfree(tower)
	assert_true(CombatRules.is_friendly_building(tower), "Node in towers group is a friendly building")

	var player = Node3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)
	assert_false(CombatRules.is_friendly_building(player), "Player is not a building")

	var enemy = Node3D.new()
	enemy.add_to_group("enemies")
	add_child_autoqfree(enemy)
	assert_false(CombatRules.is_friendly_building(enemy), "Enemy is not a building")

func test_direct_building_damage_sources() -> void:
	var bldg = BuildingBase.new()
	add_child_autoqfree(bldg)

	var other_bldg = BuildingBase.new()
	add_child_autoqfree(other_bldg)

	var player = Node3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)

	var enemy = Node3D.new()
	enemy.add_to_group("enemies")
	add_child_autoqfree(enemy)

	# 1. Player attack on friendly building must be rejected
	assert_false(
		CombatRules.can_damage(player, bldg),
		"Player must NOT be able to damage friendly building"
	)

	# 2. Building attacking itself must be rejected
	assert_false(
		CombatRules.can_damage(bldg, bldg),
		"Building must NOT be able to damage itself"
	)

	# 3. Another friendly building attacking building must be rejected
	assert_false(
		CombatRules.can_damage(other_bldg, bldg),
		"Friendly building must NOT be able to damage another friendly building"
	)

	# 4. Enemy attacking building must be accepted
	assert_true(
		CombatRules.can_damage(enemy, bldg),
		"Enemy MUST be able to damage friendly building"
	)

func test_building_take_damage_api() -> void:
	var bldg = BuildingBase.new()
	bldg.max_health = 250.0
	bldg.current_health = 250.0
	add_child_autoqfree(bldg)

	var other_bldg = BuildingBase.new()
	add_child_autoqfree(other_bldg)

	var player = Node3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)

	var enemy = Node3D.new()
	enemy.add_to_group("enemies")
	add_child_autoqfree(enemy)

	# 1. Player source: rejected, HP unchanged
	var res1 = bldg.take_damage(50.0, player)
	assert_false(res1, "take_damage from player must return false")
	assert_eq(bldg.current_health, 250.0, "Building HP must not change from player damage")

	# 2. Self source: rejected, HP unchanged
	var res2 = bldg.take_damage(50.0, bldg)
	assert_false(res2, "take_damage from self must return false")
	assert_eq(bldg.current_health, 250.0, "Building HP must not change from self damage")

	# 3. Other building source: rejected, HP unchanged
	var res3 = bldg.take_damage(50.0, other_bldg)
	assert_false(res3, "take_damage from other building must return false")
	assert_eq(bldg.current_health, 250.0, "Building HP must not change from other building damage")

	# 4. Enemy source: accepted, HP decreased
	var res4 = bldg.take_damage(50.0, enemy)
	assert_true(res4, "take_damage from enemy must return true")
	assert_eq(bldg.current_health, 200.0, "Building HP must decrease by 50 from enemy damage")

func test_hurtbox_area_filtering() -> void:
	var bldg = BuildingBase.new()
	bldg.max_health = 250.0
	bldg.current_health = 250.0
	add_child_autoqfree(bldg)

	var hurtbox = HurtboxArea.new()
	bldg.add_child(hurtbox)
	hurtbox.target_node = bldg
	hurtbox.damaged.connect(bldg._on_damaged)

	var player = Node3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)

	var enemy = Node3D.new()
	enemy.add_to_group("enemies")
	add_child_autoqfree(enemy)

	# Hurtbox take_damage from player must return false and not emit signal or damage
	var res_p = hurtbox.take_damage(40.0, Vector3.ZERO, "physical", player)
	assert_false(res_p, "Hurtbox take_damage from player must return false")
	assert_eq(bldg.current_health, 250.0, "Building HP must remain 250 after player attack on hurtbox")

	# Hurtbox take_damage from enemy must return true and damage building
	var res_e = hurtbox.take_damage(40.0, Vector3.ZERO, "physical", enemy)
	assert_true(res_e, "Hurtbox take_damage from enemy must return true")
	assert_eq(bldg.current_health, 210.0, "Building HP must decrease to 210 after enemy attack on hurtbox")

func test_deleted_attacker_delayed_attack() -> void:
	var bldg = BuildingBase.new()
	bldg.max_health = 250.0
	bldg.current_health = 250.0
	add_child_autoqfree(bldg)

	var enemy = Node3D.new()
	enemy.add_to_group("enemies")
	add_child_autoqfree(enemy)

	# Attacker node was destroyed (null reference), but team provenance was Team.PLAYER
	assert_false(
		CombatRules.can_damage(null, bldg, CombatRules.Team.PLAYER),
		"Delayed ally attack with deleted source must NOT damage friendly building"
	)

	# Attacker node was destroyed (null reference), but team provenance was Team.PLAYER against enemy
	assert_true(
		CombatRules.can_damage(null, enemy, CombatRules.Team.PLAYER),
		"Delayed ally attack with deleted source MUST damage enemy"
	)

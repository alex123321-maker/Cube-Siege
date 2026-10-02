extends GutTest

## Integration tests for Issue #56:
## - 1-block step climbing (up and down) for Grunt and Boss Gorgon
## - Multi-mob crowd navigation without mutual penetration
## - Boss Gorgon chase, stairs navigation, and crowd coexistence

const ENEMY_DUMMY_SCENE = preload("res://scenes/enemy_dummy.tscn")
const BOSS_GORGON_SCENE = preload("res://scenes/enemies/boss_gorgon.tscn")

func before_each() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg and reg.has_method("clear"):
		reg.clear()

func after_each() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg and reg.has_method("clear"):
		reg.clear()

func test_grunt_ascends_one_block_step_staircase() -> void:
	# Build a static body staircase with 4 steps (+1 block height each: Y=0, Y=1, Y=2, Y=3)
	for i in range(4):
		var step_body: StaticBody3D = StaticBody3D.new()
		step_body.collision_layer = 1
		step_body.collision_mask = 0
		var col: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(2.0, 1.0, 2.0)
		col.shape = box
		step_body.add_child(col)
		add_child_autoqfree(step_body)
		step_body.global_position = Vector3(float(i) * 1.5, float(i) * 1.0 - 0.5, 0.0)

	var player: CharacterBody3D = CharacterBody3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)
	player.global_position = Vector3(5.5, 3.9, 0.0)

	var grunt: CharacterBody3D = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(grunt)
	grunt.global_position = Vector3(0.0, 0.9, 0.0)
	grunt.target_player = player

	await wait_physics_frames(40)

	# Grunt should climb up towards Y > 1.5 and advance along X
	assert_gt(grunt.global_position.y, 1.5, "Grunt must climb 1-block steps up the staircase")
	assert_gt(grunt.global_position.x, 1.0, "Grunt must make forward progress up the stairs")

func test_boss_gorgon_ascends_one_block_stairs_without_false_cliff() -> void:
	# 2-step staircase for Boss Gorgon
	for i in range(3):
		var step_body: StaticBody3D = StaticBody3D.new()
		step_body.collision_layer = 1
		step_body.collision_mask = 0
		var col: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(4.0, 1.0, 4.0)
		col.shape = box
		step_body.add_child(col)
		add_child_autoqfree(step_body)
		step_body.global_position = Vector3(float(i) * 2.5, float(i) * 1.0 - 0.5, 0.0)

	var player: CharacterBody3D = CharacterBody3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)
	player.global_position = Vector3(5.5, 2.9, 0.0)

	var gorgon: CharacterBody3D = BOSS_GORGON_SCENE.instantiate()
	add_child_autoqfree(gorgon)
	# Authoritative spawn placing feet at Y=0.0 on step 0 (radius 1.2, front at X=0.4 before step 1 at X=0.5)
	gorgon.global_position = Vector3(-0.8, 0.0, 0.0)
	gorgon.target_player = player
	gorgon.charge_cooldown_timer = 10.0

	await wait_physics_frames(40)

	# Gorgon must ascend without getting falsely stuck by cliff detection (B1)
	assert_gt(gorgon.global_position.x, 0.2, "Gorgon must advance forward up the stairs")
	assert_gt(gorgon.global_position.y, 0.5, "Gorgon must climb the 1-block step up")

func test_multi_mob_crowd_no_mutual_penetration() -> void:
	var ground: StaticBody3D = StaticBody3D.new()
	ground.collision_layer = 1
	var g_col: CollisionShape3D = CollisionShape3D.new()
	var g_box: BoxShape3D = BoxShape3D.new()
	g_box.size = Vector3(60.0, 1.0, 60.0)
	g_col.shape = g_box
	ground.add_child(g_col)
	add_child_autoqfree(ground)
	ground.global_position = Vector3(0.0, -0.5, 0.0)

	var player: CharacterBody3D = CharacterBody3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)
	player.global_position = Vector3(15.0, 0.9, 0.0)

	var enemies: Array[CharacterBody3D] = []
	for i in range(4):
		var mob: CharacterBody3D = ENEMY_DUMMY_SCENE.instantiate()
		add_child_autoqfree(mob)
		var row: int = i / 2
		var col: int = i % 2
		mob.global_position = Vector3(float(row) * 1.0, 0.9, float(col) * 1.0)
		enemies.append(mob)

	await wait_physics_frames(30)

	# Verify forward advancement
	for i in range(enemies.size()):
		assert_gt(enemies[i].global_position.x, 0.4, "Crowd mob %d must advance towards target" % i)

	# Verify pairwise distance: Grunt radius is 0.4 (width 0.8), combined radius = 0.8
	for i in range(enemies.size()):
		for j in range(i + 1, enemies.size()):
			var p1: Vector3 = enemies[i].global_position
			var p2: Vector3 = enemies[j].global_position
			var dist_h: float = Vector2(p1.x - p2.x, p1.z - p2.z).length()
			assert_gt(dist_h, 0.65, "Enemies %d and %d must not penetrate through each other (dist=%.2f)" % [i, j, dist_h])

func test_gorgon_chase_and_crowd_separation() -> void:
	var ground: StaticBody3D = StaticBody3D.new()
	ground.collision_layer = 1
	var g_col: CollisionShape3D = CollisionShape3D.new()
	var g_box: BoxShape3D = BoxShape3D.new()
	g_box.size = Vector3(60.0, 1.0, 60.0)
	g_col.shape = g_box
	ground.add_child(g_col)
	add_child_autoqfree(ground)
	ground.global_position = Vector3(0.0, -0.5, 0.0)

	var player: CharacterBody3D = CharacterBody3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)
	player.global_position = Vector3(15.0, 0.9, 0.0)

	var gorgon: CharacterBody3D = BOSS_GORGON_SCENE.instantiate()
	add_child_autoqfree(gorgon)
	gorgon.global_position = Vector3(0.0, 0.0, 0.0) # Authoritative feet placement

	var grunt: CharacterBody3D = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(grunt)
	grunt.global_position = Vector3(2.5, 0.9, 0.0)

	await wait_physics_frames(25)

	var g_pos = gorgon.global_position
	var m_pos = grunt.global_position
	var dist_h = Vector2(g_pos.x - m_pos.x, g_pos.z - m_pos.z).length()

	# Gorgon radius 1.2 + Grunt radius 0.4 = combined radius 1.6m
	assert_gt(dist_h, 1.35, "Boss Gorgon and Grunt must maintain separation without penetration (dist=%.2f)" % dist_h)
	assert_gt(gorgon.global_position.x, 0.5, "Gorgon must actively chase and advance towards player")

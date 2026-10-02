extends GutTest

## Integration tests for Issue #56:
## - 1-block step climbing (up and down) without getting stuck or accumulating height
## - Multi-mob crowd navigation without mutual penetration
## - Boss Gorgon chase and crowd coexistence

const ENEMY_DUMMY_SCENE = preload("res://scenes/enemy_dummy.tscn")
const BOSS_GORGON_SCENE = preload("res://scenes/enemies/boss_gorgon.tscn")

func test_grunt_ascends_one_block_step_staircase() -> void:
	# Build a static body staircase with 3 steps (+1 block height each: Y=0, Y=1, Y=2)
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

	# Create a dummy player target at step 3
	var player: CharacterBody3D = CharacterBody3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)
	player.global_position = Vector3(4.5, 3.9, 0.0)

	# Spawn Grunt at step 0 (feet on Y = 0.0, center at Y = 0.9)
	var grunt: CharacterBody3D = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(grunt)
	grunt.global_position = Vector3(0.0, 0.9, 0.0)

	# Wait physics frames for engine to simulate climbing
	await wait_physics_frames(30)

	# Grunt should have climbed from Y=0.9 towards Y > 1.2
	assert_gt(grunt.global_position.y, 1.2, "Grunt must climb 1-block steps up the staircase")
	assert_gt(grunt.global_position.x, 0.4, "Grunt must make forward progress up the stairs")

func test_multi_mob_crowd_no_mutual_penetration() -> void:
	# Flat ground
	var ground: StaticBody3D = StaticBody3D.new()
	ground.collision_layer = 1
	var g_col: CollisionShape3D = CollisionShape3D.new()
	var g_box: BoxShape3D = BoxShape3D.new()
	g_box.size = Vector3(50.0, 1.0, 50.0)
	g_col.shape = g_box
	ground.add_child(g_col)
	add_child_autoqfree(ground)
	ground.global_position = Vector3(0.0, -0.5, 0.0)

	# Player target
	var player: CharacterBody3D = CharacterBody3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)
	player.global_position = Vector3(15.0, 0.9, 0.0)

	# Spawn 4 enemies close together moving towards player
	var enemies: Array[CharacterBody3D] = []
	for i in range(4):
		var mob: CharacterBody3D = ENEMY_DUMMY_SCENE.instantiate()
		add_child_autoqfree(mob)
		var row: int = i / 2
		var col: int = i % 2
		mob.global_position = Vector3(float(row) * 1.0, 0.9, float(col) * 1.0)
		enemies.append(mob)

	# Wait physics frames
	await wait_physics_frames(25)

	# Verify pairwise distance between mobs: centers must not severely penetrate
	for i in range(enemies.size()):
		for j in range(i + 1, enemies.size()):
			var p1: Vector3 = enemies[i].global_position
			var p2: Vector3 = enemies[j].global_position
			var dist_h: float = Vector2(p1.x - p2.x, p1.z - p2.z).length()
			assert_gt(dist_h, 0.45, "Enemies %d and %d must not penetrate through each other" % [i, j])

func test_gorgon_chase_and_crowd_separation() -> void:
	var ground: StaticBody3D = StaticBody3D.new()
	ground.collision_layer = 1
	var g_col: CollisionShape3D = CollisionShape3D.new()
	var g_box: BoxShape3D = BoxShape3D.new()
	g_box.size = Vector3(50.0, 1.0, 50.0)
	g_col.shape = g_box
	ground.add_child(g_col)
	add_child_autoqfree(ground)
	ground.global_position = Vector3(0.0, -0.5, 0.0)

	var player: CharacterBody3D = CharacterBody3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)
	player.global_position = Vector3(20.0, 0.9, 0.0)

	var gorgon: CharacterBody3D = BOSS_GORGON_SCENE.instantiate()
	add_child_autoqfree(gorgon)
	gorgon.global_position = Vector3(0.0, 1.5, 0.0)

	var grunt: CharacterBody3D = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(grunt)
	grunt.global_position = Vector3(2.5, 0.9, 0.0)

	# Wait physics frames
	await wait_physics_frames(20)

	var g_pos = gorgon.global_position
	var m_pos = grunt.global_position
	var dist_h = Vector2(g_pos.x - m_pos.x, g_pos.z - m_pos.z).length()
	assert_gt(dist_h, 0.7, "Grunt and Gorgon must maintain physical separation")

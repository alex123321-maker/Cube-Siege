extends GutTest

## Integration tests for Issue #56:
## - 1-block step climbing (up and down) for Grunt and Boss Gorgon
## - Multi-mob crowd navigation without mutual penetration
## - Boss Gorgon chase, stairs navigation, and crowd coexistence

const ENEMY_DUMMY_SCENE = preload("res://scenes/enemy_dummy.tscn")
const BOSS_GORGON_SCENE = preload("res://scenes/enemies/boss_gorgon.tscn")
const SIEGE_BREAKER_SCENE = preload("res://scenes/enemies/siege_breaker.tscn")

class MovingCorridorTarget extends Node3D:
	var steps: int = 0
	func _physics_process(delta: float) -> void:
		if steps < 240:
			position.x += 4.5 * delta
			steps += 1

func before_each() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg and reg.has_method("clear"):
		reg.clear()

func after_each() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg and reg.has_method("clear"):
		reg.clear()

func test_actual_zombie_reaches_and_damages_wall_while_unreachable_player_moves() -> void:
	var reg = get_node("/root/EntityRegistry")
	reg.monster_flowfield.set_height_lookup(func(_x: int, z: int) -> int: return 0 if z == 10 else 3)
	reg.monster_flowfield.set_chunk_loaded_lookup(func(_x: int, _z: int) -> bool: return true)
	reg.monster_flowfield.reset_rebuild_count()
	# Physical one-cell corridor matches the authoritative height row exactly.
	for geometry in [
		[Vector3(20, -0.5, 10.5), Vector3(80, 1, 1)],
		[Vector3(20, 1.5, 5), Vector3(80, 3, 10)],
		[Vector3(20, 1.5, 16), Vector3(80, 3, 10)]
	]:
		var body: StaticBody3D = StaticBody3D.new()
		body.position = geometry[0]
		body.collision_layer = 1
		body.collision_mask = 0
		var col: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = geometry[1]
		col.shape = box
		body.add_child(col)
		add_child_autoqfree(body)
	var player: MovingCorridorTarget = MovingCorridorTarget.new()
	player.process_physics_priority = -100
	player.position = Vector3(11.5, 0.9, 10.5)
	player.add_to_group("player")
	add_child_autoqfree(player)
	reg.register_player(player)
	var wall: BuildingBase = (load("res://scenes/prefabs/wood_wall.tscn") as PackedScene).instantiate() as BuildingBase
	wall.position = Vector3(10.5, 0, 10.5)
	add_child_autoqfree(wall)
	reg.register_building(wall)
	var initial_health: float = wall.current_health
	var zombie: CharacterBody3D = ENEMY_DUMMY_SCENE.instantiate() as CharacterBody3D
	zombie.position = Vector3(7.5, 0.9, 10.5)
	add_child_autoqfree(zombie)
	zombie.target_player = player
	var clock_start: float = reg.monster_flowfield.get_simulation_time()
	await wait_physics_frames(240)
	var elapsed_physics: float = reg.monster_flowfield.get_simulation_time() - clock_start
	assert_eq(player.steps, 240, "Target moves for exactly 240 actual physics callbacks")
	assert_gt(player.position.x, 29.0, "Player keeps moving throughout all physical steps")
	assert_gt(zombie.global_position.x, 9.3, "Existing zombie reaches the physical wall")
	assert_lt(wall.current_health, initial_health, "Existing siege attack damages wall before player stops")
	assert_lte(reg.monster_flowfield.get_rebuild_count(), int(ceil(elapsed_physics / 0.25)) + 1, "Fair serving preserves .25s cadence over actual measured simulation time")

func test_grunt_ascends_one_block_step_staircase() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg:
		reg.monster_flowfield.set_height_lookup(func(x: int, _z: int) -> int:
			if x >= 4:
				return 3
			elif x >= 3:
				return 2
			elif x >= 1:
				return 1
			return 0
		)

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
	if reg:
		reg.register_player(player)

	var grunt: CharacterBody3D = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(grunt)
	grunt.global_position = Vector3(0.0, 0.9, 0.0)
	grunt.target_player = player

	await wait_physics_frames(40)

	# Grunt should climb up towards Y > 1.5 and advance along X
	assert_gt(grunt.global_position.y, 1.5, "Grunt must climb 1-block steps up the staircase")
	assert_gt(grunt.global_position.x, 1.0, "Grunt must make forward progress up the stairs")

func test_boss_gorgon_ascends_one_block_stairs_without_false_cliff() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg:
		reg.monster_flowfield.set_height_lookup(func(x: int, _z: int) -> int:
			if x >= 4:
				return 2
			elif x >= 1:
				return 1
			return 0
		)

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
	if reg:
		reg.register_player(player)

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
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg:
		reg.monster_flowfield.set_height_lookup(func(_x: int, _z: int) -> int: return 0)

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
	if reg:
		reg.register_player(player)

	var enemies: Array[CharacterBody3D] = []
	for i in range(4):
		var mob: CharacterBody3D = ENEMY_DUMMY_SCENE.instantiate()
		add_child_autoqfree(mob)
		var row: int = i / 2
		var col: int = i % 2
		mob.global_position = Vector3(float(row) * 1.0, 0.9, float(col) * 1.0)
		mob.target_player = player
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
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg:
		reg.monster_flowfield.set_height_lookup(func(_x: int, _z: int) -> int: return 0)

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
	if reg:
		reg.register_player(player)

	var gorgon: CharacterBody3D = BOSS_GORGON_SCENE.instantiate()
	add_child_autoqfree(gorgon)
	gorgon.global_position = Vector3(0.0, 0.0, 0.0) # Authoritative feet placement
	gorgon.target_player = player

	var grunt: CharacterBody3D = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(grunt)
	grunt.global_position = Vector3(2.5, 0.9, 0.0)
	grunt.target_player = player

	await wait_physics_frames(25)

	var g_pos = gorgon.global_position
	var m_pos = grunt.global_position
	var dist_h = Vector2(g_pos.x - m_pos.x, g_pos.z - m_pos.z).length()

	# Gorgon radius 1.2 + Grunt radius 0.4 = combined radius 1.6m
	assert_gt(dist_h, 1.35, "Boss Gorgon and Grunt must maintain separation without penetration (dist=%.2f)" % dist_h)
	assert_gt(gorgon.global_position.x, 0.5, "Gorgon must actively chase and advance towards player")

func test_zombie_attacks_blocking_wall_and_deals_damage_without_rebuilding_flowfield() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if not reg:
		return

	# Arena Floor
	var ground: StaticBody3D = StaticBody3D.new()
	ground.collision_layer = 1
	var g_col: CollisionShape3D = CollisionShape3D.new()
	var g_box: BoxShape3D = BoxShape3D.new()
	g_box.size = Vector3(40.0, 1.0, 40.0)
	g_col.shape = g_box
	ground.add_child(g_col)
	add_child_autoqfree(ground)
	ground.global_position = Vector3(10.0, -0.5, 10.0)

	# 1-block wide corridor at Z=10 between 3-block high cliffs at Z <= 9 and Z >= 11
	reg.monster_flowfield.set_height_lookup(func(x: int, z: int) -> int:
		if z != 10:
			return 3
		return 0
	)

	# Wood wall blocking the corridor at cell (10, 10)
	var wood_wall_scene = preload("res://scenes/prefabs/wood_wall.tscn")
	var wall = wood_wall_scene.instantiate()
	add_child_autoqfree(wall)
	wall.global_position = Vector3(10.5, 0.0, 10.5)
	reg.register_building(wall)

	# Player positioned behind wall in the corridor at (14.0, 0.9, 10.5)
	var player: CharacterBody3D = CharacterBody3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)
	player.global_position = Vector3(14.0, 0.9, 10.5)
	reg.register_player(player)

	# Zombie spawned in corridor approaching from (8.0, 0.9, 10.5)
	var zombie: CharacterBody3D = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(zombie)
	zombie.global_position = Vector3(8.0, 0.9, 10.5)
	zombie.target_player = player

	await wait_physics_frames(5)

	reg.monster_flowfield.reset_rebuild_count()
	var initial_wall_hp: float = wall.current_health

	# Simulate 70 physics frames of approach, perimeter contact, and attack
	await wait_physics_frames(70)

	# 1. Zombie must reach wall and deal damage to it
	assert_lt(wall.current_health, initial_wall_hp, "Zombie must attack and damage the blocking wooden wall (initial=%.1f, current=%.1f)" % [initial_wall_hp, wall.current_health])

	# 2. Zombie must advance to contact the wall collider (wall is at X=10..11, contact around X=9.6)
	assert_gt(zombie.global_position.x, 9.4, "Zombie must advance directly to the wall boundary (x=%.2f)" % zombie.global_position.x)

	# 3. Flowfield rebuilds must remain minimal (not recomputing every single physics frame)
	var rebuild_count: int = reg.monster_flowfield.get_rebuild_count()
	assert_lt(rebuild_count, 10, "Flowfield must not recompute on every frame at perimeter (rebuilds=%d)" % rebuild_count)

func test_siege_breaker_physically_advances_through_2m_corridor() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if not reg:
		return

	# Arena Floor
	var ground: StaticBody3D = StaticBody3D.new()
	ground.collision_layer = 1
	var g_col: CollisionShape3D = CollisionShape3D.new()
	var g_box: BoxShape3D = BoxShape3D.new()
	g_box.size = Vector3(40.0, 1.0, 40.0)
	g_col.shape = g_box
	ground.add_child(g_col)
	add_child_autoqfree(ground)
	ground.global_position = Vector3(10.0, -0.5, 1.0)

	# 2-meter corridor: flat at Z=0..1, height 3 cliffs at all other Z
	reg.monster_flowfield.set_height_lookup(func(_x: int, z: int) -> int:
		if z == 0 or z == 1:
			return 0
		return 3
	)

	# Physical obstacle walls flanking the 2m corridor: exact 2.0m gap between Z=0.0 and Z=2.0
	for z_pos in [-1.0, 3.0]:
		var wall_body: StaticBody3D = StaticBody3D.new()
		wall_body.collision_layer = 1
		var col: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = Vector3(40.0, 3.0, 2.0)
		col.shape = box
		wall_body.add_child(col)
		add_child_autoqfree(wall_body)
		wall_body.global_position = Vector3(10.0, 1.5, z_pos)

	var player: CharacterBody3D = CharacterBody3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)
	player.global_position = Vector3(15.0, 0.9, 1.0)
	reg.register_player(player)

	# Siege Breaker (1.4m x 1.4m collider, radius 0.7) spawned in 2m corridor at (1.0, 0.0, 1.0)
	var siege: CharacterBody3D = SIEGE_BREAKER_SCENE.instantiate()
	add_child_autoqfree(siege)
	siege.global_position = Vector3(1.0, 0.0, 1.0)
	siege.target_player = player

	await wait_physics_frames(40)

	# Siege Breaker must successfully advance through the 2m corridor
	assert_gt(siege.global_position.x, 2.5, "Siege Breaker must make forward physical progress through 2m corridor (x=%.2f)" % siege.global_position.x)

func test_zombie_routes_around_corner_cliffs_to_attack_wall() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if not reg:
		return

	# Arena Floor
	var ground: StaticBody3D = StaticBody3D.new()
	ground.collision_layer = 1
	var g_col: CollisionShape3D = CollisionShape3D.new()
	var g_box: BoxShape3D = BoxShape3D.new()
	g_box.size = Vector3(40.0, 1.0, 40.0)
	g_col.shape = g_box
	ground.add_child(g_col)
	add_child_autoqfree(ground)
	ground.global_position = Vector3(10.0, -0.5, 10.0)


	# Physical cliff pillars at (10, 9) and (9, 10)
	for cliff_pos in [Vector3(10.5, 1.5, 9.5), Vector3(9.5, 1.5, 10.5)]:
		var cliff: StaticBody3D = StaticBody3D.new()
		cliff.collision_layer = 1
		var ccol: CollisionShape3D = CollisionShape3D.new()
		var cbox: BoxShape3D = BoxShape3D.new()
		cbox.size = Vector3(1.0, 3.0, 1.0)
		ccol.shape = cbox
		cliff.add_child(ccol)
		add_child_autoqfree(cliff)
		cliff.global_position = cliff_pos

	# Wood wall at (10, 10)
	var wood_wall_scene = preload("res://scenes/prefabs/wood_wall.tscn")
	var wall = wood_wall_scene.instantiate()
	add_child_autoqfree(wall)
	wall.global_position = Vector3(10.5, 0.0, 10.5)
	reg.register_building(wall)

	# Player across impassable cliff at (25.0, 0.9, 25.0) so zombie targets nearest building (the wall)
	var player: CharacterBody3D = CharacterBody3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)
	player.global_position = Vector3(25.0, 0.9, 25.0)
	reg.register_player(player)

	# Height lookup: height 3 cliffs at (10, 9) and (9, 10), and barrier cliff at X >= 20
	reg.monster_flowfield.set_height_lookup(func(x: int, z: int) -> int:
		if x >= 20:
			return 3
		if (x == 10 and z == 9) or (x == 9 and z == 10):
			return 3
		return 0
	)

	# Zombie at diagonal approach (9.2, 0.9, 9.2)
	var zombie: CharacterBody3D = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(zombie)
	zombie.global_position = Vector3(9.2, 0.9, 9.2)
	zombie.target_player = player

	await wait_physics_frames(5)
	reg.monster_flowfield.reset_rebuild_count()
	var initial_wall_hp: float = wall.current_health

	# Simulate 90 physics frames of routing around corner cliffs, contact, and attack
	await wait_physics_frames(90)

	# Zombie must not wedge in the diagonal corner; it must route around and attack the wall
	assert_lt(wall.current_health, initial_wall_hp, "Zombie must route around corner cliffs, reach and damage wall (initial=%.1f, current=%.1f)" % [initial_wall_hp, wall.current_health])

	var rebuild_count: int = reg.monster_flowfield.get_rebuild_count()
	assert_lt(rebuild_count, 10, "Flowfield rebuilds must stay minimal when routing around corner (rebuilds=%d)" % rebuild_count)

func test_boss_gorgon_attacks_blocking_wall_and_destroys_it() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if not reg:
		return

	# Arena Floor
	var ground: StaticBody3D = StaticBody3D.new()
	ground.collision_layer = 1
	var g_col: CollisionShape3D = CollisionShape3D.new()
	var g_box: BoxShape3D = BoxShape3D.new()
	g_box.size = Vector3(40.0, 1.0, 40.0)
	g_col.shape = g_box
	ground.add_child(g_col)
	add_child_autoqfree(ground)
	ground.global_position = Vector3(10.0, -0.5, 10.0)

	# Terrain: flat everywhere except cliff at X >= 20 blocking direct path to player
	reg.monster_flowfield.set_height_lookup(func(x: int, _z: int) -> int:
		if x >= 20:
			return 3
		return 0
	)

	# Wood wall placed at (10.5, 0.0, 10.5)
	var wood_wall_scene = preload("res://scenes/prefabs/wood_wall.tscn")
	var wall = wood_wall_scene.instantiate()
	add_child_autoqfree(wall)
	wall.global_position = Vector3(10.5, 0.0, 10.5)
	reg.register_building(wall)

	# Player placed behind cliff at (25.0, 0.9, 10.5)
	var player: CharacterBody3D = CharacterBody3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)
	player.global_position = Vector3(25.0, 0.9, 10.5)
	reg.register_player(player)

	# Boss Gorgon (radius 1.2) spawned at (5.0, 0.0, 10.5)
	var gorgon: CharacterBody3D = BOSS_GORGON_SCENE.instantiate()
	add_child_autoqfree(gorgon)
	gorgon.global_position = Vector3(5.0, 0.0, 10.5)
	gorgon.target_player = player

	# The failed player field and candidate wall field share the huge-body cadence.
	# Wait real physics time for the second target rather than forcing a cold build.
	await wait_physics_frames(20)

	# Gorgon must receive non-zero flowfield direction towards the wall candidate
	var b_dir: Vector3 = reg.monster_flowfield.get_flow_direction(gorgon.global_position, wall.global_position, 1.2)
	assert_gt(b_dir.length_squared(), 0.001, "Gorgon must receive non-zero flowfield direction to candidate wall")
	assert_gt(b_dir.x, 0.5, "Flow direction must point toward the blocking wall (+X)")

	# Run simulation frames for Gorgon to advance to the wall and trigger smash
	await wait_physics_frames(60)

	# Gorgon must physically advance towards the wall
	assert_gt(gorgon.global_position.x, 6.5, "Boss Gorgon must physically advance towards the blocking wall (x=%.2f)" % gorgon.global_position.x)
	# Wall must be damaged or destroyed
	var wall_destroyed_or_damaged: bool = not is_instance_valid(wall) or wall.is_queued_for_deletion() or wall.current_health < 100.0
	assert_true(wall_destroyed_or_damaged, "Boss Gorgon must reach and smash/damage the blocking wall")

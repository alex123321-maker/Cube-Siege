extends GutTest

const WOOD_WALL_SCENE = preload("res://scenes/prefabs/wood_wall.tscn")
const ARCHER_TOWER_SCENE = preload("res://scenes/prefabs/archer_tower.tscn")
const BALLISTA_TOWER_SCENE = preload("res://scenes/prefabs/ballista_tower.tscn")
const FLOOR_SPIKES_SCENE = preload("res://scenes/prefabs/floor_spikes.tscn")
const IRON_WALL_SCENE = preload("res://scenes/prefabs/iron_wall.tscn")
const ARROW_PROJECTILE_SCENE = preload("res://scenes/prefabs/arrow_projectile.tscn")
const ENEMY_DUMMY_SCENE = preload("res://scenes/enemy_dummy.tscn")
const RESOURCE_TREE_SCENE = preload("res://scenes/resource_tree.tscn")
const DECOY_DUMMY_SCENE = preload("res://scenes/prefabs/decoy_dummy.tscn")
const PLAYER_SCENE = preload("res://scenes/player.tscn")
const CombatRules = preload("res://scripts/combat/combat_rules.gd")

func after_each() -> void:
	await wait_seconds(0.2)
	for child in get_children():
		if child != null and is_instance_valid(child) and not child.is_queued_for_deletion():
			if child.name.begins_with("FloatingText") or child.name.begins_with("ArrowProjectile") or (child.get_script() and child.get_script().resource_path.ends_with("floating_text.gd")):
				child.queue_free()

func test_player_attacks_cannot_damage_friendly_buildings() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)

	var wall = WOOD_WALL_SCENE.instantiate()
	add_child_autoqfree(wall)
	wall.global_position = Vector3(0, 0, -1.2)

	var tower = ARCHER_TOWER_SCENE.instantiate()
	add_child_autoqfree(tower)
	tower.global_position = Vector3(1.5, 0, -1.2)

	var spikes = FLOOR_SPIKES_SCENE.instantiate()
	add_child_autoqfree(spikes)
	spikes.global_position = Vector3(-1.5, 0, -1.2)

	# 1. Warrior basic slash & cleave
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.combat.attack_cooldown_timer = 0.0
	player.look_at(player.global_position + Vector3(0, 0, -1), Vector3.UP)
	player.combat.trigger_slash(player, 50.0, 5.0, 180.0, false, true)
	await wait_seconds(0.25)

	assert_eq(wall.current_health, wall.max_health, "Warrior slash/cleave must not damage wall")
	assert_eq(tower.current_health, tower.max_health, "Warrior slash/cleave must not damage tower")
	assert_eq(spikes.current_health, spikes.max_health, "Warrior slash/cleave must not damage spikes")

	# 2. Archer basic arrow & piercing arrow
	player.set_class(player.CharacterClass.ARCHER, false)
	var arrow = ARROW_PROJECTILE_SCENE.instantiate()
	add_child_autoqfree(arrow)
	arrow.global_position = wall.global_position
	arrow.setup(Vector3.FORWARD, 40.0, player, 1)
	if arrow.hitbox:
		arrow.hitbox._on_area_entered(wall.hurtbox)

	assert_eq(wall.current_health, wall.max_health, "Archer arrow must not damage friendly wall")
	assert_eq(arrow.pierce_count, 1, "Arrow pierce count must not be consumed by friendly building")

	# 3. Engineer hammer smash
	player.set_class(player.CharacterClass.ENGINEER, false)
	player.combat.trigger_hammer_smash(player, 60.0, false)
	await wait_seconds(0.25)
	assert_eq(wall.current_health, wall.max_health, "Engineer hammer smash must not damage friendly wall")

func test_arrow_prefab_single_damage_and_no_building_damage() -> void:
	var wall = WOOD_WALL_SCENE.instantiate()
	add_child_autoqfree(wall)
	wall.global_position = Vector3(0, 0, -2.0)

	var enemy = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy)
	enemy.global_position = Vector3(0, 0, -5.0)
	var enemy_hurtbox: Area3D = enemy.get_node("Hurtbox") as Area3D
	var wall_hurtbox: Area3D = wall.get_node("Hurtbox") as Area3D

	var tower = ARCHER_TOWER_SCENE.instantiate()
	add_child_autoqfree(tower)

	# 1. Arrow intersects friendly wall
	var arrow1 = ARROW_PROJECTILE_SCENE.instantiate()
	add_child_autoqfree(arrow1)
	arrow1.setup(Vector3.FORWARD, 30.0, tower, 1)

	# Simulate area_entered directly on hitbox and arrow's handler
	arrow1.hitbox._on_area_entered(wall_hurtbox)
	arrow1._on_hitbox_area_entered(wall_hurtbox)

	assert_eq(wall.current_health, wall.max_health, "Wall must take 0 damage from arrow")
	assert_eq(arrow1.pierce_count, 1, "Arrow pierce count must not decrease when overlapping friendly wall")
	assert_false(arrow1.is_queued_for_deletion(), "Arrow must not be freed on friendly wall overlap")

	# 2. Arrow intersects enemy: must take EXACTLY 30 damage (single authoritative path)
	var arrow2 = ARROW_PROJECTILE_SCENE.instantiate()
	add_child_autoqfree(arrow2)
	arrow2.setup(Vector3.FORWARD, 30.0, tower, 1)

	var initial_enemy_hp: float = enemy.current_health
	# Both listeners receive area_entered signal in real prefab
	arrow2.hitbox._on_area_entered(enemy_hurtbox)
	arrow2._on_hitbox_area_entered(enemy_hurtbox)

	assert_eq(
		enemy.current_health,
		initial_enemy_hp - 30.0,
		"Enemy must receive exactly 30 damage once, without double damage from competing handlers"
	)
	assert_eq(arrow2.pierce_count, 0, "Arrow pierce count must decrease to 0 on confirmed hit")

func test_adjacent_towers_fire_without_friendly_damage() -> void:
	var tower1 = ARCHER_TOWER_SCENE.instantiate()
	add_child_autoqfree(tower1)
	tower1.global_position = Vector3(0, 0, 0)

	var tower2 = ARCHER_TOWER_SCENE.instantiate()
	add_child_autoqfree(tower2)
	tower2.global_position = Vector3(2.0, 0, 0)

	var wall = WOOD_WALL_SCENE.instantiate()
	add_child_autoqfree(wall)
	wall.global_position = Vector3(1.0, 0, 0)

	# Tower 1 fires across towards Tower 2 and Wall
	var arrow = ARROW_PROJECTILE_SCENE.instantiate()
	add_child_autoqfree(arrow)
	arrow.setup(Vector3.RIGHT, 30.0, tower1, 1)

	# Overlap with tower1 itself (self hit)
	arrow.hitbox._on_area_entered(tower1.hurtbox)
	assert_eq(tower1.current_health, tower1.max_health, "Tower 1 must not damage itself")

	# Overlap with adjacent wall
	arrow.hitbox._on_area_entered(wall.hurtbox)
	assert_eq(wall.current_health, wall.max_health, "Tower 1 arrow must not damage intermediate wall")

	# Overlap with tower2
	arrow.hitbox._on_area_entered(tower2.hurtbox)
	assert_eq(tower2.current_health, tower2.max_health, "Tower 1 arrow must not damage Tower 2")

func test_floor_spikes_overlapping_own_hurtbox_and_adjacent_buildings() -> void:
	var spikes = FLOOR_SPIKES_SCENE.instantiate()
	add_child_autoqfree(spikes)
	spikes.global_position = Vector3(0, 0, 0)

	var wall = WOOD_WALL_SCENE.instantiate()
	add_child_autoqfree(wall)
	wall.global_position = Vector3(0, 0, 0)

	var tree = RESOURCE_TREE_SCENE.instantiate()
	add_child_autoqfree(tree)
	tree.global_position = Vector3(0, 0, 0)

	var decoy = DECOY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(decoy)
	decoy.global_position = Vector3(0, 0, 0)

	var enemy = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy)
	enemy.global_position = Vector3(0, 0, 0)
	enemy.attack_timer = 999.0

	# Verify CombatRules rejects spikes damaging spikes hurtbox or wall hurtbox or decoy dummy
	assert_false(CombatRules.can_damage(spikes, spikes), "Spikes cannot damage itself")
	assert_false(CombatRules.can_damage(spikes, wall), "Spikes cannot damage adjacent wall")
	assert_false(CombatRules.can_damage(spikes, decoy), "Spikes cannot damage decoy dummy")
	assert_true(CombatRules.can_damage(spikes, enemy), "Spikes can damage enemy")

	# Wait for physics tick to register physical Area3D overlaps
	await wait_physics_frames(2)

	var overlapping: Array[Area3D] = spikes.damage_area.get_overlapping_areas()
	assert_true(overlapping.size() >= 4, "DamageArea must detect overlapping hurtboxes")

	var initial_spikes_hp: float = spikes.current_health
	var initial_wall_hp: float = wall.current_health
	var initial_tree_hp: float = tree.current_health
	var initial_decoy_hp: float = decoy.current_health
	var initial_enemy_hp: float = enemy.current_health

	# 1st trigger of check_and_damage_enemies()
	spikes.check_and_damage_enemies()

	assert_eq(spikes.current_health, initial_spikes_hp, "Spikes HP must not change (cannot damage self)")
	assert_eq(wall.current_health, initial_wall_hp, "Wall HP must not change (cannot damage friendly buildings)")
	assert_eq(tree.current_health, initial_tree_hp, "Tree HP must not change (spikes only target enemies)")
	assert_eq(decoy.current_health, initial_decoy_hp, "Decoy HP must not change (spikes only target enemies / friendly fire protected)")
	assert_eq(enemy.current_health, initial_enemy_hp - spikes.spike_damage, "Enemy must receive spike damage on first trigger")

	# 2nd trigger of check_and_damage_enemies() (multiple cycles)
	spikes.check_and_damage_enemies()

	assert_eq(spikes.current_health, initial_spikes_hp, "Spikes HP must remain intact after multiple triggers")
	assert_eq(wall.current_health, initial_wall_hp, "Wall HP must remain intact after multiple triggers")
	assert_eq(tree.current_health, initial_tree_hp, "Tree HP must remain intact after multiple triggers")
	assert_eq(decoy.current_health, initial_decoy_hp, "Decoy HP must remain intact after multiple triggers")
	assert_eq(enemy.current_health, initial_enemy_hp - (spikes.spike_damage * 2.0), "Enemy must take spike damage again on second trigger")

func test_iron_wall_thorns_reflection_only_against_enemies() -> void:
	var wall = IRON_WALL_SCENE.instantiate()
	add_child_autoqfree(wall)

	var player = Node3D.new()
	player.add_to_group("player")
	add_child_autoqfree(player)

	var tower = ARCHER_TOWER_SCENE.instantiate()
	add_child_autoqfree(tower)

	var enemy = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy)

	# 1. Player attack on IronWall: rejected, no reflection
	wall._on_damaged(50.0, Vector3.ZERO, "physical", player)
	assert_eq(wall.current_health, wall.max_health, "Iron wall must not take damage from player")

	# 2. Tower attack on IronWall: rejected, no reflection
	wall._on_damaged(50.0, Vector3.ZERO, "projectile", tower)
	assert_eq(wall.current_health, wall.max_health, "Iron wall must not take damage from tower")

	# 3. Enemy attack on IronWall: accepted, wall damaged, thorns reflected back
	var initial_enemy_hp: float = enemy.current_health
	wall._on_damaged(40.0, Vector3.ZERO, "melee", enemy)
	assert_eq(wall.current_health, wall.max_health - 40.0, "Iron wall must take damage from enemy")
	# 25% of 40 = 10 thorns damage
	assert_eq(enemy.current_health, initial_enemy_hp - 10.0, "Enemy must receive 25% reflected thorns damage")

	# 4. Direct wall.take_damage API from enemy: also accepted and reflects thorns
	var hp_before_direct = enemy.current_health
	var wall_hp_before_direct = wall.current_health
	var res_take_damage = wall.take_damage(40.0, enemy)
	assert_true(res_take_damage, "Direct wall.take_damage from enemy must return true")
	assert_eq(wall.current_health, wall_hp_before_direct - 40.0, "Iron wall must take damage via direct take_damage")
	assert_eq(enemy.current_health, hp_before_direct - 10.0, "Enemy must receive 25% reflected thorns damage via direct take_damage")

func test_delayed_attack_after_source_destruction() -> void:
	var tower = ARCHER_TOWER_SCENE.instantiate()
	add_child(tower)

	var wall = WOOD_WALL_SCENE.instantiate()
	add_child_autoqfree(wall)

	var enemy = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy)
	enemy.global_position = Vector3(10.0, 0, 0)
	enemy.attack_timer = 999.0

	var arrow = ARROW_PROJECTILE_SCENE.instantiate()
	add_child_autoqfree(arrow)
	arrow.setup(Vector3.FORWARD, 30.0, tower, 1)

	# Delete the tower that shot the arrow and wait for Godot to completely free it
	tower.queue_free()
	await wait_physics_frames(2)
	assert_false(is_instance_valid(tower), "Tower must be completely freed")

	assert_eq(arrow.source_team, CombatRules.Team.PLAYER, "Arrow must preserve Team.PLAYER provenance")

	# Track hit_confirmed signals emitted by arrow.hitbox
	var hits_confirmed: Array = []
	arrow.hitbox.hit_confirmed.connect(func(target, _dir): hits_confirmed.append(target))

	# Arrow hits friendly wall: must be rejected without errors, no pierce loss, no hit_confirmed
	var wall_hurtbox: Area3D = wall.get_node("Hurtbox") as Area3D
	arrow._on_hitbox_area_entered(wall_hurtbox)
	assert_eq(wall.current_health, wall.max_health, "Friendly wall must not take damage from orphaned arrow")
	assert_eq(arrow.pierce_count, 1, "Arrow pierce count must NOT decrease when hitting friendly wall")
	assert_eq(hits_confirmed.size(), 0, "No hit_confirmed signal on friendly wall hit")

	# Arrow hits enemy: must damage enemy, decrement pierce, emit hit_confirmed
	var enemy_hurtbox: Area3D = enemy.get_node("Hurtbox") as Area3D
	var initial_enemy_hp: float = enemy.current_health
	arrow._on_hitbox_area_entered(enemy_hurtbox)
	assert_eq(enemy.current_health, initial_enemy_hp - 30.0, "Enemy must take damage from orphaned ally arrow")
	assert_eq(arrow.pierce_count, 0, "Arrow pierce count must decrease to 0 on confirmed hit")
	assert_eq(hits_confirmed.size(), 1, "hit_confirmed must be emitted on hitting enemy")

	# Repeat hit event on enemy (competing area entered / second trigger): must NOT deal double damage
	arrow._on_hitbox_area_entered(enemy_hurtbox)
	assert_eq(enemy.current_health, initial_enemy_hp - 30.0, "Enemy must not take double damage on repeat hit event")
	assert_eq(hits_confirmed.size(), 1, "hit_confirmed must not be emitted again for already-hit target")

func test_building_repair_and_demolish() -> void:
	var wall = WOOD_WALL_SCENE.instantiate()
	add_child_autoqfree(wall)
	wall.current_health = 150.0

	# 1. Repair restores health
	var repaired = wall.repair(60.0)
	assert_true(repaired, "repair() must succeed")
	assert_eq(wall.current_health, 210.0, "Building health must increase by 60")

	# 2. Demolish destroys building
	var destroyed_emitted: Array = []
	wall.building_destroyed.connect(func(b): destroyed_emitted.append(b))
	wall.demolish()
	assert_eq(destroyed_emitted.size(), 1, "building_destroyed signal must be emitted on demolish")

func test_decoy_dummy_hurtbox_damage_sources() -> void:
	var decoy = DECOY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(decoy)
	var decoy_hurtbox: HurtboxArea = decoy.get_node("Hurtbox") as HurtboxArea
	assert_not_null(decoy_hurtbox, "Decoy must have a HurtboxArea node")

	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)

	var tower = ARCHER_TOWER_SCENE.instantiate()
	add_child_autoqfree(tower)

	var enemy = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy)
	enemy.global_position = Vector3(10.0, 0, 0)
	enemy.attack_timer = 999.0

	var initial_decoy_hp: float = decoy.current_health

	# 1. Known ally attacks (player, tower) on decoy must be rejected
	var res_p = decoy_hurtbox.take_damage(20.0, Vector3.ZERO, "physical", player)
	assert_false(res_p, "Decoy Hurtbox must reject damage from player")
	assert_eq(decoy.current_health, initial_decoy_hp, "Decoy HP must not change from player attack")

	var res_t = decoy_hurtbox.take_damage(20.0, Vector3.ZERO, "projectile", tower)
	assert_false(res_t, "Decoy Hurtbox must reject damage from tower")
	assert_eq(decoy.current_health, initial_decoy_hp, "Decoy HP must not change from tower attack")

	# 2. Delayed ally attack with null source but Team.PLAYER provenance must be rejected
	var res_delayed_ally = decoy_hurtbox.take_damage(20.0, Vector3.ZERO, "projectile", null, CombatRules.Team.PLAYER)
	assert_false(res_delayed_ally, "Decoy Hurtbox must reject delayed attack with Team.PLAYER provenance")
	assert_eq(decoy.current_health, initial_decoy_hp, "Decoy HP must not change from delayed ally attack")

	# 3. Scripted damage with null source and Team.NONE must be accepted
	var res_scripted = decoy_hurtbox.take_damage(20.0, Vector3.ZERO, "physical", null)
	assert_true(res_scripted, "Decoy Hurtbox must accept scripted null-source damage")
	assert_eq(decoy.current_health, initial_decoy_hp - 20.0, "Decoy HP must decrease by 20 from scripted damage")

	# 4. Neutral / environmental damage must be accepted
	var hp_after_scripted = decoy.current_health
	var res_neutral = decoy_hurtbox.take_damage(15.0, Vector3.ZERO, "environmental", null, CombatRules.Team.NEUTRAL)
	assert_true(res_neutral, "Decoy Hurtbox must accept neutral damage")
	assert_eq(decoy.current_health, hp_after_scripted - 15.0, "Decoy HP must decrease by 15 from neutral damage")

	# 5. Enemy attack must be accepted
	var hp_after_neutral = decoy.current_health
	var res_enemy = decoy_hurtbox.take_damage(25.0, Vector3.ZERO, "melee", enemy)
	assert_true(res_enemy, "Decoy Hurtbox must accept enemy damage")
	assert_eq(decoy.current_health, hp_after_neutral - 25.0, "Decoy HP must decrease by 25 from enemy damage")


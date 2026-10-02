extends GutTest

const WOOD_WALL_SCENE = preload("res://scenes/prefabs/wood_wall.tscn")
const ARCHER_TOWER_SCENE = preload("res://scenes/prefabs/archer_tower.tscn")
const BALLISTA_TOWER_SCENE = preload("res://scenes/prefabs/ballista_tower.tscn")
const FLOOR_SPIKES_SCENE = preload("res://scenes/prefabs/floor_spikes.tscn")
const IRON_WALL_SCENE = preload("res://scenes/prefabs/iron_wall.tscn")
const ARROW_PROJECTILE_SCENE = preload("res://scenes/prefabs/arrow_projectile.tscn")
const ENEMY_DUMMY_SCENE = preload("res://scenes/enemy_dummy.tscn")
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
	wall.global_position = Vector3(0.5, 0, 0)

	var enemy = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy)
	enemy.global_position = Vector3(0, 0, 0)

	# Verify CombatRules rejects spikes damaging spikes hurtbox or wall hurtbox
	assert_false(CombatRules.can_damage(spikes, spikes), "Spikes cannot damage itself")
	assert_false(CombatRules.can_damage(spikes, wall), "Spikes cannot damage adjacent wall")
	assert_true(CombatRules.can_damage(spikes, enemy), "Spikes can damage enemy")

	var initial_spikes_hp: float = spikes.current_health
	var initial_wall_hp: float = wall.current_health
	var initial_enemy_hp: float = enemy.current_health

	# Trigger spikes damage check with mock overlapping areas
	var enemy_hurtbox: Area3D = enemy.get_node("Hurtbox") as Area3D
	var wall_hurtbox: Area3D = wall.get_node("Hurtbox") as Area3D
	var spikes_hurtbox: Area3D = spikes.hurtbox

	for hurt in [spikes_hurtbox, wall_hurtbox, enemy_hurtbox]:
		var target: Node = hurt.get_target_node() if hurt.has_method("get_target_node") else hurt.get_parent()
		if target and CombatRules.can_damage(spikes, target):
			hurt.take_damage(spikes.spike_damage, Vector3.UP * 2.0, "spikes", spikes)

	assert_eq(spikes.current_health, initial_spikes_hp, "Spikes HP must not change")
	assert_eq(wall.current_health, initial_wall_hp, "Wall HP must not change")
	assert_eq(enemy.current_health, initial_enemy_hp - spikes.spike_damage, "Enemy must take spike damage")

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

func test_delayed_attack_after_source_destruction() -> void:
	var tower = ARCHER_TOWER_SCENE.instantiate()
	add_child_autoqfree(tower)

	var wall = WOOD_WALL_SCENE.instantiate()
	add_child_autoqfree(wall)

	var enemy = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy)

	var arrow = ARROW_PROJECTILE_SCENE.instantiate()
	add_child_autoqfree(arrow)
	arrow.setup(Vector3.FORWARD, 30.0, tower, 1)

	# Delete the tower that shot the arrow
	tower.queue_free()

	# Simulate physics tick where tower becomes invalid
	assert_eq(arrow.source_team, CombatRules.Team.PLAYER, "Arrow must preserve Team.PLAYER provenance")

	# Arrow hits friendly wall: must be rejected
	var wall_hurtbox: Area3D = wall.get_node("Hurtbox") as Area3D
	arrow.hitbox._on_area_entered(wall_hurtbox)
	assert_eq(wall.current_health, wall.max_health, "Friendly wall must not take damage from orphaned arrow")

	# Arrow hits enemy: must damage enemy
	var enemy_hurtbox: Area3D = enemy.get_node("Hurtbox") as Area3D
	var initial_enemy_hp: float = enemy.current_health
	arrow.hitbox._on_area_entered(enemy_hurtbox)
	assert_eq(enemy.current_health, initial_enemy_hp - 30.0, "Enemy must take damage from orphaned ally arrow")

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

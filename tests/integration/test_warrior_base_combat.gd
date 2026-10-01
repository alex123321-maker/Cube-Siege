extends GutTest

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const ENEMY_DUMMY_SCENE = preload("res://scenes/enemy_dummy.tscn")
const WOOD_WALL_SCENE = preload("res://scenes/prefabs/wood_wall.tscn")

var _save_snapshot: Dictionary = {}

func before_each() -> void:
	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr:
		_save_snapshot = save_mgr.snapshot_state()

func after_each() -> void:
	await wait_seconds(0.2)
	for child in get_children():
		if child != null and is_instance_valid(child) and child.name.begins_with("FloatingText"):
			child.queue_free()
	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr and not _save_snapshot.is_empty():
		save_mgr.restore_state(_save_snapshot)
		if save_mgr.is_test_environment():
			if FileAccess.file_exists(save_mgr.save_file_path):
				DirAccess.remove_absolute(save_mgr.save_file_path)

# ==============================================================================
# 1. WARRIOR BASIC ATTACK (SINGLE-TARGET) & CLEAVE (MULTI-TARGET)
# ==============================================================================

func test_warrior_basic_attack_hits_only_one_target() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.global_position = Vector3.ZERO
	player.look_at(Vector3(0, 0, -10), Vector3.UP)

	var enemy_a = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_a)
	enemy_a.global_position = Vector3(-0.5, 0, -1.5)

	var enemy_b = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_b)
	enemy_b.global_position = Vector3(0.5, 0, -1.5)

	var initial_hp_a: float = enemy_a.current_health
	var initial_hp_b: float = enemy_b.current_health

	# Trigger normal slash (LMB)
	player.combat.trigger_slash(player, 25.0, 5.0, 90.0, false, false)
	# Process physics overlaps
	if player.slash_area.has_method("_on_area_entered"):
		player.slash_area._on_area_entered(enemy_a.hurtbox)
		player.slash_area._on_area_entered(enemy_b.hurtbox)

	var a_damaged: bool = enemy_a.current_health < initial_hp_a
	var b_damaged: bool = enemy_b.current_health < initial_hp_b

	assert_true(a_damaged != b_damaged, "Exactly one target must be damaged by basic attack")
	assert_eq(player.slash_area.hits_landed, 1, "HitboxArea hits_landed must be exactly 1")

func test_warrior_cleave_hits_multiple_targets() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.global_position = Vector3.ZERO

	var enemy_a = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_a)
	enemy_a.global_position = Vector3(-0.5, 0, -1.5)

	var enemy_b = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_b)
	enemy_b.global_position = Vector3(0.5, 0, -1.5)

	var initial_hp_a: float = enemy_a.current_health
	var initial_hp_b: float = enemy_b.current_health

	# Cleave (RMB) with can_hit_multiple = true
	player.combat.trigger_slash(player, 60.0, 12.0, 180.0, false, true)
	if player.slash_area.has_method("_on_area_entered"):
		player.slash_area._on_area_entered(enemy_a.hurtbox)
		player.slash_area._on_area_entered(enemy_b.hurtbox)

	assert_lt(enemy_a.current_health, initial_hp_a, "Enemy A damaged by Cleave")
	assert_lt(enemy_b.current_health, initial_hp_b, "Enemy B damaged by Cleave")
	assert_eq(player.slash_area.hits_landed, 2, "HitboxArea hits_landed must be 2 for Cleave")

func test_warrior_basic_attack_late_entry_rejected() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)

	var enemy_a = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_a)
	var enemy_b = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_b)

	player.combat.trigger_slash(player, 25.0, 5.0, 90.0, false, false)
	player.slash_area._on_area_entered(enemy_a.hurtbox)
	assert_eq(player.slash_area.hits_landed, 1)

	# Enemy B enters late during same swing window
	var hp_b_before = enemy_b.current_health
	player.slash_area._on_area_entered(enemy_b.hurtbox)
	assert_eq(enemy_b.current_health, hp_b_before, "Late entrant must not receive damage")
	assert_eq(player.slash_area.hits_landed, 1, "Hits landed remains 1")

func test_warrior_basic_attack_multiple_hurtboxes_same_target() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)

	var enemy = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy)
	var initial_hp = enemy.current_health

	player.combat.trigger_slash(player, 25.0, 5.0, 90.0, false, false)
	# Trigger with same hurtbox twice
	player.slash_area._on_area_entered(enemy.hurtbox)
	player.slash_area._on_area_entered(enemy.hurtbox)

	assert_eq(enemy.current_health, initial_hp - 25.0, "Same target damaged only once")
	assert_eq(player.slash_area.hits_landed, 1)

func test_warrior_basic_attack_dead_target_does_not_restore_limit() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)

	var enemy_a = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_a)
	var enemy_b = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_b)

	player.combat.trigger_slash(player, 25.0, 5.0, 90.0, false, false)
	player.slash_area._on_area_entered(enemy_a.hurtbox)
	assert_eq(player.slash_area.hits_landed, 1)

	# Enemy A dies
	enemy_a.is_dying = true

	# Another target enters during same swing
	var hp_b_before = enemy_b.current_health
	player.slash_area._on_area_entered(enemy_b.hurtbox)
	assert_eq(enemy_b.current_health, hp_b_before, "Death of target does not restore single-hit limit")

func test_warrior_basic_attack_rejected_contact_does_not_consume_limit() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)

	var wall = WOOD_WALL_SCENE.instantiate()
	add_child_autoqfree(wall)
	var enemy = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy)

	player.combat.trigger_slash(player, 25.0, 5.0, 90.0, false, false)

	# Wall enters first (friendly building)
	var wall_hurtbox = wall.get_node_or_null("Hurtbox") as Area3D
	if wall_hurtbox:
		player.slash_area._on_area_entered(wall_hurtbox)
	assert_eq(player.slash_area.hits_landed, 0, "Friendly wall must not consume hit limit")

	# Now valid enemy enters
	var enemy_hp_before = enemy.current_health
	player.slash_area._on_area_entered(enemy.hurtbox)
	assert_lt(enemy.current_health, enemy_hp_before, "Valid enemy damaged after rejected friendly building")
	assert_eq(player.slash_area.hits_landed, 1)

func test_warrior_alternating_lmb_rmb_does_not_leak_mode() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)

	var enemy_1 = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_1)
	var enemy_2 = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_2)

	# 1. Normal attack (LMB) -> Single target
	player.combat.trigger_slash(player, 25.0, 5.0, 90.0, false, false)
	assert_false(player.slash_area.can_hit_multiple, "LMB slash has can_hit_multiple = false")

	# 2. Cleave (RMB) -> Multi target
	player.combat.trigger_slash(player, 60.0, 12.0, 180.0, false, true)
	assert_true(player.slash_area.can_hit_multiple, "RMB cleave has can_hit_multiple = true")

	# 3. Normal attack (LMB) again -> Single target
	player.combat.trigger_slash(player, 25.0, 5.0, 90.0, false, false)
	assert_false(player.slash_area.can_hit_multiple, "LMB slash returned to can_hit_multiple = false")

func test_engineer_hammer_retains_multi_hit() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.ENGINEER, false)

	player.combat.trigger_hammer_smash(player, 33.75, false)
	assert_true(player.slash_area.can_hit_multiple, "Engineer hammer smash must hit multiple targets")

# ==============================================================================
# 2. PARRY (ABSORB FIRST HIT, NO COUNTER DAMAGE, PRESERVE STUN)
# ==============================================================================

func test_parry_absorbs_first_hit_second_hit_damages() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	watch_signals(player)

	player.health.trigger_parry(0.5, 6.0)
	assert_true(player.health.is_parrying, "Parry is active")

	var initial_hp = player.current_health

	# 1st hit during parry: absorbed
	player.take_damage(20.0)
	assert_eq(player.current_health, initial_hp, "1st hit absorbed by parry")
	assert_false(player.health.is_parrying, "Parry consumed immediately on first hit")
	assert_signal_emitted_with_parameters(player, "parry_triggered", [true])
	assert_eq(player.health.parry_cooldown_timer, 3.0, "Cooldown set to 3.0 on success")

	# 2nd hit in same step: parry already consumed, deals damage
	player.take_damage(20.0)
	assert_eq(player.current_health, initial_hp - 20.0, "2nd hit penetrates spent parry")

func test_parry_removes_counter_damage_preserves_stun() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)

	var enemy = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy)
	enemy.global_position = player.global_position + Vector3(0, 0, 1.5)

	var enemy_initial_hp = enemy.current_health
	player.health.trigger_parry(0.5, 6.0)

	# Take damage from enemy to trigger parry branch
	player.take_damage(15.0, enemy)

	# Assert enemy received NO counter damage and was stunned
	assert_eq(enemy.current_health, enemy_initial_hp, "Enemy must receive NO counter damage from parry")
	assert_true(enemy.is_stunned, "Enemy must receive stun from parry")
	assert_eq(enemy.stun_timer, 1.0, "Stun duration must be 1.0s")

func test_parry_window_expiry_restores_damage_reception() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)

	player.health.trigger_parry(0.5, 6.0)
	assert_true(player.health.is_parrying)

	# Expire parry window
	player.health.update_timers(0.51)
	assert_false(player.health.is_parrying, "Parry window expired")
	assert_almost_eq(player.health.parry_cooldown_timer, 6.0 - 0.51, 0.01, "Failed parry keeps 6s base cooldown")

	var initial_hp = player.current_health
	player.take_damage(25.0)
	assert_eq(player.current_health, initial_hp - 25.0, "Damage dealt after parry expired")

# ==============================================================================
# 3. WARRIOR DASH VULNERABILITY & CLASS ISOLATION
# ==============================================================================

func test_warrior_takes_damage_during_dash() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)

	player.movement.perform_dash(Vector3.FORWARD)
	assert_true(player.movement.is_dashing, "Movement state is dashing")
	assert_false(player.is_dash_invulnerable(), "Warrior has no dash invulnerability")

	var initial_hp = player.current_health
	player.take_damage(30.0)
	assert_eq(player.current_health, initial_hp - 30.0, "Warrior must take damage during dash")

func test_archer_and_engineer_retain_dash_immunity() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)

	# Archer
	player.set_class(player.CharacterClass.ARCHER, false)
	player.movement.perform_dash(Vector3.FORWARD)
	assert_true(player.movement.is_dashing)
	assert_true(player.is_dash_invulnerable(), "Archer retains dash invulnerability")

	var hp_archer = player.current_health
	player.take_damage(30.0)
	assert_eq(player.current_health, hp_archer, "Archer immune to damage during dash")

	# Reset dash
	player.movement.is_dashing = false
	player.movement.dash_timer = 0.0
	player.movement.dash_cooldown_timer = 0.0

	# Engineer
	player.set_class(player.CharacterClass.ENGINEER, false)
	player.movement.perform_dash(Vector3.FORWARD)
	assert_true(player.movement.is_dashing)
	assert_true(player.is_dash_invulnerable(), "Engineer retains dash invulnerability")

	var hp_eng = player.current_health
	player.take_damage(30.0)
	assert_eq(player.current_health, hp_eng, "Engineer immune to damage during dash")

func test_class_switching_isolates_dash_state() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)

	# Switch Archer -> Warrior
	player.set_class(player.CharacterClass.ARCHER, false)
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.movement.perform_dash(Vector3.FORWARD)
	assert_false(player.is_dash_invulnerable(), "Warrior is not invulnerable after switching from Archer")

	var initial_hp = player.current_health
	player.take_damage(20.0)
	assert_eq(player.current_health, initial_hp - 20.0, "Takes damage after class switch")

func test_warrior_dash_combined_with_parry() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)

	player.movement.perform_dash(Vector3.FORWARD)
	player.health.trigger_parry(0.5, 6.0)

	var initial_hp = player.current_health

	# Hit 1: Parry absorbs the hit even though dashing
	player.take_damage(25.0)
	assert_eq(player.current_health, initial_hp, "Parry absorbs hit during dash")

	# Hit 2: Parry is now spent, warrior still dashing -> takes damage
	player.take_damage(25.0)
	assert_eq(player.current_health, initial_hp - 25.0, "Warrior takes damage during dash once parry is spent")

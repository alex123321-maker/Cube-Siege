extends GutTest

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const ENEMY_DUMMY_SCENE = preload("res://scenes/enemy_dummy.tscn")
const SIEGE_BREAKER_SCENE = preload("res://scenes/enemies/siege_breaker.tscn")
const WOOD_WALL_SCENE = preload("res://scenes/prefabs/wood_wall.tscn")

var _save_snapshot: Dictionary = {}

func before_each() -> void:
	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr:
		_save_snapshot = save_mgr.snapshot_state()

func after_each() -> void:
	await wait_seconds(0.2)
	for child in get_children():
		if child != null and is_instance_valid(child) and not child.is_queued_for_deletion():
			if child.name.begins_with("FloatingText") or child.name.begins_with("ArrowProjectile") or (child.get_script() and child.get_script().resource_path.ends_with("floating_text.gd")):
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

func test_warrior_basic_attack_single_target_via_perform_attack() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.global_position = Vector3.ZERO
	player.look_at(Vector3(0, 0, -10), Vector3.UP)

	var enemy_a = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_a)
	enemy_a.global_position = Vector3(-0.4, 0, -1.5)

	var enemy_b = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_b)
	enemy_b.global_position = Vector3(0.4, 0, -1.5)

	await wait_physics_frames(3)
	watch_signals(player.slash_area)

	var hp_a_before: float = enemy_a.current_health
	var hp_b_before: float = enemy_b.current_health

	# Trigger through public player method
	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	await wait_seconds(0.25)

	var a_damaged: bool = enemy_a.current_health < hp_a_before
	var b_damaged: bool = enemy_b.current_health < hp_b_before

	assert_true(a_damaged != b_damaged, "Exactly one target must be damaged by basic attack")
	assert_eq(player.slash_area.hits_landed, 1, "HitboxArea hits_landed must be exactly 1")
	assert_signal_emitted(player.slash_area, "hit_confirmed")
	assert_eq(get_signal_emit_count(player.slash_area, "hit_confirmed"), 1, "hit_confirmed emitted exactly once")

func test_warrior_basic_attack_late_entry_during_active_window() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.global_position = Vector3.ZERO
	player.look_at(Vector3(0, 0, -10), Vector3.UP)

	var enemy_a = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_a)
	enemy_a.move_speed = 0.0
	enemy_a.attack_timer = 99.0
	enemy_a.global_position = Vector3(-0.3, 0, -1.5)

	var enemy_b = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_b)
	enemy_b.move_speed = 0.0
	enemy_b.attack_timer = 99.0
	enemy_b.global_position = Vector3(15.0, 0, 0) # Far outside initial area

	await wait_physics_frames(3)

	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	# Wait for swing to start and connect with enemy_a (0.06s timer in perform_attack + physics frame)
	await wait_seconds(0.12)
	assert_lt(enemy_a.current_health, 80.0, "Enemy A hit by first overlap")

	# Move enemy_b into the active slash area while window is still active
	enemy_b.global_position = Vector3(0.3, 0, -1.5)
	await wait_physics_frames(3)
	await wait_seconds(0.15)

	assert_eq(enemy_b.current_health, 80.0, "Late entrant receives no damage because quota was already spent")
	assert_eq(player.slash_area.hits_landed, 1)

func test_warrior_basic_attack_target_exit_and_reentry_during_active_window() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.global_position = Vector3.ZERO
	player.look_at(Vector3(0, 0, -10), Vector3.UP)

	var enemy = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy)
	enemy.move_speed = 0.0
	enemy.attack_timer = 99.0
	enemy.global_position = Vector3(0.0, 0.0, -1.5)

	await wait_physics_frames(3)
	watch_signals(player.slash_area)

	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	await wait_seconds(0.10)

	assert_eq(enemy.current_health, 55.0, "Target receives initial hit")
	assert_eq(player.slash_area.hits_landed, 1)

	# Target exits the slash hitbox during the active swing window
	enemy.global_position = Vector3(10.0, 0.0, 0.0)
	await wait_physics_frames(2)

	# Target re-enters the slash hitbox during the active swing window
	enemy.global_position = Vector3(0.0, 0.0, -1.5)
	await wait_physics_frames(2)
	await wait_seconds(0.15)

	assert_eq(enemy.current_health, 55.0, "Target receives no second damage on re-entry during same swing")
	assert_eq(player.slash_area.hits_landed, 1)
	assert_eq(get_signal_emit_count(player.slash_area, "hit_confirmed"), 1, "hit_confirmed emitted exactly once")

func test_warrior_basic_attack_multiple_hurtboxes_same_target() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.global_position = Vector3.ZERO
	player.look_at(Vector3(0, 0, -10), Vector3.UP)

	var enemy = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy)
	enemy.global_position = Vector3(0, 0, -1.5)

	# Add second HurtboxArea to the same enemy target with proper wiring to enemy._on_damaged
	var extra_hurtbox = HurtboxArea.new()
	var extra_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(1.0, 2.0, 1.0)
	extra_shape.shape = box
	extra_hurtbox.add_child(extra_shape)
	extra_hurtbox.collision_layer = enemy.hurtbox.collision_layer
	extra_hurtbox.collision_mask = enemy.hurtbox.collision_mask
	extra_hurtbox.target_node = enemy
	extra_hurtbox.damaged.connect(Callable(enemy, "_on_damaged"))
	enemy.add_child(extra_hurtbox)

	await wait_physics_frames(3)
	watch_signals(player.slash_area)

	var initial_hp = enemy.current_health
	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	await wait_seconds(0.25)

	assert_eq(enemy.current_health, initial_hp - 25.0, "Target damaged only once (25 dmg) despite multiple connected hurtboxes")
	assert_eq(player.slash_area.hits_landed, 1)
	assert_eq(get_signal_emit_count(player.slash_area, "hit_confirmed"), 1)

func test_warrior_basic_attack_repeat_swing_after_cooldown() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.global_position = Vector3.ZERO
	player.look_at(Vector3(0, 0, -10), Vector3.UP)

	var enemy = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy)
	enemy.global_position = Vector3(0, 0, -1.5)

	await wait_physics_frames(3)

	# Swing 1
	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	await wait_seconds(0.25)
	assert_eq(enemy.current_health, 55.0, "First swing deals 25 damage")

	# Swing 2 on surviving target after cooldown
	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	await wait_seconds(0.25)
	assert_eq(enemy.current_health, 30.0, "Second swing deals 25 damage to surviving target")

func test_already_dying_target_does_not_consume_quota() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.global_position = Vector3.ZERO
	player.look_at(Vector3(0, 0, -10), Vector3.UP)

	var enemy_dying = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_dying)
	enemy_dying.global_position = Vector3(-0.3, 0, -1.5)
	enemy_dying.is_dying = true # Marked dying before the attack

	var enemy_live = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_live)
	enemy_live.global_position = Vector3(0.3, 0, -1.5)

	await wait_physics_frames(3)

	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	await wait_seconds(0.25)

	assert_eq(enemy_dying.current_health, 80.0, "Already-dying target must receive no damage")
	assert_eq(enemy_live.current_health, 55.0, "Live target must receive damage after dying target skipped")
	assert_eq(player.slash_area.hits_landed, 1)

func test_lethal_first_hit_does_not_restore_quota_for_second_target() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.global_position = Vector3.ZERO
	player.look_at(Vector3(0, 0, -10), Vector3.UP)

	var enemy_low_hp = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_low_hp)
	enemy_low_hp.current_health = 10.0 # Will die from 25.0 damage
	enemy_low_hp.global_position = Vector3(-0.3, 0, -1.5)

	var enemy_second = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_second)
	enemy_second.global_position = Vector3(0.3, 0, -1.5)

	await wait_physics_frames(3)

	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	await wait_seconds(0.25)

	assert_true(enemy_low_hp.is_dying, "First enemy was killed by the attack")
	assert_eq(enemy_second.current_health, 80.0, "Second enemy takes no damage even though first enemy died")
	assert_eq(player.slash_area.hits_landed, 1)

func test_deletion_of_first_hit_target_during_swing_does_not_affect_quota() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.global_position = Vector3.ZERO
	player.look_at(Vector3(0, 0, -10), Vector3.UP)

	var enemy_a = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_a)
	enemy_a.move_speed = 0.0
	enemy_a.attack_timer = 99.0
	enemy_a.global_position = Vector3(-0.3, 0.0, -1.5)

	var enemy_b = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_b)
	enemy_b.move_speed = 0.0
	enemy_b.attack_timer = 99.0
	enemy_b.global_position = Vector3(15.0, 0.0, 0.0)

	await wait_physics_frames(3)

	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	await wait_seconds(0.10)

	assert_eq(enemy_a.current_health, 55.0, "Enemy A took the hit")
	assert_eq(player.slash_area.hits_landed, 1)

	# Delete the already-hit node during the active swing window
	enemy_a.queue_free()
	await wait_physics_frames(1)

	# Move enemy_b into the active slash area
	enemy_b.global_position = Vector3(0.3, 0.0, -1.5)
	await wait_physics_frames(3)
	await wait_seconds(0.15)

	assert_eq(enemy_b.current_health, 80.0, "Second enemy takes no damage despite first target node deletion")
	assert_eq(player.slash_area.hits_landed, 1)

func test_rejected_height_difference_does_not_consume_quota() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.global_position = Vector3.ZERO
	player.look_at(Vector3(0, 0, -10), Vector3.UP)

	# High enemy is at Y=1.5:
	# Its Hurtbox [0.5, 2.5] physically overlaps with SlashHitbox [-0.9, 1.7] across [0.5, 1.7] (1.2m vertical overlap).
	# However, delta Y = 1.5 rounds to 2, which fails TerrainCombatRules.is_melee_connected (|rounded_delta_y| <= 1).
	var enemy_high = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_high)
	enemy_high.move_speed = 0.0
	enemy_high.attack_timer = 99.0
	enemy_high.global_position = Vector3(0.0, 1.5, -1.5)

	# Ground enemy starts far outside the attack area so it cannot be evaluated first or consume quota early
	var enemy_ground = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_ground)
	enemy_ground.move_speed = 0.0
	enemy_ground.attack_timer = 99.0
	enemy_ground.global_position = Vector3(15.0, 0.0, 0.0)

	await wait_physics_frames(3)
	watch_signals(player.slash_area)

	# Phase 1: Trigger attack while ONLY enemy_high is in the slash area.
	# Quota is free (hits_landed == 0). High enemy physically overlaps but is rejected solely by height check.
	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	await wait_physics_frames(2)
	await wait_seconds(0.08)

	# If the height check were disabled or broken, enemy_high would take damage and consume quota here
	assert_eq(enemy_high.current_health, 80.0, "High enemy rejected by height check takes no damage despite free quota")
	assert_eq(player.slash_area.hits_landed, 0, "Hits landed remains 0 because height rejection did not consume quota")
	assert_eq(get_signal_emit_count(player.slash_area, "hit_confirmed"), 0, "No hit_confirmed signal emitted for height rejection")

	# Phase 2: While the slash window is STILL active (monitoring == true), introduce ground enemy into the slash area
	enemy_ground.global_position = Vector3(0.0, 0.0, -1.5)
	await wait_physics_frames(3)
	await wait_seconds(0.15)

	# Ground enemy receives the single allowed hit; high enemy remains untouched
	assert_eq(enemy_ground.current_health, 55.0, "Ground enemy receives hit during active swing window after high target rejection")
	assert_eq(enemy_high.current_health, 80.0, "High enemy still has full health")
	assert_eq(player.slash_area.hits_landed, 1, "Single-target quota consumed exactly once")
	assert_eq(get_signal_emit_count(player.slash_area, "hit_confirmed"), 1, "Exactly one hit_confirmed emitted for the ground enemy")

func test_rejected_friendly_building_does_not_consume_quota() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.global_position = Vector3.ZERO
	player.look_at(Vector3(0, 0, -10), Vector3.UP)

	var wall = WOOD_WALL_SCENE.instantiate()
	add_child_autoqfree(wall)
	wall.global_position = Vector3(-0.4, 0, -1.5)

	var enemy = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy)
	enemy.move_speed = 0.0
	enemy.attack_timer = 99.0
	enemy.global_position = Vector3(0.4, 0, -1.5)

	await wait_physics_frames(3)

	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	await wait_seconds(0.25)

	assert_eq(wall.current_health, wall.max_health, "Friendly wall must receive no damage")
	assert_eq(enemy.current_health, 55.0, "Enemy receives damage after friendly wall is rejected")
	assert_eq(player.slash_area.hits_landed, 1)

func test_alternating_lmb_rmb_actual_damage() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.global_position = Vector3.ZERO
	player.look_at(Vector3(0, 0, -10), Vector3.UP)

	# Use 250 HP to guarantee multiple live targets at EVERY stage of the test sequence
	var enemy_a = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_a)
	enemy_a.max_health = 250.0
	enemy_a.current_health = 250.0
	enemy_a.global_position = Vector3(-0.4, 0, -1.5)

	var enemy_b = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_b)
	enemy_b.max_health = 250.0
	enemy_b.current_health = 250.0
	enemy_b.global_position = Vector3(0.4, 0, -1.5)

	await wait_physics_frames(3)

	# 1. Normal attack (LMB) -> single target
	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	await wait_seconds(0.25)

	var hp_a_1: float = enemy_a.current_health
	var hp_b_1: float = enemy_b.current_health
	assert_true((hp_a_1 < 250.0) != (hp_b_1 < 250.0), "LMB damages exactly one target")
	assert_true(hp_a_1 > 0.0 and hp_b_1 > 0.0, "Both targets remain alive after LMB 1")

	# 2. Cleave (RMB) -> multi target
	player.combat.special_cooldown_timer = 0.0
	player.perform_special_attack()
	await wait_seconds(0.25)

	var hp_a_2: float = enemy_a.current_health
	var hp_b_2: float = enemy_b.current_health
	assert_lt(hp_a_2, hp_a_1, "Enemy A damaged by Cleave")
	assert_lt(hp_b_2, hp_b_1, "Enemy B damaged by Cleave")
	assert_true(hp_a_2 > 0.0 and hp_b_2 > 0.0, "Both targets remain alive after Cleave (hp_a=%f, hp_b=%f)" % [hp_a_2, hp_b_2])

	# 3. Normal attack (LMB) again -> single target with BOTH alive targets present
	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	await wait_seconds(0.25)

	var a_took_hit_3: bool = enemy_a.current_health < hp_a_2
	var b_took_hit_3: bool = enemy_b.current_health < hp_b_2
	assert_true(a_took_hit_3 != b_took_hit_3, "LMB damages exactly one target again when multiple living targets are present")

func test_engineer_hammer_multi_target_actual_damage() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.ENGINEER, false)
	player.global_position = Vector3.ZERO
	player.look_at(Vector3(0, 0, -10), Vector3.UP)

	var enemy_a = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_a)
	enemy_a.global_position = Vector3(-0.4, 0, -1.5)

	var enemy_b = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_b)
	enemy_b.global_position = Vector3(0.4, 0, -1.5)

	await wait_physics_frames(3)

	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	await wait_seconds(0.25)

	assert_lt(enemy_a.current_health, 80.0, "Enemy A damaged by Engineer hammer")
	assert_lt(enemy_b.current_health, 80.0, "Enemy B damaged by Engineer hammer")
	assert_eq(player.slash_area.hits_landed, 2, "Engineer hammer hits multiple targets")

func test_archer_projectile_behavior_preserved() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.ARCHER, false)
	player.global_position = Vector3.ZERO
	player.look_at(Vector3(0, 0, -10), Vector3.UP)

	var enemy = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy)
	enemy.global_position = Vector3(0, 0, -3.0)

	await wait_physics_frames(3)

	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	await wait_seconds(0.35)

	assert_lt(enemy.current_health, 80.0, "Archer arrow damages enemy at range")

# ==============================================================================
# 2. PARRY (ABSORB FIRST HIT, AOE STUN, ZERO COUNTER DAMAGE & KNOCKBACK, COOLDOWNS)
# ==============================================================================

func test_parry_absorbs_single_hit_aoe_stuns_zero_counter_damage_zero_knockback() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	watch_signals(player)

	var enemy_attacker = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_attacker)
	enemy_attacker.move_speed = 0.0
	enemy_attacker.attack_timer = 99.0
	enemy_attacker.global_position = player.global_position + Vector3(0, 0, 1.5)

	var enemy_nearby = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy_nearby)
	enemy_nearby.move_speed = 0.0
	enemy_nearby.attack_timer = 99.0
	enemy_nearby.global_position = player.global_position + Vector3(2.0, 0, 0) # Within 3.5m radius

	player.health.parry_cooldown_timer = 0.0
	player.perform_utility()
	assert_true(player.health.is_parrying, "Parry is active")

	var initial_player_hp = player.current_health
	var initial_attacker_hp = enemy_attacker.current_health
	var initial_nearby_hp = enemy_nearby.current_health
	var pos_before = enemy_attacker.global_position

	# Hit 1: Absorbed
	player.take_damage(20.0, enemy_attacker)

	assert_eq(player.current_health, initial_player_hp, "1st hit absorbed by parry")
	assert_false(player.health.is_parrying, "Parry consumed on first hit")
	assert_signal_emitted_with_parameters(player, "parry_triggered", [true])
	assert_eq(get_signal_emit_count(player, "parry_triggered"), 2, "parry_triggered emitted twice: once on stance start (false), once on absorb (true)")
	assert_eq(enemy_attacker.current_health, initial_attacker_hp, "Attacker received ZERO counter damage")
	assert_eq(enemy_nearby.current_health, initial_nearby_hp, "Nearby target received ZERO counter damage")
	assert_eq(enemy_attacker.knockback_velocity, Vector3.ZERO, "Attacker received ZERO knockback impulse")

	# Both enemies in 3.5m radius are stunned for 1.0s immediately upon parry trigger
	assert_true(enemy_attacker.is_stunned, "Attacking enemy is stunned")
	assert_eq(enemy_attacker.stun_timer, 1.0, "Attacker stun is 1.0s")
	assert_true(enemy_nearby.is_stunned, "Nearby enemy within 3.5m is also stunned")
	assert_eq(enemy_nearby.stun_timer, 1.0, "Nearby stun is 1.0s")

	# Physics frame wait to ensure no horizontal knockback displacement occurs
	await wait_physics_frames(3)
	assert_eq(Vector2(enemy_attacker.velocity.x, enemy_attacker.velocity.z), Vector2.ZERO, "Attacker horizontal velocity remains zero")
	assert_almost_eq(enemy_attacker.global_position.x, pos_before.x, 0.001, "Attacker X position unchanged (no knockback)")
	assert_almost_eq(enemy_attacker.global_position.z, pos_before.z, 0.001, "Attacker Z position unchanged (no knockback)")

	# Hit 2: Penetrates because parry already consumed
	player.take_damage(20.0, enemy_attacker)
	assert_eq(player.current_health, initial_player_hp - 20.0, "2nd hit penetrates spent parry")
	assert_eq(get_signal_emit_count(player, "parry_triggered"), 2, "parry_triggered [true] not emitted again for second hit")

func test_parry_window_expiration_and_cooldowns() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)

	var enemy = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(enemy)
	enemy.move_speed = 0.0
	enemy.attack_timer = 99.0
	enemy.global_position = Vector3(0, 0, 1.5)

	# Case 1: Parry miss (window expiration)
	player.health.parry_cooldown_timer = 0.0
	player.perform_parry()
	assert_true(player.health.is_parrying, "Parry active on start")
	assert_eq(player.health.parry_cooldown_timer, PlayerHealth.PARRY_COOLDOWN, "Parry starts 6.0s cooldown timer")

	# Wait for parry window (0.5s) to expire naturally
	await wait_seconds(0.55)
	assert_false(player.health.is_parrying, "Parry expired naturally after 0.5s window")
	assert_gt(player.health.parry_cooldown_timer, 5.0, "Parry cooldown retains 6.0s baseline on miss")

	# Case 2: Parry success (absorb hit -> cooldown resets to 3.0s)
	player.health.parry_cooldown_timer = 0.0
	player.perform_parry()
	assert_true(player.health.is_parrying, "Parry active on second activation")

	player.take_damage(10.0, enemy)
	assert_false(player.health.is_parrying, "Parry consumed upon absorbing hit")
	assert_lte(player.health.parry_cooldown_timer, PlayerHealth.PARRY_SUCCESS_COOLDOWN, "Cooldown reset to 3.0s on success")
	assert_gt(player.health.parry_cooldown_timer, 2.5, "Cooldown timer active around 3.0s")

func test_parry_with_mixed_enemy_group_including_siege_breaker() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.global_position = Vector3.ZERO
	watch_signals(player)

	# 1. Real SiegeBreaker enemy (inherits EnemyBase, lacks apply_stun)
	var breaker = SIEGE_BREAKER_SCENE.instantiate()
	add_child_autoqfree(breaker)
	breaker.move_speed = 0.0
	breaker.attack_timer = 99.0
	breaker.retarget_timer = 9999.0
	breaker.global_position = player.global_position + Vector3(0, 0, 1.8) # Within 3.5m radius

	# 2. Zombie dummy enemy (implements apply_stun)
	var zombie = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(zombie)
	zombie.move_speed = 0.0
	zombie.attack_timer = 99.0
	zombie.global_position = player.global_position + Vector3(1.5, 0, 0) # Within 3.5m radius

	await wait_physics_frames(2)

	player.health.parry_cooldown_timer = 0.0
	player.perform_utility()
	assert_true(player.health.is_parrying, "Parry stance is active")

	var initial_player_hp: float = player.current_health
	var initial_breaker_hp: float = breaker.current_health
	var initial_zombie_hp: float = zombie.current_health

	# Breaker attacks player during parry window:
	# Incoming hit blocked, parry triggered, breaker skipped for stun without error, zombie stunned, zero counter damage
	player.take_damage(breaker.player_damage, breaker)

	assert_eq(player.current_health, initial_player_hp, "Breaker attack was absorbed by parry")
	assert_false(player.health.is_parrying, "Parry stance consumed on first absorbed hit")
	assert_signal_emitted_with_parameters(player, "parry_triggered", [true])
	assert_eq(breaker.current_health, initial_breaker_hp, "Siege breaker took ZERO counter damage")
	assert_eq(zombie.current_health, initial_zombie_hp, "Zombie took ZERO counter damage")
	assert_true(zombie.is_stunned, "Zombie dummy received AoE stun")
	assert_eq(zombie.stun_timer, 1.0, "Zombie stun duration is 1.0s")

# ==============================================================================
# 3. WARRIOR DASH VULNERABILITY, DUEL MODIFIERS & CLASS ISOLATION
# ==============================================================================

func test_warrior_dash_damage_timing_before_during_after() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)
	player.global_position = Vector3.ZERO
	player.look_at(Vector3(0, 0, -10), Vector3.UP)

	await wait_physics_frames(2)
	var hp = player.current_health

	# 1. Damage before dash
	player.take_damage(20.0)
	assert_eq(player.current_health, hp - 20.0, "Warrior takes damage before dash")
	hp = player.current_health

	# 2. Damage during dash with actual locomotion
	var start_pos_h: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	player.perform_dash()
	await wait_physics_frames(2)

	assert_true(player.movement.is_dashing, "Movement state is dashing")
	var current_pos_h: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	var horiz_displacement: float = current_pos_h.distance_to(start_pos_h)
	assert_gt(horiz_displacement, 0.2, "Player actually moved horizontally on XZ plane during dash (displacement: %f)" % horiz_displacement)
	assert_false(player.is_dash_invulnerable(), "Warrior is not invulnerable during dash")

	player.take_damage(20.0)
	assert_eq(player.current_health, hp - 20.0, "Warrior takes damage during active dash")
	hp = player.current_health

	# 3. Natural expiration and damage after dash
	await wait_seconds(player.movement.dash_duration + 0.05)
	assert_false(player.movement.is_dashing, "Dash naturally completed")

	player.take_damage(20.0)
	assert_eq(player.current_health, hp - 20.0, "Warrior takes damage after dash")

func test_archer_and_engineer_retain_dash_immunity() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)

	# Archer
	player.set_class(player.CharacterClass.ARCHER, false)
	player.look_at(Vector3(0, 0, -10), Vector3.UP)
	var start_archer_h: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	player.perform_dash()
	await wait_physics_frames(2)
	assert_true(player.movement.is_dashing)
	assert_gt(Vector2(player.global_position.x, player.global_position.z).distance_to(start_archer_h), 0.2, "Archer moved horizontally during dash")
	assert_true(player.is_dash_invulnerable(), "Archer retains dash invulnerability")
	var hp_archer = player.current_health
	player.take_damage(30.0)
	assert_eq(player.current_health, hp_archer, "Archer immune to damage during dash")
	await wait_seconds(player.movement.dash_duration + 0.05)
	assert_false(player.movement.is_dashing)

	# Engineer
	player.set_class(player.CharacterClass.ENGINEER, false)
	player.movement.dash_cooldown_timer = 0.0
	player.look_at(Vector3(0, 0, -10), Vector3.UP)
	var start_eng_h: Vector2 = Vector2(player.global_position.x, player.global_position.z)
	player.perform_dash()
	await wait_physics_frames(2)
	assert_true(player.movement.is_dashing)
	assert_gt(Vector2(player.global_position.x, player.global_position.z).distance_to(start_eng_h), 0.2, "Engineer moved horizontally during dash")
	assert_true(player.is_dash_invulnerable(), "Engineer retains dash invulnerability")
	var hp_eng = player.current_health
	player.take_damage(30.0)
	assert_eq(player.current_health, hp_eng, "Engineer immune to damage during dash")
	await wait_seconds(player.movement.dash_duration + 0.05)
	assert_false(player.movement.is_dashing)

func test_warrior_dash_with_duel_modifiers() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)

	var duel_target = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(duel_target)

	var third_party = ENEMY_DUMMY_SCENE.instantiate()
	add_child_autoqfree(third_party)

	player.abilities.is_dueling = true
	player.abilities.duel_target = duel_target

	await wait_physics_frames(2)

	# Third party attacks during dash
	player.perform_dash()
	await wait_physics_frames(2)

	var player_hp_before = player.current_health
	var third_party_hp_before = third_party.current_health

	# 20 damage incoming from third party: 40% reduction applied (takes 12), 20% reflected (deals 4 to attacker)
	player.take_damage(20.0, third_party)

	assert_eq(player.current_health, player_hp_before - 12.0, "Takes 60% of damage from third-party during duel dash")
	assert_eq(third_party.current_health, third_party_hp_before - 4.0, "Reflects 20% damage back to third-party attacker")

func test_warrior_dash_combined_with_parry() -> void:
	var player = PLAYER_SCENE.instantiate()
	add_child_autoqfree(player)
	player.set_class(player.CharacterClass.WARRIOR, false)

	await wait_physics_frames(2)

	player.perform_dash()
	player.perform_parry()

	var initial_hp = player.current_health

	# Hit 1: Parry absorbs the hit even though dashing
	player.take_damage(25.0)
	assert_eq(player.current_health, initial_hp, "Parry absorbs hit during dash")

	# Hit 2: Parry is now spent, warrior still dashing -> takes damage
	player.take_damage(25.0)
	assert_eq(player.current_health, initial_hp - 25.0, "Warrior takes damage during dash once parry is spent")

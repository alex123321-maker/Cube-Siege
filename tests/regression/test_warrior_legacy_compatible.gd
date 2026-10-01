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
	assert_signal_emitted(player.slash_area, "hit_confirmed")
	assert_eq(get_signal_emit_count(player.slash_area, "hit_confirmed"), 1, "hit_confirmed emitted exactly once")


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

	player.take_damage(20.0)
	assert_eq(player.current_health, hp - 20.0, "Warrior takes damage during active dash")
	hp = player.current_health

	# 3. Natural expiration and damage after dash
	await wait_seconds(player.movement.dash_duration + 0.05)
	assert_false(player.movement.is_dashing, "Dash naturally completed")

	player.take_damage(20.0)
	assert_eq(player.current_health, hp - 20.0, "Warrior takes damage after dash")



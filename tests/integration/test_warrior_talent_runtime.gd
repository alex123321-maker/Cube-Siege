extends GutTest

const PLAYER: PackedScene = preload("res://scenes/player.tscn")
const ENEMY: PackedScene = preload("res://scenes/enemy_dummy.tscn")
const ARROW: PackedScene = preload("res://scenes/prefabs/arrow_projectile.tscn")

class QuietTarget extends EnemyBase:
	func _spawn_damage_text_on_damaged(_amount: float) -> void:
		pass

var player: PlayerPrototype

func before_each() -> void:
	player = PLAYER.instantiate() as PlayerPrototype
	add_child_autoqfree(player)
	player.set_physics_process(false)
	player.global_position = Vector3(1000.0, 0.9, 1000.0)

func after_each() -> void:
	get_tree().paused = false
	await wait_seconds(0.5)

func _talents(ids: Array[String]) -> void:
	player.progression.run_build.initialize(WarriorTalentCatalog.TALENT_IDS)
	player.progression.run_build.selected_talents = ids
	player.progression.run_build._reveal_synergies()
	player.progression.run_build.build_changed.emit()

func _enemy(offset: Vector3 = Vector3(0, 0, -1.5)) -> EnemyBase:
	var enemy: EnemyBase = ENEMY.instantiate() as EnemyBase
	add_child_autoqfree(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = player.global_position + offset
	enemy.max_health = 1000.0
	enemy.current_health = 1000.0
	return enemy

func test_vampirism_uses_health_loss_and_never_shield_or_reflection() -> void:
	_talents(["tempered_blade"])
	player.current_health = 50.0
	var enemy: EnemyBase = _enemy()
	enemy.current_health = 30.0
	enemy.shield_health = 50.0
	enemy._on_damaged(1000.0, Vector3.ZERO, "physical", player)
	assert_eq(enemy.current_health, 30.0)
	assert_eq(player.current_health, 50.0)
	enemy._on_damaged(10.0, Vector3.ZERO, "reflected", player)
	assert_eq(player.current_health, 50.0)
	enemy._on_damaged(1000.0, Vector3.ZERO, "physical", player)
	assert_almost_eq(player.current_health, 51.6, 0.001, "Overkill heals from remaining 20 HP only")

func test_shield_absorbs_overflow_and_reflects_actual_fifty() -> void:
	_talents(["tempered_blade"])
	var attacker: EnemyBase = _enemy()
	var duel_target: EnemyBase = _enemy(Vector3(5, 0, 0))
	player.is_dueling = true
	player.duel_target = duel_target
	player.current_health = 50.0
	player.health.shield_health = 50.0
	player.take_damage(1000.0, attacker)
	assert_eq(player.current_health, 50.0)
	assert_eq(player.health.shield_health, 0.0)
	assert_eq(attacker.current_health, 990.0)
	assert_eq(attacker.last_damage_type, "reflected")

func test_counterattack_parries_every_hit_and_blood_synergy_heals_actual_damage() -> void:
	_talents(["counterattack", "tempered_blade"])
	player.current_health = 50.0
	var attacker: EnemyBase = _enemy()
	player.perform_parry()
	assert_almost_eq(player.health.parry_timer, WarriorTalentCatalog.COUNTER_PARRY_WINDOW, 0.001)
	player.take_damage(20.0, attacker)
	player.take_damage(20.0, attacker)
	assert_true(player.is_parrying)
	assert_almost_eq(attacker.current_health, 1000.0 - player.talents.attack_based_ability_damage() * 2, 0.001)
	assert_almost_eq(player.current_health, 50.0 + player.talents.attack_based_ability_damage() * 2 * 0.08, 0.001)

func test_hot_blood_refreshes_time_and_stun_expires() -> void:
	_talents(["hot_blood"])
	player.current_health = 50.0
	var attacker: EnemyBase = _enemy()
	player.perform_parry()
	player.take_damage(10.0, attacker)
	assert_true(attacker.status_effects.is_stunned())
	attacker.status_effects.advance(1.1)
	assert_false(attacker.status_effects.is_stunned())
	player.talents.advance(1.0)
	assert_eq(player.current_health, 55.0)
	player.talents._on_parry(true)
	player.talents.advance(4.0)
	assert_eq(player.current_health, 70.0, "Refresh adds a fresh three seconds, not a second regen stack")

func test_respec_recomputes_stats_without_healing_or_compounding_meta() -> void:
	_talents([])
	var base_damage: float = player.attack_damage
	player.current_health = 20.0
	player.progression.run_build.grant_specialization_point(3)
	for count: int in range(3):
		player.progression.run_build.invest_specialization("attack_damage")
	assert_almost_eq(player.attack_damage, base_damage * 1.24, 0.001)
	assert_eq(player.special_damage, 60.0)
	player.progression.run_build.reset_specializations()
	assert_eq(player.attack_damage, base_damage)
	assert_eq(player.current_health, 20.0)
	player.apply_mastery_stats()
	player.apply_mastery_stats()
	assert_eq(player.attack_damage, base_damage)

func test_real_whirlwind_hits_behind_and_sweeping_basic_hits_two() -> void:
	_talents(["whirlwind_cleave"])
	var behind: EnemyBase = _enemy(Vector3(0, 0, 2.0))
	await wait_physics_frames(3)
	player.combat._start_warrior_cleave(player, false)
	await wait_seconds(0.1)
	assert_eq(behind.current_health, 940.0)
	assert_eq(player.slash_area.frontal_arc_degrees, 360.0)
	await wait_seconds(0.25)
	_talents(["sweeping_strike"])
	var first: EnemyBase = _enemy(Vector3(-0.3, 0, -1.5))
	var second: EnemyBase = _enemy(Vector3(0.3, 0, -1.5))
	await wait_physics_frames(3)
	player.combat.attack_cooldown_timer = 0.0
	player.combat.perform_attack(player, 0, false, false)
	await wait_seconds(0.15)
	assert_lt(first.current_health, 1000.0)
	assert_lt(second.current_health, 1000.0)

func test_perfect_dash_is_invulnerable_and_combination_hits_each_crossed_target_once() -> void:
	_talents(["perfect_dash", "loud_triumph"])
	var enemy: EnemyBase = _enemy(Vector3(1, 0, 0))
	player.talents.on_duel_victory(enemy.global_position)
	var damage: float = player.talents.attack_based_ability_damage()
	var before_hp: float = player.current_health
	player.movement.perform_dash(Vector3.RIGHT, Vector3.RIGHT)
	assert_almost_eq(player.movement.dash_timer, 0.3, 0.001)
	player.take_damage(1000.0, enemy)
	assert_eq(player.current_health, before_hp)
	player.global_position += Vector3(2, 0, 0)
	player.talents.after_movement()
	player.talents.after_movement()
	assert_almost_eq(enemy.current_health, 1000.0 - damage, 0.001)

func test_permanent_bloodlust_openings_boost_only_basic_attack() -> void:
	var save: Node = get_node("/root/SaveManager")
	var roster: Node = get_node("/root/RosterManager")
	var snapshot: Dictionary = save.snapshot_state()
	roster.selected_slot_index = 0
	_talents(["counterattack"])
	roster.get_active_character().unlocked_talents = WarriorTalentCatalog.STARTER_IDS.duplicate()
	player.talents.refresh_meta()
	assert_almost_eq(player.attack_damage, 25.75, 0.001)
	var attacker: EnemyBase = _enemy()
	player.perform_parry()
	player.take_damage(20.0, attacker)
	assert_almost_eq(attacker.current_health, 975.0, 0.001)
	roster.get_active_character().unlocked_talents = WarriorTalentCatalog.TALENT_IDS.duplicate()
	player.talents.refresh_meta()
	assert_almost_eq(player.attack_damage, 27.25, 0.001)
	assert_eq(player.special_damage, 60.0)
	attacker.current_health = 1000.0
	player.take_damage(20.0, attacker)
	assert_almost_eq(attacker.current_health, 975.0, 0.001, "Permanent openings cannot amplify the parry ability's counter")
	assert_almost_eq(player.talents.attack_based_ability_damage(), 25.0, 0.001, "Dash and counter share the meta-free attack-property damage")
	save.restore_state(snapshot)

func test_mandatory_draft_pauses_and_specializations_refund_in_same_run() -> void:
	var panel: WarriorBuildPanel = WarriorBuildPanel.new()
	add_child_autoqfree(panel)
	panel.bind_player(player)
	player.progression.run_build.offer_checkpoint(0, true)
	assert_true(get_tree().paused)
	var reward: int = player.progression.run_build.active_reward_id
	panel._focus(reward)
	assert_false(get_tree().paused)
	assert_eq(player.progression.run_build.unspent_specialization_points, 2)
	panel.open_specializations()
	assert_true(player.progression.run_build.invest_specialization("cleave_damage"))
	player.progression.run_build.reset_specializations()
	assert_eq(player.progression.run_build.unspent_specialization_points, 2)
	panel.close_panel()
	assert_false(get_tree().paused)

func test_real_enemy_arrow_hits_player_body_once_and_passes_attacker() -> void:
	_talents([])
	var attacker: EnemyBase = _enemy(Vector3(-4, 0, 0))
	var duel_target: EnemyBase = _enemy(Vector3(5, 0, 0))
	player.is_dueling = true
	player.duel_target = duel_target
	var hp: float = player.current_health
	await wait_physics_frames(2)
	var arrow: Node3D = ARROW.instantiate() as Node3D
	add_child_autoqfree(arrow)
	arrow.global_position = player.global_position + Vector3(-2, 0, 0)
	arrow.setup(Vector3.RIGHT, 15.0, attacker)
	await wait_physics_frames(12)
	assert_almost_eq(player.current_health, hp - 9.0, 0.001)
	assert_almost_eq(attacker.current_health, 998.2, 0.001, "Reflection reaches the actual shooter")
	assert_false(is_instance_valid(arrow))

func test_duel_bonus_applies_only_to_the_selected_target_in_multi_target_cleave() -> void:
	_talents([])
	var selected: EnemyBase = _enemy(Vector3(-0.5, 0, -1.5))
	var other: EnemyBase = _enemy(Vector3(0.5, 0, -1.5))
	player.is_dueling = true
	player.duel_target = selected
	await wait_physics_frames(3)
	player.combat._start_warrior_cleave(player, true)
	await wait_seconds(0.1)
	assert_eq(selected.current_health, 928.0)
	assert_eq(other.current_health, 940.0)

func test_duel_cannot_replace_target_after_cooldown_and_detaches_symmetrically() -> void:
	_talents(["loud_triumph"])
	var first: EnemyBase = _enemy()
	var second: EnemyBase = _enemy(Vector3(5, 0, 0))
	player.abilities.perform_warrior_ultimate(player, first, true)
	var tether: Node3D = player.abilities.active_tether
	player.abilities.ultimate_cooldown_timer = 0.0
	player.abilities.perform_ultimate(player, 0, second, true)
	assert_eq(player.duel_target, first, "Expired cooldown cannot replace an unfinished Duel")
	assert_eq(player.abilities.active_tether, tether)
	assert_true(first.is_in_duel)
	assert_false(second.is_in_duel)
	first._on_damaged(1000.0, Vector3.ZERO, "physical", player)
	assert_false(player.is_dueling)
	assert_false(first.is_in_duel)
	assert_eq(player.talents.triumph_stacks, 1)
	player.abilities.perform_ultimate(player, 0, second, true)
	assert_eq(player.duel_target, second)
	assert_true(second.is_in_duel)
	player.end_duel()
	assert_false(second.is_in_duel, "Manual teardown clears both participants")
	assert_null(second.duel_opponent)
	assert_eq(player.talents.triumph_stacks, 1, "Ending a living target never awards a victory")
	await wait_physics_frames(2)
	assert_false(is_instance_valid(tether), "The completed Duel's tether is freed")

func test_enemy_arrow_keeps_duel_defense_after_shooter_is_freed() -> void:
	_talents(["tempered_blade"])
	var shooter: EnemyBase = _enemy(Vector3(-4, 0, 0))
	var selected: EnemyBase = _enemy(Vector3(5, 0, 0))
	player.abilities.perform_warrior_ultimate(player, selected, true)
	player.current_health = 50.0
	await wait_physics_frames(2)
	var arrow: Node3D = ARROW.instantiate() as Node3D
	add_child_autoqfree(arrow)
	arrow.global_position = player.global_position + Vector3(-2, 0, 0)
	arrow.setup(Vector3.RIGHT, 15.0, shooter)
	shooter.free()
	await wait_physics_frames(12)
	assert_almost_eq(player.current_health, 41.0, 0.001, "A vanished third-party shooter still deals reduced Duel damage")
	assert_eq(selected.current_health, 1000.0, "Reflection cannot be redirected to the living Duel target")
	assert_false(is_instance_valid(arrow))

func _quiet_target(offset: Vector3) -> QuietTarget:
	var target: QuietTarget = QuietTarget.new()
	add_child_autoqfree(target)
	target.set_physics_process(false)
	target.global_position = player.global_position + offset
	target.current_health = 1.0
	return target

func _seed_for_carnage(expected: bool) -> int:
	for candidate: int in range(100):
		seed(candidate)
		if (randf() < WarriorTalentCatalog.CARNAGE_CHANCE) == expected:
			return candidate
	return -1

func test_carnage_actual_cleave_kill_obeys_seeded_positive_and_negative_rolls() -> void:
	_talents(["whirlwind_cleave", "dismemberment"])
	var nearby: EnemyBase = _enemy(Vector3(1.5, 0, 0))
	for expected: bool in [true, false]:
		player.talents.morale_remaining = 0.0
		nearby.status_effects.clear()
		var victim: QuietTarget = _quiet_target(Vector3(0, 0, -1))
		var selected_seed: int = _seed_for_carnage(expected)
		assert_gte(selected_seed, 0)
		seed(selected_seed)
		victim._on_damaged(60.0, Vector3.ZERO, "cleave", player)
		assert_true(victim.is_dying, "The production damage path kills the target")
		assert_eq(player.talents.morale_remaining > 0.0, expected)
		assert_eq(nearby.status_effects.movement_multiplier() < 1.0, expected)
	randomize()

func test_actual_duel_kill_morale_changes_movement_and_expires() -> void:
	_talents(["dismemberment"])
	var victim: QuietTarget = _quiet_target(Vector3(0, 0, -1))
	var nearby: EnemyBase = _enemy(Vector3(1.5, 0, 0))
	player.abilities.perform_warrior_ultimate(player, victim, true)
	victim._on_damaged(25.0, Vector3.ZERO, "physical", player)
	assert_true(victim.is_dying)
	assert_false(player.is_dueling)
	assert_almost_eq(player.talents.movement_multiplier(), 1.2, 0.001)
	assert_almost_eq(nearby.status_effects.movement_multiplier(), 0.6, 0.001)
	player.talents.advance(WarriorTalentCatalog.MORALE_DURATION)
	nearby.status_effects.advance(WarriorTalentCatalog.MORALE_DURATION)
	assert_eq(player.talents.morale_remaining, 0.0)
	assert_eq(player.talents.movement_multiplier(), 1.0)
	assert_eq(nearby.status_effects.movement_multiplier(), 1.0)

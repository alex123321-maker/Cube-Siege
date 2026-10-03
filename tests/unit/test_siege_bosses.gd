extends GutTest

const SCENES: PackedStringArray = [
	"res://scenes/bosses/boss_01_cairn.tscn", "res://scenes/bosses/boss_02_gorgon.tscn",
	"res://scenes/bosses/boss_03_ash_oracle.tscn", "res://scenes/bosses/boss_04_mortar.tscn",
	"res://scenes/bosses/boss_05_rift_warden.tscn", "res://scenes/bosses/boss_06_rift_harbinger.tscn"]

class Target:
	extends Node3D
	var hits: int = 0
	var total_damage: float = 0.0
	func receive(amount: float, _knockback: Vector3, _kind: String, _attacker: Node) -> void:
		hits += 1
		total_damage += amount

class Cliff:
	extends RefCounted
	func height(x: int, _z: int) -> int:
		return 3 if x >= 2 else 0

func after_each() -> void:
	# Production damage feedback is attached beside the actor, outside autoqfree.
	for child: Node in get_children():
		if child.scene_file_path == "res://scenes/floating_text.tscn":
			child.queue_free()
	await get_tree().process_frame

func _target(position: Vector3) -> Target:
	var target: Target = Target.new()
	target.add_to_group("player")
	var hurtbox: HurtboxArea = HurtboxArea.new()
	hurtbox.name = "Hurtbox"
	target.add_child(hurtbox)
	hurtbox.damaged.connect(target.receive)
	add_child_autoqfree(target)
	target.global_position = position
	return target

func _boss(stage: int, target: Node3D) -> SiegeBoss:
	var boss: SiegeBoss = (load(SCENES[stage - 1]) as PackedScene).instantiate() as SiegeBoss
	boss.configure(stage, target)
	add_child_autoqfree(boss)
	boss.configure(stage, target)
	boss.set_physics_process(false)
	boss.position = Vector3(0.0, 1.5, 0.0)
	return boss

func test_six_original_articulated_models_and_readable_action_clips() -> void:
	var target: Target = _target(Vector3(0.0, 0.9, -3.0))
	for stage: int in range(1, 7):
		var boss: SiegeBoss = _boss(stage, target)
		assert_eq(boss.stage, stage)
		var model: Node3D = boss.get_node("Visuals/Model") as Node3D
		assert_gt(model.find_children("*", "MeshInstance3D", true, false).size(), 20, "Each authored silhouette has multiple articulated parts")
		var animation: AnimationPlayer = model.get_node("AnimationPlayer") as AnimationPlayer
		for clip: String in ["idle", "move", "attack_0", "attack_1", "death"]:
			assert_true(animation.has_animation(clip))
		assert_eq(boss.profile.attacks.size(), 2 if stage <= 2 else 3)

func test_warning_cannot_damage_and_active_window_hits_only_once() -> void:
	var target: Target = _target(Vector3(0.0, 0.9, -2.0))
	var boss: SiegeBoss = _boss(1, target)
	var spec: BossAttackSpec = boss.profile.attacks[0]
	var hazard: BossAttackHazard = BossAttackHazard.new()
	boss.add_child(hazard)
	hazard.setup(spec, boss, target, Vector3.ZERO, Vector3.FORWARD, boss.profile.color, Callable())
	hazard.set_physics_process(false)
	hazard._physics_process(spec.windup * 0.5)
	assert_eq(target.hits, 0)
	hazard._physics_process(spec.windup)
	assert_eq(target.hits, 0, "Warning expiration itself has no damage")
	hazard._physics_process(0.01)
	hazard._physics_process(0.01)
	assert_eq(target.hits, 1)
	assert_eq(target.total_damage, spec.damage)

func test_terrain_blocks_melee_and_does_not_block_marked_mortar() -> void:
	var target: Target = _target(Vector3(4.0, 3.9, 0.0))
	var boss: SiegeBoss = _boss(1, target)
	var spec: BossAttackSpec = boss.profile.attacks[0].duplicate() as BossAttackSpec
	var cliff: Cliff = Cliff.new()
	var hazard: BossAttackHazard = BossAttackHazard.new()
	boss.add_child(hazard)
	hazard.setup(spec, boss, target, Vector3.ZERO, Vector3.RIGHT, boss.profile.color, Callable(cliff, "height"))
	hazard.set_physics_process(false)
	assert_false(hazard._try_hit(), "Ground sector cannot cross a three-block cliff")
	spec.terrain_mode = TerrainCombatRules.TerrainMode.TERRAIN_INDEPENDENT
	assert_true(hazard._try_hit(), "Aerial marked strike checks horizontal area")

func test_fast_projectile_checks_segment_and_damages_once() -> void:
	var target: Target = _target(Vector3(0.0, 0.9, -4.0))
	var boss: SiegeBoss = _boss(3, target)
	var projectile: BossProjectile = BossProjectile.new()
	boss.add_child(projectile)
	projectile.global_position = Vector3(0.0, 0.9, 0.0)
	projectile.setup(boss, target, Vector3.FORWARD, 100.0, 12.0, boss.profile.color, Callable())
	projectile.set_physics_process(false)
	projectile._physics_process(0.1)
	projectile._physics_process(0.1)
	assert_eq(target.hits, 1, "A projectile crossing the target between frames hits once")

func test_neighbouring_fan_projectiles_share_one_contact_ledger() -> void:
	var target: Target = _target(Vector3(0.0, 0.9, -2.0))
	var boss: SiegeBoss = _boss(6, target)
	var ledger: Dictionary = {}
	for index: int in range(3):
		var projectile: BossProjectile = BossProjectile.new()
		boss.add_child(projectile)
		projectile.global_position = Vector3(0.0, 0.9, 0.0)
		projectile.setup(boss, target, Vector3.FORWARD, 100.0, 12.0, boss.profile.color, Callable(), 10.0, ledger)
		projectile.set_physics_process(false)
		projectile._physics_process(0.1)
	assert_eq(target.hits, 1, "Overlapping lanes from one release cannot multiply the same contact")
	assert_eq(target.total_damage, 12.0)

func test_boss_stun_and_hit_cannot_interrupt_committed_warning() -> void:
	var target: Target = _target(Vector3(0.0, 0.9, -3.0))
	var boss: SiegeBoss = _boss(6, target)
	boss.begin_next_attack()
	var original_clock: float = boss._timer
	boss.apply_stun(100.0)
	boss._on_damaged(1.0, Vector3(100.0, 0.0, 0.0), "physical", target)
	assert_eq(boss.state, SiegeBoss.State.WARNING)
	assert_eq(boss._timer, original_clock)
	assert_eq(boss.knockback_velocity, Vector3.ZERO)
	boss.current_health = boss.max_health * 0.2
	boss.begin_next_attack()
	assert_eq(boss.phase, 3)
	assert_lt(boss._attack.windup, boss.profile.attacks[boss._attack_index].windup)

func test_defeat_is_once_and_cancels_existing_threats_without_rewards() -> void:
	var target: Target = _target(Vector3(0.0, 0.9, -2.0))
	var boss: SiegeBoss = _boss(1, target)
	boss.begin_next_attack()
	var hazard: BossAttackHazard = null
	for child: Node in boss.get_children():
		if child is BossAttackHazard:
			hazard = child as BossAttackHazard
	watch_signals(boss)
	boss.die()
	boss.die()
	assert_signal_emit_count(boss, "defeated", 1)
	assert_true(hazard.cancelled)
	assert_false(hazard._try_hit(), "A queued warning cannot hit after its boss is dead")
	assert_eq(boss._get_xp_reward(), 0.0)
	assert_eq(target.hits, 0)

func test_line_cross_and_sector_use_visible_footprint_geometry() -> void:
	var spec: BossAttackSpec = BossAttackSpec.new()
	spec.shape = BossAttackSpec.Shape.LINE
	spec.reach = 8.0
	spec.width = 2.0
	assert_true(spec.contains_point(Vector3.ZERO, Vector3.FORWARD, Vector3(0.99, 0, -7.0)))
	assert_false(spec.contains_point(Vector3.ZERO, Vector3.FORWARD, Vector3(1.01, 0, -7.0)))
	assert_false(spec.contains_point(Vector3.ZERO, Vector3.FORWARD, Vector3(0, 0, 1.0)))
	spec.shape = BossAttackSpec.Shape.CROSS
	assert_true(spec.contains_point(Vector3.ZERO, Vector3.FORWARD, Vector3(7, 0, 0.5)))
	assert_false(spec.contains_point(Vector3.ZERO, Vector3.FORWARD, Vector3(3, 0, 3)))

func test_production_player_without_hurtbox_receives_strikes_and_projectiles() -> void:
	var player: PlayerPrototype = (load("res://scenes/player.tscn") as PackedScene).instantiate() as PlayerPrototype
	add_child_autoqfree(player)
	player.set_physics_process(false)
	player.input_enabled = false
	player.global_position = Vector3(0.0, 0.9, -2.0)
	player.current_health = 100.0
	assert_null(player.get_node_or_null("Hurtbox"))
	var boss: SiegeBoss = _boss(1, player)
	var hazard: BossAttackHazard = BossAttackHazard.new()
	boss.add_child(hazard)
	hazard.setup(boss.profile.attacks[0], boss, player, Vector3.ZERO, Vector3.FORWARD, boss.profile.color, Callable())
	hazard.set_physics_process(false)
	assert_true(hazard._try_hit())
	assert_eq(player.current_health, 78.0)
	assert_false(hazard._try_hit(), "A parried or landed contact cannot repeat")
	var projectile: BossProjectile = BossProjectile.new()
	boss.add_child(projectile)
	projectile.global_position = Vector3(0.0, 0.9, 0.0)
	projectile.setup(boss, player, Vector3.FORWARD, 100.0, 12.0, boss.profile.color, Callable())
	projectile.set_physics_process(false)
	projectile._physics_process(0.1)
	assert_eq(player.current_health, 66.0)

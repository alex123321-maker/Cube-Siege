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
	hazard._physics_process(spec.windup * 0.5)
	assert_eq(target.hits, 1, "The instant burst lands exactly at the end of preparation")
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

func _hazard(spec: BossAttackSpec, target: Node3D, origin: Vector3 = Vector3.ZERO) -> BossAttackHazard:
	var boss: SiegeBoss = _boss(1, target)
	var hazard: BossAttackHazard = BossAttackHazard.new()
	boss.add_child(hazard)
	hazard.setup(spec, boss, target, origin, Vector3.FORWARD, boss.profile.color, Callable())
	hazard.set_physics_process(false)
	return hazard

func test_live_catalog_contains_only_seven_canonical_mechanics_and_all_four_radial_variants() -> void:
	var kinds: Dictionary = {}
	var radial: Dictionary = {}
	for stage: int in range(1, 7):
		for spec: BossAttackSpec in BossEncounterCatalog.build(stage).attacks:
			kinds[spec.kind] = true
			assert_false(spec.teleport)
			assert_ne(spec.shape, BossAttackSpec.Shape.FAN)
			assert_ne(spec.shape, BossAttackSpec.Shape.CROSS)
			if spec.kind == BossAttackSpec.Kind.RADIAL_BEAM:
				radial[spec.radial_variant] = true
	assert_eq(kinds.size(), 7)
	assert_eq(radial.size(), 4)

func test_empty_lob_landing_arms_a_trap_and_later_entry_consumes_it_once() -> void:
	var target: Target = _target(Vector3(10, 0.9, 0))
	var spec: BossAttackSpec = BossEncounterCatalog.build(1).attacks[1]
	var hazard: BossAttackHazard = _hazard(spec, target)
	hazard._physics_process(spec.windup * 0.5)
	assert_true(hazard._flight.global_position.y > 4.0, "The projectile follows a real elevated arc during its warning")
	assert_eq(target.hits, 0)
	hazard._physics_process(spec.windup * 0.5)
	assert_true(hazard.armed_trap)
	assert_eq(target.hits, 0, "Empty impact arms, it does not hit remotely")
	target.global_position = Vector3(0, 0.9, 0)
	hazard._physics_process(0.01)
	hazard._physics_process(0.01)
	assert_eq(target.hits, 1)
	assert_false(hazard.armed_trap)

func test_occupied_lob_does_not_leave_a_second_trap_and_burst_cannot_damage_late_entry() -> void:
	var target: Target = _target(Vector3(0, 0.9, 0))
	var lob: BossAttackHazard = _hazard(BossEncounterCatalog.build(1).attacks[1], target)
	lob._physics_process(lob.spec.windup)
	assert_eq(target.hits, 1)
	assert_false(lob.armed_trap)
	lob._physics_process(0.1)
	assert_eq(target.hits, 1)
	target.global_position = Vector3(10, 0.9, 0)
	var burst: BossAttackHazard = _hazard(BossEncounterCatalog.build(1).attacks[0], target)
	burst._physics_process(burst.spec.windup)
	target.global_position = Vector3(0, 0.9, 0)
	burst._physics_process(0.01)
	assert_eq(target.hits, 1, "Burst is an instant, harmless aftermath cannot hit a late entrant")

func test_line_front_speed_matches_preview_and_reached_tail_deals_dps_until_end() -> void:
	var target: Target = _target(Vector3(0, 0.9, -4))
	var spec: BossAttackSpec = BossEncounterCatalog.build(3).attacks[0]
	spec.windup = 2.0
	spec.reach = 8.0
	spec.damage = 10.0
	spec.synchronise_duration()
	var hazard: BossAttackHazard = _hazard(spec, target)
	assert_eq(spec.active, spec.windup)
	hazard._physics_process(2.0)
	assert_eq(target.hits, 0)
	hazard._physics_process(0.8)
	assert_eq(target.hits, 0, "Growing front has not reached the target yet")
	hazard._physics_process(0.4)
	assert_almost_eq(target.total_damage, 2.0, 0.0001)
	hazard._physics_process(0.5)
	assert_almost_eq(target.total_damage, 7.0, 0.0001, "Already reached tail remains dangerous")
	target.global_position.x = spec.width
	hazard._physics_process(0.2)
	assert_almost_eq(target.total_damage, 7.0, 0.0001, "Perpendicular exit stops DPS immediately")
	target.global_position.x = 0.0
	hazard._physics_process(0.2)
	assert_almost_eq(target.total_damage, 8.0, 0.0001, "Only the portion before the full-reach end is damaging")

func test_four_radial_routes_preserve_preview_active_speed_and_dual_rays_are_slower() -> void:
	for variant: int in range(4):
		var spec: BossAttackSpec = BossEncounterCatalog.build(3).attacks[1].duplicate() as BossAttackSpec
		spec.radial_variant = variant
		spec.angular_speed_degrees = 60.0
		spec.synchronise_duration()
		var starts: PackedFloat32Array = spec.radial_angles(0.0)
		var ends: PackedFloat32Array = spec.radial_angles(1.0)
		assert_eq(spec.windup, spec.active)
		assert_eq(starts.size(), 1 if variant < 2 else 2)
		for index: int in range(starts.size()):
			assert_almost_eq(absf(ends[index] - starts[index]) / spec.windup, 60.0 if variant < 2 else 30.0, 0.0001)

func test_radial_whole_anchored_ray_hits_between_slow_frames_and_dual_overlap_is_not_double_damage() -> void:
	var target: Target = _target(Vector3(0, 0.9, -8))
	var spec: BossAttackSpec = BossEncounterCatalog.build(3).attacks[1].duplicate() as BossAttackSpec
	spec.angular_speed_degrees = 60.0
	spec.damage = 12.0
	spec.synchronise_duration()
	var hazard: BossAttackHazard = _hazard(spec, target)
	hazard._physics_process(spec.windup)
	hazard._physics_process(spec.active)
	assert_almost_eq(target.total_damage, 2.0, 0.0001, "Finite swept exposure survives a frame spanning the entire ray sweep")
	var before: float = target.total_damage
	spec = spec.duplicate() as BossAttackSpec
	spec.radial_variant = BossAttackSpec.RadialVariant.CENTRE_TO_EDGES
	spec.synchronise_duration()
	hazard = _hazard(spec, target)
	hazard._physics_process(spec.windup)
	hazard._physics_process(spec.active)
	assert_almost_eq(target.total_damage - before, 2.0, 0.0001, "Coincident rays at centre count their union, not both")

func test_chain_positions_are_predetermined_and_each_warning_has_its_own_explosion() -> void:
	var target: Target = _target(Vector3(0, 0.9, 0))
	var spec: BossAttackSpec = BossEncounterCatalog.build(3).attacks[2].duplicate() as BossAttackSpec
	spec.windup = 1.0
	spec.mark_gap = 0.4
	spec.synchronise_duration()
	var hazard: BossAttackHazard = _hazard(spec, target)
	assert_eq(hazard.marks.size(), 1)
	target.global_position = Vector3(20, 0.9, 20)
	hazard._physics_process(0.4)
	assert_eq(hazard.marks.size(), 2)
	assert_lt(hazard.marks[1].centre.length(), spec.spread_radius + 0.1, "Second point was selected before the hero moved")
	target.global_position = Vector3(0, 0.9, 0)
	hazard._physics_process(0.6)
	assert_true(hazard.marks[0].exploded)
	assert_false(hazard.marks[1].exploded)
	assert_eq(target.hits, 1)
	target.global_position = hazard.marks[1].centre + Vector3.UP * 0.9
	hazard._physics_process(0.4)
	assert_true(hazard.marks[1].exploded)
	assert_eq(target.hits, 2)

func test_chase_samples_exactly_six_real_positions_and_existing_marks_never_follow() -> void:
	var target: Target = _target(Vector3(0, 0.9, 0))
	var spec: BossAttackSpec = BossEncounterCatalog.build(5).attacks[2].duplicate() as BossAttackSpec
	spec.windup = 3.0
	spec.mark_gap = 0.3
	spec.synchronise_duration()
	var hazard: BossAttackHazard = _hazard(spec, target)
	for index: int in range(1, 6):
		target.global_position = Vector3(float(index) * 4.0, 0.9, float(index) * -2.0)
		hazard._physics_process(0.30001)
		assert_eq(hazard.marks[index].centre, Vector3(float(index) * 4.0, 0, float(index) * -2.0))
	assert_eq(hazard.marks.size(), 6)
	target.global_position = Vector3(99, 0.9, 99)
	hazard._physics_process(0.3)
	assert_eq(hazard.marks.size(), 6)
	assert_eq(hazard.marks[0].centre, Vector3.ZERO)
	assert_eq(target.hits, 0)

func test_sweep_warning_strip_and_stationary_body_are_safe_but_real_body_segment_hits_once() -> void:
	var target: Target = _target(Vector3(0, 0.9, -5))
	var spec: BossAttackSpec = BossEncounterCatalog.build(2).attacks[0]
	var hazard: BossAttackHazard = _hazard(spec, target)
	hazard._physics_process(spec.windup)
	assert_eq(target.hits, 0)
	hazard._physics_process(0.1)
	assert_eq(target.hits, 0, "A stationary boss cannot hurt the marked corridor")
	hazard.boss.global_position.z = -8.0
	hazard._physics_process(0.1)
	assert_eq(target.hits, 1, "Body traversal crosses the target even between frames")
	hazard.boss.global_position.z = -10.0
	hazard._physics_process(0.1)
	assert_eq(target.hits, 1)

func test_dead_owner_cancels_armed_trap_and_pending_trail_without_late_hits() -> void:
	var target: Target = _target(Vector3(20, 0.9, 20))
	var lob: BossAttackHazard = _hazard(BossEncounterCatalog.build(1).attacks[1], target)
	lob._physics_process(lob.spec.windup)
	assert_true(lob.armed_trap)
	lob.boss.die()
	target.global_position = Vector3(0, 0.9, 0)
	lob._physics_process(0.1)
	assert_eq(target.hits, 0)
	var trail: BossAttackHazard = _hazard(BossEncounterCatalog.build(5).attacks[2], target)
	trail.cancel()
	trail._physics_process(5.0)
	assert_eq(trail.marks.size(), 1)
	assert_eq(target.hits, 0)

func test_real_sweep_contact_starts_production_carry_and_boss_death_releases_it() -> void:
	var player: PlayerPrototype = (load("res://scenes/player.tscn") as PackedScene).instantiate() as PlayerPrototype
	add_child_autoqfree(player)
	player.set_physics_process(false)
	player.input_enabled = true
	player.current_health = 1000.0
	player.global_position = Vector3(0, 0.9, -5)
	var hazard: BossAttackHazard = _hazard(BossEncounterCatalog.build(2).attacks[0], player)
	hazard._physics_process(hazard.spec.windup)
	hazard.boss.state = SiegeBoss.State.ACTIVE
	hazard.boss.move_and_collide(Vector3(0, 0, -6))
	hazard._physics_process(0.1)
	assert_almost_eq(player.current_health, 970.0, 0.0001)
	assert_true(player.enemy_carry.active(player))
	assert_lt(player.global_position.z, hazard.boss.global_position.z, "The real receiver is carried ahead of the moving body")
	hazard.boss.die()
	assert_false(player.enemy_carry.active(player))
	assert_true(player.input_enabled, "Cancellation restores locomotion without toggling input flags")

func test_continuous_damage_total_and_bounded_pulses_are_independent_of_physics_step() -> void:
	for step: float in [1.0 / 60.0, 0.1, 0.37]:
		for radial: bool in [false, true]:
			var target: Target = _target(Vector3(0, 0.9, -5))
			var spec: BossAttackSpec = BossEncounterCatalog.build(3).attacks[1 if radial else 0].duplicate() as BossAttackSpec
			spec.windup = 1.0
			spec.reach = 10.0
			spec.damage = 12.0
			spec.angular_speed_degrees = 60.0
			spec.synchronise_duration()
			var hazard: BossAttackHazard = _hazard(spec, target)
			var time: float = 0.0
			while not hazard.cancelled and time < 5.0:
				hazard._physics_process(step)
				time += step
			assert_almost_eq(target.total_damage, 2.0 if radial else 6.0, 0.0001, "DPS preserves exposure and flushes the final fraction")
			assert_lte(target.hits, 4 if radial else 7, "Counter/parry events are bounded by .1s cadence, not Hz")

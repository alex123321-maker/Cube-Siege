extends "res://tools/capture_bosses.gd"

## Bounded review of all canonical elite actions, using production EnemyBase motion
## and EliteSkillController/EliteSkillHazard clocks. This adds no alternate executor.
const RegistryScript = preload("res://scripts/core/entity_registry.gd")
const STEP: float = 1.0 / 30.0

func _initialize() -> void:
	_output = "res://screenshots_debug/elites/capture/"
	super._initialize()

func _capture() -> void:
	seed(330519)
	DirAccess.make_dir_recursive_absolute(_output)
	_build_arena()
	_player.talents.build().selected_talents.clear()
	_camera.global_position = Vector3(14.0, 18.0, 10.0)
	_camera.look_at(Vector3(0.0, 0.0, -3.0))
	_lighting.apply_night_instant(_light, _environment)
	_caption.text = "CUBE SIEGE / NINE CANONICAL ELITE SKILLCHECKS"
	_detail.text = "Production archetypes / actual movement, projectiles, contact and lifetime"
	for frame: int in range(15):
		await process_frame
	await _save("00_arena")
	for index: int in range(EliteSkillCatalog.IDS.size()):
		await _elite_case(EliteSkillCatalog.IDS[index], index + 1)
	await _sustained_exit("fire_breath", 10)
	await _sustained_exit("spit_puddle", 11)
	await _terminal_cleanup_case()
	await _lost_target_case()
	_caption.text = "ELITE REVIEW COMPLETE"
	_detail.text = "%d authoritative cases / %s" % [_checks.size(), "FAIL" if _failed else "PASS"]
	await _save("99_complete")
	var report: FileAccess = FileAccess.open(_output + "gameplay_checks.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed": not _failed, "checks": _checks,
		"arena": "flat review arena; production actors and native locomotion; stationary hero then explicit side exit; not terrain/crowd/balance evidence"}, "\t"))
	report.close()
	print("ELITE_CAPTURE pass=", not _failed, " attack_samples=", _checks.size(), " seed=330519")
	_world.queue_free()
	await process_frame
	await process_frame

func _terminal_cleanup_case() -> void:
	_reset_hero()
	_lighting.apply_day_instant(_light, _environment)
	_camera.global_position = Vector3(14.0, 18.0, 14.0)
	_camera.look_at(Vector3.ZERO)
	var cycle: DayNightCycle = DayNightCycle.new()
	cycle.name = "LifecycleCycle"
	_world.add_child(cycle)
	cycle.set_process(false)
	var waves: WaveDirector = WaveDirector.new()
	waves.day_night_path = cycle.get_path()
	waves.player_path = _player.get_path()
	_world.add_child(waves)
	waves.set_process(false)
	var portal: PortalController = (load("res://scenes/portal.tscn") as PackedScene).instantiate() as PortalController
	_world.add_child(portal)
	portal.hide()
	var coordinator: WarriorRunCoordinator = WarriorRunCoordinator.new()
	_world.add_child(coordinator)
	coordinator.setup(_player, cycle, waves, portal)
	var pending_owner: EnemyBase = _spawn_elite("underground_spike")
	pending_owner.global_position.x = 4.0
	pending_owner.elite_skill_controller.start_attack()
	var warning: EliteSkillHazard = pending_owner.elite_skill_controller.hazards[0]
	warning.set_physics_process(false)
	warning.warning_duration = 10.0
	warning._physics_process(3.0)
	_player.global_position.z = 3.0
	var active_owner: EnemyBase = _spawn_elite("underground_spike")
	active_owner.global_position.x = -4.0
	active_owner.elite_skill_controller.start_attack()
	var spike: EliteSkillHazard = active_owner.elite_skill_controller.hazards[0]
	spike.set_physics_process(false)
	spike._physics_process(spike.warning_duration)
	var registry: RegistryScript = root.get_node("EntityRegistry") as RegistryScript
	var obstacle_before: bool = registry.monster_flowfield.blocked_cells.has(Vector2i(0, 3))
	_caption.text = "I1 / PENDING AND ACTIVE SPIKES / BEFORE RUN STOP"
	_detail.text = "Real actors, real collider and navigation / warning has not emerged"
	await _save("12_terminal_before")
	for frame: int in range(20):
		await process_frame
	cycle.current_day = 30
	coordinator._on_wave_completed(30)
	var synchronous: bool = coordinator.finished and warning.cancelled and spike.cancelled and warning._solid == null and spike._solid.collision_layer == 0 and not registry.monster_flowfield.blocked_cells.has(Vector2i(0, 3))
	var hp: float = _player.current_health
	warning._physics_process(20.0)
	spike._physics_process(20.0)
	for frame: int in range(30):
		await process_frame
	var passed: bool = obstacle_before and synchronous and not is_instance_valid(warning) and not is_instance_valid(spike) and is_equal_approx(hp, _player.current_health) and not registry.monster_flowfield.blocked_cells.has(Vector2i(0, -3))
	_caption.text = "I1 / REAL COORDINATOR / TERMINAL CLEANUP"
	_detail.text = "Pending spike cancelled / active collider and nav released / %s" % ("PASS" if passed else "FAIL")
	await _save("12_terminal_cleared")
	_checks.append({"case": "terminal_coordinator_cancels_pending_and_active_spikes", "obstacle_before": obstacle_before, "synchronous_cleanup": synchronous, "passed": passed})
	_failed = _failed or not passed
	for node: Node in [coordinator, portal, waves, cycle, pending_owner, active_owner]:
		node.queue_free()
	await process_frame
	await process_frame

func _lost_target_case() -> void:
	_reset_hero()
	_player.talents.reset_for_viewer(WarriorTalentCatalog.TALENT_IDS)
	_player.talents.build().selected_talents.clear()
	var actor: EnemyBase = _spawn_elite("triple_throw")
	var controller: EliteSkillController = actor.elite_skill_controller
	controller.start_attack()
	_caption.text = "B4 / FIRST LOB RELEASED / TARGET STILL PRESENT"
	_detail.text = "Real controller / next throw is pending"
	await _save("13_target_before")
	_player.free()
	controller.advance(controller.spec.interval)
	var returned: bool = controller.state == EliteSkillController.State.RECOVERY and controller._throws == 1 and is_instance_valid(actor)
	_caption.text = "B4 / TARGET FREED / CONTROLLER RETURNED"
	_detail.text = "Shooter remains alive / no future throws / released lob keeps its finite flight"
	await _save("13_target_removed")
	for frame: int in range(60):
		controller.advance(STEP)
		await process_frame
	var live_hazards: int = 0
	for child: Node in _world.get_children():
		if child is EliteSkillHazard and not child.is_queued_for_deletion():
			live_hazards += 1
	var passed: bool = returned and controller._throws == 1 and controller.cast_count == 1 and live_hazards == 0
	_detail.text = "Finite return and released effect expiry / %s" % ("PASS" if passed else "FAIL")
	await _save("13_target_expired")
	_checks.append({"case": "target_free_between_lobs_returns_without_new_throws", "returned": returned, "throws": controller._throws, "casts": controller.cast_count, "live_hazards_at_end": live_hazards, "passed": passed})
	_failed = _failed or not passed
	actor.queue_free()
	await process_frame
	quit(2 if _failed else 0)

func _spawn_elite(skill_id: String) -> EnemyBase:
	var spec: EliteSkillSpec = EliteSkillCatalog.create_spec(skill_id)
	var actor: EnemyBase = (load(spec.scene_path) as PackedScene).instantiate() as EnemyBase
	_world.add_child(actor)
	actor.global_position = Vector3(0.0, actor.half_height, 0.0)
	actor.target_player = _player
	actor.set_physics_process(false)
	EliteSkillController.attach(actor, skill_id, Callable(self, "_flat_height"))
	return actor

func _reset_hero() -> void:
	_player.global_position = Vector3(0.0, 0.9, -3.0)
	_player.velocity = Vector3.ZERO
	_player.current_health = _player.max_health
	_player.health.shield_health = 0.0
	_player.health.is_parrying = false
	_player.talents.statuses.clear()

func _drive_actor(actor: EnemyBase) -> void:
	# The recording fixes rendering at 30Hz. Hazards retain engine physics.
	# Stop after this cast's recovery, so ordinary archetype attacks do not pollute
	# the measured skill damage. The full sandbox keeps their normal AI enabled.
	if actor.elite_skill_controller.state != EliteSkillController.State.COOLDOWN:
		actor._physics_process(STEP)
	_player.health.update_timers(STEP)

func _elite_case(skill_id: String, index: int) -> void:
	_reset_hero()
	var actor: EnemyBase = _spawn_elite(skill_id)
	var controller: EliteSkillController = actor.elite_skill_controller
	var spec: EliteSkillSpec = controller.spec
	var started: bool = controller.start_attack()
	var before: float = _player.current_health
	var expected: float = spec.damage
	var active_end: float = spec.windup + 0.3
	var active_snapshot: float = spec.windup + 0.08
	match spec.kind:
		EliteSkillSpec.Kind.TRIPLE_THROW:
			expected *= 3.0
			active_end = 2.0 * spec.interval + spec.flight_time + 0.3
			active_snapshot = spec.flight_time + 0.08
		EliteSkillSpec.Kind.BACKSWING:
			expected *= 2.0
			active_end = spec.windup + spec.interval + 0.3
		EliteSkillSpec.Kind.UNDERGROUND_SPIKE:
			active_end = spec.windup + spec.lifetime + 0.3
			active_snapshot = spec.windup + 0.35
		EliteSkillSpec.Kind.RETURNING_BLADE:
			expected *= 2.0
			active_end = spec.windup + 2.0 * spec.reach / spec.speed + spec.interval + 0.3
			active_snapshot = spec.windup + 3.0 / spec.speed
		EliteSkillSpec.Kind.LEAP_STRIKE:
			active_end = spec.windup + spec.flight_time + 0.3
			active_snapshot = spec.windup + spec.flight_time * 0.5
		EliteSkillSpec.Kind.FIRE_BREATH:
			expected *= spec.duration
			active_end = spec.windup + spec.duration + 0.3
			active_snapshot = spec.windup + spec.duration * 0.5
		EliteSkillSpec.Kind.SPIT_PUDDLE:
			expected += spec.residue_damage_per_second * spec.lifetime
			active_end = spec.windup + 3.0 / spec.speed + spec.lifetime + 0.5
			active_snapshot = spec.windup + 3.0 / spec.speed + 0.4
		EliteSkillSpec.Kind.FOOT_MINE:
			active_end = spec.windup + 0.5
		EliteSkillSpec.Kind.SHORT_LUNGE:
			active_end = spec.windup + spec.reach / spec.speed + spec.recovery + 0.3
			active_snapshot = spec.windup + 3.0 / spec.speed
	var stem: String = "%02d_%s" % [index, skill_id]
	var warning_window: float = spec.flight_time if spec.kind == EliteSkillSpec.Kind.TRIPLE_THROW else spec.windup
	var warning_safe: bool = false
	var obstacle_seen: bool = false
	var obstacle_ray_hit: bool = false
	var navigation_blocked: bool = false
	var max_body_height: float = actor.global_position.y
	var recovery_stop_seen: bool = false
	var recovery_position: Vector3 = Vector3.INF
	_caption.text = "ELITE %d / %s" % [index, spec.title]
	for frame: int in range(ceili(active_end / STEP)):
		_drive_actor(actor)
		max_body_height = maxf(max_body_height, actor.global_position.y)
		_detail.text = "%s / %.2fs / HP loss %.2f" % [EliteSkillController.State.keys()[controller.state], float(frame) * STEP, before - _player.current_health]
		if frame == floori(warning_window * 0.55 / STEP):
			warning_safe = is_equal_approx(before, _player.current_health)
			await _save(stem + "_warning")
		if frame == ceili(active_snapshot / STEP):
			if spec.kind == EliteSkillSpec.Kind.UNDERGROUND_SPIKE:
				for hazard: EliteSkillHazard in controller.hazards:
					if is_instance_valid(hazard) and is_instance_valid(hazard._solid):
						obstacle_seen = hazard._solid.collision_layer == 1
						var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(2.0, 1.0, -3.0), Vector3(-2.0, 1.0, -3.0), 1)
						var result: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(query)
						obstacle_ray_hit = result.get("collider") == hazard._solid
						var registry: RegistryScript = root.get_node("EntityRegistry") as RegistryScript
						navigation_blocked = registry.monster_flowfield.blocked_cells.has(Vector2i(0, -3))
			await _save(stem + "_active")
		if controller.state == EliteSkillController.State.RECOVERY:
			if recovery_position == Vector3.INF:
				recovery_position = actor.global_position
			elif actor.global_position.distance_to(recovery_position) <= 0.02:
				recovery_stop_seen = true
		await process_frame
	var loss: float = before - _player.current_health
	var actual_end: Vector3 = actor.global_position
	var extra_ok: bool = true
	match spec.kind:
		EliteSkillSpec.Kind.UNDERGROUND_SPIKE:
			extra_ok = obstacle_seen and obstacle_ray_hit and navigation_blocked
		EliteSkillSpec.Kind.LEAP_STRIKE:
			extra_ok = max_body_height > actor.half_height + 2.0 and Vector2(actual_end.x, actual_end.z).distance_to(Vector2(0.0, -3.0)) <= 0.15
		EliteSkillSpec.Kind.SHORT_LUNGE:
			extra_ok = actual_end.z < -5.0 and recovery_stop_seen
	var live_hazards: int = 0
	for child: Node in _world.get_children():
		if child is EliteSkillHazard and not child.is_queued_for_deletion():
			live_hazards += 1
	var passed: bool = started and warning_safe and absf(loss - expected) <= 0.06 and extra_ok and live_hazards == 0
	_checks.append({"skill": skill_id, "source_page": spec.source_page, "scene": spec.scene_path,
		"warning_safe": warning_safe, "expected_damage": expected, "actual_health_loss": loss,
		"physical_spike": obstacle_seen, "spike_ray_hit": obstacle_ray_hit, "nav_blocked": navigation_blocked,
		"body_max_height": max_body_height, "body_final_position": [actual_end.x, actual_end.y, actual_end.z],
		"recovery_stop_seen": recovery_stop_seen, "live_hazards_at_end": live_hazards, "passed": passed})
	_failed = _failed or not passed
	print("ELITE_SAMPLE ", stem, " expected=", expected, " loss=", loss, " warning_safe=", warning_safe, " extra_ok=", extra_ok, " hazards=", live_hazards, " pass=", passed)
	await _save(stem + "_cleared")
	controller.cancel_attack()
	actor.queue_free()
	await process_frame
	await process_frame

func _sustained_exit(skill_id: String, index: int) -> void:
	_reset_hero()
	var actor: EnemyBase = _spawn_elite(skill_id)
	var controller: EliteSkillController = actor.elite_skill_controller
	var spec: EliteSkillSpec = controller.spec
	controller.start_attack()
	var before: float = _player.current_health
	var exit_time: float = spec.windup + 0.55
	if spec.kind == EliteSkillSpec.Kind.SPIT_PUDDLE:
		exit_time += 3.0 / spec.speed
	var after_exit_flush: float = -1.0
	var fixed_origin_seen: bool = false
	_caption.text = "ELITE / %s / SIDE EXIT" % spec.title
	for frame: int in range(ceili((exit_time + 0.6) / STEP)):
		var time: float = float(frame) * STEP
		if time >= exit_time:
			_player.global_position.x = 4.0
		_drive_actor(actor)
		for hazard: EliteSkillHazard in controller.hazards:
			if is_instance_valid(hazard):
				fixed_origin_seen = fixed_origin_seen or (hazard.direction.is_equal_approx(Vector3.FORWARD) and (spec.kind != EliteSkillSpec.Kind.SPIT_PUDDLE or absf(hazard._spit_land_position.x) < 0.01))
		if frame == ceili((exit_time - 0.1) / STEP):
			await _save("%02d_%s_inside" % [index, skill_id])
		if frame == ceili((exit_time + 0.15) / STEP):
			after_exit_flush = _player.current_health
			await _save("%02d_%s_side_exit" % [index, skill_id])
		_detail.text = "Locked direction / actual exposure ends outside / HP loss %.2f" % (before - _player.current_health)
		await process_frame
	var passed: bool = before > _player.current_health and after_exit_flush > 0.0 and is_equal_approx(after_exit_flush, _player.current_health) and fixed_origin_seen
	_checks.append({"skill": skill_id, "case": "side_exit_stops_new_exposure", "actual_health_loss": before - _player.current_health,
		"health_after_exit_flush": after_exit_flush, "health_at_end": _player.current_health, "fixed_origin": fixed_origin_seen, "passed": passed})
	_failed = _failed or not passed
	print("ELITE_SIDE_EXIT ", skill_id, " pass=", passed)
	controller.cancel_attack()
	actor.queue_free()
	await process_frame
	await process_frame

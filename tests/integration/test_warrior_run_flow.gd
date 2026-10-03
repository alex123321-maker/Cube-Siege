extends GutTest

class TestWaves extends WaveDirector:
	var last_boss: SiegeBoss
	var spawned_stages: Array[int] = []
	var owned_bosses: Array[SiegeBoss] = []
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass
	func spawn_boss(_scene: PackedScene, stage: int) -> SiegeBoss:
		last_boss = SiegeBoss.new()
		last_boss.configure(stage, player)
		owned_bosses.append(last_boss)
		spawned_stages.append(stage)
		return last_boss
	func _exit_tree() -> void:
		for boss: SiegeBoss in owned_bosses:
			if is_instance_valid(boss):
				boss.free()

var _save: Node
var _snapshot: Dictionary
var _storage: String
var _player: PlayerPrototype
var _cycle: DayNightCycle
var _waves: TestWaves
var _portal: PortalController
var _coordinator: WarriorRunCoordinator

func before_each() -> void:
	_save = get_node("/root/SaveManager")
	_snapshot = _save.snapshot_state()
	_storage = _save.storage_dir
	_save.set_storage_dir("user://test_warrior_run_flow/")
	_save.reset_to_defaults()
	_player = preload("res://scenes/player.tscn").instantiate() as PlayerPrototype
	add_child_autoqfree(_player)
	_player.set_physics_process(false)
	_cycle = DayNightCycle.new()
	add_child_autoqfree(_cycle)
	_cycle.set_process(false)
	_waves = TestWaves.new()
	_waves.player = _player
	add_child_autoqfree(_waves)
	_cycle.phase_changed.connect(_waves._on_phase_changed)
	_portal = preload("res://scenes/portal.tscn").instantiate() as PortalController
	add_child_autoqfree(_portal)
	_coordinator = WarriorRunCoordinator.new()
	add_child_autoqfree(_coordinator)
	_coordinator.setup(_player, _cycle, _waves, _portal)

func after_each() -> void:
	for child: Node in get_children():
		if child is EliteSkillHazard:
			(child as EliteSkillHazard).cancel()
		elif child.scene_file_path == "res://scenes/floating_text.tscn":
			child.queue_free()
	_save.restore_state(_snapshot)
	_save.set_storage_dir(_storage)
	get_node("/root/RosterManager").run_active = false
	var file: String = "user://test_warrior_run_flow/cube_siege_save.json"
	if FileAccess.file_exists(file):
		DirAccess.remove_absolute(file)
	await get_tree().process_frame

func test_growing_nights_and_boss_gate_preserve_day_and_no_midrun_save() -> void:
	assert_eq(_cycle.day_duration, 30.0)
	assert_eq(_cycle.get_night_duration(1), 22.0)
	assert_eq(_cycle.get_night_duration(29), 78.0)
	_cycle.current_day = 5
	_cycle.start_night()
	assert_true(_cycle.boss_pending)
	_cycle._process(1000.0)
	assert_true(_cycle.is_night, "Boss night persists past the ordinary timer")
	assert_eq(_cycle.current_day, 5)
	assert_eq(_save.roster_slots[0].max_day, 0, "Progress is only committed after extraction")
	assert_false(_cycle.finish_boss_night(10), "Another wave's callback cannot finish this boss")
	_coordinator._on_boss_defeated(_waves.last_boss)
	assert_false(_cycle.is_night)
	assert_eq(_cycle.current_day, 6)
	assert_eq(_player.player_level, 2)
	assert_eq(_player.progression.run_build.unspent_specialization_points, 1)

func test_all_thirty_waves_spawn_six_stages_and_final_saves_retained_hero_once() -> void:
	_save.roster_slots[0].unlocked_talents.append("loud_triumph")
	_player.progression.record_resource_gathered(75)
	var results: Array = []
	_coordinator.run_finished.connect(func(won: bool, extracted: bool, earned: int) -> void: results.append([won, extracted, earned]))
	for wave: int in range(1, 31):
		assert_eq(_cycle.current_day, wave)
		_cycle.start_night()
		if wave % 5 == 0:
			_coordinator._on_boss_defeated(_waves.last_boss)
		else:
			_cycle.complete_night()
	assert_eq(_waves.spawned_stages, [1, 2, 3, 4, 5, 6])
	assert_eq(_player.player_level, 7, "Every boss grants exactly one level")
	assert_true(_coordinator.finished)
	assert_false(_cycle.running)
	assert_false(_waves.is_active)
	assert_eq(results.size(), 1)
	assert_eq(results[0], [true, true, 590])
	assert_eq(_save.run_history.size(), 1)
	assert_eq(int(_save.roster_slots[0].victories), 1)
	assert_true(_save.roster_slots[0].unlocked_talents.has("loud_triumph"))
	_coordinator._on_player_died()
	_coordinator._on_portal_evacuated(30, 99999)
	assert_eq(_save.run_history.size(), 1, "Late death/extraction callbacks cannot duplicate or replace victory")

func test_real_portal_extraction_commits_level_and_collected_resource_reward() -> void:
	_player.progression.grant_level()
	_player.progression.record_resource_gathered(50)
	_portal.current_state = PortalController.State.ACTIVE
	_portal.evacuate_player(_player)
	assert_true(_coordinator.finished)
	assert_eq(int(_save.roster_slots[0].talent_xp), 240)
	assert_eq(_save.run_history[0].outcome, "evacuated")
	assert_eq(_save.run_history.size(), 1)
	_portal.evacuate_player(_player)
	assert_eq(_save.run_history.size(), 1)

func test_death_resets_openings_and_cancels_checkpoint() -> void:
	_save.roster_slots[0].unlocked_talents.append("counterattack")
	_save.roster_slots[0].talent_xp = 1000
	_player.progression.run_build.offer_checkpoint(1, true)
	_coordinator._on_player_died()
	assert_true(_coordinator.finished)
	assert_false(_player.progression.run_build.active)
	assert_eq(_save.roster_slots[0].unlocked_talents, WarriorTalentCatalog.STARTER_IDS)
	assert_eq(int(_save.roster_slots[0].talent_xp), 0)
	assert_eq(_save.run_history[0].outcome, "defeat")

func test_sunrise_despawns_without_a_kill_reward() -> void:
	var enemy: EnemyBase = preload("res://scenes/enemy_dummy.tscn").instantiate() as EnemyBase
	add_child_autoqfree(enemy)
	enemy.set_physics_process(false)
	var before: float = _player.current_xp
	_waves._on_phase_changed(false, 2)
	await get_tree().process_frame
	assert_eq(_player.current_xp, before)
	assert_false(is_instance_valid(enemy))

func test_failed_death_save_can_retry_without_another_death_signal() -> void:
	_save.roster_slots[0].talent_xp = 1234
	var valid_path: String = _save.save_file_path
	_save.save_file_path += "/missing/subfolder/save.json"
	_coordinator._on_player_died()
	assert_push_error("Failed to open save file")
	assert_false(_coordinator.finished)
	assert_false(_cycle.running)
	assert_eq(int(_save.roster_slots[0].talent_xp), 1234, "Failed transaction rolls back until retry")
	_save.save_file_path = valid_path
	assert_true(_coordinator.retry_save())
	assert_eq(_save.run_history[0].outcome, "defeat")
	assert_eq(int(_save.roster_slots[0].talent_xp), 0)
	assert_false(_coordinator.retry_save())
	assert_eq(_save.run_history.size(), 1)

func test_failed_final_save_preserves_victory_across_late_extraction_callback() -> void:
	var valid_path: String = _save.save_file_path
	_save.save_file_path += "/missing/subfolder/save.json"
	_cycle.current_day = 30
	_coordinator._on_wave_completed(30)
	assert_push_error("Failed to open save file")
	assert_false(_coordinator.finished)
	_save.save_file_path = valid_path
	_coordinator._on_portal_evacuated(30, 99999)
	assert_true(_coordinator.finished)
	assert_true(_coordinator.victory)
	assert_eq(_save.run_history[0].outcome, "victory")
	assert_eq(int(_save.roster_slots[0].victories), 1)
	assert_eq(_save.run_history.size(), 1)

func _elite_cast(skill_id: String, point: Vector3) -> EliteSkillController:
	_player.global_position = point + Vector3.UP * 0.9
	var definition: EliteSkillSpec = EliteSkillCatalog.create_spec(skill_id)
	var enemy: EnemyBase = (load(definition.scene_path) as PackedScene).instantiate() as EnemyBase
	add_child_autoqfree(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = point + Vector3(3.0, enemy.half_height, 0.0)
	enemy.target_player = _player
	var controller: EliteSkillController = EliteSkillController.attach(enemy, skill_id, func(_x: int, _z: int) -> int: return 0)
	assert_true(controller.start_attack())
	return controller

func _check_terminal_elite_cleanup(outcome: String, fail_save: bool = false) -> void:
	var registry: Node = get_node("/root/EntityRegistry")
	var pending: EliteSkillController = _elite_cast("underground_spike", Vector3(12.5, 0.0, 12.5))
	var warning: EliteSkillHazard = pending.hazards[0]
	warning.warning_duration = 0.1
	var active: EliteSkillController = _elite_cast("underground_spike", Vector3(18.5, 0.0, 18.5))
	var spike: EliteSkillHazard = active.hazards[0]
	spike._physics_process(spike.warning_duration)
	assert_true(is_instance_valid(spike._solid))
	assert_true(registry.monster_flowfield.blocked_cells.has(Vector2i(18, 18)))
	var shooter: EliteSkillController = _elite_cast("triple_throw", Vector3(24.5, 0.0, 24.5))
	var lob: EliteSkillHazard = shooter.hazards[0]
	var valid_path: String = _save.save_file_path
	if fail_save:
		_save.save_file_path += "/missing/subfolder/save.json"
	match outcome:
		"evacuated":
			_portal.current_state = PortalController.State.ACTIVE
			_portal.evacuate_player(_player)
		"victory":
			_cycle.current_day = 30
			_coordinator._on_wave_completed(30)
		"defeat":
			_coordinator._on_player_died()
	if fail_save:
		assert_push_error("Failed to open save file")
	assert_eq(_coordinator.finished, not fail_save)
	assert_false(_player.progression.run_build.active)
	for hazard: EliteSkillHazard in [warning, spike, lob]:
		assert_true(hazard.cancelled, "Terminal stop synchronously cancels sibling effects, including released projectiles")
		var before: float = hazard.elapsed
		hazard._physics_process(10.0)
		assert_eq(hazard.elapsed, before)
		assert_eq(hazard.hit_count, 0 if hazard == warning or hazard == lob else 1)
	assert_null(warning._solid, "The pending spike must not create a collider after terminal stop")
	assert_eq(spike._solid.collision_layer, 0)
	assert_false(registry.monster_flowfield.blocked_cells.has(Vector2i(18, 18)))
	for controller: EliteSkillController in [pending, active, shooter]:
		assert_eq(controller.hazards.size(), 0)
		assert_eq(controller.enemy.process_mode, Node.PROCESS_MODE_DISABLED)
	var hp: float = _player.current_health
	for frame: int in range(12):
		await get_tree().physics_frame
	assert_false(is_instance_valid(warning))
	assert_false(is_instance_valid(spike))
	assert_false(is_instance_valid(lob))
	assert_false(registry.monster_flowfield.blocked_cells.has(Vector2i(12, 12)))
	assert_false(registry.monster_flowfield.blocked_cells.has(Vector2i(18, 18)))
	assert_eq(_player.current_health, hp)
	if fail_save:
		assert_eq(_save.run_history.size(), 0)
		_save.save_file_path = valid_path
		assert_true(_coordinator.retry_save())
		await get_tree().physics_frame
		assert_false(registry.monster_flowfield.blocked_cells.has(Vector2i(12, 12)))
	assert_eq(_save.run_history.size(), 1)
	assert_eq(_save.run_history[0].outcome, outcome)

func test_evacuating_cancels_pending_and_active_elite_effects() -> void:
	await _check_terminal_elite_cleanup("evacuated")

func test_victory_cancels_pending_and_active_elite_effects() -> void:
	await _check_terminal_elite_cleanup("victory")

func test_death_cancels_pending_and_active_elite_effects() -> void:
	await _check_terminal_elite_cleanup("defeat")

func test_failed_terminal_save_cancels_elite_effects_before_retry() -> void:
	await _check_terminal_elite_cleanup("victory", true)

func test_lethal_spike_cannot_create_obstacle_after_its_damage_ends_the_run() -> void:
	var controller: EliteSkillController = _elite_cast("underground_spike", Vector3(30.5, 0.0, 30.5))
	var hazard: EliteSkillHazard = controller.hazards[0]
	_player.current_health = 1.0
	hazard._physics_process(hazard.warning_duration)
	assert_true(_coordinator.finished)
	assert_true(hazard.cancelled)
	assert_null(hazard._solid, "A terminal callback during impact must stop the remainder of this same physics step")
	assert_false(get_node("/root/EntityRegistry").monster_flowfield.blocked_cells.has(Vector2i(30, 30)))
	await get_tree().physics_frame
	assert_false(is_instance_valid(hazard))

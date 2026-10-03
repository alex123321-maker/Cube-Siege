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
	_save.restore_state(_snapshot)
	_save.set_storage_dir(_storage)
	get_node("/root/RosterManager").run_active = false
	var file: String = "user://test_warrior_run_flow/cube_siege_save.json"
	if FileAccess.file_exists(file):
		DirAccess.remove_absolute(file)

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

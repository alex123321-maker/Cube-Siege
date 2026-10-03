extends SceneTree

## Finite, accelerated integration driver for the actual production main scene.
## Uses isolated saves before autoload; this is not a balance playthrough.
## Day/night clocks are advanced explicitly, incidental regular spawning is
## disabled, and each real boss is held at 10 HP for one production sword hit.

const DEADLINE_SECONDS: float = 150.0
const CAPTURE_DIR: String = "res://screenshots_debug/progression/run/"
var _checks: int = 0
var _failures: int = 0
var _capture: bool = false
var _immediate_teardown: bool = false
var _main: Node3D
var _player: PlayerPrototype
var _cycle: DayNightCycle
var _director: WaveDirector
var _coordinator: WarriorRunCoordinator
var _panel: WarriorBuildPanel
var _save: Node
var _watchdog: Timer
var _checkpoint_waves: Array[int] = []
var _boss_stages: Array[int] = []

func _initialize() -> void:
	_capture = OS.get_cmdline_user_args().has("--capture")
	_immediate_teardown = OS.get_cmdline_user_args().has("--immediate-teardown")
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	call_deferred("_run")

func _check(condition: bool, label: String) -> bool:
	_checks += 1
	if condition:
		print("[PASS] ", label)
	else:
		_failures += 1
		push_error("[FAIL] " + label)
	return condition

func _run() -> void:
	_watchdog = Timer.new()
	_watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	_watchdog.one_shot = true
	_watchdog.wait_time = DEADLINE_SECONDS
	_watchdog.timeout.connect(_on_deadline)
	root.add_child(_watchdog)
	_watchdog.start()
	_save = root.get_node("SaveManager")
	if not _check(_save.is_test_environment(), "save profile isolated before autoload"):
		_finish()
		return
	_save.reset_to_defaults()
	_save.selected_slot_index = 0
	_save.roster_slots[0].talent_xp = 7200
	var roster: Node = root.get_node("RosterManager")
	for definition: WarriorTalentDefinition in WarriorTalentCatalog.get_all():
		if definition.unlock_cost > 0:
			_check(roster.unlock_talent(0, definition.id), "production unlock " + definition.id)
	var retained_ids: Array[String] = roster.get_unlocked_talents(0)
	_main = preload("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(_main)
	current_scene = _main
	_player = _main.get_node("Player") as PlayerPrototype
	_cycle = _main.get_node("DayNightCycle") as DayNightCycle
	_director = _main.get_node("WaveDirector") as WaveDirector
	_coordinator = _main.run_coordinator
	_panel = _main.get_node("HUD").build_panel
	_check(_cycle.day_duration == 30.0 and _cycle.get_night_duration(1) == 22.0, "production main has actual 30 second day and growing first night")
	# Clock acceleration is confined to this driver. Production scene values
	# remain untouched and no test double replaces the director or boss scenes.
	_cycle.set_process(false)
	_director.set_process(false)
	await process_frame
	if not _check(_panel.visible and paused, "mandatory first choice opens actual HUD and pauses gameplay"):
		_finish()
		return
	await _snapshot("initial_draft.png")
	_resolve_checkpoint(0)
	for _frame: int in range(16):
		await process_frame
		await physics_frame
	var map: MapGenerator = _main.get_node("MapGenerator") as MapGenerator
	_check(map.active_chunks.size() == 49, "actual procedural terrain initialized 49 production chunks")
	_player.set_physics_process(false)
	_player.global_position = Vector3(0.0, 0.9, 0.0)
	_player.velocity = Vector3.ZERO
	for wave: int in range(1, 31):
		if not _check(_cycle.current_day == wave and not _cycle.is_night, "wave %d begins from production day state" % wave):
			_finish()
			return
		_cycle.start_night()
		if wave % 5 == 0:
			if not await _defeat_real_boss(wave):
				_finish()
				return
		else:
			_cycle._process(_cycle.time_left + 0.1)
		await process_frame
		if _player.progression.run_build.active_reward_id >= 0:
			_resolve_checkpoint(wave)
			await process_frame
		if wave == 5:
			_panel.open_specializations()
			await process_frame
			_panel._invest("cleave_damage")
			_check(int(_player.progression.run_build.specializations.get("cleave_damage", 0)) == 1, "actual specialization UI invests a kill-earned level point")
			await _snapshot("specializations.png")
			_player.progression.run_build.reset_specializations()
			_check(_player.progression.run_build.specializations.is_empty() and _player.progression.run_build.unspent_specialization_points == 1, "free respec restores the point through production build")
			_panel.close_panel()
		await physics_frame
	_check(_checkpoint_waves == [0, 2, 5, 10, 15, 20], "checkpoint schedule stops at six selected talents")
	_check(_boss_stages == [1, 2, 3, 4, 5, 6], "all six actual boss scenes completed in order")
	_check(_player.progression.player_level == 7, "six bosses grant exactly six levels with no ordinary kill XP")
	_check(_coordinator.finished and _coordinator.victory and not _cycle.running, "wave 30 finishes in production victory state")
	var overlay: Control = _main.get_node("HUD/Margin/GameOverOverlay") as Control
	_check(overlay.visible and overlay.title_label.text == "ОСАДА ПРЕОДОЛЕНА!", "actual terminal overlay displays victory")
	await _snapshot("victory.png")
	var expected_xp: int = _player.progression.get_extraction_xp()
	_check(_save.run_history.size() == 1 and _save.run_history[0].outcome == "victory", "one authoritative terminal history transaction")
	_check(_save.roster_slots[0].completed_runs == 1 and _save.roster_slots[0].victories == 1 and _save.meta_xp == expected_xp, "one final reward and one retained victorious hero")
	# A delayed duplicate terminal signal must not append history or award XP.
	root.get_node("EventBus").portal_evacuated.emit(30, expected_xp)
	_check(_save.run_history.size() == 1 and _save.meta_xp == expected_xp, "late extraction callback does not duplicate the victory")
	_check(_save.load_from_disk(), "final save reloads from the isolated profile")
	_check(roster.get_unlocked_talents(0) == retained_ids and _save.roster_slots[0].victories == 1, "reloaded winner retains all nine opened talents")
	_finish()

func _resolve_checkpoint(wave: int) -> void:
	var build: WarriorRunBuild = _player.progression.run_build
	var options: Array[WarriorTalentDefinition] = build.get_talent_options()
	_check(_panel.visible and paused and not options.is_empty(), "wave %d reward uses actual mandatory modal" % wave)
	if options.is_empty():
		_panel._focus(build.active_reward_id)
		return
	_checkpoint_waves.append(wave)
	_panel._choose(options[0].id, build.active_reward_id)
	_check(not paused and not _panel.visible, "wave %d choice resumes gameplay" % wave)

func _defeat_real_boss(wave: int) -> bool:
	for _frame: int in range(6):
		await process_frame
		await physics_frame
	var boss: SiegeBoss = _coordinator._boss
	if not _check(is_instance_valid(boss), "wave %d production director spawns a real boss" % wave):
		return false
	var stage: int = wave / 5
	_boss_stages.append(stage)
	_check(boss.stage == stage and boss.scene_file_path == WarriorRunCoordinator.BOSS_SCENES[stage - 1].resource_path, "wave %d uses correct authored boss scene" % wave)
	_check(boss.get_node_or_null("Visuals/Model/AnimationPlayer") != null, "wave %d has its authored model animation" % wave)
	_cycle._process(_cycle.time_left + 1000.0)
	_check(_cycle.is_night and _cycle.boss_pending and _cycle.current_day == wave, "wave %d night waits for actual boss death despite expired clock" % wave)
	boss.set_physics_process(false)
	boss.global_position = Vector3(0.0, MonsterLocomotion.calculate_spawn_y(0.0, boss), -2.0)
	_player.look_at(Vector3(0.0, _player.global_position.y, -2.0), Vector3.UP)
	if wave == 5:
		# Accelerated clocks do not naturally wait out the 3 s lighting tween.
		# Snap through production lighting API so the capture shows actual night.
		_cycle.apply_lighting_state()
		await _snapshot("boss_night.png")
	boss.current_health = 10.0
	for _frame: int in range(3):
		await physics_frame
	var level_before: int = _player.progression.player_level
	_player.combat.attack_cooldown_timer = 0.0
	_player.combat.perform_attack(_player, 0, false, false)
	for _frame: int in range(60):
		await process_frame
		if _player.progression.run_build.active_reward_id >= 0:
			_resolve_checkpoint(wave)
		if _coordinator._resolved_boss_waves.has(wave):
			break
		await physics_frame
	return _check(_coordinator._resolved_boss_waves.has(wave) and _player.progression.player_level == level_before + 1, "wave %d production sword hit kills boss and grants exactly one level" % wave)

func _snapshot(filename: String) -> void:
	if not _capture:
		return
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
	for _frame: int in range(6):
		await process_frame
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(CAPTURE_DIR + filename) == OK, "GPU capture " + filename)

func _finish() -> void:
	paused = false
	_watchdog.stop()
	_watchdog.queue_free()
	if _immediate_teardown and is_instance_valid(_main):
		_main.queue_free()
	# Production sword timers and destruction tweens may still be suspended
	# after the final modal. Let active casts finish while their owner exists.
	for _frame: int in range(24):
		await process_frame
		await physics_frame
	if not _immediate_teardown and is_instance_valid(_main):
		_main.queue_free()
	for _frame: int in range(4):
		await process_frame
		await physics_frame
	_check(get_nodes_in_group("player").is_empty() and get_nodes_in_group("enemies").is_empty(), "production main actors unregister during teardown")
	print("WARRIOR_RUN_SMOKE: %d/%d checks passed; accelerated transitions, controlled boss health, not balance playthrough" % [_checks - _failures, _checks])
	quit(0 if _failures == 0 else 1)

func _on_deadline() -> void:
	push_error("Warrior run smoke exceeded its finite deadline.")
	quit(2)

extends SceneTree

## Finite integration of menu entry, real gameplay Input, and profile restoration.
## Stationary targets isolate weapon checks; the navigation check uses live AI.
var _arena: GameplaySandbox
var _save: Node
var _capture: bool = false
var _checks: int = 0
var _failures: int = 0
var _before: Dictionary
var _storage: String
var _disk_hash: String
var _watchdog: Timer
const OUTPUT: String = "res://screenshots_debug/sandbox/capture/"
const ACTIONS: Array[String] = ["move_up", "aim_up", "attack_lmb", "special_rmb", "class_utility", "dash", "ultimate"]

func _initialize() -> void:
	_capture = OS.get_cmdline_user_args().has("--capture")
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	_run.call_deferred()

func _check(condition: bool, label: String) -> bool:
	_checks += 1
	if condition:
		print("[PASS] ", label)
	else:
		_failures += 1
		push_error("[FAIL] " + label)
	return condition

func _frames(count: int = 2) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame

func _action(name: String, frames: int = 2) -> void:
	Input.action_press(name)
	await _frames(frames)
	Input.action_release(name)
	await _frames()

func _snapshot(name: String) -> void:
	if not _capture:
		return
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	_check(picture.save_png(OUTPUT + name + ".png") == OK, "capture " + name)

func _run() -> void:
	_watchdog = Timer.new()
	_watchdog.process_mode = Node.PROCESS_MODE_ALWAYS
	_watchdog.one_shot = true
	_watchdog.wait_time = 120.0
	_watchdog.timeout.connect(func() -> void: push_error("Sandbox integration deadline"); _finish(124))
	root.add_child(_watchdog)
	_watchdog.start()
	_save = root.get_node("SaveManager")
	if not _check(_save.is_test_environment(), "profile isolated before autoload"):
		_finish()
		return
	_save.reset_to_defaults()
	_save.roster_slots[0].talent_xp = 1777
	_save.roster_slots[0].title = "Sandbox integration sentinel"
	_save.selected_slot_index = 0
	_check(_save.save_to_disk(), "sentinel profile written only in test storage")
	_before = _save.snapshot_state()
	_storage = _save.storage_dir
	_disk_hash = FileAccess.get_sha256(_save.save_file_path)
	var menu: Control = preload("res://scenes/main_menu.tscn").instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	await _frames()
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	await _snapshot("00_menu_entry")
	(menu.get_node("ViewMain/VBox/BtnSandbox") as Button).pressed.emit()
	await _frames(4)
	_arena = current_scene as GameplaySandbox
	if not _check(_arena != null, "menu button opens separate production sandbox scene"):
		_finish()
		return
	_check(GameplaySandboxSession.is_active(), "sandbox session active")
	_check(_save.storage_dir == GameplaySandboxSession.PROFILE_DIR, "sandbox redirects incidental save actions")
	_check(_arena.player.is_physics_processing() and _arena.player.input_enabled, "normal native player input and physics enabled")
	_check(_arena.camera is CameraFollow and _arena.camera.target == _arena.player, "production camera follows actual actor")
	_check(is_equal_approx(_arena.camera.fov, 45.0), "production fixed field of view")
	_check(not paused and not _arena.editor.panel.visible, "flat arena opens ready for play")
	_arena.camera.mouse_override = Vector2(640.0, 360.0)
	await _snapshot("01_flat_arena")
	await _check_warrior()
	await _check_archer_and_engineer()
	await _check_spawns_and_reset()
	_arena.return_to_menu()
	await _frames(4)
	_check(current_scene is Control, "return button opens main menu")
	_check(not GameplaySandboxSession.is_active() and not paused, "session and pause cleanly restored")
	_check(_save.storage_dir == _storage, "ordinary storage path restored")
	_check(_save.snapshot_state() == _before, "ordinary hero and progression restored exactly")
	_check(FileAccess.get_sha256(_save.save_file_path) == _disk_hash, "ordinary profile file stayed byte identical")
	_finish()

func _target(offset: Vector3) -> EnemyBase:
	var enemy: EnemyBase = preload("res://scenes/enemy_dummy.tscn").instantiate() as EnemyBase
	_arena.enemies.add_child(enemy)
	enemy.global_position = _arena.player.global_position + offset
	enemy.set_physics_process(false)
	enemy.max_health = 10000.0
	enemy.current_health = 10000.0
	return enemy

func _check_warrior() -> void:
	var player: PlayerPrototype = _arena.player
	var origin: Vector3 = player.global_position
	await _action("move_up", 18)
	var travel: Vector3 = player.global_position - origin
	_check(travel.length() > 0.2 and travel.normalized().dot(PlayerMovementMath.DEFAULT_SCREEN_FORWARD) > 0.9, "native WASD uses gameplay screen basis")
	_arena.toggle_editor(true)
	await _frames()
	_check(paused and _arena.editor.panel.visible, "editor pauses actual encounter")
	_arena.configure_talents(WarriorTalentCatalog.TALENT_IDS)
	_check(player.progression.run_build.selected_talents.size() == 9, "sandbox allows all nine selected talents")
	_check(player.progression.run_build.discovered_synergies.size() == 3, "selected pairs activate real hidden synergies")
	_check(_arena.set_specialization("attack_damage", 10000), "specialization rank has no sandbox cap")
	_check(is_equal_approx(player.talents.multiplier("attack_damage"), 801.0), "large rank changes actual runtime multiplier")
	_arena.set_specialization("attack_damage", 0)
	_arena.set_specialization("cleave_radius", 3)
	await _snapshot("02_editor_build")
	_arena.toggle_editor(false)
	await _frames(5)
	_check(not paused and not _arena.editor.panel.visible, "closing editor resumes native gameplay")
	Input.action_press("aim_up")
	await _frames(18)
	var front: EnemyBase = _target(Vector3(0.0, 0.0, -1.8))
	var rear: EnemyBase = _target(Vector3(0.0, 0.0, 2.5))
	await _frames(3)
	await _action("attack_lmb", 9)
	_check(front.current_health < 10000.0, "native LMB dispatches warrior sword damage")
	var rear_before: float = rear.current_health
	await _action("special_rmb", 21)
	_check(rear.current_health < rear_before, "native RMB with whirlwind hits rear sector during real lunge")
	await _snapshot("03_warrior_combat")
	await _action("class_utility", 2)
	_check(player.health.is_parrying, "native Q starts production parry window")
	var before_dash: Vector3 = player.global_position
	await _action("dash", 10)
	_check(player.global_position.distance_to(before_dash) > 1.0, "native Space executes real dash movement")
	Input.action_release("aim_up")
	_arena.clear_encounter()
	await _frames(5)
	player = _arena.player
	var duel: EnemyBase = _target(Vector3(0.0, 0.0, -4.0))
	await _frames(3)
	_arena.camera.mouse_override = _arena.camera.unproject_position(duel.global_position)
	await _action("ultimate", 18)
	_check(player.is_dueling and player.duel_target == duel, "native F acquires the real aimed duel target")
	await _snapshot("04_duel")

func _check_archer_and_engineer() -> void:
	_arena.select_character(1)
	await _frames(5)
	var player: PlayerPrototype = _arena.player
	_check(player.current_class == PlayerPrototype.CharacterClass.ARCHER and _arena.camera.target == player, "class selection replaces actor and retargets gameplay camera")
	Input.action_press("aim_up")
	await _frames(18)
	var target: EnemyBase = _target(Vector3(0.0, 0.0, -6.0))
	await _frames(3)
	await _action("attack_lmb", 34)
	_check(target.current_health < 10000.0, "native archer LMB arrow hits actual monster")
	var hp_before: float = target.current_health
	await _action("special_rmb", 40)
	_check(target.current_health < hp_before, "native archer RMB piercing arrow hits actual monster")
	await _action("class_utility", 18)
	_check(not get_nodes_in_group("decoy").is_empty(), "native archer Q creates production decoy")
	await _action("ultimate", 2)
	_check(player.is_eagle_eye, "native archer F enables Eagle Eye")
	await _snapshot("05_archer")
	Input.action_release("aim_up")
	_arena.select_character(2)
	await _frames(5)
	player = _arena.player
	_check(player.current_class == PlayerPrototype.CharacterClass.ENGINEER, "existing engineer selectable")
	Input.action_press("aim_up")
	await _frames(18)
	target = _target(Vector3(0.0, 0.0, -1.8))
	await _frames(3)
	await _action("attack_lmb", 12)
	_check(target.current_health < 10000.0, "native engineer LMB hammer hits actual monster")
	await _action("special_rmb", 16)
	var turret_found: bool = false
	for child: Node in _arena.encounter.get_children():
		if child.get_script() == preload("res://scripts/temp_turret.gd"):
			turret_found = true
	_check(turret_found, "native engineer RMB deploys production turret")
	await _action("class_utility", 2)
	_check(is_instance_valid(player.active_remote_mine), "native engineer Q arms production mine")
	await _action("ultimate", 2)
	_check(player.ultimate_cooldown_timer > 0.0, "native engineer F begins orbital attack")
	await _frames(80)
	await _snapshot("06_engineer")
	Input.action_release("aim_up")

func _check_spawns_and_reset() -> void:
	_arena.select_character(0)
	await _frames(5)
	var entries: Array[GameplaySandboxCatalog.SpawnEntry] = GameplaySandboxCatalog.entries()
	_check(entries.size() >= 19, "catalogue contains ordinary enemies, legacy boss, six bosses and nine elites")
	_arena.toggle_editor(true)
	await _frames()
	for entry: GameplaySandboxCatalog.SpawnEntry in entries:
		_check(_arena.spawn_monster(entry.id) == 1, "spawn " + entry.id)
		await _frames(2)
	_check(root.get_node("EntityRegistry").get_enemy_count() >= 19, "spawned catalogue actors are registered in actual encounter")
	await _snapshot("07_spawn_catalogue")
	_arena.clear_encounter()
	await _frames(3)
	_check(root.get_node("EntityRegistry").get_enemy_count() == 0, "reset removes all previous actors and effects")
	_arena.toggle_editor(false)
	await _frames(5)
	_check(_arena.spawn_monster("zombie") == 1, "live AI navigation case spawned")
	await _frames(3)
	var enemy: EnemyBase = _arena.enemies.get_child(0) as EnemyBase
	var before: float = enemy.global_position.distance_to(_arena.player.global_position)
	await _frames(45)
	_check(enemy.global_position.distance_to(_arena.player.global_position) < before - 0.1, "production monster walks towards player on flat authoritative navigation")
	_arena.player.take_damage(100000.0)
	await _frames(3)
	_check(paused and _arena.editor.panel.visible, "sandbox death keeps reset controls available")
	_check(_save.storage_dir == GameplaySandboxSession.PROFILE_DIR, "death remains confined to sandbox profile")
	_arena.clear_encounter()
	await _frames(3)
	_check(_arena.player.current_health > 0.0 and _arena.player.input_enabled, "reset respawns a playable actor")

func _finish(code: int = -1) -> void:
	for action: String in ACTIONS:
		Input.action_release(action)
	paused = false
	if is_instance_valid(_watchdog):
		_watchdog.stop()
	print("GAMEPLAY_SANDBOX_SMOKE: %d/%d checks passed" % [_checks - _failures, _checks])
	quit(code if code >= 0 else (0 if _failures == 0 else 2))

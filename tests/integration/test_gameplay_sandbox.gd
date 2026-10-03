extends GutTest

const SCENE: PackedScene = preload("res://scenes/tools/gameplay_sandbox.tscn")

class MenuFailureSandbox extends GameplaySandbox:
	func _change_scene_to_menu() -> Error:
		return ERR_CANT_OPEN

var sandbox: GameplaySandbox
var _save: Node
var _snapshot: Dictionary
var _storage: String
var _running: bool
var _return: bool

func before_each() -> void:
	_save = get_node("/root/SaveManager")
	_snapshot = _save.snapshot_state()
	_storage = _save.storage_dir
	_running = get_node("/root/RosterManager").run_active
	_return = get_node("/root/RosterManager").return_to_character_select
	sandbox = SCENE.instantiate() as GameplaySandbox
	add_child(sandbox)
	await wait_physics_frames(2)

func after_each() -> void:
	Input.action_release("attack_lmb")
	Input.action_release("move_up")
	get_tree().paused = false
	if is_instance_valid(sandbox):
		sandbox.queue_free()
		await wait_physics_frames(2)
	GameplaySandboxSession.leave(self)
	_save.restore_state(_snapshot)
	_save.set_storage_dir(_storage)
	get_node("/root/RosterManager").run_active = _running
	get_node("/root/RosterManager").return_to_character_select = _return
	get_node("/root/VFXManager").clear_effects()

func test_session_begin_twice_restores_original_memory_storage_flags_and_navigation() -> void:
	assert_eq(_save.storage_dir, GameplaySandboxSession.PROFILE_DIR)
	_save.meta_xp = 971
	get_node("/root/RosterManager").run_active = true
	assert_true(GameplaySandboxSession.begin(self), "Menu and scene can both begin the same session")
	sandbox.queue_free()
	await wait_physics_frames(2)
	assert_false(GameplaySandboxSession.is_active())
	assert_eq(_save.snapshot_state(), _snapshot)
	assert_eq(_save.storage_dir, _storage)
	assert_eq(get_node("/root/RosterManager").run_active, _running)
	assert_eq(get_node("/root/RosterManager").return_to_character_select, _return)
	GameplaySandboxSession.leave(self)
	assert_eq(_save.snapshot_state(), _snapshot, "Repeated leave cannot overwrite the restored profile")

func test_player_uses_native_input_physics_camera_and_each_existing_character_model() -> void:
	assert_true(sandbox.player is PlayerPrototype)
	assert_true(sandbox.player.input_enabled)
	assert_true(sandbox.player.is_physics_processing())
	assert_true(sandbox.camera is CameraFollow)
	assert_eq(sandbox.camera.target, sandbox.player)
	assert_false(sandbox.player.uses_meta_progression())
	for class_id: int in range(3):
		sandbox.select_character(class_id)
		await wait_physics_frames(2)
		assert_eq(int(sandbox.player.current_class), class_id)
		assert_eq(sandbox.player.hero_warrior.visible, class_id == 0)
		assert_eq(sandbox.player.hero_archer.visible, class_id == 1)
		assert_eq(sandbox.player.hero_engineer.visible, class_id == 2)
		assert_eq(sandbox.camera.target, sandbox.player)
		assert_not_null(sandbox.player.building_system)
		assert_not_null(sandbox.player.radial_menu)

func test_all_nine_talents_and_arbitrary_specialization_ranks_use_real_run_build() -> void:
	sandbox.configure_talents(WarriorTalentCatalog.TALENT_IDS)
	var build: WarriorRunBuild = sandbox.player.progression.run_build
	assert_eq(build.selected_talents.size(), 9, "Sandbox selection deliberately permits all nine")
	assert_eq(build.discovered_synergies.size(), 3)
	assert_true(sandbox.set_specialization("attack_damage", 100001))
	assert_eq(int(build.specializations.attack_damage), 100001)
	assert_almost_eq(sandbox.player.attack_damage, PlayerCombat.new().attack_damage * build.get_property_multiplier("attack_damage"), 0.1)
	assert_true(sandbox.set_specialization("vampirism", 14))
	assert_false(sandbox.set_specialization("not_a_property", 8))
	assert_false(sandbox.set_specialization("attack_damage", -1))
	sandbox.player.add_xp(90.0)
	var xp: float = sandbox.player.current_xp
	var level: int = sandbox.player.player_level
	assert_true(build.invest_specialization("attack_damage"), "Native HUD spends a kill-earned point in the same production build")
	var native_rank: int = int(build.specializations.attack_damage)
	var remaining_points: int = build.unspent_specialization_points
	sandbox.configure_talents(["hot_blood"])
	assert_eq(sandbox.player.current_xp, xp, "Editing talents does not discard native kill progression")
	assert_eq(sandbox.player.player_level, level)
	assert_eq(int(build.specializations.attack_damage), native_rank, "Talent edits preserve specialization changes made through native HUD")
	assert_eq(build.unspent_specialization_points, remaining_points, "Talent edits cannot refund a point already spent by native HUD")
	assert_false(sandbox.set_specialization("vampirism", 1), "An absent talent does not expose its extra property")

func test_spawn_catalogue_uses_every_production_scene_and_real_elite_controller() -> void:
	var entries: Array[GameplaySandboxCatalog.SpawnEntry] = GameplaySandboxCatalog.entries()
	assert_eq(entries.size(), 19, "Three archetypes, previous Gorgon, six bosses and nine canonical elites")
	for entry: GameplaySandboxCatalog.SpawnEntry in entries:
		sandbox.clear_monsters()
		await wait_physics_frames(1)
		assert_eq(sandbox.spawn_monster(entry.id), 1, entry.title)
		var monster: CharacterBody3D = sandbox.enemies.get_child(0) as CharacterBody3D
		assert_eq(monster.scene_file_path, entry.scene.resource_path)
		assert_true(monster.is_physics_processing())
		if not entry.elite_skill.is_empty():
			assert_true(monster is EnemyBase)
			assert_not_null((monster as EnemyBase).elite_skill_controller)
			assert_eq((monster as EnemyBase).elite_skill_controller.spec.id, entry.elite_skill)
		if entry.boss_stage > 0:
			assert_true(monster is SiegeBoss)
			assert_eq((monster as SiegeBoss).stage, entry.boss_stage)
	assert_eq(sandbox.spawn_monster("not_a_monster"), 0)
	assert_eq(sandbox.spawn_monster("zombie", 0), 0)
	sandbox.clear_monsters()
	assert_eq(sandbox.spawn_monster("boss_01_cairn"), 1)
	var boss_bar: Control = sandbox.hud.get_node("Margin/BossBarContainer") as Control
	assert_true(boss_bar.visible, "The actual boss spawn event opens the production health bar")
	sandbox.clear_monsters()
	assert_false(boss_bar.visible, "Removing bosses administratively closes their native health display")

func test_flat_navigation_matches_floor_and_normal_monster_approaches_player() -> void:
	var registry: Node = get_node("/root/EntityRegistry")
	assert_eq(registry.monster_flowfield.get_cell_height(31, 53), 0)
	assert_true(registry.monster_flowfield.chunk_loaded_lookup.call(99, 99))
	assert_false(registry.monster_flowfield.chunk_loaded_lookup.call(100, 100))
	assert_eq(sandbox.spawn_monster("zombie"), 1)
	var monster: EnemyBase = sandbox.enemies.get_child(0) as EnemyBase
	var initial: float = monster.global_position.distance_to(sandbox.player.global_position)
	await wait_seconds(0.7)
	assert_lt(monster.global_position.distance_to(sandbox.player.global_position), initial, "Real archetype AI moves toward the player over the actual flat floor")
	assert_between(monster.global_position.y, 0.8, 1.1, "Flat mapping prevents virtual biome height/fall")

func test_reset_removes_native_pending_casts_monsters_and_buildings_preserving_configuration() -> void:
	sandbox.configure_talents(["wide_lunge", "whirlwind_cleave"])
	sandbox.set_specialization("cleave_radius", 3)
	assert_eq(sandbox.spawn_monster("boss_01_cairn"), 1)
	var old_player: GameplaySandboxPlayer = sandbox.player
	var old_boss: SiegeBoss = sandbox.enemies.get_child(0) as SiegeBoss
	old_player.perform_special_attack()
	sandbox.building_system.place_building(Vector3(4, 0, 4), Vector2i(4, 4), BuildingSystem.PrefabType.WOOD_WALL)
	sandbox.clear_encounter()
	await wait_seconds(0.6)
	assert_false(is_instance_valid(old_player))
	assert_false(is_instance_valid(old_boss))
	assert_eq(sandbox.enemies.get_child_count(), 0)
	assert_eq(sandbox.building_system.placed_buildings.size(), 0)
	assert_eq(sandbox.player.progression.run_build.selected_talents, ["wide_lunge", "whirlwind_cleave"])
	assert_eq(int(sandbox.player.progression.run_build.specializations.cleave_radius), 3)
	assert_true(sandbox.player.input_enabled)

func test_death_and_respawn_have_no_permadeath_or_run_transaction() -> void:
	var isolated: Dictionary = _save.snapshot_state()
	sandbox.player.take_damage(10000.0)
	assert_eq(sandbox.player.current_health, 0.0)
	assert_true(get_tree().paused)
	assert_true(sandbox.editor.panel.visible)
	assert_eq(_save.snapshot_state(), isolated)
	sandbox.clear_encounter()
	assert_gt(sandbox.player.current_health, 0.0)
	assert_eq(_save.snapshot_state(), isolated)
	sandbox.toggle_editor(false)
	await wait_process_frames(4)
	assert_false(get_tree().paused)

func test_editor_resume_waits_for_gui_mouse_release_without_native_attack_leak() -> void:
	sandbox.toggle_editor(true)
	Input.action_press("attack_lmb")
	sandbox.toggle_editor(false)
	await wait_process_frames(4)
	assert_true(get_tree().paused, "A held GUI click cannot become a world attack")
	Input.action_release("attack_lmb")
	await wait_process_frames(4)
	await wait_physics_frames(2)
	assert_false(get_tree().paused)
	assert_eq(sandbox.player.attack_cooldown_timer, 0.0)

func test_failed_menu_load_keeps_editor_pause_session_and_profile() -> void:
	sandbox.queue_free()
	await wait_physics_frames(2)
	var instance: Node3D = SCENE.instantiate() as Node3D
	instance.set_script(MenuFailureSandbox)
	sandbox = instance as GameplaySandbox
	add_child(sandbox)
	await wait_physics_frames(2)
	sandbox.toggle_editor(true)
	var before_return: Dictionary = _save.snapshot_state()
	sandbox.return_to_menu()
	assert_true(get_tree().paused, "Failed scene loading must not resume combat behind the editor")
	assert_true(sandbox.editor.panel.visible)
	assert_true(GameplaySandboxSession.is_active())
	assert_eq(_save.storage_dir, GameplaySandboxSession.PROFILE_DIR)
	assert_eq(_save.snapshot_state(), before_return)
	assert_true(sandbox.editor.notice.text.contains("Не удалось вернуться в меню"))

func _press_key(keycode: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	Input.parse_input_event(event)
	var release: InputEventKey = InputEventKey.new()
	release.keycode = keycode
	Input.parse_input_event(release)

func test_native_p_then_editor_reset_or_class_change_transfers_pause_without_stale_modal() -> void:
	for class_id: int in [0, 1]:
		_press_key(KEY_P)
		await wait_process_frames(2)
		var native_panel: WarriorBuildPanel = sandbox.hud.build_panel
		assert_true(native_panel.visible, "Actual P input opens the ordinary specialization panel")
		assert_true(get_tree().paused)
		_press_key(KEY_F2)
		await wait_process_frames(2)
		assert_true(sandbox.editor.panel.visible)
		assert_false(native_panel.visible, "F2 closes the previous pause owner before acquiring pause")
		assert_false(native_panel.is_processing_input())
		_press_key(KEY_P)
		await wait_process_frames(2)
		assert_false(native_panel.visible, "P cannot open a hidden modal behind the arena editor")
		if class_id == 0:
			sandbox.clear_encounter()
		else:
			sandbox.select_character(class_id)
		await wait_process_frames(2)
		native_panel = sandbox.hud.build_panel
		assert_true(get_tree().paused, "Replacing the HUD cannot resume combat behind the editor")
		assert_false(native_panel.visible)
		assert_false(native_panel.is_processing_input())
		_press_key(KEY_F2)
		await wait_process_frames(6)
		assert_false(get_tree().paused, "Closing F2 restores the original playable state after HUD replacement")
		assert_false(sandbox.editor.panel.visible)
		assert_true(native_panel.is_processing_input())
		assert_true(sandbox.player.input_enabled)
		_press_key(KEY_P)
		await wait_process_frames(2)
		assert_true(native_panel.visible, "Ordinary HUD input remains available outside the editor")
		_press_key(KEY_P)
		await wait_process_frames(2)
		assert_false(get_tree().paused)
	_press_key(KEY_F2)
	await wait_process_frames(2)
	assert_true(get_tree().paused)
	_press_key(KEY_F2)
	_press_key(KEY_F2)
	assert_true(sandbox.editor.panel.visible, "An immediate reopen cancels the pending close")
	assert_true(get_tree().paused)
	_press_key(KEY_F2)
	await wait_process_frames(6)
	assert_false(get_tree().paused, "Rapid close/reopen preserves the original pause owner until the final safe resume")
	assert_true((sandbox.hud.build_panel as WarriorBuildPanel).is_processing_input())

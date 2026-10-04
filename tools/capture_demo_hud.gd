extends SceneTree

## Render actual HUD components with a reproducible, paused combat state.
## --path . -s tools/capture_demo_hud.gd -- --output=docs/verification/demo_hud
var _output: String = "res://docs/verification/demo_hud/"

func _initialize() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=").trim_suffix("/") + "/"
	call_deferred("_capture")

func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("HUD capture needs a rendering display.")
		quit(1)
		return
	create_timer(40.0).timeout.connect(func() -> void: quit(2))
	DirAccess.make_dir_recursive_absolute(_output)
	var main: Node3D = load("res://scenes/main.tscn").instantiate() as Node3D
	var map: MapGenerator = main.get_node("MapGenerator") as MapGenerator
	map.random_seed = false
	map.custom_seed = 1337
	map.load_radius_chunks = 1
	root.add_child(main)
	current_scene = main
	main.get_node("WaveDirector").set_process(false)
	main.get_node("DayNightCycle").set_process(false)
	var player: PlayerPrototype = main.get_node("Player") as PlayerPrototype
	player.set_physics_process(false)
	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	await process_frame
	if player.progression.run_build.active_reward_id >= 0:
		hud.build_panel._focus(player.progression.run_build.active_reward_id)
	var bar: HBoxContainer = hud.get_node("Margin/BottomCenter/SkillsActionBar") as HBoxContainer
	var status_bar: HUDStatusBar = hud.get_node("Margin/StatusEffects") as HUDStatusBar
	for enemy: Node in main.get_node("Enemies").get_children():
		enemy.queue_free()
	player.set_class(PlayerPrototype.CharacterClass.WARRIOR, false)
	player.talents.build().selected_talents.assign(["hot_blood", "counterattack", "wide_lunge", "whirlwind_cleave", "tempered_blade", "dismemberment"])
	player.talents.build().specializations = {"cleave_radius": 2, "cleave_cooldown": 2, "parry_window": 2, "hot_blood_healing": 2}
	player.talents.build().build_changed.emit()
	player.status_effects.refresh_regeneration(1, 3.0, 6.0, 5.0)
	player.resource_multiplier = 2
	player.health.trigger_parry(player.talents.parry_duration())
	player.take_damage(1.0)
	player.health.update_timers(0.435)
	player.talents._dismember(player.global_position)
	player.talents.statuses.apply_slow("demo-web", 0.4, 4.0)
	player.talents.advance(1.0)
	player.health.shield_health = 12.0
	status_bar.refresh()
	bar._refresh_action_set()
	await _hover_and_save(bar.get_node("SlotRMB") as Control, "warrior_ability.png")
	await _hover_and_save(bar.get_node("SlotSpace") as Control, "dash_ability.png")
	await _hover_and_save(status_bar.get_child(0) as Control, "regeneration_effect.png")
	await _hover_and_save(status_bar.get_node("HotBlood") as Control, "hot_blood_effect.png")
	await _hover_and_save(status_bar.get_node("Parry") as Control, "counter_effect.png")
	var cycle: DayNightCycle = main.get_node("DayNightCycle") as DayNightCycle
	cycle.boss_pending = true
	hud._update_day_night_label(0.0, true, 5)
	await _hover_and_save(hud.day_night_timer_label as Control, "boss_phase.png")
	cycle.boss_pending = false
	hud._update_day_night_label(cycle.time_left, false, 1)
	player.health.update_timers(1.0)
	player.set_class(PlayerPrototype.CharacterClass.ENGINEER, false)
	player.movement.perform_dash(Vector3.FORWARD)
	player.movement.update_timers(0.075)
	status_bar.refresh()
	bar._refresh_action_set()
	await _hover_and_save(bar.get_node("SlotF") as Control, "engineer_ability.png")
	main.queue_free()
	await process_frame
	print("DEMO_HUD_CAPTURE_PASS ", _output)
	quit(0)

func _hover_and_save(control: Control, filename: String) -> void:
	await process_frame
	await process_frame
	var event: InputEventMouseMotion = InputEventMouseMotion.new()
	event.position = control.get_global_rect().get_center()
	Input.parse_input_event(event)
	await create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	if picture.is_empty() or picture.save_png(_output.path_join(filename)) != OK:
		push_error("Cannot save HUD screenshot: " + filename)
		quit(1)

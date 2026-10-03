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
	var bar: HBoxContainer = hud.get_node("Margin/BottomCenter/SkillsActionBar") as HBoxContainer
	var status_bar: HUDStatusBar = hud.get_node("Margin/StatusEffects") as HUDStatusBar
	for enemy: Node in main.get_node("Enemies").get_children():
		enemy.queue_free()
	player.set_class(PlayerPrototype.CharacterClass.WARRIOR, false)
	player.status_effects.refresh_regeneration(1, 3.0, 6.0, 5.0)
	player.vampirism_heal = 4.0
	player.resource_multiplier = 2
	player.health.trigger_parry()
	player.health.update_timers(0.25)
	status_bar.refresh()
	bar._refresh_action_set()
	await _hover_and_save(bar.get_node("SlotRMB") as Control, "warrior_ability.png")
	await _hover_and_save(status_bar.get_child(0) as Control, "regeneration_effect.png")
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

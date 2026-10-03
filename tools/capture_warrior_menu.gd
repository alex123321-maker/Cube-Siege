extends SceneTree

## Finite renderer capture using an isolated profile, never the player's save.
func _initialize() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	call_deferred("_capture")

func _capture() -> void:
	create_timer(45.0).timeout.connect(func() -> void: quit(2))
	var save: Node = root.get_node("SaveManager")
	if not save.is_test_environment():
		push_error("Menu capture requires an isolated test profile before autoload.")
		quit(1)
		return
	save.reset_to_defaults()
	var menu: Control = preload("res://scenes/main_menu.tscn").instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	root.size = Vector2i(1280, 720)
	await process_frame
	# Exercise actual GUI routing for menu -> hero card -> radial tree.
	await _click(menu.get_node("ViewMain/VBox/BtnPlay") as Button)
	await _click(menu.get_node("ViewCharacters/HBox/Slot0/VBox/BtnStart") as Button)
	if not (menu.get_node("ViewTalents") as Control).visible:
		push_error("Warrior selection did not open its tree.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute("res://screenshots_debug/progression/menu")
	await _snapshot(Vector2i(1280, 720), "fresh_1280.png")
	save.roster_slots[0].talent_xp = 7200
	root.get_node("RosterManager").unlock_talent(0, "loud_triumph")
	menu.update_talents_ui()
	(menu.get_node("ViewTalents") as WarriorTalentTree)._select_talent("counterattack")
	await _snapshot(Vector2i(1920, 1080), "partial_1920.png")
	for definition: WarriorTalentDefinition in WarriorTalentCatalog.get_all():
		root.get_node("RosterManager").unlock_talent(0, definition.id)
	menu.update_talents_ui()
	await _snapshot(Vector2i(2560, 1080), "complete_wide.png")
	menu.queue_free()
	await process_frame
	quit(0)

func _snapshot(resolution: Vector2i, filename: String) -> void:
	root.size = resolution
	for _frame: int in range(8):
		await process_frame
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png("res://screenshots_debug/progression/menu/" + filename)
	if result != OK:
		push_error("Menu screenshot failed: " + filename)
	print("CAPTURE ", filename, " ", resolution)

func _click(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.pressed = pressed
		root.push_input(event)
		await process_frame

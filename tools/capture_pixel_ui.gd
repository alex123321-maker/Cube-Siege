extends SceneTree

## Capture the production UI, without touching the player's profile.
## Requires the full checkout SHA in CUBE_SIEGE_CAPTURE_REVISION, a rendering
## display, --test-profile and a finite outer timeout; see PIXEL_UI_INTEGRATION.md.
var _resolution: Vector2i = Vector2i(1280, 720)
var _output: String = "res://tmp/pixel_ui"
var _failures: Array[String] = []
var _measurements: Array[Dictionary] = []
var _screenshots: Array[String] = []

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--width="):
			_resolution.x = argument.trim_prefix("--width=").to_int()
		elif argument.begins_with("--height="):
			_resolution.y = argument.trim_prefix("--height=").to_int()
		elif argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=").replace("\\", "/").trim_suffix("/")
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.size = _resolution
	call_deferred("_capture")

func _capture() -> void:
	var revision: String = OS.get_environment("CUBE_SIEGE_CAPTURE_REVISION").strip_edges().to_lower()
	var revision_pattern: RegEx = RegEx.create_from_string("^[0-9a-f]{40}$")
	if revision_pattern.search(revision) == null:
		push_error("Set CUBE_SIEGE_CAPTURE_REVISION to the full 40-character Git SHA of the checkout before capturing.")
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		push_error("Pixel UI capture requires a rendering display.")
		quit(1)
		return
	create_timer(85.0, true, false, true).timeout.connect(func() -> void:
		push_error("Pixel UI capture exceeded its 85 second watchdog.")
		quit(2))
	var save: Node = root.get_node("SaveManager")
	if not save.is_test_environment():
		push_error("Pixel UI capture requires --test-profile before autoload.")
		quit(1)
		return
	save.reset_to_defaults()
	if _resolution.x < 1280 or _resolution.y < 720:
		push_error("Capture resolution must be at least 1280 x 720.")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(_output) != OK:
		push_error("Cannot create output directory: " + _output)
		quit(1)
		return
	var main: Node3D = preload("res://scenes/main.tscn").instantiate() as Node3D
	var map: MapGenerator = main.get_node("MapGenerator") as MapGenerator
	map.random_seed = false
	map.custom_seed = 1337
	map.load_radius_chunks = 1
	root.add_child(main)
	current_scene = main
	main.get_node("WaveDirector").set_process(false)
	main.get_node("DayNightCycle").set_process(false)
	var player: PlayerPrototype = main.get_node("Player") as PlayerPrototype
	player.set_process(false)
	player.set_physics_process(false)
	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	await _settle(4)
	if player.progression.run_build.active_reward_id >= 0:
		hud.build_panel._focus(player.progression.run_build.active_reward_id)
	for enemy: Node in main.get_node("Enemies").get_children():
		enemy.queue_free()
	await _settle(24)
	var building_system: BuildingSystem = main.get_node("BuildingSystem") as BuildingSystem
	building_system.add_resource(999999999, 999999999, 999999999, 999999999)
	var action_bar: HBoxContainer = hud.get_node("Margin/BottomCenter/SkillsActionBar") as HBoxContainer
	for class_id: int in [0, 1, 2]:
		player.set_class(class_id, false)
		action_bar._refresh_action_set()
		player.attack_cooldown_timer = 0.35
		player.special_cooldown_timer = 3.45
		player.parry_cooldown_timer = 6.7
		player.ultimate_cooldown_timer = 99.9
		player.movement.dash_cooldown_timer = 2.25
		hud._on_health_changed(player.max_health * 0.62, player.max_health)
		hud._on_xp_changed(7654.0, 9999.0, 99)
		await _settle(3)
		var filename: String = ["warrior_hud", "archer_hud", "engineer_hud"][class_id]
		_check_hud(hud, filename)
		await _snapshot(filename)
		for slot_name: String in ["SlotLMB", "SlotRMB", "SlotSpace", "SlotQ", "SlotF", "SlotTab"]:
			await _hover_snapshot(action_bar.get_node(slot_name) as Control, filename.trim_suffix("_hud") + "_tooltip_" + slot_name.trim_prefix("Slot").to_lower())
	hud._on_health_changed(player.max_health * 0.2, player.max_health)
	await _settle(3)
	_check_hud(hud, "health_critical")
	await _snapshot("health_critical")
	hud._on_health_changed(player.max_health, player.max_health)
	var boss: SiegeBoss = preload("res://scenes/bosses/boss_06_rift_harbinger.tscn").instantiate() as SiegeBoss
	boss.position = player.global_position + Vector3(16, 0, 16)
	boss.set_process(false)
	boss.set_physics_process(false)
	main.get_node("Enemies").add_child(boss)
	hud.show_boss_bar(boss)
	hud._on_boss_health_changed(boss.max_health * 0.73, boss.max_health)
	await _settle(3)
	_check_subtree(hud.get_node("Margin/BossBarContainer"), "boss_health")
	await _snapshot("boss_health")
	hud._on_boss_defeated()
	boss.queue_free()
	player.set_class(PlayerPrototype.CharacterClass.WARRIOR, false)
	player.talents.build().selected_talents.assign(["hot_blood", "counterattack", "wide_lunge", "whirlwind_cleave", "tempered_blade", "dismemberment"])
	player.talents.build().specializations = {"cleave_radius": 2, "cleave_cooldown": 2, "parry_window": 2, "hot_blood_healing": 2}
	player.talents.build().unspent_specialization_points = 1234
	player.talents.build().build_changed.emit()
	player.status_effects.refresh_regeneration(1, 3.0, 6.0, 5.0)
	player.resource_multiplier = 2
	player.health.trigger_parry(player.talents.parry_duration())
	player.take_damage(1.0)
	player.health.update_timers(0.435)
	player.talents._dismember(player.global_position)
	player.talents.statuses.apply_slow("pixel-ui-web", 0.4, 4.0)
	player.talents.statuses.apply_stun("pixel-ui-impact", 2.0)
	player.talents.advance(1.0)
	player.health.shield_health = 12.0
	hud.status_bar.refresh()
	action_bar._refresh_action_set()
	await _settle(3)
	_check_hud(hud, "statuses")
	await _snapshot("statuses")
	await _hover_snapshot(action_bar.get_node("SlotRMB") as Control, "ability_tooltip")
	for status_index: int in range(hud.status_bar.get_child_count()):
		await _hover_snapshot(hud.status_bar.get_child(status_index) as Control, "status_tooltip_%02d" % status_index)
	var cycle: DayNightCycle = main.get_node("DayNightCycle") as DayNightCycle
	cycle.boss_pending = true
	hud._update_day_night_label(0.0, true, 30)
	await _settle(3)
	_check_hud(hud, "boss_pending")
	await _snapshot("boss_pending")
	cycle.boss_pending = false
	hud._update_day_night_label(180.0, false, 1)
	await _capture_long_tooltip(hud)
	var settings: SettingsModal = hud.get_node("Margin/SettingsModal") as SettingsModal
	settings.open_modal()
	await _settle(3)
	_check_subtree(settings.get_node("Panel"), "settings")
	await _snapshot("settings")
	settings.close_modal()
	var radial: Control = hud.get_node("Margin/RadialMenu") as Control
	radial.toggle_menu()
	for category: String in ["Walls", "Towers", "Traps", "Utility"]:
		radial.open_category(category)
		await _settle(3)
		_check_subtree(radial, "build_" + category.to_lower())
		await _snapshot("build_" + category.to_lower())
	radial.close_menu()
	var workbench: Control = hud.get_node("Margin/WorkbenchModal") as Control
	workbench.open()
	# UI validation is independent of the dramatic gameplay slow-motion.
	Engine.time_scale = 1.0
	for tab: int in range(3):
		workbench.tabs.current_tab = tab
		await _settle(3)
		var name: String = ["crafting", "salvage", "mastery"][tab]
		_check_subtree(workbench.get_node("Panel"), "workbench_" + name)
		await _snapshot("workbench_" + name)
	workbench.close()
	hud.build_panel.open_specializations()
	await _settle(4)
	_check_subtree(hud.build_panel, "specializations")
	await _snapshot("specializations")
	hud.build_panel.close_panel()
	player.talents.build().selected_talents.clear()
	player.talents.build().unlocked_talents.assign(WarriorTalentCatalog.TALENT_IDS)
	seed(1337)
	player.talents.build().offer_checkpoint(2)
	await _settle(4)
	_check_subtree(hud.build_panel, "talent_checkpoint")
	await _snapshot("talent_checkpoint")
	if player.progression.run_build.active_reward_id >= 0:
		hud.build_panel._focus(player.progression.run_build.active_reward_id)
	paused = false
	await _capture_modal_windows(hud)
	main.queue_free()
	await _settle(2)
	var menu: Control = preload("res://scenes/main_menu.tscn").instantiate() as Control
	root.add_child(menu)
	current_scene = menu
	await _settle(3)
	_check_subtree(menu.get_node("ViewMain"), "main_menu")
	await _snapshot("main_menu")
	menu.show_view("settings")
	await _settle(3)
	_check_subtree(menu.get_node("ViewSettings"), "menu_settings")
	await _snapshot("menu_settings")
	menu.show_view("main")
	await _settle(2)
	await _click(menu.get_node("ViewMain/VBox/BtnPlay") as Button)
	if not (menu.get_node("ViewCharacters") as Control).visible:
		_failures.append("Menu click did not open character selection")
	_check_subtree(menu.get_node("ViewCharacters"), "character_select")
	await _snapshot("character_select")
	await _click(menu.get_node("ViewCharacters/HBox/Slot0/VBox/BtnStart") as Button)
	var tree: WarriorTalentTree = menu.get_node("ViewTalents") as WarriorTalentTree
	if not tree.visible:
		_failures.append("Warrior card click did not open the talent tree")
	tree._select_talent("counterattack")
	await _settle(3)
	_check_subtree(tree, "talent_tree_locked")
	await _snapshot("talent_tree_locked")
	save.roster_slots[0].talent_xp = 7200
	for definition: WarriorTalentDefinition in WarriorTalentCatalog.get_all():
		root.get_node("RosterManager").unlock_talent(0, definition.id)
	menu.update_talents_ui()
	await _settle(3)
	_check_subtree(tree, "talent_tree_opened")
	await _snapshot("talent_tree_opened")
	menu.queue_free()
	await _settle(2)
	var report: Dictionary = {"revision": revision, "resolution": [_resolution.x, _resolution.y], "logical_viewport": [_screen().size.x, _screen().size.y], "screenshots": _screenshots, "measurements": _measurements, "failures": _failures, "passed": _failures.is_empty()}
	var report_file: FileAccess = FileAccess.open(_output.path_join("geometry.json"), FileAccess.WRITE)
	if report_file == null:
		push_error("Cannot write geometry report.")
		quit(1)
		return
	report_file.store_string(JSON.stringify(report, "\t"))
	report_file.close()
	for failure: String in _failures:
		push_error(failure)
	print("PIXEL_UI_CAPTURE_", "PASS" if _failures.is_empty() else "FAIL", " ", _output, " screenshots=", _screenshots.size())
	quit(0 if _failures.is_empty() else 1)

func _screen() -> Rect2:
	return Rect2(Vector2.ZERO, root.get_visible_rect().size)

func _settle(frames: int = 3) -> void:
	for frame: int in range(frames):
		await process_frame

func _snapshot(name: String) -> void:
	_move_mouse(Vector2(2, _screen().size.y - 2))
	await _settle(2)
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	if picture.is_empty() or picture.save_png(_output.path_join(name + ".png")) != OK:
		_failures.append("Cannot save screenshot: " + name)
		return
	if picture.get_size() != _resolution:
		_failures.append("Screenshot %s has resolution %s, expected %s" % [name, picture.get_size(), _resolution])
	_screenshots.append(name + ".png")

func _hover_snapshot(control: Control, name: String) -> void:
	_move_mouse(control.get_global_rect().get_center())
	await create_timer(0.8, true, false, true).timeout
	var tooltips: Array[HUDTooltip] = []
	_collect_tooltips(root, tooltips)
	if tooltips.is_empty():
		_failures.append(name + ": hovering did not display the production tooltip")
	for tooltip: HUDTooltip in tooltips:
		_check_subtree(tooltip, name)
		if tooltip.size.x > 460.0:
			_failures.append(name + ": production tooltip exceeds 460 logical pixels")
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	if picture.is_empty() or picture.save_png(_output.path_join(name + ".png")) != OK:
		_failures.append("Cannot save tooltip screenshot: " + name)
		return
	if picture.get_size() != _resolution:
		_failures.append("Screenshot %s has resolution %s, expected %s" % [name, picture.get_size(), _resolution])
	_screenshots.append(name + ".png")

func _collect_tooltips(node: Node, results: Array[HUDTooltip]) -> void:
	if node is HUDTooltip and (node as HUDTooltip).is_visible_in_tree():
		results.append(node as HUDTooltip)
	for child: Node in node.get_children():
		_collect_tooltips(child, results)

func _move_mouse(position: Vector2) -> void:
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.position = position
	# Control rectangles are already in logical viewport coordinates.
	root.push_input(motion, true)

func _click(button: Button) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventMouseButton = InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = button.get_global_rect().get_center()
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func _capture_modal_windows(hud: CanvasLayer) -> void:
	# Exercise the HUD's actual windows without applying an upgrade or ending a run.
	var draft: Control = hud.get_node("Margin/CardDraftPopup") as Control
	seed(395668)
	draft.open_draft(null, 5)
	Engine.time_scale = 1.0
	await _settle(3)
	var draft_panel: Control = draft.get_node("CenterContainer/Panel") as Control
	_check_modal_panel(draft_panel, "card_draft")
	var cards: HBoxContainer = draft.cards_container as HBoxContainer
	var previous: Control = null
	for child: Node in cards.get_children():
		var card: Control = child as Control
		_check_panel_contents(card, card.get_global_rect(), "card_draft")
		if previous and previous.get_global_rect().intersects(card.get_global_rect()):
			_failures.append("card_draft: adjacent cards overlap")
		previous = card
	await _snapshot("card_draft")
	draft.hide()
	var result: Control = hud.get_node("Margin/GameOverOverlay") as Control
	result.show_game_over()
	await _settle(3)
	_check_modal_panel(result.get_node("Panel") as Control, "game_over")
	await _snapshot("game_over")
	result.hide()

func _check_modal_panel(panel: Control, scenario: String) -> void:
	if not panel.is_visible_in_tree():
		_failures.append(scenario + ": production modal did not open")
		return
	_check_subtree(panel, scenario)
	_check_panel_contents(panel, panel.get_global_rect(), scenario)
	if panel.get_global_rect().get_center().distance_to(_screen().get_center()) > 1.0:
		_failures.append(scenario + ": modal panel is not centered")

func _check_panel_contents(node: Node, bounds: Rect2, scenario: String) -> void:
	if node is Control:
		var control: Control = node as Control
		if not control.is_visible_in_tree():
			return
		var rectangle: Rect2 = control.get_global_rect()
		if rectangle.has_area() and not bounds.grow(1.0).encloses(rectangle):
			_failures.append("%s: %s extends beyond its panel" % [scenario, control.name])
	for child: Node in node.get_children():
		_check_panel_contents(child, bounds, scenario)

func _capture_long_tooltip(hud: CanvasLayer) -> void:
	# A production tooltip with deliberately long localized text exercises wrapping.
	var tooltip: HUDTooltip = HUDTooltip.new("Закалённый клинок и совершенное парирование: усиление боевого мастерства\nКаждый удар восстанавливает здоровье. Этот проверочный текст проверяет перенос длинного описания на несколько строк без выхода за декоративную рамку.\nПерезарядка: 123.45 с. Дальность: 999 м.")
	hud.get_node("Margin").add_child(tooltip)
	await _settle(3)
	tooltip.position = (_screen().size - tooltip.size) * 0.5
	await _settle(2)
	_check_subtree(tooltip, "long_tooltip")
	if tooltip.size.x > 460.0:
		_failures.append("long_tooltip: width exceeds 460 logical pixels: %s" % tooltip.size.x)
	await _snapshot("long_tooltip")
	tooltip.queue_free()
	await _settle(2)

func _check_hud(hud: CanvasLayer, scenario: String) -> void:
	var resources: Control = hud.get_node("Margin/Resources") as Control
	var top: Control = hud.get_node("Margin/TopCenter") as Control
	var bar: Control = hud.get_node("Margin/BottomCenter/SkillsActionBar") as Control
	_check_subtree(resources, scenario)
	_check_subtree(top, scenario)
	_check_subtree(bar, scenario)
	_check_subtree(hud.get_node("Margin/PlayerFloatingHP"), scenario)
	if resources.get_global_rect().intersects(top.get_global_rect()):
		_failures.append(scenario + ": resource panel overlaps the wave header")
	var status_bar: HUDStatusBar = hud.get_node("Margin/StatusEffects") as HUDStatusBar
	if status_bar.visible:
		_check_subtree(status_bar, scenario)
		if status_bar.get_global_rect().intersects(resources.get_global_rect()):
			_failures.append(scenario + ": status icons overlap the resource panel")
	if hud._build_button and hud._build_button.visible:
		_check_control(hud._build_button, scenario)
		if status_bar.visible and hud._build_button.get_global_rect().intersects(status_bar.get_global_rect()):
			_failures.append(scenario + ": specialization button overlaps status icons")
	var previous: Control = null
	var interval: float = -1.0
	for child: Node in bar.get_children():
		var slot: HUDActionSlot = child as HUDActionSlot
		if slot == null:
			continue
		if previous:
			if previous.get_global_rect().intersects(slot.get_global_rect()):
				_failures.append(scenario + ": action slots overlap")
			var current_interval: float = slot.position.x - previous.position.x
			if interval > 0.0 and not is_equal_approx(interval, current_interval):
				_failures.append(scenario + ": action slot spacing is uneven")
			interval = current_interval
		previous = slot

func _check_subtree(node: Node, scenario: String) -> void:
	if node is Control:
		var control: Control = node as Control
		if not control.is_visible_in_tree():
			return
		# Scroll contents intentionally extend behind their clipping viewport.
		if not _outside_scroll_viewport(control):
			_check_control(control, scenario)
	for child: Node in node.get_children():
		_check_subtree(child, scenario)

func _outside_scroll_viewport(control: Control) -> bool:
	var ancestor: Node = control.get_parent()
	while ancestor and ancestor != root:
		if ancestor is ScrollContainer:
			return not (ancestor as ScrollContainer).get_global_rect().encloses(control.get_global_rect())
		ancestor = ancestor.get_parent()
	return false

func _check_control(control: Control, scenario: String) -> void:
	var rectangle: Rect2 = control.get_global_rect()
	_measurements.append({"scenario": scenario, "node": str(control.get_path()), "rect": [rectangle.position.x, rectangle.position.y, rectangle.size.x, rectangle.size.y]})
	if rectangle.size.x < 0.01 or rectangle.size.y < 0.01:
		return
	if not _screen().grow(1.0).encloses(rectangle):
		_failures.append("%s: %s extends beyond viewport: %s" % [scenario, control.name, rectangle])
	if control is Label:
		var label: Label = control as Label
		if label.text.is_empty():
			return
		var font: Font = label.get_theme_font("font")
		var font_size: int = label.get_theme_font_size("font_size")
		var width: float = label.size.x if label.autowrap_mode != TextServer.AUTOWRAP_OFF else -1.0
		var text_size: Vector2 = font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size)
		text_size.y += float(maxi(0, label.get_line_count() - 1) * label.get_theme_constant("line_spacing"))
		if text_size.x > label.size.x + 1.0 and label.autowrap_mode == TextServer.AUTOWRAP_OFF:
			_failures.append("%s: text overflows %s horizontally: %.1f > %.1f (%s)" % [scenario, label.name, text_size.x, label.size.x, label.text])
		if text_size.y > label.size.y + 3.0:
			_failures.append("%s: text overflows %s vertically: %.1f > %.1f (%s)" % [scenario, label.name, text_size.y, label.size.y, label.text])
	elif control is Button:
		var button: Button = control as Button
		if button.text.is_empty():
			return
		var style: StyleBox = button.get_theme_stylebox("normal")
		var available: Vector2 = button.size - style.get_minimum_size()
		if button.icon and button.icon_alignment != HORIZONTAL_ALIGNMENT_CENTER:
			var icon_width: float = float(button.get_theme_constant("icon_max_width")) if button.expand_icon else button.icon.get_width()
			available.x -= icon_width + button.get_theme_constant("h_separation")
		var button_font: Font = button.get_theme_font("font")
		var button_font_size: int = button.get_theme_font_size("font_size")
		var button_width: float = available.x if button.autowrap_mode != TextServer.AUTOWRAP_OFF else -1.0
		var button_text: Vector2 = button_font.get_multiline_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, button_width, button_font_size)
		if button_text.x > available.x + 1.0 and button.autowrap_mode == TextServer.AUTOWRAP_OFF:
			_failures.append("%s: button text overflows %s horizontally: %.1f > %.1f (%s)" % [scenario, button.name, button_text.x, available.x, button.text])
		if button_text.y > available.y + 3.0:
			_failures.append("%s: button text overflows %s vertically: %.1f > %.1f (%s)" % [scenario, button.name, button_text.y, available.y, button.text])

extends GutTest

## Geometry regressions supplement the rendered capture; they do not certify art.
const HUD_SCENE: PackedScene = preload("res://scenes/hud.tscn")
const MENU_SCENE: PackedScene = preload("res://scenes/main_menu.tscn")
const VIEW_SIZES: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1706, 720), Vector2i(1280, 800)]

func test_long_localized_tooltip_wraps_inside_its_frame() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = VIEW_SIZES[0]
	add_child_autoqfree(viewport)
	var tooltip: HUDTooltip = HUDTooltip.new("Закалённый клинок и совершенное парирование: усиление боевого мастерства\nКаждый удар восстанавливает здоровье. Длинное описание остаётся внутри декоративной рамки при переносе строк.\nПерезарядка: 123.45 с. Дальность: 999 м.")
	viewport.add_child(tooltip)
	await _settle()
	assert_lte(tooltip.size.x, 460.0, "A long title must not make the tooltip span the screen")
	assert_gt(tooltip.size.x, 300.0, "Descriptions retain a useful reading width")
	for child: Node in tooltip.get_children():
		_assert_text_in_tree(child, tooltip.get_global_rect(), "tooltip")

func test_settings_and_workbench_tabs_keep_text_inside_their_panels() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = VIEW_SIZES[0]
	add_child_autoqfree(viewport)
	var hud: CanvasLayer = HUD_SCENE.instantiate() as CanvasLayer
	viewport.add_child(hud)
	hud.set_process(false)
	var settings: SettingsModal = hud.get_node("Margin/SettingsModal") as SettingsModal
	var workbench: Control = hud.get_node("Margin/WorkbenchModal") as Control
	var buildings: BuildingSystem = BuildingSystem.new()
	viewport.add_child(buildings)
	buildings.add_resource(999999999, 999999999, 999999999)
	workbench.building_system = buildings
	workbench.update_ui()
	for view_size: Vector2i in VIEW_SIZES:
		viewport.size = view_size
		settings.open_modal()
		await _settle()
		var screen: Rect2 = Rect2(Vector2.ZERO, Vector2(view_size))
		var settings_panel: Control = settings.get_node("Panel") as Control
		assert_true(screen.encloses(settings_panel.get_global_rect()), "Settings panel stays on screen at %s" % view_size)
		_assert_text_in_tree(settings_panel, settings_panel.get_global_rect(), "settings")
		settings.close_modal()
		workbench.show()
		for tab: int in range(3):
			workbench.tabs.current_tab = tab
			await _settle()
			var panel: Control = workbench.get_node("Panel") as Control
			assert_true(screen.encloses(panel.get_global_rect()), "Workbench stays on screen at %s" % view_size)
			_assert_text_in_tree(panel, panel.get_global_rect(), "workbench tab %d" % tab)
		workbench.hide()

func test_warrior_talent_detail_and_purchase_caption_fit_at_supported_ratios() -> void:
	var viewport: SubViewport = SubViewport.new()
	viewport.size = VIEW_SIZES[0]
	add_child_autoqfree(viewport)
	var menu: Control = MENU_SCENE.instantiate() as Control
	viewport.add_child(menu)
	menu.open_talents_for_slot(0)
	var tree: WarriorTalentTree = menu.get_node("ViewTalents") as WarriorTalentTree
	for view_size: Vector2i in VIEW_SIZES:
		viewport.size = view_size
		for talent_id: String in ["counterattack", "tempered_blade", "whirlwind_cleave"]:
			tree._select_talent(talent_id)
			await _settle()
			_assert_text_in_tree(tree, Rect2(Vector2.ZERO, Vector2(view_size)), "talent detail %s at %s" % [talent_id, view_size])

func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame

func _assert_text_in_tree(node: Node, bounds: Rect2, scenario: String) -> void:
	if node is Control and not (node as Control).is_visible_in_tree():
		return
	if node is Label or node is Button:
		var control: Control = node as Control
		assert_true(bounds.grow(1.0).encloses(control.get_global_rect()), "%s: %s remains inside its panel" % [scenario, control.name])
		var text: String = (node as Label).text if node is Label else (node as Button).text
		var wrap: TextServer.AutowrapMode = (node as Label).autowrap_mode if node is Label else (node as Button).autowrap_mode
		var available: Vector2 = control.size
		if node is Button:
			var button: Button = node as Button
			available -= button.get_theme_stylebox("normal").get_minimum_size()
			if button.icon and button.icon_alignment != HORIZONTAL_ALIGNMENT_CENTER:
				available.x -= button.get_theme_constant("icon_max_width") + button.get_theme_constant("h_separation")
		var width: float = available.x if wrap != TextServer.AUTOWRAP_OFF else -1.0
		var text_size: Vector2 = control.get_theme_font("font").get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width, control.get_theme_font_size("font_size"))
		if node is Label:
			text_size.y += float(maxi(0, (node as Label).get_line_count() - 1) * control.get_theme_constant("line_spacing"))
		if wrap == TextServer.AUTOWRAP_OFF:
			assert_lte(text_size.x, available.x + 1.0, "%s: %s text fits horizontally" % [scenario, control.name])
		assert_lte(text_size.y, available.y + 3.0, "%s: %s text fits vertically" % [scenario, control.name])
	for child: Node in node.get_children():
		_assert_text_in_tree(child, bounds, scenario)

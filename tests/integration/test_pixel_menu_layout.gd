extends GutTest

const RADIAL_SCENE: PackedScene = preload("res://scenes/radial_menu.tscn")
const WORKBENCH_SCENE: PackedScene = preload("res://scenes/workbench_modal.tscn")
const RADIAL_SCRIPT: GDScript = preload("res://scripts/radial_menu.gd")
const WORKBENCH_SCRIPT: GDScript = preload("res://scripts/workbench_modal.gd")
const SETTINGS_SCENE: PackedScene = preload("res://scenes/settings_modal.tscn")
const THEME_SCRIPT: GDScript = preload("res://scripts/ui/pixel_hud_theme.gd")

## Presentation fixture: selecting descriptions must not spend the player's XP.
class MenuRoster extends Node:
	var slots: Array[Dictionary] = [{"talent_xp": 999999999}]
	var opened: Array[String] = []

	func get_unlocked_talents(_slot_index: int) -> Array[String]:
		return opened.duplicate()

	func can_unlock_talent(_slot_index: int, _talent_id: String) -> bool:
		return false


func _viewport(size: Vector2i) -> SubViewport:
	var result: SubViewport = SubViewport.new()
	result.size = size
	add_child_autoqfree(result)
	return result


func _settle() -> void:
	for _frame: int in range(4):
		await get_tree().process_frame


func _assert_inside(parent: Control, child: Control, reason: String) -> void:
	assert_true(parent.get_global_rect().grow(0.1).encloses(child.get_global_rect()), "%s: parent=%s child=%s" % [reason, parent.get_global_rect(), child.get_global_rect()])


func test_talent_nodes_and_every_description_fit_the_menu_at_supported_aspects() -> void:
	var viewport: SubViewport = _viewport(Vector2i(1280, 590))
	var roster: MenuRoster = MenuRoster.new()
	add_child_autoqfree(roster)
	var menu: WarriorTalentTree = WarriorTalentTree.new()
	menu.theme = THEME_SCRIPT.create()
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(menu)
	menu.setup(roster, 0)
	for dimensions: Vector2i in [Vector2i(1280, 590), Vector2i(1706, 590), Vector2i(1280, 670)]:
		viewport.size = dimensions
		await _settle()
		var buttons: Array[Button] = []
		for definition: WarriorTalentDefinition in WarriorTalentCatalog.get_all():
			var button: Button = menu._graph._buttons[definition.id]
			_assert_inside(menu._graph, button, "Talent icon must fit its graph: " + definition.id)
			for previous: Button in buttons:
				assert_false(previous.get_global_rect().intersects(button.get_global_rect()), "Talent nodes must not overlap: %s / %s" % [previous.name, button.name])
			buttons.append(button)
			menu._select_talent(definition.id)
			await _settle()
			var information: PanelContainer = menu._purchase_button.get_parent().get_parent() as PanelContainer
			_assert_inside(menu, information, "Descriptions must not push the information panel below the menu")
			for label: Control in [menu._detail_title, menu._detail_text, menu._purchase_button]:
				_assert_inside(information, label, "Long descriptions and prerequisite captions must stay in the frame")
			assert_true(menu._detail_title.size.y >= menu._detail_title.get_combined_minimum_size().y - 0.1, "Wrapped titles need their full text height")
		menu._select_talent("counterattack")
		assert_true(menu._purchase_button.text.contains("ПРЕДЫДУЩИЙ"), "The test must exercise the long locked-prerequisite caption")
	assert_eq(roster.slots[0].talent_xp, 999999999, "Inspecting the presentation must not spend XP")
	var learned: Array[String] = ["sweeping_strike"]
	menu._graph.refresh(learned)
	var learned_badge: Label = menu._graph._state_badges["sweeping_strike"]
	assert_eq(learned_badge.text, "✓", "An opened talent needs a readable learned marker")
	assert_true(learned_badge.visible)
	var available_badge: Label = menu._graph._state_badges["counterattack"]
	assert_eq(available_badge.text, "", "An available unopened talent must not look learned")
	assert_false(available_badge.visible)
	var locked_badge: Label = menu._graph._state_badges["whirlwind_cleave"]
	assert_eq(locked_badge.text, "×", "A locked prerequisite needs a readable locked marker")
	assert_true(locked_badge.visible)
	await _settle()
	for talent_id: String in menu._graph._state_badges:
		_assert_inside(menu._graph._buttons[talent_id], menu._graph._state_badges[talent_id], "Status marker must stay inside its talent node")


func test_build_categories_and_all_prices_fit_without_overlapping_the_header() -> void:
	var viewport: SubViewport = _viewport(Vector2i(1280, 720))
	var menu: RADIAL_SCRIPT = RADIAL_SCENE.instantiate() as RADIAL_SCRIPT
	menu.theme = THEME_SCRIPT.create()
	viewport.add_child(menu)
	menu.toggle_menu()
	var categories: Array[String] = ["Walls", "Traps", "Towers", "Utility"]
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1706, 720), Vector2i(1280, 800)]:
		viewport.size = dimensions
		await _settle()
		var panel: Control = menu.get_node("CenterPanel")
		var title: Label = panel.get_node("Title")
		var hint: Label = panel.get_node("Hint")
		var previous: Array[Button] = []
		for path: String in ["BtnWalls", "BtnTraps", "BtnTowers", "BtnUtility"]:
			var button: Button = panel.get_node(path)
			_assert_inside(panel, button, "Category buttons must stay in the frame")
			assert_false(button.get_global_rect().intersects(title.get_global_rect()), "Category buttons must not cover the title")
			assert_false(button.get_global_rect().intersects(hint.get_global_rect()), "Category buttons must not cover the hint")
			for other: Button in previous:
				assert_false(button.get_global_rect().intersects(other.get_global_rect()), "Category buttons must remain evenly separated")
			previous.append(button)
		for category: String in categories:
			menu.open_category(category)
			await _settle()
			var submenu: Control = menu.get_node("SubMenuPanel")
			assert_false(panel.get_global_rect().intersects(submenu.get_global_rect()), "The build list needs a gap beside the category panel")
			assert_true(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(submenu.get_global_rect()), "The submenu must fit the viewport")
			for item: Button in submenu.get_node("VBox").get_children():
				if item.visible:
					_assert_inside(submenu, item, "Building art and two-line price must stay inside the submenu")
					assert_not_null(item.icon, "Every available building needs its generated icon")


func test_workbench_crafting_and_mastery_fit_with_large_resource_counts() -> void:
	var viewport: SubViewport = _viewport(Vector2i(1280, 720))
	var building: BuildingSystem = BuildingSystem.new()
	building.name = "BuildingSystem"
	viewport.add_child(building)
	building.add_resource(123456789, 987654321, 123456789, 0)
	var modal: WORKBENCH_SCRIPT = WORKBENCH_SCENE.instantiate() as WORKBENCH_SCRIPT
	modal.building_system_path = NodePath("../BuildingSystem")
	modal.theme = THEME_SCRIPT.create()
	viewport.add_child(modal)
	modal.show()
	modal.update_ui()
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1706, 720), Vector2i(1280, 800)]:
		viewport.size = dimensions
		for tab: int in [0, 2]:
			modal.tabs.current_tab = tab
			await _settle()
			var panel: Control = modal.get_node("Panel")
			assert_true(Rect2(Vector2.ZERO, Vector2(dimensions)).encloses(panel.get_global_rect()), "Workbench frame must fit the viewport")
			if tab == 0:
				for button: Button in [modal.btn_weapon, modal.btn_armor, modal.btn_boots]:
					_assert_inside(modal.tabs, button, "Crafting descriptions with large counters must stay in their tab")
			else:
				_assert_inside(modal.tabs, modal.mastery_label, "Mastery counter must wrap inside its tab")
				for button: Button in [modal.btn_blood, modal.btn_surv, modal.btn_agil, modal.btn_craft]:
					_assert_inside(modal.tabs, button, "The two-column mastery grid must not overflow its tab")


func test_settings_labels_and_sliders_stay_in_the_modal_frame() -> void:
	var viewport: SubViewport = _viewport(Vector2i(1280, 720))
	var modal: SettingsModal = SETTINGS_SCENE.instantiate() as SettingsModal
	modal.theme = THEME_SCRIPT.create()
	viewport.add_child(modal)
	modal.open_modal()
	for dimensions: Vector2i in [Vector2i(1280, 720), Vector2i(1706, 720), Vector2i(1280, 800)]:
		viewport.size = dimensions
		await _settle()
		var panel: Control = modal.get_node("Panel")
		_assert_inside(panel, modal.camera_option, "Camera choice must fit the settings frame")
		_assert_inside(panel, modal.btn_close, "Close caption must fit the settings frame")
		for slider: HSlider in modal._audio_sliders.values():
			_assert_inside(panel, slider, "Audio sliders must fit the settings frame")
			for child: Control in slider.get_parent().get_children():
				_assert_inside(panel, child, "Audio labels must stay aligned beside their sliders")

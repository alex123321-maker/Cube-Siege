extends Control
class_name RadialMenu

signal prefab_selected(type: int)

@onready var panel: Control = $CenterPanel
@onready var submenu: Control = $SubMenuPanel
@onready var category_label: Label = $SubMenuPanel/CategoryTitle

const DEFINITIONS = preload("res://scripts/resources/building_definition.gd")

var is_open: bool = false
var active_category: String = ""

func _ready() -> void:
	visible = false
	_configure_presentation()
	_configure_item($SubMenuPanel/VBox/BtnWoodWall, 1)
	_configure_item($SubMenuPanel/VBox/BtnFloorSpikes, 2)
	_configure_item($SubMenuPanel/VBox/BtnArcherTower, 3)
	_configure_item($SubMenuPanel/VBox/BtnIronWall, 4)
	_configure_item($SubMenuPanel/VBox/BtnBallista, 5)
	_configure_item($SubMenuPanel/VBox/BtnCampfire, 6)

func _configure_presentation() -> void:
	panel.offset_left = -170.0
	panel.offset_right = 170.0
	panel.offset_top = -150.0
	panel.offset_bottom = 150.0
	var backdrop: Panel = Panel.new()
	backdrop.name = "PixelFrame"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.add_theme_stylebox_override("panel", PixelUI.panel("ui_action_slot_normal", Vector4(16, 16, 16, 16)))
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(backdrop)
	panel.move_child(backdrop, 0)
	var buttons: Array[Button] = [$CenterPanel/BtnWalls, $CenterPanel/BtnTraps, $CenterPanel/BtnTowers, $CenterPanel/BtnUtility]
	var icons: Array[String] = ["building_wood_wall", "building_floor_spikes", "building_archer_tower", "building_campfire"]
	for index: int in range(buttons.size()):
		var button: Button = buttons[index]
		_set_rect(button, Rect2(Vector2(18 + (index % 2) * 160, 62 + floori(float(index) / 2.0) * 76), Vector2(144, 60)))
		button.icon = PixelUI.texture(icons[index])
		button.expand_icon = true
		button.add_theme_constant_override("icon_max_width", 24)
		button.add_theme_font_size_override("font_size", 13)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_set_rect($CenterPanel/Title, Rect2(16, 16, 308, 32))
	_set_rect($CenterPanel/Hint, Rect2(16, 214, 308, 64))
	var hint: Label = $CenterPanel/Hint
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	submenu.offset_left = 190.0
	submenu.offset_right = 550.0
	submenu.offset_top = -150.0
	submenu.offset_bottom = 150.0
	(submenu as Panel).add_theme_stylebox_override("panel", PixelUI.panel("ui_action_slot_normal", Vector4(16, 16, 16, 16)))
	category_label.offset_left = -160.0
	category_label.offset_right = 160.0
	category_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _set_rect(control: Control, rectangle: Rect2) -> void:
	control.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	control.position = rectangle.position
	control.size = rectangle.size

func _configure_item(button: Button, type_id: int) -> void:
	var definition: BuildingDefinition = DEFINITIONS.get_definition(type_id)
	var price: PackedStringArray = []
	if definition.wood_cost > 0:
		price.append("%d дерева" % definition.wood_cost)
	if definition.stone_cost > 0:
		price.append("%d камня" % definition.stone_cost)
	if definition.iron_cost > 0:
		price.append("%d железа" % definition.iron_cost)
	button.text = "%s\n%s" % [definition.display_name, " · ".join(price)]
	button.tooltip_text = "%s\n\n%s\n\nЛКМ — установить • ПКМ — отменить\nE — ремонт • Shift + E — демонтаж с возвратом 50%%" % [definition.display_name, definition.description]
	button.icon = load(definition.icon_path) as Texture2D
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width", 40)
	button.custom_minimum_size = Vector2(0, 68)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 13)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_menu"):
		toggle_menu()

func toggle_menu() -> void:
	is_open = !is_open
	visible = is_open
	if is_open:
		submenu.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func open_category(cat: String) -> void:
	active_category = cat
	submenu.visible = true
	var titles: Dictionary[String, String] = {"Walls": "УКРЕПЛЕНИЯ", "Traps": "ЛОВУШКИ", "Towers": "ОГНЕВАЯ ПОДДЕРЖКА", "Utility": "ПОМОЩЬ ГЕРОЮ"}
	category_label.text = titles.get(cat, cat.to_upper())

	# Hide all sub-items, show only matching
	$SubMenuPanel/VBox/BtnWoodWall.visible = (cat == "Walls")
	$SubMenuPanel/VBox/BtnIronWall.visible = (cat == "Walls")
	$SubMenuPanel/VBox/BtnFloorSpikes.visible = (cat == "Traps")
	$SubMenuPanel/VBox/BtnArcherTower.visible = (cat == "Towers")
	$SubMenuPanel/VBox/BtnBallista.visible = (cat == "Towers")
	$SubMenuPanel/VBox/BtnCampfire.visible = (cat == "Utility")

func _on_walls_pressed() -> void:
	open_category("Walls")

func _on_traps_pressed() -> void:
	open_category("Traps")

func _on_towers_pressed() -> void:
	open_category("Towers")

func _on_utility_pressed() -> void:
	open_category("Utility")

func _on_wood_wall_selected() -> void:
	emit_signal("prefab_selected", 1) # PrefabType.WOOD_WALL
	close_menu()

func _on_iron_wall_selected() -> void:
	emit_signal("prefab_selected", 4) # PrefabType.IRON_WALL
	close_menu()

func _on_floor_spikes_selected() -> void:
	emit_signal("prefab_selected", 2) # PrefabType.FLOOR_SPIKES
	close_menu()

func _on_archer_tower_selected() -> void:
	emit_signal("prefab_selected", 3) # PrefabType.ARCHER_TOWER
	close_menu()

func _on_ballista_selected() -> void:
	emit_signal("prefab_selected", 5) # PrefabType.BALLISTA
	close_menu()

func _on_campfire_selected() -> void:
	prefab_selected.emit(6)
	close_menu()

func close_menu() -> void:
	is_open = false
	visible = false

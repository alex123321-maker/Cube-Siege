extends Control

signal prefab_selected(type: int)

@onready var panel: Control = $CenterPanel
@onready var submenu: Control = $SubMenuPanel
@onready var category_label: Label = $SubMenuPanel/CategoryTitle

var is_open: bool = false
var active_category: String = ""

func _ready() -> void:
	visible = false

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
	category_label.text = cat.to_upper()

	# Hide all sub-items, show only matching
	$SubMenuPanel/VBox/BtnWoodWall.visible = (cat == "Walls")
	$SubMenuPanel/VBox/BtnIronWall.visible = (cat == "Walls")
	$SubMenuPanel/VBox/BtnFloorSpikes.visible = (cat == "Traps")
	$SubMenuPanel/VBox/BtnArcherTower.visible = (cat == "Towers")
	$SubMenuPanel/VBox/BtnBallista.visible = (cat == "Towers")

func _on_walls_pressed() -> void:
	open_category("Walls")

func _on_traps_pressed() -> void:
	open_category("Traps")

func _on_towers_pressed() -> void:
	open_category("Towers")

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

func close_menu() -> void:
	is_open = false
	visible = false

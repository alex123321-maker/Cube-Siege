extends Control

@onready var view_main: Control = $ViewMain
@onready var view_settings: Control = $ViewSettings
@onready var view_characters: Control = $ViewCharacters
@onready var view_talents: WarriorTalentTree = $ViewTalents
@onready var roster_mgr: Node = get_node_or_null("/root/RosterManager")
@onready var camera_option: OptionButton = get_node_or_null("ViewSettings/Panel/VBox/CameraDistanceRow/CameraOption")
@onready var slot_cards: Array[Control] = [$ViewCharacters/HBox/Slot0, $ViewCharacters/HBox/Slot1, $ViewCharacters/HBox/Slot2]
var inspecting_slot_index: int = 0

func _ready() -> void:
	_setup_settings_ui()
	view_talents.play_requested.connect(start_run_with_slot)
	view_talents.back_requested.connect(_on_btn_back_to_chars_pressed)
	if roster_mgr:
		roster_mgr.run_active = false
	if roster_mgr and roster_mgr.return_to_character_select:
		roster_mgr.return_to_character_select = false
		show_view("characters")
	else:
		show_view("main")
	update_character_cards()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		show_view("characters" if view_talents.visible else "main")
		get_viewport().set_input_as_handled()

func _setup_settings_ui() -> void:
	if not camera_option:
		return
	camera_option.clear()
	for title: String in ["Близко", "Средне", "Далеко"]:
		camera_option.add_item(title)
	var settings: Node = get_node_or_null("/root/GameSettings")
	if settings:
		camera_option.select(settings.get_camera_distance())
	camera_option.item_selected.connect(_on_camera_distance_selected)

func _on_camera_distance_selected(index: int) -> void:
	var settings: Node = get_node_or_null("/root/GameSettings")
	if settings:
		settings.set_camera_distance(index)

func show_view(view_name: String) -> void:
	view_main.visible = view_name == "main"
	view_settings.visible = view_name == "settings"
	view_characters.visible = view_name == "characters"
	view_talents.visible = view_name == "talents"
	if view_name == "characters":
		update_character_cards()
	elif view_name == "talents":
		view_talents.setup(roster_mgr, inspecting_slot_index)
	elif view_name == "settings":
		var settings: Node = get_node_or_null("/root/GameSettings")
		if settings and camera_option:
			camera_option.select(settings.get_camera_distance())

func _on_btn_play_pressed() -> void: show_view("characters")
func _on_btn_settings_pressed() -> void: show_view("settings")
func _on_btn_quit_pressed() -> void: get_tree().quit()
func _on_btn_back_to_main_pressed() -> void: show_view("main")

func update_character_cards() -> void:
	if not roster_mgr:
		return
	for index: int in range(3):
		var slot: Dictionary = roster_mgr.slots[index]
		var card: Control = slot_cards[index]
		(card.get_node("VBox/Title") as Label).text = str(slot.class_name).to_upper()
		(card.get_node("VBox/Desc") as Label).text = str(slot.title) if index == 0 else "Пока недоступен"
		(card.get_node("VBox/Stats/LevelLabel") as Label).text = "ЭВАКУАЦИИ: %d" % int(slot.get("completed_runs", 0))
		(card.get_node("VBox/Stats/DayLabel") as Label).text = "РЕКОРД: ВОЛНА %d" % int(slot.max_day)
		(card.get_node("VBox/Stats/XPLabel") as Label).text = "ОПЫТ: %d" % int(slot.get("talent_xp", 0))
		var start: Button = card.get_node("VBox/BtnStart") as Button
		var talents: Button = card.get_node("VBox/BtnTalents") as Button
		start.disabled = index != 0
		talents.disabled = index != 0
		start.text = "ВЫБРАТЬ ВОИНА" if index == 0 else "ПОЗЖЕ"
		talents.text = "ДЕРЕВО ТАЛАНТОВ" if index == 0 else "ПОЗЖЕ"

func start_run_with_slot(slot_idx: int) -> void:
	if slot_idx != 0 or not roster_mgr:
		return
	var previous: int = roster_mgr.selected_slot_index
	roster_mgr.selected_slot_index = slot_idx
	var save_mgr: Node = get_node_or_null("/root/SaveManager")
	if save_mgr and not save_mgr.save_to_disk():
		roster_mgr.selected_slot_index = previous
		return
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func open_talents_for_slot(slot_idx: int) -> void:
	if slot_idx != 0:
		return
	inspecting_slot_index = slot_idx
	show_view("talents")

func _on_btn_start_0_pressed() -> void: open_talents_for_slot(0)
func _on_btn_start_1_pressed() -> void: pass
func _on_btn_start_2_pressed() -> void: pass
func _on_btn_talents_0_pressed() -> void: open_talents_for_slot(0)
func _on_btn_talents_1_pressed() -> void: pass
func _on_btn_talents_2_pressed() -> void: pass
func update_talents_ui() -> void: view_talents.refresh()
func _on_btn_back_to_chars_pressed() -> void: show_view("characters")

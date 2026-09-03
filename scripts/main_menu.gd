extends Control

@onready var view_main: Control = $ViewMain
@onready var view_settings: Control = $ViewSettings
@onready var view_characters: Control = $ViewCharacters
@onready var view_talents: Control = $ViewTalents

@onready var roster_mgr: Node = get_node_or_null("/root/RosterManager")

var inspecting_slot_index: int = 0

# Slot UI references
@onready var slot_cards: Array[Control] = [
	$ViewCharacters/HBox/Slot0,
	$ViewCharacters/HBox/Slot1,
	$ViewCharacters/HBox/Slot2
]

# Talent Tree UI references
@onready var talent_char_title: Label = $ViewTalents/VBox/CharTitle
@onready var talent_points_label: Label = $ViewTalents/VBox/PointsLabel
@onready var btn_talent_blood: Button = $ViewTalents/VBox/Grid/BtnBlood
@onready var btn_talent_surv: Button = $ViewTalents/VBox/Grid/BtnSurv
@onready var btn_talent_agil: Button = $ViewTalents/VBox/Grid/BtnAgil
@onready var btn_talent_craft: Button = $ViewTalents/VBox/Grid/BtnCraft

func _ready() -> void:
	if roster_mgr and roster_mgr.return_to_character_select:
		roster_mgr.return_to_character_select = false
		show_view("characters")
	else:
		show_view("main")
	update_character_cards()

func show_view(view_name: String) -> void:
	view_main.visible = (view_name == "main")
	view_settings.visible = (view_name == "settings")
	view_characters.visible = (view_name == "characters")
	view_talents.visible = (view_name == "talents")
	if view_name == "characters":
		update_character_cards()
	elif view_name == "talents":
		update_talents_ui()

# --- Main View Buttons ---
func _on_btn_play_pressed() -> void:
	show_view("characters")

func _on_btn_settings_pressed() -> void:
	show_view("settings")

func _on_btn_quit_pressed() -> void:
	get_tree().quit()

func _on_btn_back_to_main_pressed() -> void:
	show_view("main")

# --- Character Slots ---
func update_character_cards() -> void:
	if not roster_mgr:
		return

	for i in range(3):
		var s: Dictionary = roster_mgr.slots[i]
		var card: Control = slot_cards[i]
		if not card:
			continue

		var title_lbl: Label = card.get_node("VBox/Title") as Label
		var desc_lbl: Label = card.get_node("VBox/Desc") as Label
		var level_lbl: Label = card.get_node("VBox/Stats/LevelLabel") as Label
		var day_lbl: Label = card.get_node("VBox/Stats/DayLabel") as Label
		var xp_lbl: Label = card.get_node("VBox/Stats/XPLabel") as Label

		var is_current: bool = (i == roster_mgr.selected_slot_index)
		if title_lbl:
			if is_current:
				title_lbl.text = "★ " + s.class_name.to_upper() + " [ТЕКУЩИЙ]"
			else:
				title_lbl.text = s.class_name.to_upper()
		if desc_lbl:
			desc_lbl.text = s.title
		if level_lbl:
			level_lbl.text = "УРОВЕНЬ: " + str(s.level)
		if day_lbl:
			day_lbl.text = "РЕКОРД: ДЕНЬ " + str(s.max_day)
		if xp_lbl:
			xp_lbl.text = "БОЕВОЙ ОПЫТ: " + str(s.battle_xp) + " XP"

func start_run_with_slot(slot_idx: int) -> void:
	if roster_mgr:
		roster_mgr.selected_slot_index = slot_idx
		roster_mgr.save_roster()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func open_talents_for_slot(slot_idx: int) -> void:
	inspecting_slot_index = slot_idx
	show_view("talents")

# Slot button signals
func _on_btn_start_0_pressed() -> void: start_run_with_slot(0)
func _on_btn_start_1_pressed() -> void: start_run_with_slot(1)
func _on_btn_start_2_pressed() -> void: start_run_with_slot(2)

func _on_btn_talents_0_pressed() -> void: open_talents_for_slot(0)
func _on_btn_talents_1_pressed() -> void: open_talents_for_slot(1)
func _on_btn_talents_2_pressed() -> void: open_talents_for_slot(2)

# --- Talent Tree UI ---
func update_talents_ui() -> void:
	if not roster_mgr:
		return
	var s: Dictionary = roster_mgr.slots[inspecting_slot_index]
	if talent_char_title:
		talent_char_title.text = "ДЕРЕВО ТАЛАНТОВ: " + s.class_name.to_upper() + " (" + s.title + ")"
	if talent_points_label:
		talent_points_label.text = "ДОСТУПНО ОЧКОВ: " + str(s.available_points)

	if btn_talent_blood:
		btn_talent_blood.text = "🩸 Кровожадность (" + str(s.bloodlust) + "/25)\n[+2% Урона за ранг]"
	if btn_talent_surv:
		btn_talent_surv.text = "🛡 Выживаемость (" + str(s.survival) + "/25)\n[+4 HP, +1% Защита]"
	if btn_talent_agil:
		btn_talent_agil.text = "⚡ Проворство (" + str(s.agility) + "/25)\n[+1.5% Скорость, -1.5% Откат]"
	if btn_talent_craft:
		btn_talent_craft.text = "🔨 Ремесло (" + str(s.crafting) + "/25)\n[+3% Ресурсы, +4% HP Зданий]"

func _on_invest_blood_pressed() -> void:
	if roster_mgr and roster_mgr.invest_talent(inspecting_slot_index, "bloodlust"):
		update_talents_ui()

func _on_invest_surv_pressed() -> void:
	if roster_mgr and roster_mgr.invest_talent(inspecting_slot_index, "survival"):
		update_talents_ui()

func _on_invest_agil_pressed() -> void:
	if roster_mgr and roster_mgr.invest_talent(inspecting_slot_index, "agility"):
		update_talents_ui()

func _on_invest_craft_pressed() -> void:
	if roster_mgr and roster_mgr.invest_talent(inspecting_slot_index, "crafting"):
		update_talents_ui()

func _on_reset_talents_pressed() -> void:
	if roster_mgr:
		roster_mgr.reset_talents(inspecting_slot_index)
		update_talents_ui()

func _on_btn_back_to_chars_pressed() -> void:
	show_view("characters")

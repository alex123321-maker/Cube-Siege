extends Control

signal retry_save_requested()
var _retry_save: bool = false

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var subtitle_label: Label = $Panel/VBox/SubtitleLabel
@onready var restart_btn: Button = $Panel/VBox/RestartBtn

func _ready() -> void:
	$Panel.add_theme_stylebox_override("panel", PixelUI.panel("ui_action_slot_normal", Vector4(16, 16, 16, 16)))
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.add_theme_font_size_override("font_size", 22)
	visible = false
	if restart_btn:
		restart_btn.pressed.connect(_on_restart_pressed)

func show_victory() -> void:
	show_result(false, 0)

func show_result(won: bool, earned_xp: int) -> void:
	_retry_save = false
	visible = true
	title_label.text = "ОСАДА ПРЕОДОЛЕНА!" if won else "ЭВАКУАЦИЯ УСПЕШНА!"
	title_label.modulate = Color(0.2, 1.0, 0.4)
	subtitle_label.text = "Герой сохранён. +%d опыта для открытия талантов.\nМожно вернуться в меню и продолжить этим Воином." % earned_xp
	restart_btn.text = "В МЕНЮ ГЕРОЯ"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func show_game_over() -> void:
	_retry_save = false
	visible = true
	title_label.text = "ГЕРОЙ ПОГИБ"
	title_label.modulate = Color(1.0, 0.2, 0.2)
	subtitle_label.text = "Открытия и развитие этого героя потеряны.\nСледующий Воин начнёт с трёх базовых талантов."
	restart_btn.text = "В МЕНЮ ГЕРОЯ"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func show_save_error(message: String) -> void:
	_retry_save = true
	visible = true
	title_label.text = "НЕ УДАЛОСЬ СОХРАНИТЬ РЕЗУЛЬТАТ"
	title_label.modulate = Color.CORAL
	subtitle_label.text = message + "\nРезультат сохранён в памяти; повтор не изменит награду."
	restart_btn.text = "ПОВТОРИТЬ СОХРАНЕНИЕ"
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_restart_pressed() -> void:
	if _retry_save:
		retry_save_requested.emit()
		return
	var roster = get_node_or_null("/root/RosterManager")
	if roster:
		roster.return_to_character_select = true
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

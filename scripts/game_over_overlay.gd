extends Control

@onready var title_label: Label = $Panel/VBox/TitleLabel
@onready var subtitle_label: Label = $Panel/VBox/SubtitleLabel
@onready var restart_btn: Button = $Panel/VBox/RestartBtn

func _ready() -> void:
	visible = false
	if restart_btn:
		restart_btn.pressed.connect(_on_restart_pressed)

func show_victory() -> void:
	visible = true
	title_label.text = "EXTRACTION SUCCESSFUL!"
	title_label.modulate = Color(0.2, 1.0, 0.4)
	subtitle_label.text = "Hero successfully saved to Meta-Roster!\nAwarded +500 Meta-XP."
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func show_game_over() -> void:
	visible = true
	title_label.text = "DEFEATED - PERMADEATH"
	title_label.modulate = Color(1.0, 0.2, 0.2)
	subtitle_label.text = "Your hero has fallen in the siege.\nCharacter data has been permanently erased."
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _on_restart_pressed() -> void:
	var roster = get_node_or_null("/root/RosterManager")
	if roster:
		roster.return_to_character_select = true
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

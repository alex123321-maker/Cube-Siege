class_name SettingsModal
extends Control

## In-game settings modal. Allows real-time adjustment of settings (such as camera distance)
## with smooth continuous in-game camera interpolation.

@onready var camera_option: OptionButton = get_node_or_null("Panel/VBox/CameraDistanceRow/CameraOption")
@onready var btn_close: Button = get_node_or_null("Panel/VBox/BtnClose")

func _ready() -> void:
	visible = false
	if btn_close:
		btn_close.pressed.connect(close_modal)

	if camera_option:
		camera_option.clear()
		camera_option.add_item("Близко", 0)
		camera_option.add_item("Средне", 1)
		camera_option.add_item("Далеко", 2)
		var gs = get_node_or_null("/root/GameSettings")
		if gs:
			camera_option.select(gs.get_camera_distance())
		camera_option.item_selected.connect(_on_camera_distance_selected)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if visible:
			close_modal()
			get_viewport().set_input_as_handled()
		else:
			# If another modal is open, let that modal handle cancellation
			var wb_modal = get_node_or_null("../WorkbenchModal")
			if wb_modal and wb_modal.visible:
				return
			var card_draft = get_node_or_null("../CardDraftPopup")
			if card_draft and card_draft.visible:
				return
			var radial = get_node_or_null("../RadialMenu")
			if radial and radial.visible:
				return
			var game_over = get_node_or_null("../GameOverOverlay")
			if game_over and game_over.visible:
				return

			open_modal()
			get_viewport().set_input_as_handled()

func open_modal() -> void:
	visible = true
	var gs = get_node_or_null("/root/GameSettings")
	if gs and camera_option:
		camera_option.select(gs.get_camera_distance())

func close_modal() -> void:
	visible = false

func toggle_modal() -> void:
	if visible:
		close_modal()
	else:
		open_modal()

func _on_camera_distance_selected(index: int) -> void:
	var gs = get_node_or_null("/root/GameSettings")
	if gs:
		gs.set_camera_distance(index)

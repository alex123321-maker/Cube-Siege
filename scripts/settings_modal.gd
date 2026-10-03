class_name SettingsModal
extends Control

## In-game settings modal. Allows real-time adjustment of settings (such as camera distance)
## with smooth continuous in-game camera interpolation.

@onready var camera_option: OptionButton = get_node_or_null("Panel/VBox/CameraDistanceRow/CameraOption")
@onready var btn_close: Button = get_node_or_null("Panel/VBox/BtnClose")

var _settings: Node
var _audio_sliders: Dictionary[StringName, HSlider] = {}

func _ready() -> void:
	_settings = get_node("/root/GameSettings")
	visible = false
	_build_audio_settings()
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
	for audio_bus: StringName in _audio_sliders:
		_audio_sliders[audio_bus].set_value_no_signal(_settings.get_audio_level(audio_bus) * 100.0)
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

func _build_audio_settings() -> void:
	var rows: VBoxContainer = get_node("Panel/VBox") as VBoxContainer
	var panel: Panel = get_node("Panel") as Panel
	panel.offset_top = -255.0
	panel.offset_bottom = 255.0
	var names: Dictionary[StringName, String] = {
		&"Master": "Общая громкость", &"Music": "Музыка", &"SFX": "Звуки боя", &"Ambience": "Атмосфера"
	}
	for audio_bus: StringName in _settings.AUDIO_BUSES:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		rows.add_child(row)
		rows.move_child(row, rows.get_child_count() - 2)
		var label: Label = Label.new()
		label.text = names[audio_bus]
		label.custom_minimum_size.x = 152.0
		row.add_child(label)
		var slider: HSlider = HSlider.new()
		slider.max_value = 100.0
		slider.step = 1.0
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.custom_minimum_size = Vector2(140, 32)
		slider.value = _settings.get_audio_level(audio_bus) * 100.0
		slider.tooltip_text = names[audio_bus]
		row.add_child(slider)
		slider.value_changed.connect(_on_audio_level_changed.bind(audio_bus))
		_audio_sliders[audio_bus] = slider

func _on_audio_level_changed(value: float, audio_bus: StringName) -> void:
	_settings.set_audio_level(audio_bus, value / 100.0)

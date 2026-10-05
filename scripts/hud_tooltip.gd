class_name HUDTooltip
extends PanelContainer

func _init(detail: String = "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size.x = 362.0
	add_theme_stylebox_override("panel", PixelUI.panel("ui_action_slot_normal", Vector4(16, 12, 16, 12)))
	var body: VBoxContainer = VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 8)
	add_child(body)
	var newline: int = detail.find("\n")
	var title: Label = Label.new()
	title.custom_minimum_size.x = 330.0
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.text = detail.substr(0, newline) if newline >= 0 else detail
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	title.add_theme_font_size_override("font_size", 17)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(title)
	if newline >= 0:
		var divider: TextureRect = TextureRect.new()
		divider.texture = PixelUI.texture("ui_tooltip_divider")
		divider.custom_minimum_size.y = 2.0
		divider.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		divider.stretch_mode = TextureRect.STRETCH_SCALE
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(divider)
		var label: Label = Label.new()
		label.custom_minimum_size.x = 330.0
		label.text = detail.substr(newline + 1)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_constant_override("line_spacing", 4)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(label)

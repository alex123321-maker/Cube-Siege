class_name HUDTooltip
extends PanelContainer

func _init(detail: String = "") -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.04, 0.065, 0.98)
	style.border_color = Color(0.35, 0.65, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(4)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 6
	add_theme_stylebox_override("panel", style)
	var body: VBoxContainer = VBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_theme_constant_override("separation", 8)
	add_child(body)
	var newline: int = detail.find("\n")
	var title: Label = Label.new()
	title.text = detail.substr(0, newline) if newline >= 0 else detail
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	title.add_theme_font_size_override("font_size", 17)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(title)
	if newline >= 0:
		var label: Label = Label.new()
		label.custom_minimum_size.x = 330.0
		label.text = detail.substr(newline + 1)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_constant_override("line_spacing", 4)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(label)

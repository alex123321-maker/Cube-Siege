class_name PixelHUDTheme
extends RefCounted

## Shared presentation theme; gameplay remains the source of every UI value.
static func create() -> Theme:
	var result: Theme = (load("res://resources/hud_theme.tres") as Theme).duplicate() as Theme
	result.set_stylebox("panel", "PanelContainer", PixelUI.panel("ui_action_slot_normal", Vector4(12, 10, 12, 10)))
	result.set_stylebox("panel", "HUDPanel", PixelUI.panel("ui_action_slot_normal", Vector4(10, 8, 10, 8)))
	for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
		var key: String = "ui_keycap_frame_pressed" if state == "pressed" else "ui_keycap_frame_normal"
		var button: StyleBoxTexture = PixelUI.panel(key, Vector4(9, 5, 9, 5))
		if state == "hover" or state == "focus":
			button.modulate_color = Color(1.15, 1.1, 0.9)
		elif state == "disabled":
			button.modulate_color = Color(0.55, 0.6, 0.65)
		result.set_stylebox(state, "Button", button)
		result.set_stylebox(state, "OptionButton", button)
		var small: StyleBoxTexture = PixelUI.panel(key, Vector4(5, 5, 5, 5))
		small.modulate_color = button.modulate_color
		result.set_stylebox(state, "HUDIconButton", small)
	result.set_color("font_hover_color", "Button", Color(1, 0.9, 0.62))
	result.set_color("font_pressed_color", "Button", Color(1, 0.85, 0.45))
	result.set_stylebox("panel", "TabContainer", PixelUI.panel("ui_action_slot_normal", Vector4(12, 10, 12, 10)))
	for state: String in ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled"]:
		var tab: StyleBoxTexture = PixelUI.panel("ui_keycap_frame_normal", Vector4(10, 6, 10, 6))
		if state == "tab_selected":
			tab.modulate_color = Color(1.12, 1.08, 0.88)
		elif state == "tab_unselected" or state == "tab_disabled":
			tab.modulate_color = Color(0.65, 0.72, 0.82)
		result.set_stylebox(state, "TabContainer", tab)
	result.set_color("font_selected_color", "TabContainer", Color(1, 0.9, 0.62))
	result.set_stylebox("background", "ProgressBar", PixelUI.panel("ui_xp_bar_bg", Vector4(2, 2, 2, 2)))
	result.set_stylebox("fill", "ProgressBar", PixelUI.panel("ui_xp_bar_fill", Vector4.ZERO))
	for bar: String in ["HealthProgressBar", "HealthyProgressBar", "BossProgressBar"]:
		result.set_stylebox("background", bar, PixelUI.panel("ui_health_bar_bg", Vector4(3, 3, 3, 3)))
		result.set_stylebox("fill", bar, PixelUI.panel("ui_health_bar_full" if bar == "HealthyProgressBar" else "ui_health_bar_danger", Vector4.ZERO))
	return result

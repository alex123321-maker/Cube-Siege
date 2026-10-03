class_name HUDStatusSlot
extends Control

const ICONS: Dictionary[StringName, Texture2D] = {
	&"regeneration": preload("res://assets/ui/status_effects/regeneration.svg"),
	&"invulnerability": preload("res://assets/ui/status_effects/invulnerability.svg"),
	&"vampirism": preload("res://assets/ui/status_effects/vampirism.svg"),
	&"harvest": preload("res://assets/ui/status_effects/harvest.svg"),
	&"parry": preload("res://assets/ui/hud_visual_kit/icons/warrior_parry.png"),
	&"duel": preload("res://assets/ui/hud_visual_kit/icons/warrior_duel.png"),
	&"eagle_eye": preload("res://assets/ui/hud_visual_kit/icons/archer_eagle_eye.png"),
	&"dash": preload("res://assets/ui/hud_visual_kit/icons/warrior_dash.png"),
}

var effect: PlayerStatusEffect
var _time: Label
var _frame: StyleBoxFlat
var _hovered: bool = false

func _init() -> void:
	custom_minimum_size = Vector2(52, 64)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_frame = StyleBoxFlat.new()
	_frame.bg_color = Color(0.025, 0.045, 0.065, 0.95)
	_frame.set_border_width_all(2)
	_frame.set_corner_radius_all(3)
	_time = Label.new()
	_time.position = Vector2(0, 48)
	_time.size = Vector2(52, 16)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time.add_theme_font_size_override("font_size", 11)
	_time.add_theme_color_override("font_color", Color(0.9, 0.98, 1.0))
	_time.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_time)
	mouse_entered.connect(func() -> void: _hovered = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hovered = false; queue_redraw())

func set_effect(snapshot: PlayerStatusEffect) -> void:
	effect = snapshot
	_time.text = effect.time_text()
	tooltip_text = "%s\n%s" % [effect.title, effect.description]
	if effect.duration > 0.0:
		tooltip_text += "\nДлительность: %s с." % snappedf(effect.duration, 0.01)
	queue_redraw()

func _make_custom_tooltip(for_text: String) -> Object:
	return HUDTooltip.new(for_text)

func _draw() -> void:
	if not effect:
		return
	_frame.border_color = effect.accent if _hovered else effect.accent.darkened(0.42)
	draw_style_box(_frame, Rect2(2, 0, 48, 48))
	var icon: Texture2D = ICONS.get(effect.icon_id) as Texture2D
	if icon:
		draw_texture_rect(icon, Rect2(6, 4, 40, 40), false)
	if effect.duration > 0.0:
		var elapsed: float = 1.0 - effect.remaining_ratio()
		if elapsed > 0.001:
			var center: Vector2 = Vector2(26, 24)
			var wedge: PackedVector2Array = [center]
			var segments: int = maxi(2, ceili(elapsed * 48.0))
			for index: int in range(segments + 1):
				var angle: float = -PI * 0.5 + TAU * elapsed * float(index) / float(segments)
				wedge.append(center + Vector2(cos(angle), sin(angle)) * 22.0)
			draw_colored_polygon(wedge, Color(0.005, 0.012, 0.02, 0.8))
		draw_arc(Vector2(26, 24), 22.0, -PI * 0.5 + TAU * (1.0 - effect.remaining_ratio()), PI * 1.5, 48, effect.accent, 2.0, true)

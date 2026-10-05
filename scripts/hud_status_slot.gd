class_name HUDStatusSlot
extends Control

static var ICONS: Dictionary[StringName, Texture2D] = {
	&"regeneration": PixelUI.texture("effect_regeneration"),
	&"invulnerability": PixelUI.texture("effect_invulnerability"),
	&"vampirism": PixelUI.texture("effect_lifesteal"),
	&"harvest": PixelUI.texture("resource_wood"),
	&"parry": PixelUI.texture("warrior_parry"),
	&"duel": PixelUI.texture("warrior_duel"),
	&"eagle_eye": PixelUI.texture("archer_sniper_eye"),
	&"dash": PixelUI.texture("warrior_combat_dash"),
	&"counter": PixelUI.texture("warrior_counterattack"),
	&"hot_blood": PixelUI.texture("warrior_hot_blood"),
	&"morale": PixelUI.texture("effect_morale"),
	&"triumph": PixelUI.texture("warrior_loud_triumph"),
	&"tempered_blade": PixelUI.texture("warrior_tempered_blade"),
	&"slow": PixelUI.texture("effect_slow"),
	&"stun": PixelUI.texture("effect_stun"),
	&"shield": PixelUI.texture("effect_barrier"),
}

var effect: PlayerStatusEffect
var _time: Label
var _frame: StyleBoxTexture
var _hovered: bool = false

func _init() -> void:
	custom_minimum_size = Vector2(52, 64)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_frame = PixelUI.panel("ui_action_slot_normal", Vector4.ZERO)
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
	_frame = PixelUI.panel("ui_action_slot_hover" if _hovered else "ui_action_slot_normal", Vector4.ZERO)
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

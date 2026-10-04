class_name PlayerStatusEffect
extends RefCounted

## Read-only presentation snapshot. Gameplay timers remain in their owning component.
var id: StringName
var title: String
var description: String
var icon_id: StringName
var remaining: float
var duration: float
var accent: Color
var duration_label: String

func _init(effect_id: StringName, caption: String, detail: String, icon_key: StringName, seconds_left: float = 0.0, total_seconds: float = 0.0, tint: Color = Color(0.3, 0.9, 0.65), condition: String = "∞") -> void:
	id = effect_id
	title = caption
	description = detail
	icon_id = icon_key
	remaining = maxf(seconds_left, 0.0)
	duration = maxf(total_seconds, 0.0)
	accent = tint
	duration_label = condition

func remaining_ratio() -> float:
	return clampf(remaining / duration, 0.0, 1.0) if duration > 0.0 else 1.0

func time_text() -> String:
	if duration <= 0.0:
		return duration_label
	return "%.1fс" % remaining if remaining < 10.0 else "%dс" % ceili(remaining)

extends RefCounted
class_name AbilityPlan

class Action extends RefCounted:
	var path: String
	var step: AbilityStep
	var start: float
	var source: String = "База"

var actions: Array[Action] = []
var errors: PackedStringArray = []
var duration: float = 0.0
var cooldown: float = 0.0
var draft: bool = true
var title: String

func valid() -> bool:
	return errors.is_empty() and not actions.is_empty()

func describe() -> String:
	if not errors.is_empty():
		return "ОШИБКИ\n" + "\n".join(errors)
	var lines: PackedStringArray = []
	for action: Action in actions:
		var detail: String = action.step.kind_label()
		if action.step.kind == AbilityStep.Kind.AREA:
			detail += " · %.1f урона · %.1f м · %.0f°" % [action.step.damage, action.step.radius, action.step.arc_degrees]
		elif action.step.kind == AbilityStep.Kind.MOVE:
			detail += " · %.1f м" % action.step.distance
		lines.append("%.2f–%.2f  %s\n  %s  [%s]" % [action.start, action.start + action.step.duration, action.path, detail, action.source])
	return "\n".join(lines)

extends RefCounted
class_name AbilityTrace

var sequence: int = 0
var cast_id: int = 0
var time: float = 0.0
var slot: String = ""
var target: String = ""
var reason: String = ""
var amount: float = 0.0

func describe() -> String:
	var recipient: String = " → " + target if not target.is_empty() else ""
	return "%05.2f  %s%s · %s" % [time, slot, recipient, reason]

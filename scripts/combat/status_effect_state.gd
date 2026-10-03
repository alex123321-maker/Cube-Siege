extends RefCounted
class_name StatusEffectState

class TimedEffect extends RefCounted:
	var source: String
	var strength: float
	var remaining: float
	func _init(p_source: String, p_strength: float, p_duration: float) -> void:
		source = p_source
		strength = p_strength
		remaining = p_duration

var slows: Array[TimedEffect] = []
var stuns: Array[TimedEffect] = []

func advance(delta: float) -> void:
	_advance_list(slows, delta)
	_advance_list(stuns, delta)

func _advance_list(effects: Array[TimedEffect], delta: float) -> void:
	for index: int in range(effects.size() - 1, -1, -1):
		effects[index].remaining -= maxf(0.0, delta)
		if effects[index].remaining <= 0.0:
			effects.remove_at(index)

func apply_slow(source: String, strength: float, duration: float) -> void:
	_apply(slows, source, clampf(strength, 0.0, 1.0), duration)

func apply_stun(source: String, duration: float) -> void:
	_apply(stuns, source, 1.0, duration)

func _apply(effects: Array[TimedEffect], source: String, strength: float, duration: float) -> void:
	if duration <= 0.0 or not is_finite(duration) or not is_finite(strength):
		return
	for effect: TimedEffect in effects:
		if effect.source == source:
			effect.strength = strength
			effect.remaining = duration
			return
	effects.append(TimedEffect.new(source, strength, duration))

func movement_multiplier(resistance: float = 0.0) -> float:
	var result: float = 1.0
	for effect: TimedEffect in slows:
		result *= 1.0 - effect.strength * (1.0 - clampf(resistance, 0.0, 1.0))
	return result

func is_stunned() -> bool:
	return not stuns.is_empty()

func clear() -> void:
	slows.clear()
	stuns.clear()

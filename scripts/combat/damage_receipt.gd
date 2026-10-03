extends RefCounted
class_name DamageReceipt

## Actual losses, rather than attempted damage, drive reflection and life steal.
var health_loss: float = 0.0
var shield_loss: float = 0.0
var remaining_health: float = 0.0
var remaining_shield: float = 0.0

static func resolve(incoming: float, health: float, shield: float, health_multiplier: float = 1.0) -> DamageReceipt:
	var result: DamageReceipt = DamageReceipt.new()
	result.remaining_health = maxf(0.0, health)
	result.remaining_shield = maxf(0.0, shield)
	if incoming <= 0.0 or not is_finite(incoming) or health <= 0.0:
		return result
	if shield > 0.0:
		# The breaking hit is fully absorbed; reductions never strengthen the shield.
		result.shield_loss = minf(incoming, shield)
		result.remaining_shield -= result.shield_loss
	else:
		result.health_loss = minf(maxf(0.0, incoming * health_multiplier), health)
		result.remaining_health -= result.health_loss
	return result

func reflection_base() -> float:
	return health_loss + shield_loss

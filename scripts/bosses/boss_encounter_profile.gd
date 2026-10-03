extends Resource
class_name BossEncounterProfile

@export var title: String = ""
@export var health: float = 1000.0
@export var speed: float = 2.0
@export var color: Color = Color.CORAL
@export var attacks: Array[BossAttackSpec] = []
@export var phase_thresholds: PackedFloat32Array = PackedFloat32Array()

func phase_for_health(current: float, maximum: float) -> int:
	var phase: int = 1
	for threshold: float in phase_thresholds:
		if current / maxf(maximum, 1.0) <= threshold:
			phase += 1
	return phase

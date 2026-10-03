extends Resource
class_name EliteSkillSpec

## Canonical skillcheck behavior; values remain first-version tuning.
enum Kind { TRIPLE_THROW, BACKSWING, UNDERGROUND_SPIKE, RETURNING_BLADE, LEAP_STRIKE, FIRE_BREATH, SPIT_PUDDLE, FOOT_MINE, SHORT_LUNGE }

@export var id: String = ""
@export var title: String = ""
@export var source_page: String = ""
@export var scene_path: String = ""
@export var kind: Kind = Kind.TRIPLE_THROW
@export var windup: float = 1.0
@export var damage: float = 18.0
@export var residue_damage_per_second: float = 10.0
@export var reach: float = 5.0
@export var width: float = 1.8
@export var radius: float = 1.4
@export var arc_degrees: float = 60.0
@export var flight_time: float = 0.8
@export var interval: float = 0.65
@export var speed: float = 13.0
@export var duration: float = 1.5
@export var lifetime: float = 3.0
@export var recovery: float = 0.8
@export var cooldown: float = 6.0
@export var trigger_range: float = 12.0
@export var color: Color = Color(1.0, 0.52, 0.16)

func footprint(shape: BossAttackSpec.Shape, range_value: float = -1.0) -> BossAttackSpec:
	var result: BossAttackSpec = BossAttackSpec.new()
	result.title = title
	result.shape = shape
	result.windup = windup
	result.reach = reach if range_value < 0.0 else range_value
	result.width = width
	result.arc_degrees = arc_degrees
	result.damage = damage
	return result

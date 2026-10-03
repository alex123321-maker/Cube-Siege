extends Resource
class_name BossAttackSpec

## One authoritative footprint and clock, consumed by damage and presentation.
enum Shape { CIRCLE, SECTOR, LINE, FAN, CROSS }

@export var title: String = ""
@export var shape: Shape = Shape.CIRCLE
@export var windup: float = 1.2
@export var active: float = 0.22
@export var recovery: float = 1.5
@export var damage: float = 20.0
@export var reach: float = 4.0
@export var width: float = 1.3
@export var arc_degrees: float = 100.0
@export var projectile_count: int = 3
@export var projectile_speed: float = 10.0
@export var target_centered: bool = false
@export var charge: bool = false
@export var teleport: bool = false
@export var slowing: float = 0.0
@export var terrain_mode: TerrainCombatRules.TerrainMode = TerrainCombatRules.TerrainMode.TERRAIN_DEPENDENT

func contains_point(origin: Vector3, direction: Vector3, point: Vector3) -> bool:
	var offset: Vector3 = point - origin
	offset.y = 0.0
	var distance: float = offset.length()
	match shape:
		Shape.CIRCLE:
			return distance <= reach
		Shape.SECTOR:
			return distance <= reach and (distance < 0.001 or direction.dot(offset / distance) >= cos(deg_to_rad(arc_degrees * 0.5)))
		Shape.LINE:
			var along: float = offset.dot(direction)
			return along >= 0.0 and along <= reach and absf(offset.dot(direction.cross(Vector3.UP))) <= width * 0.5
		Shape.CROSS:
			var side: Vector3 = direction.cross(Vector3.UP)
			return (absf(offset.dot(direction)) <= reach and absf(offset.dot(side)) <= width * 0.5) or (absf(offset.dot(side)) <= reach and absf(offset.dot(direction)) <= width * 0.5)
	return false

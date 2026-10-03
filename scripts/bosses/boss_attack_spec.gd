extends Resource
class_name BossAttackSpec

## One authoritative footprint and clock, consumed by damage and presentation.
enum Shape { CIRCLE, SECTOR, LINE, FAN, CROSS }
enum Kind { BURST, LOBBED, LINE_BEAM, RADIAL_BEAM, CHAIN, CHASE, SWEEP }
enum RadialVariant { LEFT_TO_RIGHT, RIGHT_TO_LEFT, CENTRE_TO_EDGES, EDGES_TO_CENTRE }

@export var title: String = ""
@export var kind: Kind = Kind.BURST
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
@export var radial_variant: RadialVariant = RadialVariant.LEFT_TO_RIGHT
@export var angular_speed_degrees: float = 70.0
@export var ray_half_angle_degrees: float = 5.0
@export var mark_count: int = 7
@export var mark_gap: float = 0.35
@export var spread_radius: float = 6.0
@export var trap_lifetime: float = 8.0
@export var flight_height: float = 5.0

## Canonical previews and active rays use these same functions, never a second clock.
func synchronise_duration() -> void:
	match kind:
		Kind.LINE_BEAM:
			active = windup
		Kind.RADIAL_BEAM:
			var dual: bool = radial_variant >= RadialVariant.CENTRE_TO_EDGES
			var route: float = arc_degrees * (0.5 if dual else 1.0)
			windup = route / maxf(radial_speed(), 0.01)
			active = windup
		Kind.CHAIN, Kind.CHASE:
			active = float((6 if kind == Kind.CHASE else mark_count) - 1) * mark_gap + 0.30

func radial_speed() -> float:
	return angular_speed_degrees * (0.5 if radial_variant >= RadialVariant.CENTRE_TO_EDGES else 1.0)

func radial_angles(progress: float) -> PackedFloat32Array:
	var half_arc: float = arc_degrees * 0.5
	var p: float = clampf(progress, 0.0, 1.0)
	match radial_variant:
		RadialVariant.LEFT_TO_RIGHT:
			return PackedFloat32Array([lerpf(-half_arc, half_arc, p)])
		RadialVariant.RIGHT_TO_LEFT:
			return PackedFloat32Array([lerpf(half_arc, -half_arc, p)])
		RadialVariant.CENTRE_TO_EDGES:
			return PackedFloat32Array([-half_arc * p, half_arc * p])
	return PackedFloat32Array([-half_arc * (1.0 - p), half_arc * (1.0 - p)])

func contains_ray(origin: Vector3, facing: Vector3, point: Vector3, angle: float) -> bool:
	var offset: Vector3 = point - origin
	offset.y = 0.0
	return offset.length() <= reach and (offset.length() < 0.001 or facing.rotated(Vector3.UP, deg_to_rad(angle)).dot(offset.normalized()) >= cos(deg_to_rad(ray_half_angle_degrees)))

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

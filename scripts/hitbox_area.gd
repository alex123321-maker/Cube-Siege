extends Area3D
class_name HitboxArea

## Presentation can react to a real hit, including late overlap entries.
signal hit_confirmed(target: Node, direction: Vector3)

@export var damage: float = 25.0
@export var knockback_force: float = 6.0
@export var damage_type: String = "physical"
@export var can_hit_multiple: bool = true
@export var terrain_mode: TerrainCombatRules.TerrainMode = TerrainCombatRules.TerrainMode.TERRAIN_DEPENDENT

var hit_entities: Array[Node] = []
var owner_entity: Node = null
var hits_landed: int = 0
var _hit_target_ids: Dictionary = {}
## Optional frontal sector inside the broad-phase shape. Zero radius disables it.
var frontal_radius: float = 0.0
var frontal_arc_degrees: float = 180.0

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func set_owner_entity(p_owner: Node) -> void:
	owner_entity = p_owner

func reset_hits() -> void:
	hits_landed = 0
	_hit_target_ids.clear()
	hit_entities.clear()

func _on_area_entered(area: Area3D) -> void:
	if not can_hit_multiple and hits_landed >= 1:
		return

	if not area.has_method("take_damage"):
		return

	var target: Node = area.get_target_node() if area.has_method("get_target_node") else area.get_parent()
	if not is_instance_valid(target) or target == owner_entity:
		return

	# Rejection: already dying targets cannot receive damage and must not consume hit quota or emit hit_confirmed
	if "is_dying" in target and target.is_dying:
		return

	var target_id: int = target.get_instance_id()
	if _hit_target_ids.has(target_id) or hit_entities.has(target):
		return

	# Player attacks must NEVER damage friendly buildings!
	if owner_entity and (owner_entity.is_in_group("player") or owner_entity.name == "Player"):
		if target.is_in_group("buildings") or target.is_in_group("walls"):
			return
		if frontal_radius > 0.0 and target is Node3D:
			var local: Vector3 = to_local((target as Node3D).global_position)
			var planar: Vector2 = Vector2(local.x, local.z)
			if planar.length() > frontal_radius:
				return
			if not planar.is_zero_approx() and -local.z / planar.length() < cos(deg_to_rad(frontal_arc_degrees * 0.5)) - 0.0001:
				return

	# Height connectivity check for terrain-dependent melee attacks
	if terrain_mode == TerrainCombatRules.TerrainMode.TERRAIN_DEPENDENT:
		var source_pos: Vector3 = owner_entity.global_position if (owner_entity and owner_entity is Node3D) else global_position
		var target_pos: Vector3 = target.global_position if (target is Node3D) else area.global_position
		var height_lookup: Callable = Callable()
		var map_gen: Node = get_tree().get_first_node_in_group("map_generator") if is_inside_tree() else null
		if map_gen and map_gen.has_method("get_voxel_height"):
			height_lookup = Callable(map_gen, "get_voxel_height")
		if not TerrainCombatRules.is_melee_connected(source_pos, target_pos, height_lookup):
			return

	if not can_hit_multiple and hits_landed >= 1:
		return

	var hit_direction: Vector3 = (target.global_position - global_position).normalized() if (target is Node3D) else Vector3.FORWARD
	hit_direction.y = 0.0
	var attacker = owner_entity if is_instance_valid(owner_entity) else null

	var hit_result = area.take_damage(damage, knockback_force * hit_direction, damage_type, attacker)
	if hit_result == false:
		return

	hits_landed += 1
	_hit_target_ids[target_id] = true
	hit_entities.append(target)
	hit_confirmed.emit(target, hit_direction)

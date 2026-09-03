extends Area3D
class_name HitboxArea

@export var damage: float = 25.0
@export var knockback_force: float = 6.0
@export var damage_type: String = "physical"
@export var can_hit_multiple: bool = true

var hit_entities: Array[Node] = []
var owner_entity: Node = null

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func set_owner_entity(p_owner: Node) -> void:
	owner_entity = p_owner

func _on_area_entered(area: Area3D) -> void:
	if area.has_method("take_damage"):
		var target: Node = area.get_target_node() if area.has_method("get_target_node") else area.get_parent()
		if target == owner_entity or hit_entities.has(target):
			return

		# Player attacks must NEVER damage friendly buildings!
		if owner_entity and (owner_entity.is_in_group("player") or owner_entity.name == "Player"):
			if target and (target.is_in_group("buildings") or target.is_in_group("walls")):
				return

		hit_entities.append(target)
		var hit_direction: Vector3 = (target.global_position - global_position).normalized()
		hit_direction.y = 0.0
		area.take_damage(damage, knockback_force * hit_direction, damage_type, owner_entity)

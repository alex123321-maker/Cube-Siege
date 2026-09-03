extends Node3D

@export var speed: float = 24.0
@export var damage: float = 30.0
@export var pierce_count: int = 1

var direction: Vector3 = Vector3.FORWARD
var lifetime: float = 2.5
var shooter_entity: Node = null
var hit_targets: Array[Node] = []

@onready var hitbox: Area3D = $Hitbox

func setup(p_direction: Vector3, p_damage: float, p_owner: Node, p_pierce: int = 1) -> void:
	direction = p_direction.normalized()
	damage = p_damage
	shooter_entity = p_owner
	pierce_count = p_pierce
	if direction.length_squared() > 0.01:
		look_at(global_position + direction, Vector3.UP)
	if has_node("Hitbox"):
		$Hitbox.damage = damage
		$Hitbox.set_owner_entity(p_owner)

func _physics_process(delta: float) -> void:
	global_position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _on_hitbox_area_entered(area: Area3D) -> void:
	if not area.has_method("take_damage"):
		return

	var target: Node = area.get_target_node() if area.has_method("get_target_node") else area.get_parent()
	if not target or target == shooter_entity or hit_targets.has(target):
		return

	# Never hit friendly buildings or walls!
	if target.is_in_group("buildings") or target.is_in_group("walls"):
		return

	hit_targets.append(target)

	# Direct damage dealing
	var hit_direction: Vector3 = direction
	hit_direction.y = 0.0
	area.take_damage(damage, hit_direction * 4.0, "projectile", shooter_entity)

	pierce_count -= 1
	if pierce_count <= 0:
		call_deferred("queue_free")

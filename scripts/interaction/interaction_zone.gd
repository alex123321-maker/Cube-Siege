class_name InteractionZone
extends Area3D

## Dedicated collision area for player interaction detection (Issue #42).
## Operates strictly on the interaction collision layer (Layer 6, bit 5: value 32),
## completely decoupled from combat hurtboxes, solid bodies, and visual occlusion.

const INTERACTION_LAYER: int = 32 # 3D physics layer 6

@export var target_node: Node = null

func _init(p_target: Node = null) -> void:
	collision_layer = INTERACTION_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	if p_target:
		target_node = p_target

func _ready() -> void:
	collision_layer = INTERACTION_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	if not target_node:
		target_node = get_parent()

func get_interaction_target() -> Node:
	return target_node

static func create_zone(p_target: Node, p_shape: Shape3D = null, p_offset: Vector3 = Vector3.ZERO) -> InteractionZone:
	var zone = InteractionZone.new(p_target)
	zone.name = "InteractionZone"
	var col = CollisionShape3D.new()
	if p_shape:
		col.shape = p_shape
	else:
		var sphere = SphereShape3D.new()
		sphere.radius = 1.2
		col.shape = sphere
	col.position = p_offset
	zone.add_child(col)
	return zone

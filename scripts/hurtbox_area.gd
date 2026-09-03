extends Area3D
class_name HurtboxArea

signal damaged(amount: float, knockback: Vector3, damage_type: String, attacker: Node)

@export var target_node_path: NodePath
@export var mesh_to_flash_path: NodePath

var target_node: Node = null
var mesh_to_flash: MeshInstance3D = null
var original_material: Material = null
var flash_material: StandardMaterial3D = null

func _ready() -> void:
	if has_node(target_node_path):
		target_node = get_node(target_node_path)
	else:
		target_node = get_parent()

	if has_node(mesh_to_flash_path):
		mesh_to_flash = get_node(mesh_to_flash_path)
		if mesh_to_flash and mesh_to_flash.mesh and mesh_to_flash.mesh.material:
			original_material = mesh_to_flash.mesh.material

	flash_material = StandardMaterial3D.new()
	flash_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_material.albedo_color = Color(1.0, 1.0, 1.0, 1.0)

func get_target_node() -> Node:
	return target_node

func take_damage(amount: float, knockback: Vector3, damage_type: String, attacker: Node) -> void:
	emit_signal("damaged", amount, knockback, damage_type, attacker)
	flash_hit()

func flash_hit() -> void:
	if mesh_to_flash:
		mesh_to_flash.material_override = flash_material
		await get_tree().create_timer(0.08).timeout
		if is_instance_valid(mesh_to_flash):
			mesh_to_flash.material_override = null

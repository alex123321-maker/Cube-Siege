extends Area3D
class_name HurtboxArea

signal damaged(amount: float, knockback: Vector3, damage_type: String, attacker: Node)

const HIT_HIGHLIGHT: Shader = preload("res://assets/vfx/shaders/hit_highlight.gdshader")

@export var target_node_path: NodePath
@export var mesh_to_flash_path: NodePath

var target_node: Node = null
var mesh_to_flash: MeshInstance3D = null
var flash_material: ShaderMaterial = null
var _previous_overlay: Material = null
var _flash_tween: Tween = null

func _ready() -> void:
	if has_node(target_node_path):
		target_node = get_node(target_node_path)
	else:
		target_node = get_parent()

	if has_node(mesh_to_flash_path):
		var candidate = get_node(mesh_to_flash_path)
		if candidate is MeshInstance3D:
			mesh_to_flash = candidate
		elif candidate is Node3D:
			var meshes: Array[Node] = candidate.find_children("*", "MeshInstance3D", true, false)
			if not meshes.is_empty():
				mesh_to_flash = meshes[0] as MeshInstance3D
			else:
				mesh_to_flash = candidate.find_child("*", true, false) as MeshInstance3D
	flash_material = ShaderMaterial.new()
	flash_material.shader = HIT_HIGHLIGHT

func get_target_node() -> Node:
	if not is_instance_valid(target_node):
		target_node = get_node_or_null(target_node_path) if has_node(target_node_path) else get_parent()
	return target_node

func take_damage(amount: float, knockback: Vector3 = Vector3.ZERO, damage_type: String = "physical", attacker: Node = null, attacker_team: CombatRules.Team = CombatRules.Team.NONE) -> bool:
	var target: Node = get_target_node()
	if target and "is_dying" in target and target.is_dying:
		return false
	var eff_team: CombatRules.Team = attacker_team
	if eff_team == CombatRules.Team.NONE and is_instance_valid(attacker):
		eff_team = CombatRules.get_team(attacker)
	if not CombatRules.can_damage(attacker, target, eff_team):
		return false
	emit_signal("damaged", amount, knockback, damage_type, attacker)
	flash_hit()
	return true

func flash_hit() -> void:
	if not is_instance_valid(mesh_to_flash):
		return
	# Restart one pulse on rapid hits; an older timer must not erase a newer hit.
	if _flash_tween:
		_flash_tween.kill()
	if mesh_to_flash.material_overlay != flash_material:
		_previous_overlay = mesh_to_flash.material_overlay
	mesh_to_flash.material_overlay = flash_material
	flash_material.set_shader_parameter("strength", 1.0)
	_flash_tween = create_tween()
	_flash_tween.tween_property(flash_material, "shader_parameter/strength", 0.0, 0.12) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flash_tween.tween_callback(_restore_overlay)

func _restore_overlay() -> void:
	if is_instance_valid(mesh_to_flash) and mesh_to_flash.material_overlay == flash_material:
		mesh_to_flash.material_overlay = _previous_overlay
	_previous_overlay = null

func _exit_tree() -> void:
	if _flash_tween:
		_flash_tween.kill()
	_restore_overlay()

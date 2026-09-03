extends Node3D

@onready var line_mesh: ImmediateMesh = ImmediateMesh.new()
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var source_node: Node3D = null
var target_node: Node3D = null

func setup(p_source: Node3D, p_target: Node3D) -> void:
	source_node = p_source
	target_node = p_target

func _process(_delta: float) -> void:
	if not source_node or not is_instance_valid(source_node) or not target_node or not is_instance_valid(target_node):
		queue_free()
		return

	if not mesh_instance:
		mesh_instance = $MeshInstance3D
		if not mesh_instance: return

	# Draw glowing tether line between source and target
	line_mesh.clear_surfaces()
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	line_mesh.surface_add_vertex(source_node.global_position + Vector3(0, 1.0, 0))
	line_mesh.surface_add_vertex(target_node.global_position + Vector3(0, 1.0, 0))
	line_mesh.surface_end()
	mesh_instance.mesh = line_mesh

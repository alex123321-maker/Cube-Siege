extends SceneTree

const EXPECTED_HEIGHT_METERS: float = 2.0
const HEIGHT_TOLERANCE_METERS: float = 0.06


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var asset_path: String = _argument(args, "--asset", "")
	var report_path: String = _argument(args, "--report", "")
	if asset_path.is_empty():
		_fail("Missing required --asset res://path.glb")
		return

	var resource: Resource = load(asset_path)
	if not resource is PackedScene:
		_fail("Godot did not import %s as PackedScene" % asset_path)
		return
	var instance: Node = (resource as PackedScene).instantiate()
	root.add_child(instance)

	var meshes: Array[MeshInstance3D] = []
	var skeletons: Array[Skeleton3D] = []
	var animation_players: Array[AnimationPlayer] = []
	_collect(instance, meshes, skeletons, animation_players)
	if meshes.is_empty():
		_fail("Imported scene contains no MeshInstance3D")
		return

	var bounds: AABB = _combined_bounds(meshes)
	var materials_ok: bool = _materials_present(meshes)
	var front_marker: Node3D = instance.find_child("FrontMarker", true, false) as Node3D
	var front_marker_z: float = _relative_transform(front_marker, instance).origin.z if front_marker else NAN
	var animations: PackedStringArray = _animation_names(animation_players)
	var height_ok: bool = absf(bounds.size.y - EXPECTED_HEIGHT_METERS) <= HEIGHT_TOLERANCE_METERS
	var orientation_ok: bool = front_marker != null and front_marker_z > 0.0
	var skeleton_ok: bool = not skeletons.is_empty() and skeletons[0].get_bone_count() >= 2
	var animation_ok: bool = animations.has("calibration_idle")
	var checks: Dictionary = {
		"asset_imported": true,
		"mesh_present": not meshes.is_empty(),
		"materials_present": materials_ok,
		"height_is_two_meters": height_ok,
		"front_is_positive_z": orientation_ok,
		"skeleton_hierarchy_present": skeleton_ok,
		"calibration_animation_visible": animation_ok,
	}
	var ok: bool = true
	for value: bool in checks.values():
		ok = ok and value
	var report: Dictionary = {
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"asset": asset_path,
		"checks": checks,
		"mesh_count": meshes.size(),
		"material_surface_count": _material_surface_count(meshes),
		"bounds_m": {"position": _vector(bounds.position), "size": _vector(bounds.size)},
		"front_marker_z_m": front_marker_z,
		"skeleton_count": skeletons.size(),
		"bone_count": skeletons[0].get_bone_count() if not skeletons.is_empty() else 0,
		"animations": animations,
		"ok": ok,
	}
	if not report_path.is_empty():
		var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
		if file == null:
			_fail("Cannot write report to %s" % report_path)
			return
		file.store_string(JSON.stringify(report, "  "))
	print("ART_PIPELINE_GODOT_VALIDATION=" + JSON.stringify(report))
	quit(0 if ok else 1)


func _argument(args: PackedStringArray, name: String, default_value: String) -> String:
	var index: int = args.find(name)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else default_value


func _collect(node: Node, meshes: Array[MeshInstance3D], skeletons: Array[Skeleton3D], animation_players: Array[AnimationPlayer]) -> void:
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	elif node is Skeleton3D:
		skeletons.append(node as Skeleton3D)
	elif node is AnimationPlayer:
		animation_players.append(node as AnimationPlayer)
	for child: Node in node.get_children():
		_collect(child, meshes, skeletons, animation_players)


func _combined_bounds(meshes: Array[MeshInstance3D]) -> AABB:
	var first: bool = true
	var result: AABB
	for mesh_instance: MeshInstance3D in meshes:
		var local: AABB = mesh_instance.get_aabb()
		var transformed: AABB = _relative_transform(mesh_instance, null) * local
		result = transformed if first else result.merge(transformed)
		first = false
	return result


func _relative_transform(node: Node3D, stop: Node) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != stop:
		if current is Node3D:
			result = (current as Node3D).transform * result
		current = current.get_parent()
	return result


func _materials_present(meshes: Array[MeshInstance3D]) -> bool:
	for mesh_instance: MeshInstance3D in meshes:
		if mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() == 0:
			return false
		for surface: int in range(mesh_instance.mesh.get_surface_count()):
			if mesh_instance.get_active_material(surface) == null:
				return false
	return true


func _material_surface_count(meshes: Array[MeshInstance3D]) -> int:
	var total: int = 0
	for mesh_instance: MeshInstance3D in meshes:
		total += mesh_instance.mesh.get_surface_count() if mesh_instance.mesh else 0
	return total


func _animation_names(players: Array[AnimationPlayer]) -> PackedStringArray:
	var result := PackedStringArray()
	for player: AnimationPlayer in players:
		for library_name: StringName in player.get_animation_library_list():
			var library: AnimationLibrary = player.get_animation_library(library_name)
			for animation_name: StringName in library.get_animation_list():
				if not result.has(String(animation_name)):
					result.append(String(animation_name))
	return result


func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _fail(message: String) -> void:
	push_error(message)
	quit(1)

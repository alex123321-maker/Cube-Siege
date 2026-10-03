extends Node3D

## Presentation only. Radius, arc, duration and position come from real combat.
## Original code-native meshes; no collision bodies or global VFX manager edits.
var actor: Node3D
var radius: float = 4.2
var arc_degrees: float = 360.0
var active_duration: float = 0.3
var charge: bool = false
var _age: float = 0.0
var _mode: int = 0
var _material: StandardMaterial3D
var _ribbon_material: StandardMaterial3D
var _boundary: MeshInstance3D
var _ribbons: Array[MeshInstance3D] = []
var _height_lookup: Callable
var _pieces: MultiMesh
var _origins: Array[Vector3] = []
var _velocities: Array[Vector3] = []
var _sizes: Array[float] = []

static func spawn_cleave(owner_node: Node3D, p_radius: float, p_arc: float, duration: float, preparing: bool = false) -> Node3D:
	if not is_instance_valid(owner_node) or not owner_node.is_inside_tree():
		return null
	var effect: Node3D = (load("res://scripts/effects/warrior/warrior_talent_vfx.gd") as Script).new()
	owner_node.get_parent().add_child(effect)
	effect.setup_cleave(owner_node, p_radius, p_arc, duration, preparing)
	return effect

static func spawn_dismember(owner_node: Node3D, death_position: Vector3, p_radius: float) -> Node3D:
	if not is_instance_valid(owner_node) or not owner_node.is_inside_tree():
		return null
	var effect: Node3D = (load("res://scripts/effects/warrior/warrior_talent_vfx.gd") as Script).new()
	owner_node.get_parent().add_child(effect)
	effect.setup_dismember(death_position, p_radius)
	return effect

func setup_cleave(owner_node: Node3D, p_radius: float, p_arc: float, duration: float, preparing: bool) -> void:
	actor = owner_node
	radius = p_radius
	arc_degrees = p_arc
	active_duration = duration
	charge = preparing
	_cache_height()
	_material = _make_material(Color(0.30, 0.69, 0.92, 0.65 if charge else 0.93), 0.5 if charge else 1.3)
	_boundary = _add_mesh(_band(radius - 0.055, radius, arc_degrees), _material)
	if not is_equal_approx(arc_degrees, 360.0):
		_add_radial_edges()
	if not charge:
		_ribbon_material = _make_material(Color(0.72, 0.92, 1.0, 0.8), 1.7)
		for index: int in range(2 if arc_degrees >= 359.0 else 1):
			var ribbon: MeshInstance3D = _add_mesh(_band(radius - 0.50, radius - 0.10, 105.0 if arc_degrees >= 359.0 else arc_degrees), _ribbon_material)
			ribbon.position.y = 0.55 + index * 0.12
			ribbon.rotation.y = PI * index
			_ribbons.append(ribbon)
	_follow_actor()

func setup_dismember(death_position: Vector3, p_radius: float) -> void:
	_mode = 1
	radius = p_radius
	active_duration = 0.9
	_cache_height()
	global_position = death_position
	global_position.y = _ground_height(death_position)
	_material = _make_material(Color(0.54, 0.87, 0.93, 0.62), 0.45)
	_boundary = _add_mesh(_band(radius - 0.08, radius, 360.0), _material)
	_boundary.position.y = 0.07
	_pieces = MultiMesh.new()
	_pieces.transform_format = MultiMesh.TRANSFORM_3D
	_pieces.use_colors = true
	_pieces.instance_count = 14
	var cube: BoxMesh = BoxMesh.new()
	cube.size = Vector3.ONE
	_pieces.mesh = cube
	var debris: MultiMeshInstance3D = MultiMeshInstance3D.new()
	debris.multimesh = _pieces
	var debris_material: StandardMaterial3D = StandardMaterial3D.new()
	debris_material.vertex_color_use_as_albedo = true
	debris_material.albedo_color = Color.WHITE
	debris_material.roughness = 0.8
	debris.material_override = debris_material
	add_child(debris)
	for index: int in range(_pieces.instance_count):
		var angle: float = float(index) * 2.39996
		var size: float = 0.10 + float(index % 4) * 0.045
		_origins.append(Vector3(sin(angle) * 0.25, 0.65 + float(index % 3) * 0.2, cos(angle) * 0.25))
		_velocities.append(Vector3(sin(angle) * (1.2 + index % 3), 2.5 + index % 4 * 0.45, cos(angle) * (1.2 + index % 3)))
		_sizes.append(size)
		_pieces.set_instance_color(index, Color(0.30 + float(index % 3) * 0.10, 0.12, 0.14))
		_pieces.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), _origins[index]))

func _process(delta: float) -> void:
	_age += delta
	if _mode == 0:
		if not is_instance_valid(actor) or not actor.is_inside_tree() or ("current_health" in actor and actor.current_health <= 0.0):
			queue_free()
			return
		_follow_actor()
		var progress: float = clampf(_age / maxf(active_duration, 0.01), 0.0, 1.0)
		if charge:
			_material.albedo_color.a = 0.35 + progress * 0.30
		else:
			for index: int in range(_ribbons.size()):
				_ribbons[index].rotation.y = PI * index + progress * TAU if arc_degrees >= 359.0 else 0.0
			_material.albedo_color.a = 0.93 if _age <= active_duration else 0.93 * maxf(0.0, 1.0 - (_age - active_duration) / 0.12)
			_ribbon_material.albedo_color.a = 0.80 if _age <= active_duration else 0.80 * maxf(0.0, 1.0 - (_age - active_duration) / 0.12)
		if _age >= active_duration + (0.0 if charge else 0.12):
			queue_free()
	else:
		var progress: float = clampf(_age / active_duration, 0.0, 1.0)
		_boundary.scale = Vector3.ONE * minf(1.0, 0.5 + progress * 2.0)
		_material.albedo_color.a = 0.62 * (1.0 - progress)
		for index: int in range(_pieces.instance_count):
			var position: Vector3 = _origins[index] + _velocities[index] * _age + Vector3.DOWN * 7.0 * _age * _age
			position.y = maxf(_ground_height(global_position + position) - global_position.y + 0.06, position.y)
			var rotation: Basis = Basis(Vector3(sin(index), 0.7, cos(index)).normalized(), _age * (3.0 + index % 4))
			_pieces.set_instance_transform(index, Transform3D(rotation.scaled(Vector3.ONE * _sizes[index] * (1.0 - progress * progress)), position))
		if _age >= active_duration:
			queue_free()

func _follow_actor() -> void:
	global_position = actor.global_position
	global_position.y = _ground_height(actor.global_position) + 0.07
	global_rotation = Vector3(0.0, actor.global_rotation.y, 0.0)

func _cache_height() -> void:
	var map: MapGenerator = get_tree().get_first_node_in_group("map_generator") as MapGenerator
	if map:
		_height_lookup = Callable(map, "get_voxel_height")

func _ground_height(position: Vector3) -> float:
	return float(_height_lookup.call(TerrainCombatRules.world_to_voxel(position.x), TerrainCombatRules.world_to_voxel(position.z))) if _height_lookup.is_valid() else 0.0

func _make_material(color: Color, emission: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.emission_enabled = true
	material.emission = Color(color, 1.0)
	material.emission_energy_multiplier = emission
	return material

func _add_mesh(vertices: PackedVector3Array, material: Material) -> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	return visual

func _band(inner: float, outer: float, angle: float) -> PackedVector3Array:
	var vertices: PackedVector3Array = PackedVector3Array()
	var arc: float = deg_to_rad(angle)
	var segments: int = maxi(12, ceili(angle / 5.0))
	for index: int in range(segments):
		var a: float = -arc * 0.5 + arc * float(index) / segments
		var b: float = -arc * 0.5 + arc * float(index + 1) / segments
		var first: Vector3 = Vector3(sin(a), 0.0, -cos(a))
		var second: Vector3 = Vector3(sin(b), 0.0, -cos(b))
		vertices.append_array(PackedVector3Array([first * inner, first * outer, second * outer, first * inner, second * outer, second * inner]))
	return vertices

func _add_radial_edges() -> void:
	for sign: float in [-1.0, 1.0]:
		var direction: Vector3 = Vector3.FORWARD.rotated(Vector3.UP, deg_to_rad(arc_degrees * 0.5) * sign)
		var side: Vector3 = direction.cross(Vector3.UP) * 0.035
		_add_mesh(PackedVector3Array([-side, side, direction * radius + side, -side, direction * radius + side, direction * radius - side]), _material)

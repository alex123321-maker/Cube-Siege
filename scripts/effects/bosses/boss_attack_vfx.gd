extends Node3D
class_name BossAttackVFX

## Code-native threat graphics. Footprint vertices use the same spec as real damage.
var spec: BossAttackSpec
var direction: Vector3 = Vector3.FORWARD
var tint: Color = Color.CORAL
var height_lookup: Callable
var _fill: MeshInstance3D
var _edge: MeshInstance3D
var _fill_material: StandardMaterial3D
var _edge_material: StandardMaterial3D
var _peak: MeshInstance3D

func setup(p_spec: BossAttackSpec, p_direction: Vector3, p_tint: Color, p_height: Callable) -> void:
	spec = p_spec
	direction = p_direction
	tint = p_tint
	height_lookup = p_height
	_fill_material = _material(Color(tint, 0.12), 0.45)
	_edge_material = _material(Color(tint, 0.95), 1.2)
	_fill = _mesh(_footprint(false), _fill_material)
	_edge = _mesh(_footprint(true), _edge_material)
	_peak = MeshInstance3D.new()
	var crystal: PrismMesh = PrismMesh.new()
	crystal.size = Vector3(0.45, 0.8, 0.45)
	_peak.mesh = crystal
	_peak.material_override = _material(Color(tint, 0.85), 1.8)
	_peak.position.y = 0.45
	_peak.visible = false
	add_child(_peak)

func set_warning_progress(progress: float) -> void:
	if _fill_material:
		_fill_material.albedo_color.a = 0.10 + 0.20 * clampf(progress, 0.0, 1.0)
		_edge_material.emission_energy_multiplier = 0.7 + progress * 0.6

func show_impact() -> void:
	_fill_material.albedo_color.a = 0.65
	_edge_material.emission_energy_multiplier = 1.7
	_peak.visible = true
	_peak.scale = Vector3(1.0, 1.0, 1.0)

func set_impact_progress(progress: float) -> void:
	_fill_material.albedo_color.a = lerpf(0.65, 0.05, progress)
	_peak.scale = Vector3(1.0 + progress * 1.5, 1.0 + progress * 2.0, 1.0 + progress * 1.5)
	_peak.position.y = 0.45 + progress * 0.6

func _material(color: Color, emission: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = tint
	material.emission_energy_multiplier = emission
	return material

func _mesh(vertices: PackedVector3Array, material: Material) -> MeshInstance3D:
	var result: MeshInstance3D = MeshInstance3D.new()
	var mesh: ArrayMesh = ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	result.mesh = mesh
	result.material_override = material
	result.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(result)
	return result

func _footprint(edge: bool) -> PackedVector3Array:
	var vertices: PackedVector3Array = PackedVector3Array()
	match spec.shape:
		BossAttackSpec.Shape.CIRCLE, BossAttackSpec.Shape.SECTOR:
			var arc: float = TAU if spec.shape == BossAttackSpec.Shape.CIRCLE else deg_to_rad(spec.arc_degrees)
			var steps: int = maxi(12, int(ceilf(arc * 8.0)))
			for index: int in range(steps):
				var a: Vector3 = direction.rotated(Vector3.UP, -arc * 0.5 + arc * float(index) / steps) * spec.reach
				var b: Vector3 = direction.rotated(Vector3.UP, -arc * 0.5 + arc * float(index + 1) / steps) * spec.reach
				if edge:
					_quad(vertices, a * 0.97, a, b, b * 0.97)
				else:
					_triangle(vertices, Vector3.ZERO, a, b)
			if edge and spec.shape == BossAttackSpec.Shape.SECTOR:
				_strip(vertices, Vector3.ZERO, direction.rotated(Vector3.UP, -arc * 0.5) * spec.reach, 0.07)
				_strip(vertices, Vector3.ZERO, direction.rotated(Vector3.UP, arc * 0.5) * spec.reach, 0.07)
		BossAttackSpec.Shape.LINE:
			_rectangle(vertices, Vector3.ZERO, direction * spec.reach, spec.width, edge)
		BossAttackSpec.Shape.CROSS:
			_rectangle(vertices, -direction * spec.reach, direction * spec.reach, spec.width, edge)
			var side: Vector3 = direction.cross(Vector3.UP)
			_rectangle(vertices, -side * spec.reach, side * spec.reach, spec.width, edge)
		BossAttackSpec.Shape.FAN:
			for index: int in range(spec.projectile_count):
				var angle: float = lerpf(-spec.arc_degrees * 0.5, spec.arc_degrees * 0.5, float(index) / maxi(1, spec.projectile_count - 1))
				var ray: Vector3 = direction.rotated(Vector3.UP, deg_to_rad(angle))
				# The swept projectile contact radius is .75m; show its whole lane.
				_rectangle(vertices, ray * 1.5, ray * spec.reach, 1.5, edge)
				_disc(vertices, ray * 1.5, 0.75, edge)
				_disc(vertices, ray * spec.reach, 0.75, edge)
	return vertices

func _disc(vertices: PackedVector3Array, center: Vector3, radius: float, edge: bool) -> void:
	for index: int in range(24):
		var a: Vector3 = Vector3(sin(TAU * index / 24.0), 0.0, cos(TAU * index / 24.0)) * radius
		var b: Vector3 = Vector3(sin(TAU * (index + 1) / 24.0), 0.0, cos(TAU * (index + 1) / 24.0)) * radius
		if edge:
			_quad(vertices, center + a * 0.90, center + a, center + b, center + b * 0.90)
		else:
			_triangle(vertices, center, center + a, center + b)

func _rectangle(vertices: PackedVector3Array, start: Vector3, finish: Vector3, width: float, edge: bool) -> void:
	var side: Vector3 = (finish - start).normalized().cross(Vector3.UP) * width * 0.5
	if edge:
		_strip(vertices, start + side, finish + side, 0.08)
		_strip(vertices, start - side, finish - side, 0.08)
		_strip(vertices, start - side, start + side, 0.08)
		_strip(vertices, finish - side, finish + side, 0.08)
	else:
		_quad(vertices, start - side, start + side, finish + side, finish - side)

func _strip(vertices: PackedVector3Array, start: Vector3, finish: Vector3, width: float) -> void:
	var side: Vector3 = (finish - start).normalized().cross(Vector3.UP) * width * 0.5
	_quad(vertices, start - side, start + side, finish + side, finish - side)

func _quad(vertices: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_triangle(vertices, a, b, c)
	_triangle(vertices, a, c, d)

func _triangle(vertices: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	vertices.append(_ground_vertex(a))
	vertices.append(_ground_vertex(b))
	vertices.append(_ground_vertex(c))

func _ground_vertex(point: Vector3) -> Vector3:
	if height_lookup.is_valid():
		var world: Vector3 = global_position + point
		point.y = float(height_lookup.call(TerrainCombatRules.world_to_voxel(world.x), TerrainCombatRules.world_to_voxel(world.z))) - global_position.y + 0.06
	else:
		point.y = 0.06
	return point

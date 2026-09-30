class_name ArrowImpactVFX
extends Node3D

## One directional contact, a short rebound and a low-opacity dust tail.
## All clocks, debris and cleanup are visual; no colliders or damage state.
const SHADER: Shader = preload("res://assets/vfx/shaders/arrow_impact.gdshader")
var _profile: ArrowImpactProfile
var _age: float = 0.0
var _duration: float = 0.0
var _rebound: Vector3
var _contact_basis: Basis
var _offset: Vector3
var _materials: Array[ShaderMaterial] = []
var _contact: MeshInstance3D
var _outline: MeshInstance3D
var _dust: MeshInstance3D
var _shards: MultiMesh
var _velocities: Array[Vector3] = []
var _sizes: Array[float] = []

func setup(profile: ArrowImpactProfile, incoming: Vector3, terrain: bool = false) -> void:
	_profile = profile
	_rebound = -incoming.normalized() if not incoming.is_zero_approx() else Vector3.BACK
	_duration = maxf(profile.contact_lifetime, maxf(profile.shard_lifetime, profile.dust_lifetime))
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var camera: Camera3D = get_viewport().get_camera_3d()
	var facing: Basis = camera.global_basis if camera else Basis.IDENTITY
	var projected := Vector2(_rebound.dot(facing.x), _rebound.dot(facing.y))
	var angle: float = projected.angle() - PI * 0.25
	_contact_basis = facing * Basis(Vector3.BACK, angle)
	# The burst originates near the arrow tip. A small surface bias prevents
	# fighting with the struck mesh; ordinary scene depth still occludes it.
	_offset = _rebound * (0.08 if terrain else -0.28) + facing.z * 0.12
	var tint: Color = Color(0.66, 0.65, 0.59) if terrain else profile.contact_color
	_outline = _card("ContactEdge", profile.contact_texture, Color(0.22, 0.16, 0.09), profile.contact_lifetime, 0.5, 0.0)
	(_outline.material_override as ShaderMaterial).set_shader_parameter("dark_edge", true)
	_contact = _card("Contact", profile.contact_texture, tint, profile.contact_lifetime, 1.0, profile.emission)
	_dust = _card("ReboundDust", profile.dust_texture, profile.dust_color, profile.dust_lifetime, profile.dust_opacity, 0.0)
	(_dust.material_override as ShaderMaterial).set_shader_parameter("dust", true)
	_make_shards(tint)
	_update_visuals()

func _card(node_name: String, texture: Texture2D, tint: Color, life: float, opacity: float, glow: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = node_name
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	node.mesh = quad
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("artwork", texture)
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("lifetime", life)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("emission", glow)
	node.material_override = material
	_materials.append(material)
	add_child(node)
	return node

func _make_shards(tint: Color) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0.0, 0.0, -0.75)
	var tail := Vector3(0.0, 0.0, 0.35)
	var rim: Array[Vector3] = [Vector3(0.10, 0.0, 0.0), Vector3(0.0, 0.07, 0.0), Vector3(-0.10, 0.0, 0.0), Vector3(0.0, -0.07, 0.0)]
	for index in range(4):
		for vertex: Vector3 in [tip, rim[index], rim[(index + 1) % 4], tail, rim[(index + 1) % 4], rim[index]]:
			mesh.surface_add_vertex(vertex)
	mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, material)
	_shards = MultiMesh.new()
	_shards.transform_format = MultiMesh.TRANSFORM_3D
	_shards.use_colors = true
	_shards.mesh = mesh
	_shards.instance_count = clampi(_profile.shard_count, 4, 16)
	var instance := MultiMeshInstance3D.new()
	instance.name = "ReboundShards"
	instance.multimesh = _shards
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	# Isolated deterministic variation must not consume gameplay random state.
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	var side: Vector3 = _rebound.cross(Vector3.UP).normalized()
	if side.is_zero_approx():
		side = Vector3.RIGHT
	for index in range(_shards.instance_count):
		var velocity: Vector3 = (_rebound + side * rng.randf_range(-0.65, 0.65)
			+ Vector3.UP * rng.randf_range(-0.1, 0.75)).normalized() * _profile.shard_speed * rng.randf_range(0.55, 1.1)
		_velocities.append(velocity)
		_sizes.append(rng.randf_range(0.16, 0.31))
		_shards.set_instance_color(index, tint.lerp(Color(1.0, 0.95, 0.79), rng.randf_range(0.0, 0.7)))

func _process(delta: float) -> void:
	_age += delta
	if _age >= _duration:
		queue_free()
		return
	_update_visuals()

func _update_visuals() -> void:
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("age", _age)
	var phase: float = clampf(_age / _profile.contact_lifetime, 0.0, 1.0)
	var size: float = _profile.contact_size * lerpf(0.68, 1.06, 1.0 - pow(1.0 - phase, 3.0))
	_contact.transform = Transform3D(_contact_basis.scaled_local(Vector3(size, size * 0.68, size)), _offset)
	_outline.transform = Transform3D(_contact_basis.scaled_local(Vector3(size * 1.09, size * 0.75, size)), _offset - _contact_basis.z * 0.015)
	_contact.visible = phase < 1.0
	_outline.visible = phase < 1.0
	var dust_phase: float = clampf(_age / _profile.dust_lifetime, 0.0, 1.0)
	var dust_size: float = _profile.dust_size * lerpf(0.45, 1.1, dust_phase)
	_dust.transform = Transform3D(_contact_basis.scaled_local(Vector3(dust_size, dust_size * 0.65, dust_size)),
		_offset + _rebound * _age * 0.95 + Vector3.UP * _age * 0.25)
	_dust.visible = dust_phase < 1.0
	var shard_phase: float = clampf(_age / _profile.shard_lifetime, 0.0, 1.0)
	for index in range(_velocities.size()):
		var velocity: Vector3 = _velocities[index] + Vector3.DOWN * _age * 7.0
		var up: Vector3 = Vector3.UP if absf(velocity.normalized().dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
		var facing: Basis = Basis.looking_at(velocity, up)
		var scale_factor: float = _sizes[index] * (1.0 - shard_phase * shard_phase)
		var at: Vector3 = _offset + _velocities[index] * _age + Vector3.DOWN * 3.5 * _age * _age
		_shards.set_instance_transform(index, Transform3D(facing.scaled_local(Vector3.ONE * scale_factor), at))

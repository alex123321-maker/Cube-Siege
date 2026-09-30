class_name SwordVFX
extends Node3D

## Textured, layered sword presentation. No damage or physics bodies.
const RIBBON_SHADER: Shader = preload("res://assets/vfx/shaders/sword_ribbon.gdshader")
const CONTACT_SHADER: Shader = preload("res://assets/vfx/shaders/sword_contact.gdshader")
var _profile: SwordVFXProfile
var _age: float = 0.0
var _duration: float = 0.4
var _materials: Array[ShaderMaterial] = []
var _ribbons: Array[MeshInstance3D] = []
var _shards: MultiMesh
var _origins: Array[Vector3] = []
var _velocities: Array[Vector3] = []
var _contact: bool = false
var _light: OmniLight3D
var _contact_offset: Vector3 = Vector3.ZERO

func setup_slash(profile: SwordVFXProfile, radius: float, arc_degrees: float) -> void:
	_profile = profile
	_duration = profile.lifetime + 0.10
	_add_ribbon(radius, profile.ribbon_width, arc_degrees, 0.0, profile.lifetime, profile.arc_opacity)
	# A slender delayed filament gives the edge a second rhythm.
	_add_ribbon(radius + 0.10, profile.ribbon_width * 0.26, arc_degrees * 0.88,
		0.022, profile.lifetime * 0.72, 0.66 * profile.arc_opacity)
	_ribbons[1].position.y = 0.07
	_ribbons[1].rotation.y = -0.09
	_create_shards(profile.shard_count, radius, arc_degrees)

func setup_contact(profile: SwordVFXProfile, direction: Vector3) -> void:
	_profile = profile
	_contact = true
	_duration = maxf(0.44, profile.contact_lifetime)
	var camera: Camera3D = get_viewport().get_camera_3d()
	# Approximate the struck surface instead of burying the sprite in the torso.
	# Depth testing remains enabled, so walls still occlude the contact.
	_contact_offset = -direction.normalized() * 0.32
	if camera:
		_contact_offset += (camera.global_position - global_position).normalized() * 0.28
	var sprite := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * profile.contact_size
	sprite.mesh = quad
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sprite)
	sprite.position = _contact_offset
	if camera:
		sprite.look_at(camera.global_position, Vector3.UP)
	sprite.rotate_object_local(Vector3.FORWARD, -0.15)
	var material := ShaderMaterial.new()
	material.shader = CONTACT_SHADER
	material.set_shader_parameter("artwork", profile.contact_texture)
	material.set_shader_parameter("contact_color", profile.contact_color)
	material.set_shader_parameter("lifetime", profile.contact_lifetime)
	material.set_shader_parameter("intensity", profile.emission)
	sprite.material_override = material
	_materials.append(material)
	_ribbons.append(sprite)
	_create_shards(12, 0.0, 90.0, direction)
	_light = OmniLight3D.new()
	_light.light_color = profile.contact_color
	_light.light_energy = 1.5
	_light.omni_range = 2.2
	_light.shadow_enabled = false
	add_child(_light)
	_light.position = _contact_offset

func _make_material(delay: float, life: float, opacity: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = RIBBON_SHADER
	material.set_shader_parameter("artwork", _profile.ribbon_texture)
	material.set_shader_parameter("body_color", _profile.body_color)
	material.set_shader_parameter("edge_color", _profile.edge_color)
	material.set_shader_parameter("start_delay", delay)
	material.set_shader_parameter("lifetime", life)
	material.set_shader_parameter("sweep_time", _profile.sweep_time)
	material.set_shader_parameter("intensity", _profile.emission)
	material.set_shader_parameter("opacity", opacity)
	_materials.append(material)
	return material

func _add_ribbon(radius: float, width: float, arc: float, delay: float,
		life: float, opacity: float) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for index in range(65):
		var u: float = float(index) / 64.0
		var angle: float = deg_to_rad(lerpf(-arc * 0.5, arc * 0.5, u))
		var radial := Vector3(sin(angle), 0.0, -cos(angle))
		var rise: float = sin(u * PI) * 0.08
		mesh.surface_set_uv(Vector2(u, 0.0))
		mesh.surface_add_vertex(radial * radius + Vector3.UP * rise)
		mesh.surface_set_uv(Vector2(u, 1.0))
		mesh.surface_add_vertex(radial * (radius - width) + Vector3.UP * rise)
	mesh.surface_end()
	var ribbon := MeshInstance3D.new()
	ribbon.mesh = mesh
	ribbon.material_override = _make_material(delay, life, opacity)
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ribbon)
	_ribbons.append(ribbon)

func _create_shards(count: int, radius: float, arc: float,
		direction: Vector3 = Vector3.FORWARD) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices: Array[Vector3] = [Vector3(0, 0, -0.65), Vector3(-0.14, 0, 0.1),
		Vector3(0.14, 0, 0.1), Vector3(-0.14, 0, 0.1), Vector3(0, 0, 0.35), Vector3(0.14, 0, 0.1)]
	for vertex: Vector3 in vertices:
		mesh.surface_add_vertex(vertex)
	mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = _profile.contact_color if _contact else _profile.edge_color
	material.emission_energy_multiplier = 1.4
	mesh.surface_set_material(0, material)
	_shards = MultiMesh.new()
	_shards.transform_format = MultiMesh.TRANSFORM_3D
	_shards.use_colors = true
	_shards.mesh = mesh
	_shards.instance_count = count
	var renderer := MultiMeshInstance3D.new()
	renderer.multimesh = _shards
	renderer.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(renderer)
	for index in range(count):
		var f: float = (float(index) + 0.5) / maxf(1.0, float(count))
		var angle: float = deg_to_rad(lerpf(-arc * 0.55, arc * 0.55, f))
		var radial := Vector3(sin(angle), 0.0, -cos(angle))
		_origins.append(radial * radius * (0.8 + 0.18 * sin(float(index) * 3.1)))
		var tangent := Vector3(-radial.z, 0.0, radial.x)
		var velocity: Vector3 = (tangent * 1.5 + radial * 0.6) * (1.0 + f)
		if _contact:
			_origins[index] += _contact_offset
			var turn: float = float(index) * 2.39996
			velocity = Vector3(cos(turn), 0.35 + sin(turn) * 0.65, sin(turn)) * (3.5 + f * 4.0)
			velocity += direction.normalized() * 1.8
		_velocities.append(velocity)
		_shards.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))

func _process(delta: float) -> void:
	_age += delta
	if _age >= _duration:
		queue_free()
		return
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("age", _age)
	for index in range(_ribbons.size()):
		var ribbon: MeshInstance3D = _ribbons[index]
		var growth: float = lerpf(0.85, 1.03, 1.0 - pow(1.0 - clampf(_age / 0.12, 0.0, 1.0), 3.0))
		if _contact:
			growth = lerpf(0.62, 1.22, 1.0 - pow(1.0 - clampf(_age / 0.10, 0.0, 1.0), 3.0))
		ribbon.scale = Vector3.ONE * growth
		if not _contact:
			var sweep: float = 1.0 - pow(1.0 - clampf(_age / 0.18, 0.0, 1.0), 3.0)
			ribbon.rotation.y = lerpf(-0.28, 0.18, sweep) - float(index) * 0.09
			ribbon.rotation.z = -0.10
	if _light:
		_light.light_energy = 1.5 * pow(maxf(0.0, 1.0 - _age / 0.10), 2.0)
	if not _shards:
		return
	for index in range(_shards.instance_count):
		var delay: float = 0.012 if _contact else float(index) * 0.004
		var t: float = maxf(0.0, _age - delay)
		var life: float = (0.24 if _contact else 0.20) + float(index % 4) * 0.04
		var opacity: float = maxf(0.0, 1.0 - t / life)
		if _age < delay:
			opacity = 0.0
		var at: Vector3 = _origins[index] + _velocities[index] * t + Vector3.DOWN * t * t * 2.0
		if _contact:
			at = _origins[index] + _velocities[index] * (1.0 - exp(-t * 5.0)) / 5.0 + Vector3.DOWN * t * t * 3.0
		var basis := Basis.looking_at(_velocities[index].normalized(), Vector3.UP)
		var size: float = (0.20 if _contact else 0.16) * (0.6 + opacity)
		basis = basis.scaled(Vector3(size, size, size * (1.2 + float(index % 3) * 0.6)))
		_shards.set_instance_transform(index, Transform3D(basis, at))
		var color: Color = _profile.contact_color if _contact else _profile.edge_color
		if _contact:
			color = Color(1.0, 0.95, 0.73).lerp(_profile.contact_color.darkened(0.15), clampf(t / life, 0.0, 1.0))
		color.a = opacity
		_shards.set_instance_color(index, color)

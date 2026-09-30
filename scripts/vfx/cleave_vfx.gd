class_name CleaveVFX
extends Node3D

## One clock for the entire slash, including fixed-FPS recordings and cleanup.
## Geometry has depth testing; fragments never create collision bodies.
const BLADE_SHADER: Shader = preload("res://assets/vfx/shaders/cleave_blade.gdshader")
var _profile: CleaveVFXProfile
var _age: float = 0.0
var _lifetime: float = 0.8
var _materials: Array[ShaderMaterial] = []
var _blades: Array[MeshInstance3D] = []
var _fragments: MultiMesh
var _origins: Array[Vector3] = []
var _velocities: Array[Vector3] = []
var _sizes: Array[float] = []
var _light: OmniLight3D
var _charge_owner: Node3D
var _charge: bool = false
var _contact: bool = false

func setup_release(profile: CleaveVFXProfile, visual_duration: float) -> void:
	_profile = profile
	_lifetime = maxf(profile.lifetime, visual_duration) + 0.12
	# A solid bevel and translucent wake, rather than a filled semicircle.
	_add_blade(profile.radius, profile.blade_width, 180.0, 0.0, 0.48, 0, 0.92)
	_add_blade(profile.radius + 0.12, 0.10, 172.0, 0.018, 0.40, 1, 0.9)
	_add_blade(profile.radius - 0.45, 0.07, 160.0, 0.038, 0.36, 1, 0.55)
	_add_blade(profile.radius - 0.20, 1.6, 180.0, 0.025, 0.56, 2, 0.65)
	_blades[1].position.y = 0.10
	_blades[2].position.y = -0.12
	_blades[3].position.y = 0.15
	_blades[3].rotation.z = 0.12
	_create_fragments(profile.fragment_count + profile.spark_count, profile.radius)
	_ground_cuts()
	_add_glint(Vector3(0.65, 0.30, -0.7), 2.4, 0.11)
	_add_light(4.5)
	if profile.release_sound and DisplayServer.get_name() != "headless":
		var audio := AudioStreamPlayer3D.new()
		audio.stream = profile.release_sound
		audio.volume_db = profile.volume_db
		audio.unit_size = 14.0
		audio.max_distance = 55.0
		add_child(audio)
		audio.play()
	var camera: CameraFollow = get_viewport().get_camera_3d() as CameraFollow
	if camera:
		camera.add_combat_impulse(-global_basis.z, 0.075)

func setup_charge(profile: CleaveVFXProfile, owner_node: Node3D, duration: float) -> void:
	_profile = profile
	_charge = true
	_charge_owner = owner_node
	_lifetime = duration
	_add_blade(1.30, 0.09, 110.0, 0.0, duration, 1, 0.8)
	_add_blade(1.05, 0.035, 90.0, 0.0, duration, 2, 0.7)
	_blades[0].rotation.z = -0.55
	_blades[1].rotation.x = 0.65
	_add_light(1.8)

func setup_contact(profile: CleaveVFXProfile, direction: Vector3) -> void:
	_profile = profile
	_contact = true
	_lifetime = 0.46
	# Pull the flash onto the struck surface, with normal depth occlusion.
	_add_glint(-direction.normalized() * 0.30, 1.85, 0.13)
	_create_fragments(14, 0.0)
	_add_light(2.5)

func _material(layer: int, delay: float, life: float, opacity: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BLADE_SHADER
	material.set_shader_parameter("steel_color", _profile.steel_color)
	material.set_shader_parameter("edge_color", _profile.edge_color)
	material.set_shader_parameter("gold_color", _profile.gold_color)
	material.set_shader_parameter("intensity", _profile.emission)
	material.set_shader_parameter("sweep_time", _profile.sweep_time)
	material.set_shader_parameter("delay", delay)
	material.set_shader_parameter("lifetime", life)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("layer", layer)
	_materials.append(material)
	return material

func _add_blade(radius: float, width: float, arc: float, delay: float,
		life: float, layer: int, opacity: float) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for index in range(73):
		var u: float = float(index) / 72.0
		var angle: float = deg_to_rad(lerpf(-arc * 0.5, arc * 0.5, u))
		var radial := Vector3(sin(angle), 0.0, -cos(angle))
		# The blade narrows at the tips and lifts off the ground at its heart.
		var taper: float = pow(maxf(0.0, sin(u * PI)), 0.65)
		var rise: float = sin(u * PI) * 0.14
		mesh.surface_set_uv(Vector2(u, 0.0))
		mesh.surface_add_vertex(radial * radius + Vector3.UP * rise)
		mesh.surface_set_uv(Vector2(u, 1.0))
		mesh.surface_add_vertex(radial * (radius - width * taper) + Vector3.UP * (rise - 0.16 * taper))
	mesh.surface_end()
	var blade := MeshInstance3D.new()
	blade.mesh = mesh
	blade.material_override = _material(layer, delay, life, opacity)
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blade)
	_blades.append(blade)

func _add_glint(at: Vector3, size: float, life: float) -> void:
	var glint := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size * 0.75)
	glint.mesh = quad
	glint.material_override = _material(4, 0.0, life, 0.95)
	glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glint)
	glint.position = at
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		glint.look_at(camera.global_position)
		glint.rotate_object_local(Vector3.FORWARD, -0.4)

func _add_light(reach: float) -> void:
	_light = OmniLight3D.new()
	_light.light_color = _profile.gold_color
	_light.omni_range = reach
	_light.shadow_enabled = false
	_light.light_energy = 0.0
	add_child(_light)
	_light.position = Vector3(0.0, 0.4, -0.6)

func _create_fragments(count: int, radius: float) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = _profile.gold_color
	material.emission_energy_multiplier = 0.45
	mesh.material = material
	_fragments = MultiMesh.new()
	_fragments.transform_format = MultiMesh.TRANSFORM_3D
	_fragments.use_colors = true
	_fragments.mesh = mesh
	_fragments.instance_count = count
	var renderer := MultiMeshInstance3D.new()
	renderer.multimesh = _fragments
	renderer.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(renderer)
	for index in range(count):
		var f: float = (float(index) + 0.5) / maxf(float(count), 1.0)
		var angle: float = lerpf(-PI * 0.50, PI * 0.50, f)
		var radial := Vector3(sin(angle), 0.0, -cos(angle))
		var tangent := Vector3(-radial.z, 0.0, radial.x)
		var noise: float = 0.5 + 0.5 * sin(float(index) * 17.73)
		var origin: Vector3 = radial * radius * (0.70 + noise * 0.28)
		var velocity: Vector3 = radial * (0.8 + noise * 1.4) + tangent * (1.0 + noise * 2.5)
		velocity.y = 0.3 + noise * 2.4
		if _contact:
			var turn: float = float(index) * 2.39996
			velocity = Vector3(cos(turn), sin(turn * 1.6) * 0.7 + 0.5, sin(turn)) * (3.0 + noise * 4.0)
		_origins.append(origin)
		_velocities.append(velocity)
		_sizes.append(0.028 + noise * 0.080)
		_fragments.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))

func _ground_cuts() -> void:
	var vertices: Array[Vector3] = []
	var texcoords: Array[Vector2] = []
	var count: int = 0
	for index in range(22):
		var u: float = (float(index) + 0.5) / 22.0
		var angle: float = lerpf(-PI * 0.46, PI * 0.46, u)
		var radial := Vector3(sin(angle), 0.0, -cos(angle))
		var at: Vector3 = to_global(radial * (_profile.radius - 0.25))
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 1.0, at + Vector3.DOWN * 2.2, 1)
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var center: Vector3 = to_local((hit.position as Vector3) + Vector3.UP * 0.018)
		# Skip ledges disconnected from the player's elevation.
		if absf(center.y + 1.15) > 1.05:
			continue
		var tangent := Vector3(-radial.z, 0.0, radial.x) * (0.16 + 0.1 * sin(float(index) * 5.3))
		var depth: Vector3 = radial * 0.065
		var points: Array[Vector3] = [center - tangent - depth, center + tangent - depth,
			center - tangent + depth, center + tangent - depth, center + tangent + depth, center - tangent + depth]
		var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1),
			Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
		for vertex in range(6):
			texcoords.append(uvs[vertex])
			vertices.append(points[vertex])
		count += 1
	if count == 0:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(vertices.size()):
		mesh.surface_set_uv(texcoords[index])
		mesh.surface_add_vertex(vertices[index])
	mesh.surface_end()
	var ground := MeshInstance3D.new()
	ground.name = "GroundCuts"
	ground.mesh = mesh
	ground.material_override = _material(3, 0.02, _profile.lifetime, 1.0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

func _process(delta: float) -> void:
	_age += delta
	if _age >= _lifetime or (_charge and (not is_instance_valid(_charge_owner)
			or not _charge_owner.is_inside_tree())):
		queue_free()
		return
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("age", _age)
	if _charge:
		global_position = _charge_owner.global_position + Vector3.UP * 0.25
		global_basis = _charge_owner.global_basis
		var buildup: float = clampf(_age / _lifetime, 0.0, 1.0)
		for blade: MeshInstance3D in _blades:
			blade.scale = Vector3.ONE * lerpf(1.15, 0.55, buildup)
			blade.rotation.y = -0.7 + buildup * 1.6
		_light.light_energy = buildup * 0.55
		return
	var expansion: float = 1.0 - pow(1.0 - clampf(_age / 0.13, 0.0, 1.0), 3.0)
	for index in range(_blades.size()):
		_blades[index].scale = Vector3.ONE * lerpf(0.70, 1.0, expansion)
		_blades[index].rotation.y = lerpf(-0.16, 0.05, expansion) - float(index) * 0.025
	_light.light_energy = (2.4 if _contact else 3.4) * pow(maxf(0.0, 1.0 - _age / 0.16), 2.0)
	if not _fragments:
		return
	for index in range(_fragments.instance_count):
		var f: float = float(index) / maxf(float(_fragments.instance_count - 1), 1.0)
		var delay: float = 0.008 if _contact else f * _profile.sweep_time
		var t: float = maxf(0.0, _age - delay)
		var life: float = 0.25 + float(index % 5) * 0.065
		var fade: float = maxf(0.0, 1.0 - t / life)
		if _age < delay:
			fade = 0.0
		var spark: bool = _contact or index >= _profile.fragment_count
		var at: Vector3 = _origins[index] + _velocities[index] * t + Vector3.DOWN * t * t * 3.8
		var size: float = _sizes[index] * (0.6 + fade * 0.4)
		var orientation := Basis.from_euler(Vector3(t * 4.0, float(index) + t * 3.0, t * 2.0))
		if spark:
			orientation = Basis.looking_at(_velocities[index].normalized(), Vector3.UP)
		var dimensions := Vector3(size, size, size * (4.5 if spark else 1.0))
		_fragments.set_instance_transform(index, Transform3D(orientation.scaled(dimensions), at))
		var color: Color = _profile.gold_color if spark else _profile.edge_color.lerp(_profile.steel_color, t / life)
		color.a = fade
		_fragments.set_instance_color(index, color)

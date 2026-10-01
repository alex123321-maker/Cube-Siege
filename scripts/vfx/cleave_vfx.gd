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
var _weapon_tip: Node3D
var _weapon_glint: MeshInstance3D
var _contact_direction: Vector3 = Vector3.FORWARD
var _contact_target: Node3D
var _contact_offset: Vector3

func setup_release(profile: CleaveVFXProfile, visual_duration: float) -> void:
	_profile = profile
	_lifetime = maxf(profile.lifetime, visual_duration) + 0.12
	# A broad frontal blade matches the real sector; its painted body erodes locally.
	_add_blade(profile.radius, profile.blade_width, profile.ability.arc_degrees, 0.0, 0.38, 0, 0.98)
	_add_blade(profile.radius, 0.28, profile.ability.arc_degrees, 0.0, 0.32, 8, 0.92)
	_add_blade(profile.radius - 0.18, 1.9, profile.ability.arc_degrees, 0.035, 0.45, 2, 0.42)
	_blades[0].position.y = 0.16
	_blades[1].position.y = 0.17
	_blades[2].position.y = -0.08
	_ground_sector()
	_create_fragments(profile.fragment_count + profile.spark_count, profile.radius)
	_ground_cuts()
	_add_glint(Vector3(0.45, 0.40, -0.75), 1.5, 0.08)
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

func setup_charge(profile: CleaveVFXProfile, owner_node: Node3D, duration: float,
		weapon_tip: Node3D = null) -> void:
	_profile = profile
	_charge = true
	_charge_owner = owner_node
	_weapon_tip = weapon_tip
	_lifetime = duration
	global_position = owner_node.global_position + Vector3.UP * 0.25
	global_basis = owner_node.global_basis
	_ground_sector()
	_weapon_glint = _add_glint(Vector3.ZERO, 0.65, duration, true)
	_add_light(1.8)

func setup_contact(profile: CleaveVFXProfile, direction: Vector3, target: Node3D = null) -> void:
	_profile = profile
	_contact = true
	_contact_direction = global_basis.inverse() * direction.normalized()
	_lifetime = 0.58
	_contact_target = target
	if is_instance_valid(target):
		_contact_offset = global_position - target.global_position
	# Pull the flash onto the struck surface, with normal depth occlusion.
	var scar: MeshInstance3D = _add_glint(Vector3.ZERO, 2.0, 0.40)
	scar.material_override = _material(6, 0.0, 0.40, 1.0)
	var camera: Camera3D = get_viewport().get_camera_3d()
	scar.position = (camera.global_position - global_position).normalized() * 0.62 if camera else -direction.normalized() * 0.55
	_create_fragments(18, 0.0)
	_add_light(2.5)

func _material(layer: int, delay: float, life: float, opacity: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = BLADE_SHADER
	material.set_shader_parameter("steel_color", _profile.steel_color)
	material.set_shader_parameter("edge_color", _profile.edge_color)
	material.set_shader_parameter("gold_color", _profile.gold_color)
	material.set_shader_parameter("artwork", _profile.ribbon_texture)
	material.set_shader_parameter("traveling_head", _profile.traveling_head)
	material.set_shader_parameter("charging", _charge)
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
		var angle: float = deg_to_rad(lerpf(arc * 0.5, -arc * 0.5, u))
		var radial := Vector3(sin(angle), 0.0, -cos(angle))
		# The blade narrows at the tips and lifts off the ground at its heart.
		var taper: float = pow(maxf(0.0, sin(u * PI)), 0.45) * lerpf(0.5, 1.25, u)
		var rise: float = sin(u * PI) * 0.45 + (u - 0.5) * 0.55
		mesh.surface_set_uv(Vector2(u, 0.0))
		mesh.surface_add_vertex(radial * radius + Vector3.UP * rise)
		mesh.surface_set_uv(Vector2(u, 1.0))
		mesh.surface_add_vertex(radial * (radius - width * taper) + Vector3.UP * (rise - 0.55 * taper))
	mesh.surface_end()
	var blade := MeshInstance3D.new()
	blade.mesh = mesh
	blade.material_override = _material(layer, delay, life, opacity)
	blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blade)
	_blades.append(blade)

func _add_glint(at: Vector3, size: float, life: float, buildup: bool = false) -> MeshInstance3D:
	var glint := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size * 0.75)
	glint.mesh = quad
	glint.material_override = _material(5 if buildup else 4, 0.0, life, 0.95)
	glint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(glint)
	glint.position = at
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		glint.look_at(camera.global_position)
		glint.rotate_object_local(Vector3.FORWARD, -0.4)
	return glint

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
		var angle: float = lerpf(PI * 0.50, -PI * 0.50, f)
		var radial := Vector3(sin(angle), 0.0, -cos(angle))
		var tangent := Vector3(-radial.z, 0.0, radial.x)
		var noise: float = 0.5 + 0.5 * sin(float(index) * 17.73)
		var origin: Vector3 = radial * radius * (0.70 + noise * 0.28)
		var velocity: Vector3 = radial * (0.8 + noise * 1.4) + tangent * (1.0 + noise * 2.5)
		velocity.y = 0.1 + noise * 1.4
		if _contact:
			var turn: float = float(index) * 2.39996
			var sideways: Vector3 = _contact_direction.cross(Vector3.UP).normalized()
			velocity = _contact_direction * (2.0 + noise * 2.2) + sideways * cos(turn) * 3.5
			velocity.y = sin(turn) * 1.6 + 0.7
		_origins.append(origin)
		_velocities.append(velocity)
		_sizes.append(0.018 + noise * 0.055)
		_fragments.set_instance_transform(index, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))

func _ground_sector() -> void:
	# Sample the real terrain; never project a disc across an unsupported ledge.
	const SEGMENTS: int = 24
	const RINGS: int = 4
	var points: Array[Vector3] = []
	var valid: Array[bool] = []
	for segment in range(SEGMENTS + 1):
		var angle: float = deg_to_rad(lerpf(-_profile.ability.arc_degrees * 0.5,
			_profile.ability.arc_degrees * 0.5, float(segment) / SEGMENTS))
		for ring in range(RINGS + 1):
			var radial := Vector3(sin(angle), 0.0, -cos(angle)) * _profile.radius * float(ring) / RINGS
			var at: Vector3 = to_global(radial)
			var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP, at + Vector3.DOWN * 2.3, 1)
			var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
			valid.append(not hit.is_empty())
			points.append(to_local((hit.position as Vector3) + Vector3.UP * 0.025) if not hit.is_empty() else Vector3.ZERO)
	var indices: Array[int] = []
	for segment in range(SEGMENTS):
		for ring in range(RINGS):
			var a: int = segment * (RINGS + 1) + ring
			var b: int = a + RINGS + 1
			if not (valid[a] and valid[b] and valid[a + 1] and valid[b + 1]):
				continue
			var low: float = minf(minf(points[a].y, points[b].y), minf(points[a + 1].y, points[b + 1].y))
			var high: float = maxf(maxf(points[a].y, points[b].y), maxf(points[a + 1].y, points[b + 1].y))
			if high - low > 0.6 or absf(low + 1.15) > 1.05:
				continue
			for vertex: int in [a, b, a + 1, b, b + 1, a + 1]:
				indices.append(vertex)
	if indices.is_empty():
		# ImmediateMesh rejects empty surfaces.
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex: int in indices:
		mesh.surface_set_uv(Vector2(float(vertex / (RINGS + 1)) / SEGMENTS, float(vertex % (RINGS + 1)) / RINGS))
		mesh.surface_add_vertex(points[vertex])
	mesh.surface_end()
	var ground := MeshInstance3D.new()
	ground.name = "CleaveFootprint"
	ground.mesh = mesh
	ground.material_override = _material(7, 0.0, _lifetime if _charge else 0.58, 0.9)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

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
	if _contact and is_instance_valid(_contact_target) and _contact_target.is_inside_tree():
		global_position = _contact_target.global_position + _contact_offset
	if _charge:
		global_position = _charge_owner.global_position + Vector3.UP * 0.25
		global_basis = _charge_owner.global_basis
		var buildup: float = clampf(_age / _lifetime, 0.0, 1.0)
		if is_instance_valid(_weapon_tip):
			_weapon_glint.global_position = _weapon_tip.get_global_transform_interpolated().origin
			_light.global_position = _weapon_glint.global_position
		_weapon_glint.scale = Vector3.ONE * lerpf(0.25, 1.0, buildup)
		_light.light_energy = buildup * 0.55
		return
	var expansion: float = 1.0 - pow(1.0 - clampf(_age / 0.09, 0.0, 1.0), 3.0)
	for index in range(_blades.size()):
		_blades[index].scale = Vector3.ONE * lerpf(0.90, 1.0, expansion)
		_blades[index].visible = _age < 0.45
	_light.light_energy = (2.0 if _contact else 3.4) * pow(maxf(0.0, 1.0 - _age / 0.18), 2.0)
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
		var dimensions := Vector3(size * (0.5 if spark else 1.0), size * (0.5 if spark else 1.0), size * (3.0 if spark else 1.0))
		_fragments.set_instance_transform(index, Transform3D(orientation.scaled(dimensions), at))
		var color: Color = _profile.gold_color if spark else _profile.edge_color.lerp(_profile.steel_color, t / life)
		color.a = fade
		_fragments.set_instance_color(index, color)

class_name MineExplosionVFX
extends Node3D

## One self-expiring presentation root. All timing uses the simulation delta.
const PLUME: Shader = preload("res://assets/vfx/shaders/mine_plume.gdshader")
const RING: Shader = preload("res://assets/vfx/shaders/mine_ring.gdshader")
const FLASH: Shader = preload("res://assets/vfx/shaders/sword_contact.gdshader")
const GROUND: Shader = preload("res://assets/vfx/shaders/mine_ground_imprint.gdshader")
var _profile: MineVFXProfile
var _age: float = 0.0
var _duration: float = 1.5
var _materials: Array[ShaderMaterial] = []
var _lobes: Array[Dictionary] = []
var _embers: MultiMesh
var _velocities: Array[Vector3] = []
var _light: OmniLight3D
var _volume: MeshInstance3D
var _ground: Node3D

func setup(profile: MineVFXProfile, blast_radius: float) -> void:
	_profile = profile
	_duration = maxf(profile.smoke_lifetime + 0.24, maxf(profile.ember_lifetime, profile.fire_lifetime + 0.08))
	_duration = maxf(_duration, profile.wave_lifetime)
	_duration = maxf(_duration, profile.ground_lifetime)
	var size: float = maxf(blast_radius, 0.1) / 4.5
	# Three offset rolling fire lobes, one central body, then cooling smoke.
	for index in range(3):
		var angle: float = float(index) * TAU / 3.0 + 0.35
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		_add_lobe(true, outward * 0.3 * size + Vector3.UP * 0.05,
			outward * 2.5 * size + Vector3.UP * 1.1, Vector2(2.5, 2.5) * size * profile.fire_scale,
			0.025 * float(index), profile.fire_lifetime * 0.9, 0.9, angle * 0.12)
	_add_lobe(true, Vector3.UP * 0.45, Vector3.UP * 1.4,
		Vector2(3.5, 3.5) * size * profile.fire_scale, 0.0, profile.fire_lifetime, 1.0, -0.08)
	for index in range(5):
		var angle: float = float(index) * 2.39996
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		_add_lobe(false, outward * 0.5 * size + Vector3.UP * (0.1 + float(index % 2) * 0.45),
			outward * 1.4 * size + Vector3.UP * (0.9 + float(index % 3) * 0.3),
			Vector2(2.4, 2.4) * size * profile.smoke_scale,
			0.09 + float(index) * 0.022, profile.smoke_lifetime, profile.smoke_opacity, angle * 0.065)
	# Flattened low dust lobes connect the impulse to the ground.
	for index in range(6):
		var angle: float = float(index) * TAU / 6.0
		var outward := Vector3(cos(angle), 0.0, sin(angle))
		_add_lobe(false, outward * 0.35 * size + Vector3.DOWN * 0.55,
			outward * 5.0 * size + Vector3.UP * 0.15, Vector2(2.3, 0.9) * size,
			0.02, 0.7, 0.42, 0.0, true)
	_add_flash(size)
	_add_ring(blast_radius)
	_add_ground_imprint(blast_radius)
	_add_embers(size)
	_light = OmniLight3D.new()
	_light.light_color = profile.hot_color
	_light.light_energy = profile.light_energy
	_light.omni_range = blast_radius * 1.3
	_light.shadow_enabled = false
	add_child(_light)
	_light.position.y = 0.8
	_update_visuals()

func _add_lobe(is_fire: bool, origin: Vector3, velocity: Vector3, size: Vector2,
		delay: float, life: float, opacity: float, turn: float, dust: bool = false) -> void:
	var material := ShaderMaterial.new()
	material.shader = PLUME
	material.set_shader_parameter("artwork", _profile.fire_texture if is_fire else _profile.smoke_texture)
	material.set_shader_parameter("base_color", _profile.flame_color if is_fire else (_profile.dust_color if dust else _profile.smoke_color))
	material.set_shader_parameter("hot_color", _profile.hot_color)
	material.set_shader_parameter("fire", is_fire)
	material.set_shader_parameter("intensity", _profile.emission)
	material.set_shader_parameter("lifetime", life)
	material.set_shader_parameter("delay", delay)
	material.set_shader_parameter("opacity", opacity)
	material.set_shader_parameter("turn", turn)
	var sprite: MeshInstance3D = _quad(size, material)
	_lobes.append({"node": sprite, "origin": origin, "velocity": velocity, "delay": delay, "life": life, "fire": is_fire})

func _quad(size: Vector2, material: ShaderMaterial) -> MeshInstance3D:
	var sprite := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	sprite.mesh = quad
	sprite.material_override = material
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sprite.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(sprite)
	_materials.append(material)
	return sprite

func _add_flash(size: float) -> void:
	var material := ShaderMaterial.new()
	material.shader = FLASH
	material.set_shader_parameter("artwork", _profile.flash_texture)
	material.set_shader_parameter("contact_color", _profile.hot_color)
	material.set_shader_parameter("lifetime", 0.11)
	material.set_shader_parameter("intensity", _profile.emission * 1.25)
	var sprite: MeshInstance3D = _quad(Vector2.ONE * size * 3.3, material)
	sprite.position.y = 0.3
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		sprite.look_at(camera.global_position, Vector3.UP)

func _add_ring(radius: float) -> void:
	# A single bounded 3D density field. No camera-facing peripheral sprites.
	var reach: float = maxf(radius, 0.1)
	var half_height: float = reach * 0.17
	var material := ShaderMaterial.new()
	material.shader = RING
	material.set_shader_parameter("artwork", _profile.ring_texture)
	material.set_shader_parameter("tint", _profile.flame_color)
	material.set_shader_parameter("hot_color", _profile.hot_color)
	material.set_shader_parameter("opacity", _profile.ring_opacity)
	material.set_shader_parameter("edge_lifetime", _profile.wave_edge_lifetime)
	material.set_shader_parameter("hold_time", _profile.wave_hold_time)
	material.set_shader_parameter("lifetime", _profile.wave_lifetime)
	material.set_shader_parameter("radius", reach)
	material.set_shader_parameter("half_height", half_height)
	material.set_shader_parameter("burst_origin", global_position)
	material.render_priority = -1
	var bounds := BoxMesh.new()
	bounds.size = Vector3(reach * 2.0, half_height * 2.0, reach * 2.0)
	_volume = MeshInstance3D.new()
	_volume.name = "BlastVolume"
	_volume.mesh = bounds
	_volume.material_override = material
	_volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_volume.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_volume)
	_materials.append(material)

func _add_embers(size: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.075
	mesh.height = 0.28
	mesh.radial_segments = 4
	mesh.rings = 1
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.emission_enabled = true
	material.emission = _profile.flame_color
	material.emission_energy_multiplier = _profile.emission
	mesh.material = material
	_embers = MultiMesh.new()
	_embers.transform_format = MultiMesh.TRANSFORM_3D
	_embers.use_colors = true
	_embers.mesh = mesh
	_embers.instance_count = clampi(_profile.ember_count, 0, 40)
	var renderer := MultiMeshInstance3D.new()
	renderer.multimesh = _embers
	renderer.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	renderer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(renderer)
	for index in range(_embers.instance_count):
		var angle: float = float(index) * 2.39996
		var speed: float = (3.5 + float(index % 7) * 0.55) * size
		_velocities.append(Vector3(cos(angle) * speed, 2.1 + float(index % 5) * 0.7, sin(angle) * speed))

func _add_ground_imprint(radius: float) -> void:
	_ground = Node3D.new()
	_ground.name = "GroundImprint"
	add_child(_ground)
	if _profile.ground_opacity <= 0.0:
		return
	var reach: float = maxf(radius, 0.1)
	var affected := AABB(global_position - Vector3.ONE * reach, Vector3.ONE * reach * 2.0)
	var material := ShaderMaterial.new()
	material.shader = GROUND
	material.render_priority = -2
	material.set_shader_parameter("burst_origin", global_position)
	material.set_shader_parameter("radius", reach)
	material.set_shader_parameter("lifetime", _profile.ground_lifetime)
	material.set_shader_parameter("opacity", _profile.ground_opacity)
	material.set_shader_parameter("ember_color", _profile.flame_color)
	_materials.append(material)
	# Terrain is registered by MapGenerator. Query once at detonation, never per
	# frame. Share its mesh: no copying, sampling grid, ray casts or floating quad.
	for receiver: Node in get_tree().get_nodes_in_group("terrain"):
		for child: Node in receiver.get_children():
			var surface := child as MeshInstance3D
			if not surface or not surface.mesh:
				continue
			var world_bounds: AABB = surface.global_transform * surface.get_aabb()
			if not affected.intersects(world_bounds):
				continue
			var imprint := MeshInstance3D.new()
			imprint.mesh = surface.mesh
			imprint.material_override = material
			imprint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			imprint.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
			_ground.add_child(imprint)
			imprint.global_transform = surface.global_transform
			# Streaming must never leave a scorch patch on an unloaded surface.
			surface.tree_exiting.connect(imprint.queue_free, CONNECT_ONE_SHOT)

func _process(delta: float) -> void:
	_age += delta
	if _age >= _duration:
		queue_free()
		return
	_update_visuals()

func _update_visuals() -> void:
	_volume.visible = _age < _profile.wave_lifetime
	_ground.visible = _age < _profile.ground_lifetime
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("age", _age)
	for lobe: Dictionary in _lobes:
		var sprite: MeshInstance3D = lobe.node
		var elapsed: float = maxf(0.0, _age - float(lobe.delay))
		var phase: float = clampf(elapsed / float(lobe.life), 0.0, 1.0)
		sprite.visible = _age >= float(lobe.delay) and phase < 1.0
		sprite.position = lobe.origin + lobe.velocity * (1.0 - exp(-elapsed * 2.6)) / 2.6
		var growth: float = lerpf(0.42, 1.25, 1.0 - exp(-elapsed * 13.0)) if lobe.fire else lerpf(0.75, 1.5, phase)
		sprite.scale = Vector3.ONE * growth
	var t: float = clampf(_age / _profile.ember_lifetime, 0.0, 1.0)
	for index in range(_velocities.size()):
		var velocity: Vector3 = _velocities[index]
		var at: Vector3 = velocity * (1.0 - exp(-_age * 2.3)) / 2.3
		at.y = maxf(-0.65, velocity.y * _age - 5.0 * _age * _age)
		var shrink: float = (1.0 - t * t) * (0.7 + float(index % 3) * 0.2)
		var basis := Basis(Vector3(0.4, 1.0, 0.3).normalized(), _age * 8.0 + float(index)).scaled(Vector3.ONE * shrink)
		_embers.set_instance_transform(index, Transform3D(basis, at))
		var tint: Color = _profile.hot_color.lerp(_profile.flame_color, smoothstep(0.0, 0.65, t))
		tint.a = 1.0 - smoothstep(0.2, 1.0, t)
		_embers.set_instance_color(index, tint)
	_light.light_energy = _profile.light_energy * pow(maxf(0.0, 1.0 - _age / 0.24), 2.0)

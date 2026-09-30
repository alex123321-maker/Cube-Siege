class_name SwordBladeTrail
extends MeshInstance3D

## A bounded world-space history of the displayed blade, owned by presentation.
## One reusable mesh per bound warrior; no damage, timers, or scene searches.
const TRAIL_SHADER: Shader = preload("res://assets/vfx/shaders/sword_blade_trail.gdshader")
const CLEAVE_ARTWORK: Texture2D = preload("res://assets/vfx/cleave/cleave_ribbon_v2.png")
const MAX_SAMPLES: int = 32
const BREAK_DISTANCE: float = 2.0
var _profile: SwordVFXProfile
var _base_anchor: Node3D
var _tip_anchor: Node3D
var _surface: ImmediateMesh = ImmediateMesh.new()
var _bases: Array[Vector3] = []
var _tips: Array[Vector3] = []
var _times: Array[float] = []
var _clock: float = 0.0
var _emitting: bool = false
var _cleave: bool = false

func setup(profile: SwordVFXProfile, base_anchor: Node3D, tip_anchor: Node3D) -> void:
	_profile = profile
	_base_anchor = base_anchor
	_tip_anchor = tip_anchor
	top_level = true
	global_transform = Transform3D.IDENTITY
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	process_priority = 100
	mesh = _surface
	var material := ShaderMaterial.new()
	material.shader = TRAIL_SHADER
	material.set_shader_parameter("artwork", profile.ribbon_texture)
	material.set_shader_parameter("body_color", profile.body_color)
	material.set_shader_parameter("edge_color", profile.edge_color)
	material.set_shader_parameter("intensity", profile.emission)
	material.set_shader_parameter("opacity", profile.blade_trail_opacity)
	material_override = material
	# Prime Godot's interpolation pumps before the first attack.
	_base_anchor.get_global_transform_interpolated()
	_tip_anchor.get_global_transform_interpolated()

func set_attack_phase(active: bool, animation_time: float, cleave: bool = false) -> void:
	var start: float = 0.12 if cleave else _profile.blade_trail_start
	var end: float = 0.30 if cleave else _profile.blade_trail_end
	_emitting = active and animation_time >= start and animation_time <= end
	if _cleave != cleave:
		_cleave = cleave
		var material: ShaderMaterial = material_override as ShaderMaterial
		material.set_shader_parameter("artwork", CLEAVE_ARTWORK if cleave else _profile.ribbon_texture)
		material.set_shader_parameter("artwork_rect", Vector4(0.025, 0.25, 0.948, 0.485)
			if cleave else Vector4(0.16, 0.28, 0.74, 0.46))
	(material_override as ShaderMaterial).set_shader_parameter("intensity", _profile.emission * (1.65 if cleave else 1.0))

func reset_trail() -> void:
	_emitting = false
	_bases.clear()
	_tips.clear()
	_times.clear()
	_surface.clear_surfaces()

func _process(delta: float) -> void:
	if not _profile:
		return
	if not is_instance_valid(_base_anchor) or not is_instance_valid(_tip_anchor):
		reset_trail()
		set_process(false)
		return
	if not _tip_anchor.is_visible_in_tree():
		reset_trail()
		return
	_clock += delta
	while not _times.is_empty() and _clock - _times[0] >= _profile.blade_trail_lifetime:
		_pop_oldest()
	if _emitting:
		var blade_base: Vector3 = _base_anchor.get_global_transform_interpolated().origin
		var blade_tip: Vector3 = _tip_anchor.get_global_transform_interpolated().origin
		# A teleport must not leave a bright strip across the map.
		if not _tips.is_empty() and (blade_tip.distance_to(_tips[-1]) > BREAK_DISTANCE \
				or blade_base.distance_to(_bases[-1]) > BREAK_DISTANCE):
			_bases.clear()
			_tips.clear()
			_times.clear()
		if _tips.is_empty() or blade_tip.distance_squared_to(_tips[-1]) > 0.000001 \
				or blade_base.distance_squared_to(_bases[-1]) > 0.000001:
			_bases.append(blade_base)
			_tips.append(blade_tip)
			_times.append(_clock)
			if _times.size() > MAX_SAMPLES:
				_pop_oldest()
	_rebuild_surface()

func _pop_oldest() -> void:
	_bases.pop_front()
	_tips.pop_front()
	_times.pop_front()

func _rebuild_surface() -> void:
	_surface.clear_surfaces()
	if _times.size() < 2:
		return
	_surface.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for index in range(_times.size()):
		var freshness: float = clampf(1.0 - (_clock - _times[index]) / _profile.blade_trail_lifetime, 0.0, 1.0)
		var u: float = float(index) / float(_times.size() - 1)
		_surface.surface_set_color(Color(1.0, 1.0, 1.0, freshness))
		_surface.surface_set_uv(Vector2(u, 0.0))
		_surface.surface_add_vertex(_tips[index])
		_surface.surface_set_color(Color(1.0, 1.0, 1.0, freshness))
		_surface.surface_set_uv(Vector2(u, 1.0))
		_surface.surface_add_vertex(_bases[index])
	_surface.surface_end()

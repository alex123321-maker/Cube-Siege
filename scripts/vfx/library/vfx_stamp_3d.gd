class_name VFXStamp3D
extends Node3D

## Small reusable accent. Instantiate a preset, place it, then optionally bind_target.
## Uses one delta clock and one per-instance material; needs no timer or manager.
@export var profile: VFXStampProfile
var _age: float = 0.0
var _quad: MeshInstance3D
var _material: StandardMaterial3D
var _target: Node3D
var _target_offset: Vector3
var _bound_to_target: bool = false

func _ready() -> void:
	if not profile or not profile.texture or profile.lifetime <= 0.0:
		push_error("VFXStamp3D requires a texture and positive lifetime")
		queue_free()
		return
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_material.billboard_keep_scale = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_texture = profile.texture
	_material.albedo_color = Color(profile.tint, 0.0)
	_material.emission_enabled = profile.emission > 0.0
	_material.emission = profile.tint
	_material.emission_energy_multiplier = profile.emission
	_material.emission_texture = profile.texture
	_quad = MeshInstance3D.new()
	_quad.mesh = mesh
	_quad.material_override = _material
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)
	_step(0.0)

func bind_target(target: Node3D) -> void:
	_target = target
	_bound_to_target = is_instance_valid(target)
	if _bound_to_target:
		_target_offset = global_position - target.global_position

func _process(delta: float) -> void:
	_step(delta)

func _step(delta: float) -> void:
	if not is_instance_valid(_quad):
		return
	_age += delta
	if _age >= profile.lifetime or (_bound_to_target and not is_instance_valid(_target)):
		queue_free()
		return
	if _bound_to_target:
		global_position = _target.global_position + _target_offset
	var t: float = clampf(_age / profile.lifetime, 0.0, 1.0)
	var expansion: float = 1.0 - pow(1.0 - t, 2.0)
	var size: Vector2 = profile.start_size.lerp(profile.end_size, expansion)
	_quad.scale = Vector3(size.x, size.y, 1.0)
	_quad.position = profile.drift * _age
	var rise: float = minf(1.0, _age / maxf(0.001, minf(profile.rise_seconds, profile.lifetime)))
	var opacity: float = rise * pow(1.0 - t, 1.4) * profile.tint.a
	_material.albedo_color = Color(profile.tint, opacity)
	_material.emission_energy_multiplier = profile.emission * rise * (1.0 - t)

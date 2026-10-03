extends Node3D
class_name CampfireVisual

## A small warm flame silhouette; quiet mint/gold boundary communicates healing.
@onready var warm_light: OmniLight3D = $WarmLight
@onready var embers: GPUParticles3D = $Embers

var flame: Node3D
var _time: float = 0.0
var _aura: MultiMeshInstance3D = null
var _active: bool = true

func setup(radius: float, flame_model: Node3D) -> void:
	flame = flame_model
	_aura = MultiMeshInstance3D.new()
	_aura.name = "HealingBoundary"
	var marker: BoxMesh = BoxMesh.new()
	marker.size = Vector3(0.06, 0.025, 0.30)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.60, 0.89, 0.60, 0.30)
	material.no_depth_test = false
	marker.material = material
	var markers: MultiMesh = MultiMesh.new()
	markers.transform_format = MultiMesh.TRANSFORM_3D
	markers.mesh = marker
	markers.instance_count = 40
	for index: int in range(markers.instance_count):
		var angle: float = TAU * float(index) / float(markers.instance_count)
		var at: Vector3 = Vector3(cos(angle) * radius, 0.035, sin(angle) * radius)
		markers.set_instance_transform(index, Transform3D(Basis(Vector3.UP, -angle), at))
	_aura.multimesh = markers
	_aura.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_aura.visible = false
	add_child(_aura)

func set_aura_visible(enabled: bool) -> void:
	if is_instance_valid(_aura):
		_aura.visible = enabled and _active

func _process(delta: float) -> void:
	if not _active or not is_instance_valid(flame):
		return
	_time += delta
	var flicker: float = sin(_time * 9.0) * 0.5 + sin(_time * 15.7) * 0.25
	flame.scale = Vector3(1.0 - flicker * 0.06, 1.0 + flicker * 0.16, 1.0 + flicker * 0.05)
	flame.rotation.y = sin(_time * 3.1) * 0.06
	warm_light.light_energy = 0.90 + flicker * 0.12

func extinguish() -> void:
	_active = false
	embers.emitting = false
	flame.visible = false
	warm_light.visible = false
	set_aura_visible(false)

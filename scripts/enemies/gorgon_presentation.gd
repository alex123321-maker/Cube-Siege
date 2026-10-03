extends Node3D
class_name GorgonPresentation

## Presentation only. The boss supplies its phase/progress; collision, attack
## commitment, movement and damage remain in the boss controller.
@onready var body: Node3D = $StoneGorgon/body
@onready var head: Node3D = $StoneGorgon/head
@onready var arm_left: Node3D = $StoneGorgon/arm_left
@onready var arm_right: Node3D = $StoneGorgon/arm_right
@onready var leg_left: Node3D = $StoneGorgon/leg_left
@onready var leg_right: Node3D = $StoneGorgon/leg_right

var _rest: Dictionary[Node3D, Transform3D] = {}
var _clock: float = 0.0
var _smash_time: float = 0.0
var _dead: bool = false

func _ready() -> void:
	# Upper-body pieces follow the waist while hooves retain their own stance.
	head.reparent(body, true)
	arm_left.reparent(body, true)
	arm_right.reparent(body, true)
	for part: Node3D in [body, head, arm_left, arm_right, leg_left, leg_right]:
		_rest[part] = part.transform
	var face: MeshInstance3D = head as MeshInstance3D
	if face:
		for surface in range(face.mesh.get_surface_count()):
			var material: StandardMaterial3D = face.get_active_material(surface) as StandardMaterial3D
			if material and material.resource_name in ["flame", "hot"]:
				var warm_eye: StandardMaterial3D = material.duplicate() as StandardMaterial3D
				warm_eye.emission_enabled = true
				warm_eye.emission_energy_multiplier = 2.2
				face.set_surface_override_material(surface, warm_eye)

func update_pose(delta: float, phase: StringName, progress: float, horizontal_speed: float) -> void:
	if _dead:
		return
	_clock += delta
	_smash_time = maxf(0.0, _smash_time - delta)
	for part: Node3D in _rest:
		part.transform = _rest[part]
	match phase:
		&"windup":
			var commitment: float = smoothstep(0.0, 0.8, progress)
			body.position.y -= commitment * 0.13
			body.rotation.x = -0.24 * commitment
			head.rotation.x = -0.22 * commitment
			arm_left.rotation = Vector3(0.25 * commitment, 0.0, -0.08 * commitment)
			arm_right.rotation = Vector3(0.25 * commitment, 0.0, 0.08 * commitment)
			leg_left.rotation = Vector3(0.10 * commitment, 0.0, -0.04 * commitment)
			leg_right.rotation = Vector3(0.10 * commitment, 0.0, 0.04 * commitment)
			# The last bracing beats are much smaller than the threat footprint.
			body.position.y += sin(_clock * 32.0) * 0.008 * commitment
		&"charge":
			var hoof_beat: float = sin(_clock * 25.0)
			body.position.y -= 0.10 - absf(hoof_beat) * 0.035
			body.rotation.x = -0.32
			head.rotation.x = -0.30
			arm_left.rotation.x = 0.40
			arm_right.rotation.x = 0.40
			leg_left.rotation.x = hoof_beat * 0.40
			leg_right.rotation.x = -hoof_beat * 0.40
		&"recovery":
			var slumped: float = 1.0 - smoothstep(0.65, 1.0, progress)
			body.position.y -= slumped * 0.16
			body.rotation.x = -slumped * 0.13
			head.rotation.x = -slumped * 0.36
			arm_left.rotation.z = -slumped * 0.10
			arm_right.rotation.z = slumped * 0.10
		_:
			if horizontal_speed > 0.15:
				var stride: float = sin(_clock * minf(12.0, horizontal_speed * 2.2))
				leg_left.rotation.x = stride * 0.25
				leg_right.rotation.x = -stride * 0.25
				arm_left.rotation.x = -stride * 0.11
				arm_right.rotation.x = stride * 0.11
				body.position.y += absf(stride) * 0.035
				body.rotation.z = stride * 0.018
			else:
				body.position.y += sin(_clock * 2.2) * 0.025
			if _smash_time > 0.0:
				var impact: float = _smash_time / 0.30
				body.rotation.x -= impact * 0.12
				arm_left.rotation.x += impact * 0.40
				arm_right.rotation.x += impact * 0.40

func play_smash() -> void:
	_smash_time = 0.30

func play_death() -> void:
	if _dead:
		return
	_dead = true
	var fall: Tween = create_tween()
	fall.set_parallel(true)
	fall.tween_property(body, "rotation:x", -0.45, 0.25)
	fall.tween_property(body, "position:y", _rest[body].origin.y - 0.40, 0.25)
	fall.tween_property(arm_left, "rotation:z", -0.3, 0.25)
	fall.tween_property(arm_right, "rotation:z", 0.3, 0.25)

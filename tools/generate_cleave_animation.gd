extends SceneTree

## Author a dedicated full-body clip against the production warrior's rigid rig.
const PLAYER: PackedScene = preload("res://scenes/player.tscn")
const OUTPUT: String = "res://assets/animations/actions/warrior_cleave.tres"

func _initialize() -> void:
	call_deferred("_generate")

func _generate() -> void:
	var player: Node3D = PLAYER.instantiate() as Node3D
	root.add_child(player)
	player.set_physics_process(false)
	var model: Node3D = player.get_node("Visuals/HeroWarrior") as Node3D
	var clip := Animation.new()
	clip.resource_name = "WarriorCleave"
	clip.length = 0.82
	_rotation(clip, ^"root", [Vector4(0, 0, 0, 0), Vector4(0.20, 0, -10, 0),
		Vector4(0.28, 0, 3, 0), Vector4(0.38, 0, 10, 0), Vector4(0.58, 0, 4, 0), Vector4(0.82, 0, 0, 0)])
	_rotation(clip, ^"root/torso", [Vector4(0, 0, 0, 0), Vector4(0.10, -5, -38, 4),
		Vector4(0.20, -8, -64, 6), Vector4(0.24, -6, -58, 4), Vector4(0.28, 6, -5, -2),
		Vector4(0.34, 10, 64, -6), Vector4(0.40, 7, 54, -4), Vector4(0.52, 5, 36, -3),
		Vector4(0.66, 2, 15, -1), Vector4(0.82, 0, 0, 0)])
	_rotation(clip, ^"root/torso/head", [Vector4(0, 0, 0, 0), Vector4(0.20, 2, 30, 0),
		Vector4(0.28, -3, 5, 0), Vector4(0.34, -2, -24, 0), Vector4(0.58, 0, -10, 0), Vector4(0.82, 0, 0, 0)])
	var arm: Node3D = model.get_node("root/torso/right_arm") as Node3D
	# The imported model faces +Z locally; its wrapper rotates it 180 degrees.
	# Raise the hand through shoulder flexion, with bounded twist and abduction.
	# A shortest-arc rotation toward the tip can instead put the hand behind it.
	var arm_rest: Vector3 = arm.rotation_degrees
	_rotation(clip, ^"root/torso/right_arm", [Vector4(0, arm_rest.x, arm_rest.y, arm_rest.z),
		Vector4(0.10, -42, -12, -10), Vector4(0.20, -62, -18, -12),
		Vector4(0.24, -64, -12, -10), Vector4(0.28, -58, 0, -8),
		Vector4(0.34, -52, 16, -6), Vector4(0.40, -48, 18, -5),
		Vector4(0.58, -28, 8, -6), Vector4(0.82, arm_rest.x, arm_rest.y, arm_rest.z)])
	var left: Node3D = model.get_node("root/torso/left_arm") as Node3D
	var rest_left: Vector3 = left.rotation_degrees
	_rotation(clip, ^"root/torso/left_arm", [Vector4(0, rest_left.x, rest_left.y, rest_left.z),
		Vector4(0.20, -8, -10, -6), Vector4(0.28, -12, -5, -6), Vector4(0.34, -6, 10, -4),
		Vector4(0.58, -4, 6, 2), Vector4(0.82, rest_left.x, rest_left.y, rest_left.z)])
	_rotation(clip, ^"root/right_leg", [Vector4(0, 0, 0, 0), Vector4(0.20, 10, 0, -7),
		Vector4(0.34, -8, 0, -4), Vector4(0.58, -3, 0, -2), Vector4(0.82, 0, 0, 0)])
	_rotation(clip, ^"root/left_leg", [Vector4(0, 0, 0, 0), Vector4(0.20, -8, 0, 5),
		Vector4(0.34, 12, 0, 4), Vector4(0.58, 4, 0, 2), Vector4(0.82, 0, 0, 0)])
	var torso: Node3D = model.get_node("root/torso") as Node3D
	var position_track: int = clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(position_track, ^"root/torso")
	for key: Vector4 in [Vector4(0, 0, 0, 0), Vector4(0.20, 0, -0.12, 0.10),
		Vector4(0.28, 0, -0.04, -0.12), Vector4(0.34, 0, -0.06, -0.16), Vector4(0.58, 0, -0.02, -0.04), Vector4(0.82, 0, 0, 0)]:
		clip.track_insert_key(position_track, key.x, torso.position + Vector3(key.y, key.z, key.w))
	DirAccess.make_dir_recursive_absolute("res://assets/animations/actions")
	var result: Error = ResourceSaver.save(clip, OUTPUT)
	print("CLEAVE_ANIMATION saved=", result == OK, " tracks=", clip.get_track_count(), " length=", clip.length)
	player.queue_free()
	await process_frame
	quit(0 if result == OK else 2)

func _rotation(clip: Animation, path: NodePath, keys: Array[Vector4]) -> void:
	var track: int = clip.add_track(Animation.TYPE_ROTATION_3D)
	clip.track_set_path(track, path)
	for key: Vector4 in keys:
		clip.track_insert_key(track, key.x, Quaternion.from_euler(Vector3(deg_to_rad(key.y), deg_to_rad(key.z), deg_to_rad(key.w))))

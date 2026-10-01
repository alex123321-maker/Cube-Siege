extends SceneTree

## Report actual bound rigs; declarations of imported forward are checked against wrappers.
const PLAYER: PackedScene = preload("res://scenes/player.tscn")
const ENEMIES: Array[PackedScene] = [preload("res://scenes/enemy_dummy.tscn"),
	preload("res://scenes/enemies/ranged_skirmisher.tscn"), preload("res://scenes/enemies/siege_breaker.tscn")]
var _records: Array[Dictionary] = []
var _failed: bool = false
var _output: String = ""

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--report="):
			_output = argument.trim_prefix("--report=")
	call_deferred("_inspect")

func _inspect() -> void:
	var player: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	root.add_child(player)
	player.set_physics_process(false)
	player.set_process_input(false)
	for index in range(3):
		player.set_class(index, false)
		var model: Node3D = player.presentation.active_model
		var profile: CharacterAnimationProfile = player.presentation.animation_profile
		var record: Dictionary = _record(model, player, Vector3.BACK if index == 0 else Vector3.FORWARD)
		record["class_id"] = index
		record["animation_root"] = str(player.presentation.anim_player.root_node)
		record["clips"] = Array(player.presentation.anim_player.get_animation_list())
		var anchors: Dictionary = {}
		for path: NodePath in [profile.torso_path, profile.head_path, profile.right_arm_path,
				profile.left_arm_path, profile.blade_base_path, profile.blade_tip_path]:
			if path.is_empty():
				continue
			var node: Node3D = model.get_node_or_null(path) as Node3D
			if not node:
				_failed = true
				anchors[str(path)] = "MISSING"
			else:
				anchors[str(path)] = {"local_position": _vector(node.position),
					"current_local_rotation_degrees": _vector(node.rotation_degrees)}
		record["anchors"] = anchors
		_records.append(record)
	player.queue_free()
	for scene: PackedScene in ENEMIES:
		var enemy: EnemyBase = scene.instantiate() as EnemyBase
		root.add_child(enemy)
		enemy.set_physics_process(false)
		_records.append(_record(enemy.presentation.model_root, enemy, Vector3.BACK))
		enemy.queue_free()
	await process_frame
	var report: Dictionary = {"schema_version": 1, "engine": Engine.get_version_info().string,
		"forward_contract_pass": not _failed, "models": _records,
		"limitation": "Forward is a known rig declaration, not inferred anatomy. Local joint snapshots include the current presentation pose, not canonical bone rest. Inspect front and weapon-side footage."}
	if not _output.is_empty():
		var file: FileAccess = FileAccess.open(_output, FileAccess.WRITE)
		if not file:
			push_error("Cannot write rig report: " + _output)
			quit(2)
			return
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("VFX_RIG_REPORT ", JSON.stringify(report))
	quit(2 if _failed else 0)

func _record(model: Node3D, actor: Node3D, imported_forward: Vector3) -> Dictionary:
	var actor_forward: Vector3 = actor.global_basis.inverse() * model.global_basis * imported_forward
	var agreement: float = actor_forward.normalized().dot(Vector3.FORWARD)
	_failed = _failed or agreement < 0.99
	return {"model": str(model.name), "source_scene": model.scene_file_path,
		"imported_forward": _vector(imported_forward), "wrapper_rotation_degrees": _vector(model.rotation_degrees),
		"actor_local_forward": _vector(actor_forward), "forward_dot_expected": agreement}

func _vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

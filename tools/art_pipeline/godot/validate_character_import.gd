extends SceneTree

const EXPECTED_ANIMATIONS := ["idle", "walk", "attack", "special", "utility", "block", "ultimate"]
const EXPECTED_HOOKS := ["root", "torso", "head", "right_arm", "left_arm", "right_leg", "left_leg", "sword", "shield"]
const EXPECTED_LENGTHS := {
	"idle": 1.2,
	"walk": 0.8,
	"attack": 0.35,
	"special": 0.5,
	"utility": 0.5,
	"block": 0.5,
	"ultimate": 0.8,
}

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var asset_path: String = _argument(args, "--asset", "")
	var report_path: String = _argument(args, "--report", "")
	if asset_path.is_empty():
		_fail("Missing --asset res://path")
		return
	var scene: PackedScene = load(asset_path) as PackedScene
	if scene == null:
		_fail("Could not load %s" % asset_path)
		return
	var instance: Node = scene.instantiate()
	root.add_child(instance)
	var player: AnimationPlayer = instance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var meshes: Array[Node] = instance.find_children("*", "MeshInstance3D", true, false)
	var missing_hooks := PackedStringArray()
	for hook: String in EXPECTED_HOOKS:
		if instance.find_child(hook, true, false) == null:
			missing_hooks.append(hook)
	var missing_animations := PackedStringArray()
	var bad_lengths := PackedStringArray()
	if player:
		for animation_name: String in EXPECTED_ANIMATIONS:
			if not player.has_animation(animation_name):
				missing_animations.append(animation_name)
			else:
				var actual: float = player.get_animation(animation_name).length
				if not is_equal_approx(actual, EXPECTED_LENGTHS[animation_name]):
					bad_lengths.append("%s=%0.3f" % [animation_name, actual])
	var checks := {
		"scene_instantiates": true,
		"mesh_count_at_least_20": meshes.size() >= 20,
		"weapon_hooks_own_meshes": _weapon_meshes_present(instance),
		"hooks_preserved": missing_hooks.is_empty(),
		"animations_preserved": player != null and missing_animations.is_empty(),
		"animation_timings_preserved": bad_lengths.is_empty(),
		"idle_loops": _loops(player, "idle"),
		"walk_loops": _loops(player, "walk"),
	}
	var ok: bool = not checks.values().has(false)
	var report := {
		"asset": asset_path,
		"checks": checks,
		"mesh_count": meshes.size(),
		"rig_type": "rigid node hierarchy",
		"missing_hooks": missing_hooks,
		"missing_animations": missing_animations,
		"bad_lengths": bad_lengths,
		"ok": ok,
	}
	if not report_path.is_empty():
		var file := FileAccess.open(report_path, FileAccess.WRITE)
		if file == null:
			_fail("Cannot write validation report: " + report_path)
			return
		file.store_string(JSON.stringify(report, "  "))
	print("ART_PIPELINE_CHARACTER_VALIDATION=" + JSON.stringify(report))
	instance.free()
	quit(0 if ok else 1)

func _loops(player: AnimationPlayer, name: String) -> bool:
	return player != null and player.has_animation(name) and player.get_animation(name).loop_mode == Animation.LOOP_LINEAR

func _weapon_meshes_present(instance: Node) -> bool:
	for path: String in ["root/torso/right_arm/sword", "root/torso/left_arm/shield"]:
		var hook: Node = instance.get_node_or_null(path)
		if hook == null or hook.find_children("*", "MeshInstance3D", true, false).is_empty():
			return false
	return true

func _argument(args: PackedStringArray, name: String, fallback: String) -> String:
	var index: int = args.find(name)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback

func _fail(message: String) -> void:
	push_error(message)
	quit(1)

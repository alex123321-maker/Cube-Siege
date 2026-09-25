extends SceneTree
## Paired OFF/ON samples in the actual main scene, with all gameplay systems running.
var player: CharacterBody3D
var tick: int = 0
var off_samples: PackedFloat64Array = PackedFloat64Array()
var on_samples: PackedFloat64Array = PackedFloat64Array()

func _initialize() -> void:
	seed(12)
	call_deferred("_start")

func _start() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	player = scene.get_node("Player") as CharacterBody3D
	player.set_class(0, false)
	Input.action_press("aim_up")

func _process(_delta: float) -> bool:
	if not is_instance_valid(player):
		return false
	tick += 1
	var cycle: int = tick / 240
	var enabled: bool = cycle % 2 == 1
	player.presentation.procedural_enabled = enabled
	var angle: float = float(tick % 240) / 240.0 * TAU
	Input.action_press("move_right", maxf(sin(angle), 0))
	Input.action_press("move_left", maxf(-sin(angle), 0))
	Input.action_press("move_down", maxf(cos(angle), 0))
	Input.action_press("move_up", maxf(-cos(angle), 0))
	if tick % 240 > 60:
		var usec: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000000
		if enabled: on_samples.append(usec)
		else: off_samples.append(usec)
	if tick >= 1440:
		var output: FileAccess = FileAccess.open("res://docs/animation/issue12/main_scene_performance.json", FileAccess.WRITE)
		output.store_string(JSON.stringify({"scene": "res://scenes/main.tscn", "frames": tick,
			"off": _summary(off_samples), "on": _summary(on_samples),
			"metric": "Whole-scene TIME_PROCESS microseconds; paired 4-second OFF/ON windows; first second discarded; includes world simulation and rendering. Not an isolated animation profiler."}, "  "))
		quit()
	return false

func _summary(values: PackedFloat64Array) -> Dictionary:
	values.sort()
	var total: float = 0
	for value: float in values: total += value
	return {"samples": values.size(), "mean_usec": total / values.size(),
		"median_usec": values[values.size() / 2], "p95_usec": values[int(values.size() * 0.95)]}

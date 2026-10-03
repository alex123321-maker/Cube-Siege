extends SceneTree

## Run this IDENTICAL harness against two real game checkouts. No subsystem is
## disabled to imitate the baseline. Each scenario has a fresh, seeded scene.
const MOB_PATHS: Array[String] = ["res://scenes/enemy_dummy.tscn", "res://scenes/enemies/ranged_skirmisher.tscn", "res://scenes/enemies/siege_breaker.tscn", "res://scenes/enemies/boss_gorgon.tscn"]
const WALL_PATH: String = "res://scenes/prefabs/wood_wall.tscn"

class Target extends Node3D:
	func take_damage(_amount: float, _source: Node = null, _knockback: Vector3 = Vector3.ZERO) -> void:
		pass

class Samples extends RefCounted:
	var recording: bool = false
	var start_us: int = 0
	var callbacks_ms: Array[float] = []
	var engine_physics_ms: Array[float] = []
	var memory_bytes: Array[float] = []
	var frame_limit: int = 0
	var completed_us: int = 0
	var on_complete: Callable

class StartHook extends Node:
	var samples: Samples
	func _physics_process(_delta: float) -> void:
		if samples.recording:
			samples.start_us = Time.get_ticks_usec()

class EndHook extends Node:
	var samples: Samples
	func _physics_process(_delta: float) -> void:
		if samples.recording:
			samples.callbacks_ms.append(float(Time.get_ticks_usec() - samples.start_us) / 1000.0)
			samples.engine_physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
			samples.memory_bytes.append(Performance.get_monitor(Performance.MEMORY_STATIC))
			if samples.callbacks_ms.size() >= samples.frame_limit:
				samples.completed_us = Time.get_ticks_usec()
				samples.recording = false
				samples.on_complete.call()

var _samples: Samples = Samples.new()
var _label: String = "unspecified"
var _output: String = ""
var _frames: int = 240
var _counts: Array[int] = [14, 20, 100, 500]
var _reg: Node
var _results: Array[Dictionary] = []
var _final_rebuild_count: int = 0
var _final_compute_us: int = 0

func _snapshot_measurement_end() -> void:
	_final_rebuild_count = _counter()
	_final_compute_us = _compute_us()

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		match args[i]:
			"--label": _label = args[i + 1]
			"--output": _output = args[i + 1]
			"--frames": _frames = maxi(30, int(args[i + 1]))
			"--counts":
				_counts.clear()
				for value in args[i + 1].split(","):
					_counts.append(int(value))
	call_deferred("_run")

func _solid(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	parent.add_child(body)

func _height(x: int, z: int) -> int:
	return 1 if x >= -6 and x < 6 and z >= -6 and z < 6 else 0

func _field() -> Object:
	return _reg.get("monster_flowfield") if "monster_flowfield" in _reg else null

func _counter() -> int:
	var field: Object = _field()
	return int(field.call("get_rebuild_count")) if field and field.has_method("get_rebuild_count") else 0

func _compute_us() -> int:
	var field: Object = _field()
	return int(field.call("get_compute_time_us")) if field and field.has_method("get_compute_time_us") else 0

func _run() -> void:
	_reg = root.get_node_or_null("EntityRegistry")
	if not _reg:
		push_error("Missing registry")
		quit(1)
		return
	for count in _counts:
		for dynamic in [false, true]:
			_results.append(await _scenario(count, dynamic))
	var result: Dictionary = {"label": _label, "engine": Engine.get_version_info(), "os": OS.get_name(), "physics_hz": Engine.physics_ticks_per_second, "headless": DisplayServer.get_name() == "headless", "frames": _frames, "seed": 56, "results": _results}
	var file: FileAccess = FileAccess.open(_output, FileAccess.WRITE)
	if not file:
		push_error("Cannot write benchmark output: " + _output)
		quit(1)
		return
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("BENCHMARK_OUTPUT ", _output)
	quit(0)

func _scenario(count: int, dynamic: bool) -> Dictionary:
	_reg.call("clear")
	var arena: Node3D = Node3D.new()
	root.add_child(arena)
	current_scene = arena
	_solid(arena, Vector3(0, -0.5, 0), Vector3(80, 1, 80))
	_solid(arena, Vector3(0, 0.5, 0), Vector3(12, 1, 12))
	var target: Target = Target.new()
	target.position = Vector3(0, 1, 0)
	target.add_to_group("player")
	arena.add_child(target)
	if _reg.has_method("register_player"):
		_reg.call("register_player", target)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(24, 32, 24)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 42.0
	arena.add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var field: Object = _field()
	if field:
		field.call("set_height_lookup", _height)
		field.call("set_chunk_loaded_lookup", func(x: int, z: int) -> bool: return absi(x) < 40 and absi(z) < 40)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 56 + count
	var placed: Array[Vector3] = []
	var radii: Array[float] = []
	for i in range(count):
		var roll: float = rng.randf()
		var archetype: int = 0 if roll < 0.70 else (1 if roll < 0.85 else (2 if roll < 0.95 else 3))
		var radius: float = [0.4, 0.35, 0.7, 1.2][archetype]
		var spawn: Vector3 = Vector3.ZERO
		var found: bool = false
		for attempt in range(10000):
			var angle: float = rng.randf() * TAU
			var distance: float = rng.randf_range(8.0, 28.0)
			spawn = Vector3(cos(angle) * distance, 0, sin(angle) * distance)
			found = true
			for j in range(placed.size()):
				if spawn.distance_squared_to(placed[j]) < pow(radius + radii[j] + 0.05, 2.0):
					found = false
					break
			if found:
				break
		if not found:
			push_error("Spawn candidate limit reached")
			quit(1)
			return {}
		placed.append(spawn)
		radii.append(radius)
		var mob: CharacterBody3D = (load(MOB_PATHS[archetype]) as PackedScene).instantiate() as CharacterBody3D
		spawn.y = float(_height(int(floorf(spawn.x)), int(floorf(spawn.z)))) + [0.9, 0.9, 1.2, 1.5][archetype]
		mob.position = spawn
		arena.add_child(mob)
		mob.set("target_player", target)
	var start: StartHook = StartHook.new()
	start.samples = _samples
	start.process_physics_priority = -10000
	arena.add_child(start)
	var finish: EndHook = EndHook.new()
	finish.samples = _samples
	finish.process_physics_priority = 10000
	arena.add_child(finish)
	for frame in range(60):
		await physics_frame
	await process_frame
	_samples.callbacks_ms.clear()
	_samples.engine_physics_ms.clear()
	_samples.memory_bytes.clear()
	var count_start: int = _counter()
	var compute_start: int = _compute_us()
	var wall: Node3D = null
	var started_us: int = Time.get_ticks_usec()
	_samples.frame_limit = _frames
	_samples.on_complete = _snapshot_measurement_end
	_samples.recording = true
	for frame in range(_frames):
		if dynamic:
			var angle: float = float(frame) / float(Engine.physics_ticks_per_second)
			target.position = Vector3(cos(angle) * 4.5, 1.0, sin(angle) * 4.5)
			if frame == _frames / 3:
				wall = (load(WALL_PATH) as PackedScene).instantiate() as Node3D
				wall.position = Vector3(2.5, 0.0, 8.5)
				wall.set("max_health", 1000000.0)
				# Bosses can destroy a wall during charge before the scheduled removal.
				# Preserve the real destruction callback without its cosmetic zero scale.
				wall.connect("building_destroyed", func(destroyed: Node) -> void: destroyed.queue_free())
				arena.add_child(wall)
				_reg.call("register_building", wall)
			if frame == _frames * 2 / 3 and is_instance_valid(wall):
				wall.call("take_damage", 1000001.0)
				# The destruction signal and exit-tree lifecycle are real; remove the
				# destroyed physical body before its cosmetic scale-to-zero tween.
				wall.queue_free()
		await physics_frame
	await process_frame
	_samples.recording = false
	var elapsed_us: int = _samples.completed_us - started_us
	# Read BEFORE cleanup or additional benchmarks. These belong to this interval only.
	var measured_rebuilds: int = _final_rebuild_count - count_start
	var measured_compute_us: int = _final_compute_us - compute_start
	var result: Dictionary = {"count": count, "scenario": "moving_target_real_wall" if dynamic else "stationary", "callback_ms": _samples.callbacks_ms.duplicate(), "engine_physics_monitor_ms": _samples.engine_physics_ms.duplicate(), "memory_bytes": _samples.memory_bytes.duplicate(), "elapsed_sec": float(elapsed_us) / 1000000.0, "rebuilds": measured_rebuilds, "field_compute_ms": float(measured_compute_us) / 1000.0, "wall_created": dynamic, "wall_removed": dynamic and not is_instance_valid(wall)}
	print("BENCHMARK_SCENARIO ", _label, " ", count, " ", result.scenario, " ", _samples.callbacks_ms.size(), " callbacks")
	arena.queue_free()
	await process_frame
	await physics_frame
	return result

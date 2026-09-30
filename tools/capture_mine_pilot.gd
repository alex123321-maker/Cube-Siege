extends SceneTree

const MAIN: PackedScene = preload("res://scenes/main.tscn")
const ENEMY: PackedScene = preload("res://scenes/enemy_dummy.tscn")
var _world: Node3D
var _player: CharacterBody3D
var _camera: Camera3D
var _caption: Label
var _targets: Array[CharacterBody3D] = []
var _origin: Vector3
var _manager: Node
var _label: String = "mine"
var _profile_path: String = ""
var _running: bool = false
var _age: float = 0.0
var _expiry: Dictionary[int, float] = {}
var _expected_health: Array[float] = []
var _radius: float = 4.5
var _only_phase: int = -1
var _failed: bool = false
var _no_imprint: bool = false
const OUTPUT: String = "res://docs/verification/vfx_mine_pilot/"

func _initialize() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			_label = argument.trim_prefix("--label=")
		elif argument.begins_with("--profile="):
			_profile_path = argument.trim_prefix("--profile=")
		elif argument.begins_with("--radius="):
			_radius = float(argument.trim_prefix("--radius="))
		elif argument.begins_with("--only-phase="):
			_only_phase = int(argument.trim_prefix("--only-phase="))
		elif argument == "--no-imprint":
			_no_imprint = true
	call_deferred("_capture")

func _process(delta: float) -> bool:
	if _running:
		_player.presentation.update_animations(_player, false, false, delta, _player.orientation)
		# Legacy effects use a wall-clock safety deadline. For Movie Writer only,
		# advance their remaining safety lifetime on the same clock as their tweens.
		_age += delta
		var retained: Array[Dictionary] = []
		for item: Dictionary in _manager._timed_effects:
			var id: int = item["id"]
			var instance: Node = instance_from_id(id) as Node
			if not is_instance_valid(instance):
				_expiry.erase(id)
				continue
			if not _expiry.has(id):
				_expiry[id] = _age + maxf(0.0, float(item["expires_at"] - Time.get_ticks_msec()) / 1000.0)
			if _age >= _expiry[id]:
				instance.queue_free()
				_expiry.erase(id)
			else:
				retained.append(item)
		_manager._timed_effects = retained
	return false

func _capture() -> void:
	seed(573901)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	_manager = root.get_node("VFXManager")
	_manager.set_process(false)
	if not _profile_path.is_empty():
		_manager.set("mine_profile", load(_profile_path))
		print("MINE_PROFILE ", _profile_path)
	if _no_imprint:
		var profile: MineVFXProfile = _manager.mine_profile.duplicate() as MineVFXProfile
		profile.ground_opacity = 0.0
		_manager.mine_profile = profile
	_world = MAIN.instantiate() as Node3D
	var map: MapGenerator = _world.get_node("MapGenerator") as MapGenerator
	map.random_seed = false
	map.custom_seed = 1337
	map.load_radius_chunks = 2
	root.add_child(_world)
	current_scene = _world
	_world.get_node("WaveDirector").set_process(false)
	_world.get_node("DayNightCycle").set_process(false)
	_world.get_node("HUD").hide()
	for enemy: Node in _world.get_node("Enemies").get_children():
		enemy.queue_free()
	_player = _world.get_node("Player") as CharacterBody3D
	_player.set_physics_process(false)
	_player.set_process_input(false)
	_player.set_class(2, false)
	_player.orientation.setup(Vector3.FORWARD)
	_player.get_node("PortalCompass").hide()
	_origin = Vector3(-5.0, float(map.get_voxel_height(-5, 3)) + 0.9, 3.0)
	_camera = _world.get_node("Camera3D") as Camera3D
	_camera.set_process(false)
	_camera.set_physics_process(false)
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var layer := CanvasLayer.new()
	_caption = Label.new()
	_caption.position = Vector2(28, 24)
	_caption.add_theme_font_size_override("font_size", 22)
	_caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	_caption.add_theme_constant_override("shadow_offset_x", 2)
	_caption.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_caption)
	root.add_child(layer)
	for index in range(80):
		await process_frame
	_add_target(Vector3(1.6, 0, -1.3))
	_add_target(Vector3(-1.2, 0, -3.5))
	_add_target(Vector3(5.3, 0, 0))
	# Two visible sentinels straddle the edge; no painted guide circle is used.
	_add_target(Vector3(0.35, 0.0, 0.94).normalized() * (_radius - 0.15))
	_add_target(Vector3(0.92, 0.0, 0.39).normalized() * (_radius + 0.15))
	_running = true
	for frame in range(1050 if _only_phase < 0 else 210):
		var phase: int = frame / 210 if _only_phase < 0 else _only_phase
		var local_frame: int = frame % 210
		if local_frame == 0:
			_set_view(phase)
			_player.global_position = _origin
			_player.parry_cooldown_timer = 0.0
			_player.abilities.toggle_remote_mine(_player)
			# Only the capture can override radius to verify visual scaling.
			_player.abilities.active_remote_mine.blast_radius = _radius
		elif local_frame == 2:
			_player.global_position = _grounded(_origin + Vector3(-4.0, 0.0, 2.8))
			_player.reset_physics_interpolation()
		elif local_frame == 45:
			for index in range(_targets.size()):
				if _targets[index].global_position.distance_to(_origin) <= _radius:
					_expected_health[index] -= 250.0
			_player.abilities.toggle_remote_mine(_player)
			# Check in the same call/frame, before any visual wave has travelled.
			for index in range(_targets.size()):
				if _targets[index].current_health != _expected_health[index]:
					_failed = true
			print("MINE_IMMEDIATE phase=", phase, " radius=", _radius,
				" targets=", _targets.size(), " pass=", not _failed)
		if local_frame in [45, 47, 51, 57, 69, 90, 105, 120, 144, 177]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT + "%s_%d_%03d.png" % [_label, phase, local_frame - 45])
		await process_frame
	await create_timer(0.6).timeout
	print("MINE_PILOT inside_health=", _targets[0].current_health, ",", _targets[1].current_health,
		" outside_health=", _targets[2].current_health, " active_effects=", _manager.get_active_effect_count())
	if _failed or _manager.get_active_effect_count() != 0:
		push_error("Mine damage boundary or effect cleanup changed.")
		quit(2)
		return
	quit()

func _add_target(offset: Vector3) -> void:
	var enemy: CharacterBody3D = ENEMY.instantiate() as CharacterBody3D
	_world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = _grounded(_origin + offset)
	enemy.max_health = 10000.0
	enemy.current_health = 10000.0
	enemy.get_node("Visuals/HPLabel").hide()
	_targets.append(enemy)
	_expected_health.append(10000.0)

func _grounded(at: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 12.0, at + Vector3.DOWN * 12.0, 1)
	var hit: Dictionary = _world.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return (hit.position as Vector3) + Vector3.UP * 0.9
	return at

func _set_view(phase: int) -> void:
	var offset := Vector3(15.0, 20.0, 15.0)
	var title: String = "GAME CAMERA / DAY"
	var cycle: DayNightCycle = _world.get_node("DayNightCycle") as DayNightCycle
	cycle.is_night = phase in [2, 3]
	cycle.apply_lighting_state()
	if phase == 0:
		offset *= 0.5
		title = "DETAIL / DAY"
	elif phase == 2:
		title = "GAME CAMERA / NIGHT"
	elif phase >= 3:
		if _targets.size() == 5:
			for index in range(24):
				var angle: float = TAU * float(index) / 24.0
				var distance: float = _radius * [0.57, 0.87, 1.07, 1.22][index % 4]
				_add_target(Vector3(sin(angle), 0.0, cos(angle)) * distance)
		title = "GAME CAMERA / CROWD / " + ("NIGHT" if phase == 3 else "DAY")
	_camera.global_position = _origin + offset
	_camera.look_at(_origin)
	_caption.text = _label.to_upper() + " / " + title + " / VOXEL STEPS"

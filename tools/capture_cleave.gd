extends SceneTree

## Production-world verification, driven by the real RMB combat entry point.
## --fixed-fps 60 --write-movie screenshots_debug/cleave.avi -s tools/capture_cleave.gd
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const ENEMY: PackedScene = preload("res://scenes/enemy_dummy.tscn")
const OUTPUT: String = "res://docs/verification/vfx_cleave/"
var _world: Node3D
var _player: CharacterBody3D
var _camera: CameraFollow
var _caption: Label
var _targets: Array[CharacterBody3D] = []
var _expected: Array[float] = []
var _running: bool = false
var _failed: bool = false
var _only_phase: int = -1
var _contacts: int = 0
var _releases: int = 0
var _label: String = "sovereign"

func _initialize() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--only-phase="):
			_only_phase = int(argument.trim_prefix("--only-phase="))
		elif argument.begins_with("--label="):
			_label = argument.trim_prefix("--label=")
	call_deferred("_capture")

func _process(delta: float) -> bool:
	if _running:
		_player.combat.update_timers(delta)
		_player.presentation.update_animations(_player, false, false, delta, _player.orientation)
		_camera._step_combat_impulse(delta)
	return false

func _capture() -> void:
	seed(271828)
	DirAccess.make_dir_recursive_absolute(OUTPUT)
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
	_player.set_class(0, false)
	_player.global_position = Vector3(-4.0, float(map.get_voxel_height(-4, 3)) + 0.9, 3.0)
	_player.rotation = Vector3.ZERO
	_player.orientation.setup(Vector3.FORWARD)
	_player.get_node("PortalCompass").hide()
	_camera = _world.get_node("Camera3D") as CameraFollow
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
	_add_target(Vector3(0.0, 0.0, -1.8))
	_add_target(Vector3(1.0, 0.0, -1.4))
	_add_target(Vector3(-1.0, 0.0, -1.4))
	# A sentinel behind the warrior must never be hit by the frontal special.
	_add_target(Vector3(0.0, 0.0, 2.2))
	root.get_node("VFXManager")._ensure_container().child_entered_tree.connect(_record_effect)
	_running = true
	for frame in range(700 if _only_phase < 0 else 140):
		var phase: int = frame / 140 if _only_phase < 0 else _only_phase
		var local_frame: int = frame % 140
		if local_frame == 0:
			_set_view(phase)
		if local_frame == 6:
			for index in range(3):
				_expected[index] -= _player.combat.special_damage
			_player.combat.special_cooldown_timer = 0.0
			_player.perform_special_attack()
		if local_frame == 35:
			for index in range(4):
				if not is_equal_approx(_targets[index].current_health, _expected[index]):
					_failed = true
		if local_frame in [0, 9, 15, 18, 21, 25, 33, 45, 65]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT + "%s_%d_%03d.png" % [_label, phase, local_frame])
		await process_frame
	await create_timer(0.9).timeout
	var active: int = root.get_node("VFXManager").get_active_effect_count()
	var phases: int = 5 if _only_phase < 0 else 1
	print("CLEAVE_CAPTURE damage_pass=", not _failed, " releases=", _releases,
		" contacts=", _contacts, " active_effects=", active,
		" camera_offset=", Vector2(_camera.h_offset, _camera.v_offset),
		" settled_trail=", _player.presentation.blade_trail.mesh.get_surface_count())
	if _failed or active != 0 or _releases != phases or _contacts < phases * 3:
		push_error("Cleave damage, release, contact or cleanup verification failed")
		quit(2)
		return
	quit()

func _record_effect(effect: Node) -> void:
	_count_effect.call_deferred(effect)

func _count_effect(effect: Node) -> void:
	if effect is CleaveVFX:
		if effect._contact:
			_contacts += 1
		elif not effect._charge:
			_releases += 1

func _add_target(offset: Vector3) -> void:
	var enemy: CharacterBody3D = ENEMY.instantiate() as CharacterBody3D
	_world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = _player.global_position + offset
	enemy.max_health = 10000.0
	enemy.current_health = 10000.0
	enemy.rotation.y = PI
	enemy.get_node("Visuals/HPLabel").hide()
	_targets.append(enemy)
	_expected.append(10000.0)

func _set_view(phase: int) -> void:
	var focal: Vector3 = _player.global_position + Vector3(0.0, 0.0, -0.65)
	var offset := Vector3(15.0, 20.0, 15.0)
	var title: String = "GAME CAMERA / DAY"
	var cycle: DayNightCycle = _world.get_node("DayNightCycle") as DayNightCycle
	cycle.is_night = phase in [2, 3]
	cycle.apply_lighting_state()
	if phase == 0:
		offset *= 0.40
		title = "DETAIL / DAY"
	elif phase == 2:
		title = "GAME CAMERA / NIGHT"
	elif phase == 3:
		if _targets.size() == 4:
			for index in range(24):
				var angle: float = TAU * float(index) / 24.0
				_add_target(Vector3(sin(angle), 0.0, cos(angle)) * (2.8 + float(index % 4) * 0.5))
		title = "GAME CAMERA / NIGHT / CROWD"
	elif phase == 4:
		title = "SIDE VIEW / DAY / CROWD"
		offset = Vector3(9.0, 9.0, -12.0)
	_camera.global_position = focal + offset
	_camera.look_at(focal)
	_caption.text = "SOVEREIGN EDGE  /  " + title

extends SceneTree

## Production-world verification, driven by the real RMB combat entry point.
## --fixed-fps 60 --write-movie screenshots_debug/cleave.avi -s tools/capture_cleave.gd
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const ENEMY: PackedScene = preload("res://scenes/enemy_dummy.tscn")
const OUTPUT: String = "res://docs/verification/vfx_cleave_ability/"
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
var _miss: bool = false
var _facing: float = 0.0
var _profile_real_time: bool = false
var _basic: bool = false
var _target_offsets: Array[Vector3] = []
var _pose_only: bool = false

func _initialize() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--only-phase="):
			_only_phase = int(argument.trim_prefix("--only-phase="))
		elif argument.begins_with("--label="):
			_label = argument.trim_prefix("--label=")
		elif argument == "--miss":
			_miss = true
		elif argument == "--basic":
			_basic = true
		elif argument == "--pose-only":
			_pose_only = true
		elif argument.begins_with("--facing-degrees="):
			_facing = deg_to_rad(float(argument.trim_prefix("--facing-degrees=")))
		elif argument == "--static-head":
			(root.get_node("VFXManager").CLEAVE_PROFILE as CleaveVFXProfile).traveling_head = false
		elif argument == "--profile-real-time":
			_profile_real_time = true
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
	_player.rotation = Vector3(0.0, _facing, 0.0)
	_player.orientation.setup(Vector3.FORWARD.rotated(Vector3.UP, _facing))
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
	_add_target(Vector3(2.8, 0.0, -1.0))
	_add_target(Vector3(-2.8, 0.0, -1.0))
	# A sentinel behind the warrior must never be hit by the frontal special.
	_add_target(Vector3(0.0, 0.0, 2.2))
	root.get_node("VFXManager")._ensure_container().child_entered_tree.connect(_record_effect)
	if _pose_only:
		root.get_node("VFXManager")._ensure_container().hide()
		_player.presentation.blade_trail.hide()
	_running = true
	if _profile_real_time:
		await _profile_effects()
		return
	for frame in range(700 if _only_phase < 0 else 140):
		var phase: int = frame / 140 if _only_phase < 0 else _only_phase
		var local_frame: int = frame % 140
		if local_frame == 0:
			for index in range(_targets.size()):
				_targets[index].global_position = _player.global_position + _target_offsets[index]
				_targets[index].velocity = Vector3.ZERO
				_targets[index].knockback_velocity = Vector3.ZERO
			_set_view(phase)
		if local_frame == 6:
			if not _miss:
				for index in range(1 if _basic else 3):
					_expected[index] -= _player.combat.attack_damage if _basic else _player.combat.special_damage
			if _basic:
				_player.combat.attack_cooldown_timer = 0.0
				_player.perform_attack()
			else:
				_player.combat.special_cooldown_timer = 0.0
				_player.perform_special_attack()
		if local_frame == 45:
			for index in range(4):
				if not is_equal_approx(_targets[index].current_health, _expected[index]):
					_failed = true
		if local_frame in [0, 9, 16, 19, 22, 25, 29, 35, 45, 65, 90]:
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
	if _failed or active != 0 or (not _basic and (_releases != phases or (_contacts != 0 if _miss else _contacts < phases * 3))):
		push_error("Cleave damage, release, contact or cleanup verification failed")
		quit(2)
		return
	quit()

func _profile_effects() -> void:
	# Separate from Movie Writer: renderer timings exclude encoding/readback.
	_set_view(1)
	Engine.max_fps = 120
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var manager: Node = root.get_node("VFXManager")
	manager.spawn_cleave_wave(_player.global_position, Vector3.FORWARD)
	manager.spawn_cleave_contact(_player.global_position + Vector3.FORWARD, Vector3.FORWARD)
	await create_timer(1.0).timeout
	var baseline_gpu: Array[float] = []
	var baseline_cpu: Array[float] = []
	var stress_gpu: Array[float] = []
	var stress_cpu: Array[float] = []
	var max_draws: int = 0
	for frame in range(540):
		if frame >= 180 and (frame - 180) % 90 == 0:
			for caster in range(8):
				var center: Vector3 = _player.global_position + Vector3(float(caster % 4) - 1.5, 0.0, float(caster / 4) - 0.5)
				manager.spawn_cleave_wave(center, Vector3.FORWARD)
				for contact in range(6):
					manager.spawn_cleave_contact(center + Vector3(float(contact % 3) * 0.3, 0.3, -1.0), Vector3.FORWARD)
		await RenderingServer.frame_post_draw
		var gpu: float = RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid())
		var cpu: float = RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid())
		if frame < 180:
			baseline_gpu.append(gpu)
			baseline_cpu.append(cpu)
		elif manager.get_active_effect_count() >= 16:
			stress_gpu.append(gpu)
			stress_cpu.append(cpu)
			max_draws = maxi(max_draws, RenderingServer.viewport_get_render_info(root.get_viewport_rid(),
				RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME))
		await process_frame
	await create_timer(1.0).timeout
	print("CLEAVE_REAL_TIME_PROFILE baseline_gpu=", _timing_summary(baseline_gpu),
		" baseline_render_cpu=", _timing_summary(baseline_cpu),
		" stress_gpu=", _timing_summary(stress_gpu), " stress_render_cpu=", _timing_summary(stress_cpu),
		" stress=8_releases_48_contacts max_visible_draws=", max_draws,
		" active_effects=", manager.get_active_effect_count())
	quit(0 if manager.get_active_effect_count() == 0 and not stress_gpu.is_empty() else 2)

func _timing_summary(samples: Array[float]) -> String:
	if samples.is_empty():
		return "unavailable"
	samples.sort()
	var total: float = 0.0
	for sample: float in samples:
		total += sample
	return "avg=%.2f,p95=%.2f,max=%.2fms,n=%d" % [total / float(samples.size()),
		samples[mini(int(float(samples.size()) * 0.95), samples.size() - 1)], samples[-1], samples.size()]

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
	enemy.move_speed = 0.0
	enemy.attack_timer = 1000.0
	var displacement: Vector3 = offset.rotated(Vector3.UP, _facing)
	if _miss:
		displacement *= 3.0
	_target_offsets.append(displacement)
	enemy.global_position = _player.global_position + displacement
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
	elif phase == 5:
		title = "SWORD SIDE / POSE DIAGNOSTIC"
		offset = Vector3(6.0, 3.5, 0.0)
	elif phase == 6:
		title = "FRONT / POSE DIAGNOSTIC"
		offset = Vector3(0.0, 3.0, -6.0)
	_camera.global_position = focal + offset
	_camera.look_at(focal)
	_caption.text = ("BASIC ATTACK" if _basic else "CLEAVE ABILITY") + "  /  " + title + (" / MISS" if _miss else "")

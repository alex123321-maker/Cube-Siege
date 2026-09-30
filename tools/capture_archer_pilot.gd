extends SceneTree

## Real basic archer attacks, same deterministic scene before and after.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const ENEMY: PackedScene = preload("res://scenes/enemy_dummy.tscn")
var _main: Node3D
var _player: CharacterBody3D
var _target: CharacterBody3D
var _camera: Camera3D
var _caption: Label
var _manager: Node
var _label: String = "after"
var _profile_path: String = ""
var _output: String = "res://docs/verification/vfx_archer_pilot/"
var _phase: int = 0
var _local_frame: int = 0
var _first_hit_frame: int = -1
var _damage_events: int = 0
var _shots: int = 0
var _running: bool = false
var _crowd: Array[CharacterBody3D] = []
var _impact_count: int = 0
var _surface_check: bool = false
var _wall_impacts: int = 0

func _initialize() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--label="):
			_label = argument.trim_prefix("--label=")
		elif argument.begins_with("--profile="):
			_profile_path = argument.trim_prefix("--profile=")
		elif argument == "--surface-check":
			_surface_check = true
	call_deferred("_capture")

func _process(delta: float) -> bool:
	if _running and is_instance_valid(_player):
		_player.combat.update_timers(delta)
		_player.presentation.update_animations(_player, false, false, delta, _player.orientation)
	return false

func _capture() -> void:
	seed(271828)
	_manager = root.get_node("VFXManager")
	if _label == "before" and _manager.has_method("spawn_arrow_impact"):
		push_error("Before capture requires the actual baseline implementation.")
		quit(2)
		return
	if not _profile_path.is_empty():
		_manager.set("arrow_impact_profile", load(_profile_path))
	# Legacy sparks use a wall-clock safety timeout. For offline recording only,
	# use a simulation timer so slow encoding cannot shorten the baseline.
	if _label == "before":
		_manager.set_process(false)
	_manager._ensure_container().child_entered_tree.connect(_on_effect)
	DirAccess.make_dir_recursive_absolute(_output)
	_main = MAIN.instantiate() as Node3D
	var map: MapGenerator = _main.get_node("MapGenerator") as MapGenerator
	map.random_seed = false
	map.custom_seed = 1337
	map.load_radius_chunks = 2
	root.add_child(_main)
	current_scene = _main
	_main.get_node("WaveDirector").set_process(false)
	_main.get_node("DayNightCycle").set_process(false)
	_main.get_node("HUD").hide()
	for enemy: Node in _main.get_node("Enemies").get_children():
		enemy.queue_free()
	_player = _main.get_node("Player") as CharacterBody3D
	_player.set_physics_process(false)
	_player.set_process_input(false)
	_player.set_class(1, false)
	_player.global_position = Vector3(-4.0, float(map.get_voxel_height(-4, 3)) + 0.9, 3.0)
	_player.rotation = Vector3.ZERO
	_player.orientation.setup(Vector3.FORWARD)
	_player.get_node("PortalCompass").hide()
	_camera = _main.get_node("Camera3D") as Camera3D
	_camera.set_process(false)
	_camera.set_physics_process(false)
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var layer := CanvasLayer.new()
	_caption = Label.new()
	_caption.position = Vector2(28, 24)
	_caption.add_theme_font_size_override("font_size", 21)
	_caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	_caption.add_theme_constant_override("shadow_offset_x", 2)
	_caption.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_caption)
	root.add_child(layer)
	for index in range(80):
		await process_frame
	_target = _add_target(Vector3(-4.0, float(map.get_voxel_height(-4, -3)) + 0.9, -3.0))
	(_target.get_node("Hurtbox") as HurtboxArea).damaged.connect(_on_damage)
	_running = true
	for frame in range(360 if _surface_check else 900):
		_phase = frame / 180 + (5 if _surface_check else 0)
		_local_frame = frame % 180
		if _local_frame == 0:
			_first_hit_frame = -1
			_set_view(_phase)
		var cadence: int = 24 if _phase == 3 else 60
		if _local_frame >= 15 and (_local_frame - 15) % cadence == 0 and _local_frame < 145:
			_player.perform_attack()
			_shots += 1
		var elapsed: int = _local_frame - _first_hit_frame
		if _first_hit_frame >= 0 and elapsed in [0, 2, 5, 9, 15, 24, 36]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(_output + "%s_%d_%03d.png" % [_label, _phase, elapsed])
		if _surface_check and _local_frame in [23, 27, 32, 40, 55]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(_output + "%s_%d_%03d.png" % [_label, _phase, _local_frame])
		await process_frame
	_running = false
	await create_timer(3.0).timeout
	print("ARCHER_PILOT shots=", _shots, " damage_events=", _damage_events,
		" target_health=", _target.current_health, " impacts=", _impact_count,
		" active_effects=", _manager.get_active_effect_count())
	var passed: bool = _damage_events == 36 and is_equal_approx(_target.current_health, 9100.0)
	if _surface_check:
		passed = _damage_events == 0 and _wall_impacts == 3 and _impact_count == 3
		print("ARCHER_SURFACE wall_impacts=", _wall_impacts, " miss_impacts=", _impact_count - _wall_impacts, " pass=", passed)
	if _manager.get_active_effect_count() != 0 or not passed:
		push_error("Capture had no hits or left active effects.")
		quit(3)
		return
	quit()

func _on_damage(_amount: float, _knockback: Vector3, _kind: String, _attacker: Node) -> void:
	_damage_events += 1
	if _first_hit_frame < 0:
		_first_hit_frame = _local_frame
		print("ARCHER_FIRST_HIT phase=", _phase, " frame=", _local_frame)

func _on_effect(effect: Node) -> void:
	if effect.name == "ArrowImpact":
		_impact_count += 1
		if _phase == 5:
			_wall_impacts += 1
			print("ARCHER_WALL_IMPACT frame=", _local_frame)
	if _label == "before":
		_expire_legacy(effect)

func _expire_legacy(effect: Node) -> void:
	await create_timer(0.6).timeout
	if is_instance_valid(effect):
		effect.queue_free()

func _add_target(at: Vector3) -> CharacterBody3D:
	var target: CharacterBody3D = ENEMY.instantiate() as CharacterBody3D
	_main.add_child(target)
	target.set_physics_process(false)
	target.max_health = 10000.0
	target.current_health = 10000.0
	target.global_position = at
	target.rotation.y = PI
	target.get_node("Visuals/HPLabel").hide()
	return target

func _set_view(phase: int) -> void:
	if phase >= 5:
		_set_surface_view(phase)
		return
	var focal: Vector3 = _target.global_position + Vector3(0.0, 0.5, 1.6)
	var offset := Vector3(15.0, 20.0, 15.0)
	var title: String = "GAME / DAY"
	if phase == 0:
		offset *= 0.36
		title = "DETAIL / DAY"
	elif phase == 2 or phase == 3:
		var cycle: DayNightCycle = _main.get_node("DayNightCycle") as DayNightCycle
		cycle.is_night = true
		cycle.apply_lighting_state()
		title = "GAME / NIGHT"
		if phase == 3:
			for index in range(18):
				var x: float = -4.0 + (1.8 + float(index % 3) * 1.15) * (-1.0 if index % 2 == 0 else 1.0)
				var z: float = -4.0 + float(index / 6) * 2.0
				var map: MapGenerator = _main.get_node("MapGenerator") as MapGenerator
				_crowd.append(_add_target(Vector3(x, float(map.get_voxel_height(roundi(x), roundi(z))) + 0.9, z)))
			title = "CROWD / NIGHT / 0.40s CADENCE"
	elif phase == 4:
		var cycle: DayNightCycle = _main.get_node("DayNightCycle") as DayNightCycle
		cycle.is_night = false
		cycle.apply_lighting_state()
		_player.global_position = Vector3(-8.0, _target.global_position.y, -3.0)
		_player.look_at(_target.global_position, Vector3.UP)
		_player.orientation.setup(Vector3.RIGHT)
		for target: CharacterBody3D in _crowd:
			target.queue_free()
		focal = _target.global_position + Vector3(-1.4, 0.4, 0.0)
		offset = Vector3(5.4, 7.2, 5.4)
		title = "DIRECTION CHANGE / DAY"
	_camera.global_position = focal + offset
	_camera.look_at(focal)
	_caption.text = "%s / ARCHER BASIC ATTACK / %s" % [_label.to_upper(), title]

func _set_surface_view(phase: int) -> void:
	var map: MapGenerator = _main.get_node("MapGenerator") as MapGenerator
	var focal: Vector3
	var title: String
	if phase == 5:
		var found: bool = false
		for x in range(-28, 29):
			if found:
				break
			for z in range(-28, 29):
				if found:
					break
				for step: Vector2i in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
					var h: float = float(map.get_voxel_height(x, z))
					var next_h: float = float(map.get_voxel_height(x + step.x, z + step.y))
					var behind_h: float = float(map.get_voxel_height(x - step.x, z - step.y))
					if next_h - h >= 2.0 and is_equal_approx(h, behind_h):
						var direction := Vector3(float(step.x), 0.0, float(step.y))
						_player.global_position = Vector3(float(x), h + 0.9, float(z)) - direction
						_player.look_at(_player.global_position + direction, Vector3.UP)
						_player.orientation.setup(direction)
						focal = Vector3(float(x), h + 0.8, float(z)) + direction * 0.3
						found = true
						print("ARCHER_WALL low=", h, " high=", next_h, " at=", focal)
						break
		if not found:
			push_error("No verified terrain wall found for the surface capture.")
			quit(4)
			return
		title = "REAL TERRAIN COLLISION"
	else:
		# Shoot above terrain into empty space. The normal projectile lifetime
		# still expires; no contact is fabricated for a miss.
		_player.global_position = Vector3(-4.0, 100.0, 3.0)
		_player.rotation = Vector3.ZERO
		_player.orientation.setup(Vector3.FORWARD)
		focal = _player.global_position + Vector3(0.0, 0.0, -3.0)
		title = "MISS / NO CONTACT"
	_camera.global_position = focal + Vector3(8.0, 6.0, 2.5)
	_camera.look_at(focal)
	_caption.text = "%s / ARCHER / %s" % [_label.to_upper(), title]

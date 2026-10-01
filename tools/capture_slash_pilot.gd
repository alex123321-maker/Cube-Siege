extends SceneTree

## Reproducible render of real player attacks in the production world.
## Run with --fixed-fps 60 --write-movie <path.avi> -- --label=after.
## A "before" capture requires this harness on the baseline revision.
const MAIN: PackedScene = preload("res://scenes/main.tscn")
const ENEMY: PackedScene = preload("res://scenes/enemy_dummy.tscn")
var _player: CharacterBody3D
var _camera: Camera3D
var _caption: Label
var _main: Node3D
var _targets: Array[CharacterBody3D] = []
var _label: String = "after"
var _profile_path: String = ""
var _rapid: bool = false
var _expected_contacts: int = 0
var _running: bool = false
var _contact_count: int = 0
var _trail_checks: int = 0
var _trail_max_error: float = 0.0
var _trail_max_samples: int = 0
var _output: String = "res://docs/verification/vfx_slash_pilot/"

func _initialize() -> void:
	# Keep evidence dimensions stable even if the desktop resizes the game window.
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=").trim_suffix("/") + "/"
		elif argument.begins_with("--label="):
			_label = argument.trim_prefix("--label=")
		elif argument.begins_with("--profile="):
			_profile_path = argument.trim_prefix("--profile=")
		elif argument == "--rapid":
			_rapid = true
	if not _profile_path.is_empty():
		# Capture-only override of the shared cached Resource; never writes the default file.
		var candidate: SwordVFXProfile = load(_profile_path) as SwordVFXProfile
		var shared: SwordVFXProfile = load("res://assets/vfx/sword/steel_slash.tres") as SwordVFXProfile
		for property: Dictionary in candidate.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				shared.set(property.name, candidate.get(property.name))
		print("SLASH_PROFILE ", _profile_path)
	call_deferred("_capture")

func _process(delta: float) -> bool:
	if _running and is_instance_valid(_player):
		_player.combat.update_timers(delta)
		_player.presentation.update_animations(_player, false, false, delta, _player.orientation)
	return false

func _capture() -> void:
	if _label == "before" and root.get_node("VFXManager").has_method("spawn_warrior_slash"):
		push_error("A before recording must use the baseline VFX implementation, not just a different caption.")
		quit(2)
		return
	seed(271828)
	root.get_node("VFXManager")._ensure_container().child_entered_tree.connect(_count_contact)
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
	_player.set_class(0, false)
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
	_caption.add_theme_font_size_override("font_size", 22)
	_caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	_caption.add_theme_constant_override("shadow_offset_x", 2)
	_caption.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_caption)
	root.add_child(layer)
	for index in range(80):
		await process_frame
	_add_target(_player.global_position + Vector3(0.0, 0.0, -1.8))
	_running = true
	for frame in range(900):
		var phase: int = frame / 180
		if frame % 180 == 0:
			_set_view(phase)
		if phase == 4:
			_player.rotation.y = sin(float(frame - 720) / 180.0 * TAU) * 0.45
			_player.orientation.setup(-_player.global_basis.z)
		var local_frame: int = frame % 180
		var cadence: int = 21 if _rapid else 60
		if local_frame % cadence == 15 and local_frame < 165:
			_player.combat.attack_cooldown_timer = 0.0
			_player.perform_attack()
			if phase < 4:
				_expected_contacts += 1
		if frame % 180 in [20, 23, 27, 33, 45]:
			await RenderingServer.frame_post_draw
			_audit_trail()
			var shot: Image = root.get_texture().get_image()
			shot.save_png(_output + "%s_%d_%03d.png" % [_label, phase, frame % 180])
		await process_frame
	await create_timer(0.8).timeout
	var trail_surfaces: int = _player.presentation.blade_trail.mesh.get_surface_count()
	print("SLASH_PILOT target_health=", _targets[0].current_health,
		" contacts=", _contact_count,
		" active_effects=", root.get_node("VFXManager").get_active_effect_count(),
		" trail_checks=", _trail_checks, " trail_endpoint_error=", _trail_max_error,
		" trail_max_samples=", _trail_max_samples, " settled_trail_surfaces=", trail_surfaces)
	if _label != "before" and _contact_count != _expected_contacts:
		push_error("Expected one contact per confirmed attack in the rendered sequence.")
		quit(3)
		return
	if not is_equal_approx(_targets[0].current_health, 10000.0 - float(_expected_contacts) * _player.combat.attack_damage) or root.get_node("VFXManager").get_active_effect_count() != 0:
		push_error("Damage or final cleanup changed during the profile comparison.")
		quit(5)
		return
	if _trail_checks == 0 or _trail_max_error > 0.005 or trail_surfaces != 0:
		push_error("Blade trail failed the rendered endpoint check.")
		quit(4)
		return
	quit()

func _audit_trail() -> void:
	var trail: SwordBladeTrail = _player.presentation.blade_trail
	if not is_instance_valid(trail):
		return
	_trail_max_samples = maxi(_trail_max_samples, trail._tips.size())
	if not trail._emitting or trail.mesh.get_surface_count() == 0:
		return
	var vertices: PackedVector3Array = trail.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var displayed_tip: Vector3 = trail._tip_anchor.get_global_transform_interpolated().origin
	_trail_max_error = maxf(_trail_max_error, vertices[-2].distance_to(displayed_tip))
	_trail_checks += 1

func _count_contact(effect: Node) -> void:
	# Rapid attacks overlap; Godot renames duplicate child names. Inspect the
	# effect after setup instead of counting a name that may become @Node3D@.
	_record_contact.call_deferred(effect)

func _record_contact(effect: Node) -> void:
	if is_instance_valid(effect) and effect is SwordVFX and effect._contact:
		_contact_count += 1

func _add_target(at: Vector3) -> void:
	var target: CharacterBody3D = ENEMY.instantiate() as CharacterBody3D
	_main.add_child(target)
	target.set_physics_process(false)
	target.max_health = 10000.0
	target.current_health = 10000.0
	target.global_position = at
	target.rotation.y = PI
	target.get_node("Visuals/HPLabel").hide()
	_targets.append(target)

func _set_view(phase: int) -> void:
	var focal: Vector3 = _player.global_position + Vector3(0.0, 0.0, -0.8)
	var offset: Vector3 = Vector3(15.0, 20.0, 15.0)
	var title: String = "GAME CAMERA / DAY"
	if phase == 0:
		offset *= 0.4
		title = "DETAIL / DAY"
	elif phase == 2:
		var cycle: DayNightCycle = _main.get_node("DayNightCycle") as DayNightCycle
		cycle.is_night = true
		cycle.apply_lighting_state()
		title = "GAME CAMERA / NIGHT"
	elif phase == 3:
		for index in range(24):
			var angle: float = TAU * float(index) / 24.0
			var at: Vector3 = _player.global_position + Vector3(sin(angle), 0.0, cos(angle)) * (3.2 + float(index % 3) * 0.75)
			_add_target(at)
		title = "GAME CAMERA / CROWD"
	elif phase == 4:
		for target: CharacterBody3D in _targets:
			target.global_position += Vector3(12.0, 0.0, 0.0)
			target.hide()
		var cycle: DayNightCycle = _main.get_node("DayNightCycle") as DayNightCycle
		cycle.is_night = false
		cycle.apply_lighting_state()
		focal = _player.global_position + Vector3(0.0, 0.25, -0.25)
		offset = Vector3(4.5, 4.5, -4.5)
		title = "WEAPON TRACKING / MISS"
	_camera.global_position = focal + offset
	_camera.look_at(focal)
	_caption.text = "%s  /  %s" % [_label.to_upper(), title]
	if _rapid:
		_caption.text += "  /  0.35s CADENCE"

extends SceneTree

## Bounded art/attack review in a flat arena, with production actors, clocks and lighting.
## Gameplay integration in the generated terrain is verified separately.
const PLAYER: PackedScene = preload("res://scenes/player.tscn")
const SCENES: PackedStringArray = [
	"res://scenes/bosses/boss_01_cairn.tscn", "res://scenes/bosses/boss_02_gorgon.tscn",
	"res://scenes/bosses/boss_03_ash_oracle.tscn", "res://scenes/bosses/boss_04_mortar.tscn",
	"res://scenes/bosses/boss_05_rift_warden.tscn", "res://scenes/bosses/boss_06_rift_harbinger.tscn"]
var _output: String = "res://screenshots_debug/bosses/capture/"
var _world: Node3D
var _player: PlayerPrototype
var _camera: Camera3D
var _caption: Label
var _detail: Label
var _light: DirectionalLight3D
var _environment: WorldEnvironment
var _lighting: LightingProfile = LightingProfile.new()
var _checks: Array[Dictionary] = []
var _failed: bool = false

func _initialize() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=").trim_suffix("/") + "/"
	call_deferred("_capture")

func _flat_height(_x: int, _z: int) -> int:
	return 0

func _capture() -> void:
	seed(330519)
	DirAccess.make_dir_recursive_absolute(_output)
	_build_arena()
	await _overview()
	_camera.global_position = Vector3(15.0, 20.0, 11.0)
	_camera.look_at(Vector3(0.0, 0.0, -4.0))
	_lighting.apply_night_instant(_light, _environment)
	for stage: int in range(1, 7):
		var boss: SiegeBoss = (load(SCENES[stage - 1]) as PackedScene).instantiate() as SiegeBoss
		boss.configure(stage, _player)
		_world.add_child(boss)
		boss._height_lookup = Callable(self, "_flat_height")
		boss.set_physics_process(false)
		for attack_index: int in range(boss.profile.attacks.size()):
			await _attack(boss, attack_index, 1)
		if stage >= 5:
			await _attack(boss, 0, 2 if stage == 5 else 3)
		boss.queue_free()
		await process_frame
	await _trap_and_trail()
	_caption.text = "BOSS REVIEW COMPLETE"
	_detail.text = "%d authoritative attack samples / %s" % [_checks.size(), "FAIL" if _failed else "PASS"]
	await _save("99_complete")
	var report: FileAccess = FileAccess.open(_output + "gameplay_checks.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed": not _failed, "checks": _checks, "arena": "flat; production camera offset and day/night LightingProfile; not final terrain or balance evidence"}, "\t"))
	print("BOSS_CAPTURE pass=", not _failed, " attack_samples=", _checks.size(), " seed=330519")
	quit(2 if _failed else 0)

func _build_arena() -> void:
	var save: Node = root.get_node("SaveManager")
	if not save.is_test_environment():
		_failed = true
		push_error("CAPTURE_PROFILE_FAIL: isolated storage is required before actor initialization")
		quit(2)
		return
	# The wrapper supplies a fresh isolated profile before autoloads run. Reset
	# its memory as well: actor ready must never inherit another capture's class.
	save.reset_to_defaults()
	var roster: Node = root.get_node("RosterManager")
	roster.selected_slot_index = 0
	roster.run_active = false
	_world = Node3D.new()
	root.add_child(_world)
	current_scene = _world
	var floor_body: StaticBody3D = StaticBody3D.new()
	floor_body.collision_layer = 1
	var collider: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(60.0, 0.4, 60.0)
	collider.shape = box
	floor_body.add_child(collider)
	floor_body.position.y = -0.2
	_world.add_child(floor_body)
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(0.19, 0.24, 0.20)
	material.roughness = 0.94
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = box.size
	floor_mesh.mesh = mesh
	floor_mesh.material_override = material
	floor_body.add_child(floor_mesh)
	# Low-contrast tile seams supply scale without fighting the telegraphs.
	var seam_material: StandardMaterial3D = StandardMaterial3D.new()
	seam_material.albedo_color = Color(0.15, 0.19, 0.16)
	for axis: int in range(2):
		for index: int in range(-12, 13):
			var seam: MeshInstance3D = MeshInstance3D.new()
			var strip: BoxMesh = BoxMesh.new()
			strip.size = Vector3(0.025, 0.015, 48.0) if axis == 0 else Vector3(48.0, 0.015, 0.025)
			seam.mesh = strip
			seam.material_override = seam_material
			seam.position = Vector3(index * 2.0, 0.005, 0.0) if axis == 0 else Vector3(0.0, 0.005, index * 2.0)
			_world.add_child(seam)
	_environment = WorldEnvironment.new()
	_environment.environment = Environment.new()
	var sky: Sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	_environment.environment.sky = sky
	_world.add_child(_environment)
	_light = DirectionalLight3D.new()
	_world.add_child(_light)
	_lighting.apply_base_setup(_light, _environment)
	_lighting.apply_day_instant(_light, _environment)
	_camera = Camera3D.new()
	_camera.fov = 45.0
	_world.add_child(_camera)
	_camera.current = true
	_player = PLAYER.instantiate() as PlayerPrototype
	_world.add_child(_player)
	# Review damage numbers exclude permanent openings, and each derived
	# capture selects its own talents through the ordinary runtime build.
	_player.talents.reset_for_viewer(WarriorTalentCatalog.TALENT_IDS)
	_player.set_physics_process(false)
	# Native input/locomotion are disabled by set_physics_process; carry still uses the real receiver.
	_player.input_enabled = true
	_player.get_node("PortalCompass").hide()
	_player.max_health = 10000.0
	_player.current_health = 10000.0
	_player.position = Vector3(0.0, 0.9, -3.5)
	var layer: CanvasLayer = CanvasLayer.new()
	root.add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(24.0, 20.0)
	_caption.add_theme_font_size_override("font_size", 25)
	_caption.add_theme_constant_override("shadow_offset_x", 2)
	_caption.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_caption)
	_detail = Label.new()
	_detail.position = Vector2(24.0, 56.0)
	_detail.add_theme_font_size_override("font_size", 18)
	_detail.add_theme_color_override("font_color", Color(0.80, 0.86, 0.87))
	_detail.add_theme_color_override("font_shadow_color", Color.BLACK)
	_detail.add_theme_constant_override("shadow_offset_x", 2)
	_detail.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_detail)

func _overview() -> void:
	var models: Array[SiegeBoss] = []
	_player.hide()
	_camera.global_position = Vector3(18.0, 24.0, 23.0)
	_camera.look_at(Vector3(0.0, 1.0, 0.0))
	_caption.text = "CUBE SIEGE / SIX BOSS SILHOUETTES"
	_detail.text = "Waves 5 / 10 / 15 / 20 / 25 / 30 — original articulated voxel models"
	for stage: int in range(1, 7):
		var boss: SiegeBoss = (load(SCENES[stage - 1]) as PackedScene).instantiate() as SiegeBoss
		boss.configure(stage, _player)
		_world.add_child(boss)
		boss.position = Vector3(float((stage - 1) % 3 - 1) * 7.0, 1.5, -4.0 if stage <= 3 else 4.0)
		boss.rotation.y = PI
		boss.set_physics_process(false)
		var label: Label3D = Label3D.new()
		label.text = "%d  %s" % [stage * 5, boss.display_name]
		label.position = Vector3(0.0, 3.3, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 26
		label.pixel_size = 0.009
		boss.add_child(label)
		models.append(boss)
	for frame: int in range(45):
		await process_frame
	await _save("00_silhouettes_day")
	_lighting.apply_night_instant(_light, _environment)
	for frame: int in range(15):
		await process_frame
	await _save("01_silhouettes_night")
	for boss: SiegeBoss in models:
		boss.queue_free()
	await process_frame
	_player.show()

func _attack(boss: SiegeBoss, index: int, phase: int) -> void:
	for child: Node in boss.get_children():
		if child is BossAttackHazard or child is BossProjectile:
			child.queue_free()
	await process_frame
	boss.global_position = Vector3(0.0, 1.5, 0.0)
	boss.velocity = Vector3.ZERO
	_player.global_position = Vector3(0.0, 0.9, -3.5)
	_player.health.is_parrying = false
	_player.health.shield_health = 0.0
	_player.talents.statuses.clear()
	boss.current_health = boss.max_health * (0.20 if phase == 3 else (0.40 if phase == 2 else 1.0))
	boss._attack_index = index - 1
	boss.begin_next_attack()
	var before: float = _player.current_health
	var warning_ok: bool = true
	var spec: BossAttackSpec = boss._attack
	var expected: float = spec.damage
	match spec.kind:
		BossAttackSpec.Kind.LINE_BEAM:
			expected *= spec.active * (1.0 - 3.5 / spec.reach)
		BossAttackSpec.Kind.RADIAL_BEAM:
			expected *= 2.0 * spec.ray_half_angle_degrees / spec.angular_speed_degrees
		BossAttackSpec.Kind.CHASE:
			expected *= 6.0
	var impact_time: float = spec.windup + 0.10
	if spec.kind == BossAttackSpec.Kind.LINE_BEAM:
		impact_time = spec.windup + spec.active * 0.65
	elif spec.kind == BossAttackSpec.Kind.RADIAL_BEAM:
		impact_time = spec.windup + spec.active * (0.5 if spec.radial_variant < 2 else (0.04 if spec.radial_variant == BossAttackSpec.RadialVariant.CENTRE_TO_EDGES else 0.96))
	var frames: int = ceili((spec.windup + spec.active + 0.70) * 30.0)
	var stem: String = "%02d_attack_%d_phase_%d" % [boss.stage, index, phase]
	_caption.text = "WAVE %d / %s / PHASE %d" % [boss.stage * 5, boss.display_name, phase]
	for frame: int in range(frames):
		# Drive the production controller at the recording's fixed 30Hz; hazards use engine physics.
		boss._physics_process(1.0 / 30.0)
		_player.health.update_timers(1.0 / 30.0)
		_detail.text = "%s / %s / %.2fs" % [spec.title, SiegeBoss.State.keys()[boss.state], maxf(0.0, boss._timer)]
		if frame == floori(spec.windup * 30.0 * 0.55):
			warning_ok = is_equal_approx(before, _player.current_health)
			await _save(stem + "_warning")
		if frame == ceili(impact_time * 30.0):
			await _save(stem + "_impact")
		await process_frame
	var loss: float = before - _player.current_health
	var passed: bool = warning_ok and absf(loss - expected) <= 0.04
	_checks.append({"stage": boss.stage, "attack": index, "title": spec.title, "canonical_kind": BossAttackSpec.Kind.keys()[spec.kind], "phase": phase, "warning_safe": warning_ok, "expected_damage": expected, "actual_health_loss": loss, "passed": passed})
	_failed = _failed or not passed
	print("BOSS_SAMPLE ", stem, " expected=", expected, " loss=", loss, " warning_safe=", warning_ok, " pass=", passed)

func _save(stem: String) -> void:
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(_output + stem + ".png")
	if error != OK:
		_failed = true
		push_error("CAPTURE_FRAME_FAIL: %s (%s)" % [stem, error_string(error)])
		quit(2)
		return
	print("CAPTURE_FRAME saved=", stem, ".png")

func _trap_and_trail() -> void:
	for case_index: int in range(2):
		var stage: int = 1 if case_index == 0 else 5
		var boss: SiegeBoss = (load(SCENES[stage - 1]) as PackedScene).instantiate() as SiegeBoss
		boss.configure(stage, _player)
		_world.add_child(boss)
		boss.global_position = Vector3(0, 1.5, 0)
		boss._height_lookup = Callable(self, "_flat_height")
		boss.set_physics_process(false)
		_player.global_position = Vector3(0, 0.9, -3.5)
		boss._attack_index = 0 if case_index == 0 else 1
		boss.begin_next_attack()
		var spec: BossAttackSpec = boss._attack
		var hazard: BossAttackHazard
		for child: Node in boss.get_children():
			if child is BossAttackHazard:
				hazard = child as BossAttackHazard
		var before: float = _player.current_health
		var armed_seen: bool = false
		var fixed_seen: bool = false
		var observed_marks: int = 0
		var duration: float = spec.windup + (1.0 if case_index == 0 else spec.active + 0.35)
		_caption.text = "CANONICAL / " + ("EMPTY LANDING → TRAP → ENTRY" if case_index == 0 else "SIX REAL TRAIL SNAPSHOTS / KEEP MOVING")
		for frame: int in range(ceili(duration * 30.0)):
			var time: float = float(frame) / 30.0
			if case_index == 0:
				_player.global_position.x = 7.0 if time < spec.windup + 0.45 else 0.0
			else:
				_player.global_position.x = time * 3.5
			boss._physics_process(1.0 / 30.0)
			_player.health.update_timers(1.0 / 30.0)
			if case_index == 1 and is_instance_valid(hazard):
				observed_marks = maxi(observed_marks, hazard.marks.size())
			_detail.text = "%s / %.2fs / %s" % [spec.title, time, "TRAP" if case_index == 0 else "MARKS %d/6" % observed_marks]
			if case_index == 0 and frame == ceili((spec.windup + 0.20) * 30.0):
				armed_seen = is_instance_valid(hazard) and hazard.armed_trap and is_equal_approx(before, _player.current_health)
				await _save("07_lob_empty_armed")
			if case_index == 0 and frame == ceili((spec.windup + 0.55) * 30.0):
				await _save("07_lob_trap_entry")
			if case_index == 1 and frame == ceili(spec.mark_gap * 4.0 * 30.0):
				fixed_seen = hazard.marks[0].centre.is_equal_approx(Vector3(0, 0, -3.5)) and hazard.marks.size() >= 4
				await _save("08_chase_moving_fixed_marks")
			await process_frame
		var loss: float = before - _player.current_health
		var passed: bool = (armed_seen and absf(loss - spec.damage) < 0.04) if case_index == 0 else (fixed_seen and observed_marks == 6 and is_equal_approx(loss, 0.0))
		_checks.append({"canonical_case": "empty_lob_then_trap_entry" if case_index == 0 else "moving_hero_fixed_six_marks", "expected_damage": spec.damage if case_index == 0 else 0.0, "actual_health_loss": loss, "armed_or_fixed_seen": armed_seen if case_index == 0 else fixed_seen, "observed_marks": observed_marks, "passed": passed})
		_failed = _failed or not passed
		boss.queue_free()
		await process_frame

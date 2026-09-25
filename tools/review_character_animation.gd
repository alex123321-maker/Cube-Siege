extends SceneTree
## Deterministic review using production orientation/movement/combat/presentation.
## --class 0|1|2 --output res://art/work/issue12/warrior [--foot] [--frames 1080]

var world: Node3D
var players: Array[CharacterBody3D] = []
var camera: Camera3D
var caption: Label
var telemetry: Label
var tick: int = 0
var ready_to_run: bool = false
var output: String
var class_id: int
var foot_review: bool
var max_frames: int
var samples: Array[Dictionary] = []
var baseline_usec: int = 0
var layered_usec: int = 0
var close_feet: bool = false
var lean_review: bool = false
var foot_prototype: RefCounted = preload("res://tools/foot_placement_prototype.gd").new()

func _arg(key: String, fallback: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = args.find(key)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback

func _initialize() -> void:
	call_deferred("_setup")

func _box(position: Vector3, size: Vector3, color: Color) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.position = position
	world.add_child(body)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var cube: BoxMesh = BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	body.add_child(mesh)

func _setup() -> void:
	output = _arg("--output", "res://art/work/issue12/warrior")
	class_id = int(_arg("--class", "0"))
	foot_review = OS.get_cmdline_user_args().has("--foot")
	close_feet = OS.get_cmdline_user_args().has("--close-feet")
	lean_review = OS.get_cmdline_user_args().has("--lean-only")
	max_frames = int(_arg("--frames", "1080"))
	DirAccess.make_dir_recursive_absolute(output)
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.055, 0.07, 0.10)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.85, 0.9, 1)
	environment.ambient_light_energy = 0.7
	environment_node.environment = environment
	world.add_child(environment_node)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.light_energy = 1.5
	light.shadow_enabled = true
	world.add_child(light)
	_box(Vector3(0, -0.25, 0), Vector3(140, 0.5, 140), Color(0.17, 0.21, 0.25))
	# Thin grid strips make stance sliding and movement direction visible.
	for i: int in range(-30, 31):
		var line: MeshInstance3D = MeshInstance3D.new()
		var mesh: BoxMesh = BoxMesh.new()
		mesh.size = Vector3(0.025, 0.002, 120)
		line.mesh = mesh
		line.position = Vector3(i, 0.002, 0)
		world.add_child(line)
	for i: int in 2:
		var player: CharacterBody3D = load("res://scenes/player.tscn").instantiate()
		world.add_child(player)
		player.set_physics_process(false)
		player.set_class(class_id, false)
		var separation: float = 1.2 if close_feet else 2.4
		player.position = Vector3(-separation if i == 0 else separation, 0.91, 0)
		player.get_node("PortalCompass").visible = false
		player.presentation.procedural_enabled = i == 1 or foot_review or lean_review
		if i == 0 and not foot_review and not lean_review:
			player.presentation.pose_layer.layer_weight = 0.0
		if lean_review and i == 0:
			var profile: CharacterAnimationProfile = player.presentation.animation_profile.duplicate()
			profile.movement_lean_limit = 0.0
			player.presentation.set_active_model(player.presentation.active_model, profile)
		if foot_review:
			var profile: CharacterAnimationProfile = player.presentation.animation_profile.duplicate()
			profile.foot_placement_enabled = i == 1
			profile.foot_placement_weight = 1.0
			player.presentation.set_active_model(player.presentation.active_model, profile)
		players.append(player)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 9.0
	world.add_child(camera)
	camera.make_current()
	var canvas: CanvasLayer = CanvasLayer.new()
	root.add_child(canvas)
	caption = Label.new()
	caption.position = Vector2(24, 20)
	caption.add_theme_font_size_override("font_size", 23)
	canvas.add_child(caption)
	telemetry = Label.new()
	telemetry.position = Vector2(24, 530)
	telemetry.add_theme_font_size_override("font_size", 18)
	canvas.add_child(telemetry)
	ready_to_run = true

func _physics_process(_delta: float) -> bool:
	if not ready_to_run:
		return false
	# Movie writer uses 30 fps; physics has its own fixed 60 Hz clock.
	var dt: float = 1.0 / 60.0
	tick += 1
	var t: float = tick * dt
	var move: Vector3 = Vector3.ZERO
	var aim: Vector3 = Vector3.FORWARD
	var section: String = "Idle / slow aim sweep"
	if t < 4:
		aim = Vector3.FORWARD.rotated(Vector3.UP, t * TAU / 4)
	elif t < 12:
		section = "Continuous forward > diagonal > strafe > backward"
		move = Vector3.FORWARD.rotated(Vector3.UP, (t - 4) * TAU / 8)
	elif t < 15:
		section = "180 degree turn in place"
		aim = Vector3.BACK if t < 13.5 else Vector3.FORWARD
	elif t < 18:
		section = "180 degree turn while moving"
		move = Vector3.FORWARD
		aim = Vector3.BACK if t < 16.5 else Vector3.FORWARD
	elif t < 26:
		section = "Moving LMB / RMB / Q / F"
		move = Vector3(0.7, 0, 0.7).normalized()
		# Move the cursor across the body during each authored action wind-up.
		var action_time: float = fposmod(t - 18, 2.0)
		if action_time > 0.10 and action_time < 0.65:
			aim = Vector3.LEFT
	elif t < 29:
		section = "Dash / start-stop while turning"
		move = Vector3.RIGHT if t < 27.5 else Vector3.ZERO
		aim = Vector3.LEFT
	elif t < 33:
		section = "Voxel steps / uneven foot heights"
		move = Vector3.FORWARD
	else:
		section = "Gameplay camera / aim extremes"
		aim = Vector3.FORWARD.rotated(Vector3.UP, (t - 33) * TAU)
	if tick == 1740:
		for i: int in players.size():
			var separation: float = 1.2 if close_feet else 2.4
			players[i].position = Vector3(-separation if i == 0 else separation, 0.91, 2)
			for step: int in 4:
				_box(Vector3(players[i].position.x + 0.25, 0.075 * (step + 1), -step * 1.2), Vector3(1.4, 0.15 * (step + 1), 1.2), Color(0.24, 0.32, 0.35))
	_input_move(move)
	for i: int in players.size():
		var player: CharacterBody3D = players[i]
		player.movement.update_timers(dt)
		player.health.update_timers(dt)
		player.combat.update_timers(dt)
		player.abilities.update_timers(dt, player)
		player.orientation.aim_direction = aim
		player.aim.last_aim_dir = aim
		player.orientation.process_orientation(player, dt, aim, move)
		if tick in [1081, 1201, 1321, 1441]:
			player.combat.attack_cooldown_timer = 0
			player.combat.special_cooldown_timer = 0
			player.health.parry_cooldown_timer = 0
			player.abilities.ultimate_cooldown_timer = 0
			match tick:
				1081: player.perform_attack()
				1201: player.perform_special_attack()
				1321: player.perform_utility()
				1441:
					if class_id == 0:
						var enemy: Node3D = load("res://scenes/enemy_dummy.tscn").instantiate()
						world.add_child(enemy)
						enemy.position = player.position + aim * 3
						enemy.move_speed = 0
						enemy.attack_damage = 0
					player.perform_ultimate()
		if tick == 1561:
			player.movement.dash_cooldown_timer = 0
			player.movement.perform_dash(aim)
		if tick == 1530 and player.abilities.is_dueling:
			player.abilities.end_duel(player)
		player.movement.process_movement(player, dt, null, player.orientation.directional_speed_multiplier)
		var start: int = Time.get_ticks_usec()
		player.presentation.update_animations(player, player.health.is_parrying, player.movement.is_dashing, dt, player.orientation)
		if foot_review:
			foot_prototype.update(player.presentation.pose_layer, dt)
		var elapsed: int = Time.get_ticks_usec() - start
		if i == 0: baseline_usec += elapsed
		else: layered_usec += elapsed
	var target: Vector3 = (players[0].position + players[1].position) * 0.5
	if t >= 33:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.fov = 45
		camera.position = target + Vector3(18, 24, 18)
	else:
		camera.position = target + Vector3(5, 7, 9)
	camera.look_at(target + Vector3.UP * 0.1)
	if lean_review:
		camera.size = 6.0
		camera.position = target + Vector3(3, 5, -8)
		camera.look_at(target + Vector3.UP * 0.1)
	if close_feet:
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 3.4
		camera.position = target + Vector3(0, 2, -8)
		camera.look_at(target + Vector3(0, -0.5, 0))
	caption.text = "%s | %s\nLEFT: %s     RIGHT: %s" % [["WARRIOR", "ARCHER", "ENGINEER"][class_id], section,
		"normal gait" if foot_review else "procedural OFF", "foot placement prototype" if foot_review else "procedural ON"]
	if lean_review:
		caption.text = "%s | %s\nLEFT: movement lean OFF     RIGHT: movement lean ON" % [["WARRIOR", "ARCHER", "ENGINEER"][class_id], section]
	telemetry.text = players[1].presentation.pose_layer.debug_text()
	if tick % 60 == 0:
		var layer: CharacterPoseLayer = players[1].presentation.pose_layer
		samples.append({"time": t, "section": section, "local": str(layer.local_move), "blend": str(layer.blend),
			"phase": layer.phase, "aim": str(layer.aim_yaw), "action": str(players[1].presentation.anim_player.current_animation),
			"action_time": players[1].presentation.anim_player.current_animation_position,
			"speed": players[1].get_real_velocity().length(), "foot_right": layer.right_foot_height, "foot_left": layer.left_foot_height})
	if tick in [120, 290, 420, 600, 729, 910, 1088, 1210, 1330, 1450, 1770, 1820, 2050]:
		_capture("frame_%04d.png" % tick)
	if tick >= max_frames * 2:
		ready_to_run = false
		_input_move(Vector3.ZERO)
		var report: FileAccess = FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
		report.store_string(JSON.stringify({"class": class_id, "foot_prototype": foot_review, "samples": samples,
			"off_mean_usec": float(baseline_usec) / tick, "on_mean_usec": float(layered_usec) / tick}, "  "))
		quit()
	return false

func _input_move(direction: Vector3) -> void:
	Input.action_press("move_right", maxf(direction.x, 0))
	Input.action_press("move_left", maxf(-direction.x, 0))
	Input.action_press("move_down", maxf(direction.z, 0))
	Input.action_press("move_up", maxf(-direction.z, 0))

func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(filename))

extends SceneTree
## Render imported runtime animations and actual gameplay paths as review evidence.
## --mode studio|gameplay --output res://directory [--before res://snapshot.tscn]

var output: String
var mode: String
var world: Node3D
var model: Node3D
var camera: Camera3D
var player: CharacterBody3D
var label: Label
var tick: int = 0
var recording: bool = false
var observations: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_run")

func _arg(name: String, fallback: String) -> String:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = args.find(name)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else fallback

func _run() -> void:
	mode = _arg("--mode", "studio")
	output = _arg("--output", "res://art/work/issue-8/runtime_review")
	DirAccess.make_dir_recursive_absolute(output)
	if mode == "gameplay":
		world = load("res://scenes/main.tscn").instantiate()
		# Controlled arena: actual player, HUD, lighting and unmodified follow camera.
		# Remove procedural obstacles and roaming enemies only in this disposable instance.
		world.get_node("MapGenerator").free()
		for enemy: Node in world.get_node("Enemies").get_children():
			enemy.free()
		root.add_child(world)
		await _frames(20)
		player = world.get_node("Player")
		player.set_class(player.CharacterClass.WARRIOR, false)
		# Open ground outside portal props.
		player.global_position = Vector3(7, .9, 6)
		camera = world.get_node("Camera3D")
		camera.make_current()
		model = player.get_node("Visuals/HeroWarrior")
		await _frames(30)
	else:
		_setup_studio()
		await _frames(3)
		await _studio_stills()
	var canvas := CanvasLayer.new()
	root.add_child(canvas)
	label = Label.new()
	label.position = Vector2(24, 160 if mode == "gameplay" else 24)
	label.add_theme_font_size_override("font_size", 26)
	canvas.add_child(label)
	recording = true

func _setup_studio() -> void:
	world = Node3D.new()
	root.add_child(world)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.075,.085,.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(.85,.9,1)
	env.ambient_light_energy = .65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	world.add_child(env_node)
	for data: Array in [[Vector3(-35,-35,0),1.5],[Vector3(-25,140,0),.65]]:
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = data[0]
		sun.light_energy = data[1]
		sun.shadow_enabled = data[1] > 1.0
		world.add_child(sun)
		sun.directional_shadow_max_distance = 15.0
		sun.shadow_bias = .04
		sun.shadow_normal_bias = .2
	var ground := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(30,30)
	ground.mesh = mesh
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.22,.24,.28)
	ground.material_override = material
	world.add_child(ground)
	model = load("res://assets/models/characters/hero_warrior.tscn").instantiate()
	world.add_child(model)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.1
	world.add_child(camera)
	camera.position = Vector3(3.6,2.6,-6)
	camera.look_at(Vector3(0,1,0))
	camera.make_current()

func _studio_stills() -> void:
	var ap: AnimationPlayer = model.get_node("AnimationPlayer")
	ap.play("idle")
	ap.seek(0,true)
	ap.pause()
	for item: Array in [["front",Vector3(0,1,-6)], ["side",Vector3(-6,1,0)], ["back",Vector3(0,1,6)], ["front_three_quarter",Vector3(3.6,2.6,-6)], ["side_three_quarter",Vector3(-6,2.6,-1.8)], ["back_three_quarter",Vector3(3.6,2.6,6)]]:
		camera.position = item[1]
		camera.look_at(Vector3(0,1,0))
		await _capture(item[0]+".png")
	camera.position = Vector3(3.6,2.6,-6)
	camera.look_at(Vector3(0,1,0))
	for item: Array in [["run", "walk", .12], ["lmb_contact", "attack", .06], ["rmb_contact", "special", .15], ["block", "block", .1], ["ultimate", "ultimate", .3]]:
		camera.size = 3.8 if item[0] == "ultimate" else 3.1
		camera.look_at(Vector3(0,1.3 if item[0] == "ultimate" else 1.0,0))
		ap.play(item[1])
		ap.seek(item[2],true)
		ap.pause()
		await _capture(item[0]+".png")
	var before_path: String = _arg("--before", "")
	if not before_path.is_empty():
		var before: Node3D = load(before_path).instantiate()
		world.add_child(before)
		before.position.x = 1.25
		before.rotation.y = PI
		model.position.x = -1.25
		ap.play("idle")
		ap.seek(0,true)
		ap.pause()
		camera.size = 5.1
		camera.position = Vector3(0,2.5,-7)
		camera.look_at(Vector3(0,1,0))
		var captions := CanvasLayer.new()
		root.add_child(captions)
		for i: int in range(2):
			var caption := Label.new()
			caption.text = "BEFORE / repository HEAD" if i == 0 else "AFTER / Issue #8 candidate"
			caption.position = Vector2(root.size.x * (.1 if i == 0 else .55), 30)
			caption.add_theme_font_size_override("font_size", 22)
			captions.add_child(caption)
		await _capture("before_after.png")
		captions.free()
		before.free()
		model.position.x = 0
		camera.size = 3.8
		camera.position = Vector3(3.6,2.6,-6)
		camera.look_at(Vector3(0,1.3,0))
	# Keep the raised sword inside the frame throughout the continuous movie.
	# Rear-side close-ups make the physical grip and board/forearm gap inspectable.
	for item: Array in [["shield_grip_idle", "idle", .1], ["shield_grip_run", "walk", .12], ["shield_grip_block", "block", .1]]:
		ap.play(item[1])
		ap.seek(item[2],true)
		ap.advance(0)
		ap.pause()
		var hand: Node3D = model.find_child("L_Gauntlet",true,false)
		var target: Vector3 = hand.global_position + Vector3(0,.12,-.08)
		camera.position = target + Vector3(-3,1.2,1.8)
		camera.size = 1.6
		camera.look_at(target)
		await _capture(item[0]+".png")
	camera.position = Vector3(3.6,2.6,-6)
	camera.size = 3.8
	camera.look_at(Vector3(0,1.3,0))

func _process(_delta: float) -> bool:
	if not recording:
		return false
	tick += 1
	var ap: AnimationPlayer = model.get_node("AnimationPlayer")
	match tick:
		1:
			label.text = "Idle"
			ap.play("idle")
		30:
			_observe("idle", "idle")
			_capture("idle_camera.png")
		61:
			label.text = "Run"
			if player:
				Input.action_press("move_right")
			else:
				ap.play("walk")
		90:
			_observe("run", "walk")
			_capture("run_camera.png")
		121:
			Input.action_release("move_right")
			label.text = "LMB"
			if player:
				player.perform_attack()
			else:
				ap.play("attack")
		133:
			if not player: ap.play("idle")
		123:
			_observe("LMB", "attack")
		151:
			label.text = "RMB"
			if player: player.perform_special_attack()
			else: ap.play("special")
		170:
			if not player: ap.play("idle")
		156:
			_observe("RMB", "special")
		181:
			label.text = "Q / Parry"
			if player: player.perform_utility()
			else: ap.play("utility")
		200:
			if not player: ap.play("idle")
		185:
			_observe("Q", "utility" if ap.current_animation != "block" else "block")
		211:
			label.text = "F / Duel"
			if player:
				var enemy: Node3D = load("res://scenes/enemy_dummy.tscn").instantiate()
				world.add_child(enemy)
				enemy.global_position = player.global_position + Vector3(0,0,-3)
				root.warp_mouse(camera.unproject_position(enemy.global_position))
				player.perform_ultimate()
			else:
				ap.play("ultimate")
		240:
			if not player: ap.play("idle")
		220:
			_observe("F", "ultimate")
			if player:
				assert(player.abilities.is_dueling, "F must acquire an actual duel target")
		255:
			if player:
				player.abilities.end_duel(player)
				label.text = "Crowd / gameplay camera"
				for index: int in range(12):
					var enemy: Node3D = load("res://scenes/enemy_dummy.tscn").instantiate()
					world.add_child(enemy)
					enemy.move_speed = 0
					enemy.attack_damage = 0
					var angle: float = TAU * float(index) / 12
					enemy.global_position = player.global_position + Vector3(cos(angle)*3,0,sin(angle)*3)
		280:
			if player: _capture("crowd_camera.png")
		301:
			recording = false
			Input.action_release("move_right")
			var report := FileAccess.open(output.path_join("playback.json"),FileAccess.WRITE)
			assert(report != null)
			report.store_string(JSON.stringify({"mode":mode,"observations":observations},"  "))
			quit()
	return false

func _observe(action: String, expected: String) -> void:
	var ap: AnimationPlayer = model.get_node("AnimationPlayer")
	var row := {"action":action, "animation":ap.current_animation, "time":ap.current_animation_position, "tick":tick}
	if player:
		row["speed"] = Vector2(player.velocity.x, player.velocity.z).length()
		row["duel_active"] = player.abilities.is_dueling
	observations.append(row)
	print("WARRIOR_REVIEW=",JSON.stringify(row))
	assert(ap.current_animation == expected, "Expected " + expected + " during " + action)
	if player and action == "run":
		assert(row["speed"] > 1.0, "Run evidence requires actual movement")

func _frames(count: int) -> void:
	for _i: int in count:
		await process_frame

func _capture(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(output.path_join(filename))
	assert(error == OK, "Cannot save " + filename)

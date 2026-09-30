extends SceneTree

## Inspect all playable rigs using their real class binding and imported clips.
const PLAYER: PackedScene = preload("res://scenes/player.tscn")
var _output: String = "res://docs/verification/vfx_cleave_ability/"
var _player: CharacterBody3D
var _caption: Label

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=").trim_suffix("/") + "/"
	call_deferred("_capture")

func _capture() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	var scene := Node3D.new()
	root.add_child(scene)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.10, 0.13, 0.17)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.86, 1.0)
	environment.ambient_light_energy = 0.7
	environment_node.environment = environment
	scene.add_child(environment_node)
	var light := DirectionalLight3D.new()
	scene.add_child(light)
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.8
	_player = PLAYER.instantiate() as CharacterBody3D
	scene.add_child(_player)
	_player.set_physics_process(false)
	_player.set_process_input(false)
	_player.global_position = Vector3(0, 0.9, 0)
	_player.get_node("PortalCompass").hide()
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	camera.global_position = Vector3(2.4, 1.8, -3.2)
	camera.look_at(Vector3(0, 1, 0))
	var label_layer := CanvasLayer.new()
	root.add_child(label_layer)
	_caption = Label.new()
	_caption.position = Vector2(28, 24)
	_caption.add_theme_font_size_override("font_size", 22)
	label_layer.add_child(_caption)
	DirAccess.make_dir_recursive_absolute(_output)
	for class_id in range(3):
		_player.set_class(class_id, false)
		if is_instance_valid(_player.presentation.blade_trail):
			_player.presentation.blade_trail.hide()
		var names: Array[StringName] = [&"idle", &"attack", &"special"]
		for action: StringName in names:
			_player.presentation._play_action(action)
			for frame in range(50):
				_player.presentation.update_animations(_player, false, false, 1.0 / 60.0, _player.orientation)
				_caption.text = "%s / %s / FRONT IS TOWARD CAMERA (-Z)" % [_player.presentation.active_model.name, action]
				if frame in [0, 6, 12, 18, 30]:
					await RenderingServer.frame_post_draw
					root.get_texture().get_image().save_png(_output + "model_%d_%s_%02d.png" % [class_id, action, frame])
				await process_frame
	_player.hide()
	var enemy_scenes: Array[PackedScene] = [preload("res://scenes/enemy_dummy.tscn"),
		preload("res://scenes/enemies/ranged_skirmisher.tscn"), preload("res://scenes/enemies/siege_breaker.tscn")]
	for index in range(enemy_scenes.size()):
		var enemy: EnemyBase = enemy_scenes[index].instantiate() as EnemyBase
		scene.add_child(enemy)
		enemy.set_physics_process(false)
		enemy.get_node("Visuals/HPLabel").hide()
		_caption.text = "%s / IDLE / FRONT IS TOWARD CAMERA (-Z)" % enemy.name
		for frame in range(20):
			if frame == 6:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(_output + "enemy_%d_idle.png" % index)
			await process_frame
		enemy.queue_free()
		await process_frame
	print("MODEL_FORWARD_CAPTURE classes=3 actions=idle,attack,special enemy_models=3")
	quit()

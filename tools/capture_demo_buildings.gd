extends SceneTree

## Finite render of production prefabs, including campfire lifecycle and build UI.
var _main: Node3D
var _camera: Camera3D
var _output: String = "res://screenshots_debug/demo_buildings"

func _initialize() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	call_deferred("_run")

func _wait_frames(count: int) -> void:
	for index: int in range(count):
		await process_frame

func _capture(filename: String) -> void:
	await _wait_frames(4)
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(_output.path_join(filename))
	if result != OK:
		push_error("Building capture failed: %s" % filename)
		quit(1)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_output)
	seed(20891)
	create_timer(65.0).timeout.connect(func() -> void: quit(2))
	_main = load("res://scenes/main.tscn").instantiate() as Node3D
	var map: MapGenerator = _main.get_node("MapGenerator") as MapGenerator
	map.random_seed = false
	map.custom_seed = 20891
	map.load_radius_chunks = 1
	root.add_child(_main)
	current_scene = _main
	await _wait_frames(90)
	# Resolve the canonical initial checkpoint through the real HUD action,
	# before recording production prefabs or advancing the flame animation.
	var run_player: PlayerPrototype = _main.get_node("Player") as PlayerPrototype
	var run_build: WarriorRunBuild = run_player.progression.run_build
	var build_panel: WarriorBuildPanel = _main.get_node("HUD").get("build_panel") as WarriorBuildPanel
	if run_build.active_reward_id >= 0:
		var options: Array[WarriorTalentDefinition] = run_build.get_talent_options()
		if not options.is_empty():
			build_panel._choose(options[0].id, run_build.active_reward_id)
		else:
			build_panel._focus(run_build.active_reward_id)
	if paused:
		push_error("Building capture could not resume the initial checkpoint")
		quit(1)
		return
	var director: Node = _main.get_node("WaveDirector")
	director.set_process(false)
	director.set_physics_process(false)
	var cycle: DayNightCycle = _main.get_node("DayNightCycle") as DayNightCycle
	cycle.set_process(false)
	var player: PlayerPrototype = _main.get_node("Player") as PlayerPrototype
	player.set_physics_process(false)
	var builder: BuildingSystem = _main.get_node("BuildingSystem") as BuildingSystem
	builder.add_resource(100, 100, 100)
	var cells: Array[Vector2i] = [Vector2i(3, 3), Vector2i(4, 3), Vector2i(5, 3), Vector2i(-3, 3), Vector2i(-4, 3), Vector2i(0, 6)]
	var types: Array[BuildingSystem.PrefabType] = [BuildingSystem.PrefabType.WOOD_WALL, BuildingSystem.PrefabType.IRON_WALL, BuildingSystem.PrefabType.FLOOR_SPIKES, BuildingSystem.PrefabType.ARCHER_TOWER, BuildingSystem.PrefabType.BALLISTA, BuildingSystem.PrefabType.CAMPFIRE]
	for index: int in range(types.size()):
		var cell: Vector2i = cells[index]
		builder.place_building(Vector3(cell.x + 0.5, map.get_voxel_height(cell.x, cell.y), cell.y + 0.5), cell, types[index])
	builder.cancel_build_mode()
	_camera = _main.get_node("Camera3D") as Camera3D
	_camera.set_process(false)
	_camera.set_physics_process(false)
	var focus: Vector3 = player.global_position + Vector3(0, 0, 1.0)
	_camera.global_position = focus + Vector3(15, 20, 15)
	_camera.look_at(focus)
	_camera.make_current()
	await _wait_frames(30)
	await _capture("buildings_gameplay_day.png")
	var fire: Campfire = builder.placed_buildings[Vector2i(0, 6)] as Campfire
	player.global_position = fire.global_position + Vector3(2, 0.9, 0)
	player.current_health = 50
	await _wait_frames(8)
	fire.set_focused(true)
	var sun: DirectionalLight3D = _main.get_node("SunLight") as DirectionalLight3D
	sun.light_energy = 0.38
	sun.light_color = Color(0.44, 0.52, 0.82)
	var world_env: WorldEnvironment = _main.get_node("WorldEnvironment") as WorldEnvironment
	world_env.environment.ambient_light_energy = 0.34
	world_env.environment.ambient_light_color = Color(0.26, 0.36, 0.58)
	await _capture("buildings_gameplay_night.png")
	var radial: Control = _main.get_node("HUD/Margin/RadialMenu") as Control
	radial.toggle_menu()
	radial.open_category("Utility")
	await _capture("campfire_build_menu.png")
	radial.close_menu()
	_main.queue_free()
	await _wait_frames(4)
	await _stage_models()
	print("DEMO_BUILDINGS_CAPTURE_PASS")
	quit(0)

func _stage_models() -> void:
	# This neutral stage diagnoses the production model silhouettes and lighting.
	# The main-scene captures above remain the evidence for actual gameplay readability.
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.09, 0.13, 0.17)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.82, 0.92)
	environment.ambient_light_energy = 0.65
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_environment.environment = environment
	stage.add_child(world_environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = Color(1.0, 0.91, 0.77)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	stage.add_child(sun)
	var ground: MeshInstance3D = MeshInstance3D.new()
	var ground_mesh: PlaneMesh = PlaneMesh.new()
	ground_mesh.size = Vector2(16, 12)
	var ground_material: StandardMaterial3D = StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.23, 0.30, 0.22)
	ground_material.roughness = 0.95
	ground_mesh.material = ground_material
	ground.mesh = ground_mesh
	stage.add_child(ground)
	var names: Array[String] = ["wood_wall", "iron_wall", "floor_spikes", "archer_tower", "ballista_tower", "campfire", "workbench"]
	var positions: Array[Vector3] = [Vector3(-4, 0, 1), Vector3(-2, 0, 1), Vector3(0, 0, 1), Vector3(-3, 0, -2), Vector3(0, 0, -2), Vector3(2, 0, 1), Vector3(3, 0, -2)]
	var models: Array[Node3D] = []
	for index: int in range(names.size()):
		var model: Node3D = load("res://scenes/prefabs/" + names[index] + ".tscn").instantiate() as Node3D
		model.position = positions[index]
		stage.add_child(model)
		model.set_physics_process(false)
		models.append(model)
	_camera = Camera3D.new()
	_camera.fov = 45
	stage.add_child(_camera)
	_camera.global_position = Vector3(11, 14, 11)
	_camera.look_at(Vector3(0, 0.6, 0))
	_camera.make_current()
	await _capture("building_models_isometric_day.png")
	sun.light_energy = 0.34
	sun.light_color = Color(0.42, 0.52, 0.83)
	environment.ambient_light_energy = 0.32
	await _capture("building_models_isometric_night.png")
	var fire: Campfire = models[5] as Campfire
	for model: Node3D in models:
		model.visible = model == fire
	var labels: CanvasLayer = CanvasLayer.new()
	stage.add_child(labels)
	var caption: Label = Label.new()
	caption.position = Vector2(28, 24)
	caption.text = "CAMPFIRE  /  production prefab  /  Forward+"
	caption.add_theme_font_size_override("font_size", 22)
	labels.add_child(caption)
	_camera.global_position = fire.global_position + Vector3(0, 2.1, 3.9)
	_camera.look_at(fire.global_position + Vector3.UP * 0.4)
	await _capture("campfire_front.png")
	_camera.global_position = fire.global_position + Vector3(3.9, 2.1, 0)
	_camera.look_at(fire.global_position + Vector3.UP * 0.4)
	await _capture("campfire_profile.png")
	# A short native frame sequence verifies flicker/ember movement and cleanup.
	_camera.global_position = fire.global_position + Vector3(2.9, 2.9, 2.9)
	_camera.look_at(fire.global_position + Vector3.UP * 0.4)
	DirAccess.make_dir_recursive_absolute(_output.path_join("flame_frames"))
	for index: int in range(90):
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_output.path_join("flame_frames/%03d.png" % index))
	fire.destroy_building()
	await _wait_frames(14)
	await _capture("campfire_extinguished.png")
	stage.queue_free()
	await _wait_frames(4)

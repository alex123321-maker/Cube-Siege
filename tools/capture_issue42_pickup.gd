extends SceneTree
## Capture pristine visual sequence for Issue #42:
## Destruction right next to player -> immediate pickup prompt -> hold E progress -> resource gained.
## Fully driven by real sensor detection, PlayerInteraction holding logic, and Input.action_press("interact").

func _initialize() -> void:
	call_deferred("_run_capture")

func _run_capture() -> void:
	# Safety watchdog timer to prevent hangs
	var watchdog = create_timer(20.0)
	watchdog.timeout.connect(func():
		push_error("[Watchdog] Capture timed out after 20 seconds!")
		quit(1)
	)

	var output: String = "docs/verification/issue42"
	DirAccess.make_dir_recursive_absolute(output)

	var scene_root: Node3D = Node3D.new()
	root.add_child(scene_root)
	current_scene = scene_root

	# World Environment & Directional Light
	var env_node = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.15, 0.2)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.7, 0.75)
	env_node.environment = env
	scene_root.add_child(env_node)

	var sun = DirectionalLight3D.new()
	sun.position = Vector3(10, 20, 10)
	sun.rotation_degrees = Vector3(-50, 45, 0)
	sun.shadow_enabled = true
	scene_root.add_child(sun)

	# Flat ground
	var floor_body = StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	var floor_shape = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(30, 1, 30)
	floor_shape.shape = box
	floor_shape.position = Vector3(0, -0.5, 0)
	floor_body.add_child(floor_shape)

	var floor_mesh = MeshInstance3D.new()
	var plane_mesh = PlaneMesh.new()
	plane_mesh.size = Vector2(30, 30)
	var floor_mat = StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.28, 0.42, 0.22) # Grass green
	plane_mesh.material = floor_mat
	floor_mesh.mesh = plane_mesh
	floor_body.add_child(floor_mesh)
	scene_root.add_child(floor_body)

	# Instantiate HUD first so it connects to EventBus before BuildingSystem triggers initial update
	var hud_scene = load("res://scenes/hud.tscn")
	var hud = hud_scene.instantiate() as CanvasLayer
	scene_root.add_child(hud)
	hud.visible = true

	# Instantiate Player
	var player_scene = load("res://scenes/player.tscn")
	var player = player_scene.instantiate() as CharacterBody3D
	scene_root.add_child(player)
	player.global_position = Vector3(0, 0, 0)

	# Attach BuildingSystem to player
	var bs = BuildingSystem.new()
	bs.name = "BuildingSystem"
	player.add_child(bs)
	player.building_system = bs

	# Instantiate Tree 1.6m next to player (within 4.5m interaction radius)
	var tree_scene = load("res://scenes/resource_tree.tscn")
	var tree = tree_scene.instantiate() as ResourceTree
	scene_root.add_child(tree)
	tree.global_position = Vector3(1.6, 0, 0)

	# Camera setup: angled view showing player, tree, and HUD in top-left
	var camera: Camera3D = Camera3D.new()
	scene_root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 42.0
	camera.position = Vector3(0.8, 2.4, 4.0)
	camera.look_at(Vector3(0.8, 0.9, 0), Vector3.UP)
	camera.make_current()

	# Settle physics and animations
	for i in 20:
		await physics_frame
		await process_frame

	# 1. Intact node
	await _save_frame(output.path_join("1_intact_node.png"))

	# 2. Destroy tree standing right next to it without moving player away
	tree.take_damage(200.0)

	# Let real physics engine update overlapping areas and player.interaction.process_interaction run
	var focus_acquired: bool = false
	for i in 30:
		await physics_frame
		await process_frame
		if player.interaction.focused_interactable == tree:
			focus_acquired = true
			break

	if not focus_acquired:
		push_error("[Issue42 Capture] ERROR: tree was not focused by PlayerInteraction sensor!")
		quit(1)
		return

	print("[Issue42 Capture] Tree focused by real sensor detection: ", player.interaction.focused_interactable.name)
	await _save_frame(output.path_join("2_destroyed_prompt_immediate.png"))

	# 3. Simulate hold progress via actual Input action "interact"
	Input.action_press("interact")
	var reached_halfway: bool = false
	for i in 60:
		await physics_frame
		await process_frame
		if player.interaction.interact_hold_timer >= 0.5:
			reached_halfway = true
			break

	if not reached_halfway:
		push_error("[Issue42 Capture] ERROR: hold progress did not reach 0.5s!")
		Input.action_release("interact")
		quit(1)
		return

	print("[Issue42 Capture] Holding [E] reached ~50%: timer = ", player.interaction.interact_hold_timer)
	await _save_frame(output.path_join("3_hold_progress.png"))

	# 4. Continue holding until harvest completes automatically via PlayerInteraction._execute_interaction
	var harvest_completed: bool = false
	for i in 60:
		await physics_frame
		await process_frame
		if tree.is_harvested:
			harvest_completed = true
			break

	Input.action_release("interact")

	if not harvest_completed:
		push_error("[Issue42 Capture] ERROR: harvest did not complete via hold!")
		quit(1)
		return

	print("[Issue42 Capture] Harvest completed naturally. Wood wallet: ", bs.wallet.get_wood())

	# Settle visual feedback (floating text +4 WOOD, tree mesh fade/scale)
	for i in 25:
		await physics_frame
		await process_frame

	await _save_frame(output.path_join("4_harvest_complete.png"))

	print("[Issue42 Capture] Clean visual capture completed successfully in " + output)
	quit(0)

func _save_frame(path: String) -> void:
	for _frame: int in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	var capture: Image = root.get_texture().get_image()
	if capture == null or capture.is_empty() or capture.save_png(path) != OK:
		push_error("Failed to save capture: " + path)
	else:
		print("[Capture] Saved: " + path)

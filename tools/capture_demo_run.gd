extends SceneTree

## Reproducible real gameplay recording; extra materials only stage the defenses.
## godot --path . --resolution 1280x720 --fixed-fps 30 --write-movie <out>.avi
##       -s tools/capture_demo_run.gd -- --output=<directory>
var _output: String = "res://reports/demo_run"
const DEMO_SEED: int = 8473
const CLEARING_CENTER: Vector2i = Vector2i(-15, 25)

func _initialize() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
	call_deferred("_capture")

func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This capture requires a rendering display.")
		quit(1)
		return
	create_timer(55.0).timeout.connect(func() -> void: quit(2))
	DirAccess.make_dir_recursive_absolute(_output)
	var main: Node3D = load("res://scenes/main.tscn").instantiate() as Node3D
	var map: MapGenerator = main.get_node("MapGenerator") as MapGenerator
	map.random_seed = false
	map.custom_seed = DEMO_SEED
	root.add_child(main)
	current_scene = main
	var player: PlayerPrototype = main.get_node("Player") as PlayerPrototype
	var building: BuildingSystem = main.get_node("BuildingSystem") as BuildingSystem
	var cycle: DayNightCycle = main.get_node("DayNightCycle") as DayNightCycle
	for enemy: Node in main.get_node("Enemies").get_children():
		enemy.queue_free()
	for frame: int in range(45):
		await process_frame
	player.set_class(PlayerPrototype.CharacterClass.WARRIOR, false)
	# Use the real mandatory checkpoint path; choosing a legal offered talent
	# lets the HUD restore its prior pause state and gameplay resume normally.
	var hud: CanvasLayer = main.get_node("HUD") as CanvasLayer
	var talent_panel: WarriorBuildPanel = hud.get("build_panel") as WarriorBuildPanel
	var run_build: WarriorRunBuild = player.progression.run_build
	if run_build.active_reward_id >= 0:
		var options: Array[WarriorTalentDefinition] = run_build.get_talent_options()
		if not options.is_empty():
			talent_panel._choose(options[0].id, run_build.active_reward_id)
		else:
			talent_panel._focus(run_build.active_reward_id)
	if paused:
		push_error("The initial checkpoint did not resume the real run.")
		quit(1)
		return
	# This authored view uses an existing generated flat meadow, keeping the
	# production terrain, scatter, resource density and camera orientation.
	var clearing_height: float = float(map.get_voxel_height(CLEARING_CENTER.x, CLEARING_CENTER.y))
	var player_cell: Vector2i = CLEARING_CENTER + Vector2i(-3, 4)
	player.global_position = Vector3(player_cell.x + 0.5, clearing_height + 0.9, player_cell.y + 0.5)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	var camera: CameraFollow = main.get_node("Camera3D") as CameraFollow
	camera.pan_enabled = false
	camera.set_distance_preset(CameraMath.Preset.MEDIUM, true)
	# A capture-only anchor frames all seven models. The hero stands in the
	# foreground inside the real aura; the floating health bar clears the towers.
	var camera_anchor: Node3D = Node3D.new()
	camera_anchor.name = "DemoCameraAnchor"
	camera_anchor.position = Vector3(CLEARING_CENTER.x + 0.5, clearing_height + 0.9, CLEARING_CENTER.y + 0.5)
	# Its combat-look occlusion probe faces open ground instead of the iron wall.
	camera_anchor.rotation.y = PI
	main.add_child(camera_anchor)
	camera.set_target(camera_anchor)
	building.add_resource(50, 40, 20)
	var placements: Dictionary[Vector2i, BuildingSystem.PrefabType] = {
		Vector2i(-3, 0): BuildingSystem.PrefabType.WOOD_WALL,
		Vector2i(0, -2): BuildingSystem.PrefabType.IRON_WALL,
		Vector2i(-3, -3): BuildingSystem.PrefabType.ARCHER_TOWER,
		Vector2i(3, -3): BuildingSystem.PrefabType.BALLISTA,
		Vector2i(4, 0): BuildingSystem.PrefabType.FLOOR_SPIKES,
		Vector2i(-1, 2): BuildingSystem.PrefabType.CAMPFIRE,
	}
	for relative_cell: Vector2i in placements:
		var cell: Vector2i = CLEARING_CENTER + relative_cell
		if not building.is_cell_free(cell):
			push_error("The deterministic demo staging cell is occupied: %s" % cell)
			quit(1)
			return
		var at: Vector3 = Vector3(cell.x + 0.5, map.get_voxel_height(cell.x, cell.y), cell.y + 0.5)
		building.place_building(at, cell, placements[relative_cell])
	var bench: Node3D = load("res://scenes/prefabs/workbench.tscn").instantiate() as Node3D
	var bench_cell: Vector2i = CLEARING_CENTER + Vector2i(-2, 3)
	bench.position = Vector3(bench_cell.x + 0.5, map.get_voxel_height(bench_cell.x, bench_cell.y), bench_cell.y + 0.5)
	main.add_child(bench)
	# Workbench is a StaticBody3D rather than BuildingBase, so late capture
	# placement must explicitly join/leave the same navigation registry.
	var registry: Node = root.get_node("EntityRegistry")
	registry.register_building(bench)
	bench.tree_exiting.connect(registry.unregister_building.bind(bench))
	building.cancel_build_mode()
	player.current_health = 55.0
	player.health.health_changed.emit(player.current_health, player.max_health)
	var bus: Node = root.get_node("EventBus")
	bus.player_health_changed.emit(player.current_health, player.max_health)
	var before: float = player.current_health
	var inside_position: Vector3 = player.global_position
	var outside_health: float = 0.0
	var fire: Campfire = get_first_node_in_group("campfires") as Campfire
	if fire == null:
		push_error("The staged campfire is missing.")
		quit(1)
		return
	for frame: int in range(480):
		if frame == 60:
			if player.current_health <= before:
				push_error("Expected campfire to restore actual health before night combat.")
				quit(1)
				return
			await _save("day_campfire.png")
		if frame == 75:
			var outside_position: Vector3 = fire.global_position + Vector3(5.01, 0.9, 0.0)
			var ground: float = float(map.get_voxel_height(floori(outside_position.x), floori(outside_position.z)))
			if not is_equal_approx(ground, fire.global_position.y):
				push_error("The campfire boundary capture needs the same meadow height.")
				quit(1)
				return
			outside_health = player.current_health
			player.global_position = outside_position
			player.velocity = Vector3.ZERO
			player.reset_physics_interpolation()
		if frame == 95:
			if fire.contains_player(player.global_position) or not fire.aura_area.overlaps_body(player) or not is_equal_approx(player.current_health, outside_health):
				push_error("Campfire healing must stop immediately outside its exact center radius.")
				quit(1)
				return
			await _save("campfire_exit.png")
			print("CAMPFIRE_EXACT_BOUNDARY_CAPTURE_PASS distance=", Vector2(player.global_position.x - fire.global_position.x, player.global_position.z - fire.global_position.z).length(), " health=", player.current_health)
		if frame == 100:
			var settings: Control = main.get_node("HUD/Margin/SettingsModal") as Control
			settings.open_modal()
			await _save("audio_settings.png")
			settings.close_modal()
		if frame == 105:
			player.global_position = inside_position
			player.velocity = Vector3.ZERO
			player.reset_physics_interpolation()
		if frame == 150:
			cycle.skip_to_night()
		if frame == 280:
			await _save("night_defense.png")
		if frame > 220 and frame % 38 == 0:
			player.combat.perform_attack(player, int(player.current_class), player.is_dashing, player.is_dueling)
		if frame == 300:
			player.combat.perform_special_attack(player, int(player.current_class), false, false, player.abilities)
		if frame == 310:
			await _save("night_cleave.png")
		if frame == 360:
			player.perform_dash()
		await process_frame
	print("DEMO_RUN_CAPTURE_PASS health ", before, " -> ", player.current_health,
		" buildings=", building.placed_buildings.size(), " enemies=", root.get_node("EntityRegistry").get_enemy_count())
	Input.action_release("attack_lmb")
	main.queue_free()
	await process_frame
	quit(0)

func _save(filename: String) -> void:
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	if picture.is_empty() or picture.save_png(_output.path_join(filename)) != OK:
		push_error("Cannot save screenshot: " + filename)
		quit(1)

extends SceneTree

## Reproducible real gameplay recording; extra materials only stage the defenses.
## godot --path . --resolution 1280x720 --fixed-fps 30 --write-movie <out>.avi
##       -s tools/capture_demo_run.gd -- --output=<directory>
var _output: String = "res://reports/demo_run"

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
	create_timer(35.0).timeout.connect(func() -> void: quit(2))
	DirAccess.make_dir_recursive_absolute(_output)
	var main: Node3D = load("res://scenes/main.tscn").instantiate() as Node3D
	var map: MapGenerator = main.get_node("MapGenerator") as MapGenerator
	map.random_seed = false
	map.custom_seed = 1337
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
	building.add_resource(50, 40, 20)
	for cell: Vector2i in [Vector2i(-3, -1), Vector2i(-2, -1), Vector2i(-1, -1)]:
		building.place_building(Vector3(cell.x + 0.5, 0.0, cell.y + 0.5), cell, BuildingSystem.PrefabType.WOOD_WALL)
	building.place_building(Vector3(-3.5, 0.0, 3.5), Vector2i(-4, 3), BuildingSystem.PrefabType.ARCHER_TOWER)
	building.place_building(Vector3(-2.5, 0.0, -3.5), Vector2i(-3, -4), BuildingSystem.PrefabType.BALLISTA)
	building.place_building(Vector3(3.5, 0.0, 4.5), Vector2i(3, 4), BuildingSystem.PrefabType.CAMPFIRE)
	building.cancel_build_mode()
	player.current_health = 55.0
	player.health.health_changed.emit(player.current_health, player.max_health)
	var bus: Node = root.get_node("EventBus")
	bus.player_health_changed.emit(player.current_health, player.max_health)
	var before: float = player.current_health
	for frame: int in range(480):
		if frame == 60:
			await _save("day_campfire.png")
		if frame == 100:
			var settings: Control = main.get_node("HUD/Margin/SettingsModal") as Control
			settings.open_modal()
			await _save("audio_settings.png")
			settings.close_modal()
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
	if player.current_health <= before and player.current_health > 0.0:
		push_error("Expected campfire to restore actual health during the staged run.")
		quit(1)
		return
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

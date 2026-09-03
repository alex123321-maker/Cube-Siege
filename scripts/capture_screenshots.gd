extends Node

func _ready() -> void:
	await run_captures()
	get_tree().quit()

func wait_frames(count: int = 5) -> void:
	for i in range(count):
		await get_tree().process_frame

func capture(filename: String) -> void:
	await wait_frames(3)
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	if img:
		var path = "res://docs/screenshots/" + filename
		var err = img.save_png(path)
		print("Saved screenshot [", err, "]: ", path)

func run_captures() -> void:
	DirAccess.make_dir_recursive_absolute("res://docs/screenshots")
	print("--- Starting Captures ---")

	# ==========================================
	# 1. MAIN MENU & MENUS
	# ==========================================
	var menu_scene = load("res://scenes/main_menu.tscn")
	var menu = menu_scene.instantiate()
	add_child(menu)
	
	menu.show_view("main")
	await wait_frames(10)
	await capture("01_main_menu.png")

	menu.show_view("characters")
	await wait_frames(10)
	await capture("02_character_selection.png")

	menu.open_talents_for_slot(0)
	await wait_frames(10)
	await capture("03_mastery_talents.png")

	menu.queue_free()
	await wait_frames(5)

	# ==========================================
	# 2. GAMEPLAY SCENE
	# ==========================================
	var main_scene = load("res://scenes/main.tscn")
	var main = main_scene.instantiate()
	add_child(main)
	await wait_frames(10)

	var cam: Camera3D = main.get_node_or_null("Camera3D")
	if cam:
		cam.make_current()

	var hud = main.get_node_or_null("HUD")
	var player = main.get_node_or_null("Player")
	var day_night = main.get_node_or_null("DayNightCycle")
	var radial = hud.get_node_or_null("RadialMenu") if hud else null
	var draft = hud.get_node_or_null("CardDraftPopup") if hud else null
	var bench = hud.get_node_or_null("WorkbenchModal") if hud else null
	var overlay = hud.get_node_or_null("GameOverOverlay") if hud else null

	if radial:
		radial.close_menu()
	if draft:
		draft.visible = false
	if bench:
		bench.close()
	if overlay:
		overlay.visible = false

	if hud:
		if hud.has_method("_on_resources_changed"):
			hud._on_resources_changed(24, 18, 9)
		if hud.has_method("_on_xp_changed"):
			hud._on_xp_changed(680, 1000, 4)
		if hud.has_method("_on_health_changed"):
			hud._on_health_changed(190, 200)

	# Build defenses around base
	var wall_scene = load("res://scenes/prefabs/wood_wall.tscn")
	var tower_scene = load("res://scenes/prefabs/archer_tower.tscn")
	var spikes_scene = load("res://scenes/prefabs/floor_spikes.tscn")

	if wall_scene:
		for x in [-4.0, -2.0, 2.0, 4.0]:
			var w = wall_scene.instantiate()
			w.position = Vector3(x, 0, 3.0)
			main.add_child(w)

	if tower_scene:
		var t1 = tower_scene.instantiate()
		t1.position = Vector3(-6.0, 0, 3.0)
		main.add_child(t1)

		var t2 = tower_scene.instantiate()
		t2.position = Vector3(6.0, 0, 3.0)
		main.add_child(t2)

	if spikes_scene:
		for x in [-3.0, 0.0, 3.0]:
			var sp = spikes_scene.instantiate()
			sp.position = Vector3(x, 0, 5.0)
			main.add_child(sp)

	await wait_frames(25)
	await capture("04_gameplay_day.png")

	# --- 5. RADIAL BUILDING MENU ---
	if radial:
		radial.is_open = true
		radial.visible = true
		radial.open_category("Towers")
	await wait_frames(10)
	await capture("05_radial_build_menu.png")
	if radial:
		radial.close_menu()
	await wait_frames(5)

	# --- 6. CARD DRAFT POPUP ---
	if draft:
		draft.open_draft(player, 5)
	await wait_frames(10)
	await capture("06_card_draft.png")
	if draft:
		draft.visible = false
	await wait_frames(5)

	# --- 7. WORKBENCH MODAL ---
	if bench:
		bench.open()
	await wait_frames(10)
	await capture("07_workbench_crafting.png")
	if bench:
		bench.close()
	await wait_frames(5)

	# --- 8. NIGHT PHASE & BOSS BATTLE ---
	if day_night:
		day_night.is_night = true
		day_night.time_left = 112.0
		day_night.update_hud_display()
		if day_night.sun_light:
			day_night.sun_light.light_color = Color(0.3, 0.4, 0.75, 1.0)
			day_night.sun_light.light_energy = 0.4
		if day_night.world_env and day_night.world_env.environment:
			day_night.world_env.environment.ambient_light_energy = 0.35
			day_night.world_env.environment.ambient_light_color = Color(0.18, 0.22, 0.4, 1.0)

	if main.has_method("spawn_boss_gorgon"):
		main.spawn_boss_gorgon()

	var dummy_scene = load("res://scenes/enemy_dummy.tscn")
	if dummy_scene:
		for pos in [Vector3(-3, 0.9, -5), Vector3(4, 0.9, -7), Vector3(0, 0.9, -8)]:
			var en = dummy_scene.instantiate()
			en.position = pos
			main.add_child(en)

	await wait_frames(25)
	await capture("08_night_boss_battle.png")

	# --- 9. EXTRACTION VICTORY ---
	if overlay and overlay.has_method("show_victory"):
		overlay.show_victory()
	await wait_frames(10)
	await capture("09_extraction_victory.png")

	print("--- All Captures Finished Successfully! ---")

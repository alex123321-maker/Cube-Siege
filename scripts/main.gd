extends Node3D

@onready var building_system: Node = $BuildingSystem
@onready var radial_menu: Control = $HUD/RadialMenu
@onready var player: Node = $Player
@onready var overlay: Control = $HUD/GameOverOverlay
@onready var save_manager: Node = get_node_or_null("/root/SaveManager")
@onready var day_night: Node = $DayNightCycle
@onready var hud: CanvasLayer = $HUD
@onready var map_generator: Node = get_node_or_null("MapGenerator")
@onready var enemies_container: Node = get_node_or_null("Enemies")

func _ready() -> void:
	if radial_menu and building_system:
		radial_menu.prefab_selected.connect(building_system.select_prefab)

	if player and player.has_signal("player_died"):
		player.player_died.connect(_on_player_died)

	var eb = get_node_or_null("/root/EventBus")
	if eb:
		eb.portal_evacuated.connect(_on_portal_evacuated)

	if map_generator and map_generator.has_signal("map_generated"):
		map_generator.map_generated.connect(_on_map_generated)

	_align_starting_entities()

func _on_map_generated(_seed: int) -> void:
	_align_starting_entities()

func _align_starting_entities() -> void:
	if not map_generator or not enemies_container:
		return
	for enemy in enemies_container.get_children():
		if enemy is Node3D:
			var ex: int = int(floorf(enemy.global_position.x))
			var ez: int = int(floorf(enemy.global_position.z))
			var y_floor: int = 0
			if map_generator.has_method("get_voxel_height"):
				y_floor = map_generator.get_voxel_height(ex, ez)
			elif "actual_seed" in map_generator:
				y_floor = BiomeSystem.get_voxel_height(ex, ez, map_generator.actual_seed)
			enemy.global_position.y = float(y_floor) + 0.9

func _exit_tree() -> void:
	var eb = get_node_or_null("/root/EventBus")
	if eb and eb.portal_evacuated.is_connected(_on_portal_evacuated):
		eb.portal_evacuated.disconnect(_on_portal_evacuated)

func _on_portal_evacuated(_day: int, _xp: int) -> void:
	if is_queued_for_deletion() or not is_inside_tree():
		return
	show_victory()

func _input(event: InputEvent) -> void:

	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_B and OS.is_debug_build():
			spawn_boss_gorgon()

func spawn_boss_gorgon() -> void:
	var boss_scene = preload("res://scenes/enemies/boss_gorgon.tscn")
	var boss = boss_scene.instantiate()
	add_child(boss)
	if player:
		boss.global_position = player.global_position + Vector3(0, 0, -18)
	if hud and hud.has_method("show_boss_bar"):
		hud.show_boss_bar(boss)
	var eb = get_node_or_null("/root/EventBus")
	if eb:
		eb.boss_spawned.emit(boss)

func _on_player_died() -> void:
	if save_manager:
		save_manager.record_defeat("Warrior")
	if overlay:
		overlay.show_game_over()

func show_victory() -> void:
	var days: int = 1
	if day_night and day_night.get("current_day") != null:
		days = day_night.current_day

	if save_manager:
		save_manager.record_victory("Warrior", "Warrior", days)

	if overlay:
		overlay.show_victory()

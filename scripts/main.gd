extends Node3D

@onready var building_system: Node = $BuildingSystem
@onready var radial_menu: Control = $HUD/RadialMenu
@onready var player: Node = $Player
@onready var overlay: Control = $HUD/GameOverOverlay
@onready var save_manager: Node = get_node_or_null("/root/SaveManager")
@onready var day_night: Node = $DayNightCycle
@onready var hud: CanvasLayer = $HUD

func _ready() -> void:
	if radial_menu and building_system:
		radial_menu.prefab_selected.connect(building_system.select_prefab)

	if player and player.has_signal("player_died"):
		player.player_died.connect(_on_player_died)

	var eb = get_node_or_null("/root/EventBus")
	if eb:
		eb.portal_evacuated.connect(func(_day: int, _xp: int): show_victory())

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

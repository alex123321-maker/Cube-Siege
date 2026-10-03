extends Node3D

@onready var building_system: Node = get_node_or_null("BuildingSystem")
@onready var radial_menu: Control = get_node_or_null("HUD/Margin/RadialMenu")
@onready var player: Node = get_node_or_null("Player")
@onready var overlay: Control = get_node_or_null("HUD/Margin/GameOverOverlay")
@onready var save_manager: Node = get_node_or_null("/root/SaveManager")
@onready var day_night: Node = get_node_or_null("DayNightCycle")
@onready var hud: CanvasLayer = get_node_or_null("HUD")
@onready var map_generator: Node = get_node_or_null("MapGenerator")
@onready var enemies_container: Node = get_node_or_null("Enemies")
var run_coordinator: WarriorRunCoordinator

func _ready() -> void:
	if radial_menu and building_system:
		radial_menu.prefab_selected.connect(building_system.select_prefab)

	if player is PlayerPrototype and day_night is DayNightCycle and get_node_or_null("WaveDirector") is WaveDirector:
		run_coordinator = WarriorRunCoordinator.new()
		add_child(run_coordinator)
		run_coordinator.setup(player as PlayerPrototype, day_night as DayNightCycle, get_node("WaveDirector") as WaveDirector, get_node("Portal") as PortalController)
		run_coordinator.run_finished.connect(_on_run_finished)
		run_coordinator.persistence_failed.connect(_on_persistence_failed)
		if overlay:
			overlay.retry_save_requested.connect(run_coordinator.retry_save)

	if map_generator and map_generator.has_signal("map_generated"):
		map_generator.map_generated.connect(_on_map_generated)

	_align_starting_entities()

func _on_map_generated(_seed: int) -> void:
	_align_starting_entities()

func _align_starting_entities() -> void:
	if not map_generator or not enemies_container:
		return
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if is_inside_tree() else null
	for enemy in enemies_container.get_children():
		if enemy is Node3D:
			var ex: int = int(floorf(enemy.global_position.x))
			var ez: int = int(floorf(enemy.global_position.z))
			var y_floor: int = 0
			if map_generator.has_method("get_voxel_height"):
				y_floor = map_generator.get_voxel_height(ex, ez)
			elif "actual_seed" in map_generator:
				y_floor = BiomeSystem.get_voxel_height(ex, ez, map_generator.actual_seed)
			var candidate_pos: Vector3 = enemy.global_position
			var valid_pos_found: bool = true
			if enemy is CharacterBody3D:
				candidate_pos.y = MonsterLocomotion.calculate_spawn_y(float(y_floor), enemy as CharacterBody3D)
				if space_state:
					if not MonsterLocomotion.validate_safe_spawn_point(space_state, enemy as CharacterBody3D, candidate_pos):
						valid_pos_found = false
						for offset in [
							Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1),
							Vector3(1, 0, 1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, -1)
						]:
							var alt_pos: Vector3 = candidate_pos + offset
							var alt_y: float = float(y_floor)
							if map_generator.has_method("get_voxel_height"):
								alt_y = float(map_generator.get_voxel_height(int(floorf(alt_pos.x)), int(floorf(alt_pos.z))))
							alt_pos.y = MonsterLocomotion.calculate_spawn_y(alt_y, enemy as CharacterBody3D)
							if MonsterLocomotion.validate_safe_spawn_point(space_state, enemy as CharacterBody3D, alt_pos):
								candidate_pos = alt_pos
								valid_pos_found = true
								break
			else:
				candidate_pos.y = float(y_floor) + 0.9

			if valid_pos_found:
				enemy.global_position = candidate_pos
			else:
				var reg = get_node_or_null("/root/EntityRegistry")
				if reg and reg.has_method("unregister_enemy"):
					reg.unregister_enemy(enemy)
				if enemy.get_parent():
					enemy.get_parent().remove_child(enemy)
				enemy.queue_free()

func _exit_tree() -> void:
	pass

func _on_portal_evacuated(_day: int, _xp: int) -> void:
	pass # Kept for old capture scripts; coordinator owns the live event.

func _on_run_finished(won: bool, extracted: bool, earned_xp: int) -> void:
	if not overlay:
		return
	if extracted:
		overlay.show_result(won, earned_xp)
	else:
		overlay.show_game_over()

func _on_persistence_failed(message: String) -> void:
	if overlay:
		overlay.show_save_error(message)

func _input(event: InputEvent) -> void:

	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_B and OS.is_debug_build():
			spawn_boss_gorgon()

func spawn_boss_gorgon() -> void:
	var director: WaveDirector = get_node_or_null("WaveDirector") as WaveDirector
	if director:
		director.spawn_boss(WarriorRunCoordinator.BOSS_SCENES[1], 2)

func _on_player_died() -> void:
	if overlay:
		overlay.show_game_over()

func show_victory() -> void:
	if overlay:
		overlay.show_victory()

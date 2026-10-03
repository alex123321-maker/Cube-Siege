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

var run_audio: RunAudio

func _ready() -> void:
	run_audio = RunAudio.new()
	run_audio.name = "RunAudio"
	run_audio.setup(player as PlayerPrototype, day_night as DayNightCycle)
	add_child(run_audio)
	if radial_menu and building_system:
		radial_menu.prefab_selected.connect(building_system.select_prefab)

	if player and player.has_signal("player_died"):
		player.player_died.connect(_on_player_died)

	var eb = get_node_or_null("/root/EventBus")
	if eb:
		eb.portal_evacuated.connect(_on_portal_evacuated)
		eb.night_started.connect(_on_night_started)

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
	var eb = get_node_or_null("/root/EventBus")
	if eb and eb.portal_evacuated.is_connected(_on_portal_evacuated):
		eb.portal_evacuated.disconnect(_on_portal_evacuated)
	if eb and eb.night_started.is_connected(_on_night_started):
		eb.night_started.disconnect(_on_night_started)

func _on_night_started(day_number: int) -> void:
	if day_number == 10:
		# Let the phase transition finish, then create the canonical first boss.
		call_deferred("spawn_boss_gorgon")

func _on_portal_evacuated(_day: int, _xp: int) -> void:
	if is_queued_for_deletion() or not is_inside_tree():
		return
	show_victory()

func _input(event: InputEvent) -> void:

	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_B and OS.is_debug_build():
			spawn_boss_gorgon()

func spawn_boss_gorgon() -> bool:
	var registry: Node = get_node_or_null("/root/EntityRegistry")
	if registry and registry.has_active_boss():
		return false
	var boss_scene = preload("res://scenes/enemies/boss_gorgon.tscn")
	var boss = boss_scene.instantiate()
	var spawn_pos: Vector3 = Vector3.ZERO
	if player:
		spawn_pos = player.global_position + Vector3(0, 0, -18)
	var map_gen = get_tree().get_first_node_in_group("map_generator") if is_inside_tree() else null
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state if is_inside_tree() else null

	var valid_spawn_pos: Vector3 = spawn_pos
	var found_valid: bool = false
	var candidate_offsets: Array[Vector3] = [
		Vector3.ZERO,
		Vector3(2, 0, 0), Vector3(-2, 0, 0), Vector3(0, 0, 2), Vector3(0, 0, -2),
		Vector3(2, 0, 2), Vector3(-2, 0, 2), Vector3(2, 0, -2), Vector3(-2, 0, -2)
	]
	# Search the whole spawn ring as well as the initial side. A forest deposit
	# or a steep ledge should not prevent the wave-10 encounter from appearing.
	for ring_radius: float in [14.0, 18.0, 22.0]:
		for angle_index in range(12):
			var angle: float = float(angle_index) * TAU / 12.0
			candidate_offsets.append(Vector3(cos(angle) * ring_radius, 0.0, sin(angle) * ring_radius) + Vector3(0, 0, 18))

	for offset in candidate_offsets:
		var cand: Vector3 = spawn_pos + offset
		var terrain_y: float = 0.0
		if map_gen and map_gen.has_method("get_voxel_height"):
			terrain_y = float(map_gen.get_voxel_height(TerrainCombatRules.world_to_voxel(cand.x), TerrainCombatRules.world_to_voxel(cand.z)))
		cand.y = MonsterLocomotion.calculate_spawn_y(terrain_y, boss)
		if space_state and boss is CharacterBody3D:
			if not MonsterLocomotion.validate_safe_spawn_point(space_state, boss as CharacterBody3D, cand, 1.5):
				continue
		valid_spawn_pos = cand
		found_valid = true
		break

	if not found_valid:
		boss.queue_free()
		return false

	boss.position = valid_spawn_pos
	add_child(boss)
	if hud and hud.has_method("show_boss_bar"):
		hud.show_boss_bar(boss)
	var eb = get_node_or_null("/root/EventBus")
	if eb:
		eb.boss_spawned.emit(boss)
	return true

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

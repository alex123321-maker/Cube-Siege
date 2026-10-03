extends Node
class_name WaveDirector

@export var day_night_path: NodePath
@export var player_path: NodePath

@export var spawn_interval: float = 1.6
@export var max_concurrent_enemies: int = 20

var is_active: bool = false
var spawn_timer: float = 0.0
var current_wave: int = 1

var player: Node3D = null
var day_night: Node = null

const ENEMY_GRUNT = preload("res://scenes/enemy_dummy.tscn")
const ENEMY_SIEGE = preload("res://scenes/enemies/siege_breaker.tscn")
const ENEMY_RANGED = preload("res://scenes/enemies/ranged_skirmisher.tscn")

func _ready() -> void:
	if has_node(day_night_path):
		day_night = get_node(day_night_path)
		day_night.phase_changed.connect(_on_phase_changed)

	if has_node(player_path):
		player = get_node(player_path)

func _process(delta: float) -> void:
	if not is_active:
		return

	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = spawn_interval
		try_spawn_wave_enemy()

func _on_phase_changed(is_night: bool, day_number: int) -> void:
	is_active = is_night
	current_wave = day_number
	spawn_timer = 0.0
	spawn_interval = maxf(1.35, 3.2 - float(current_wave) * 0.06)
	max_concurrent_enemies = mini(42, 10 + current_wave)

	if not is_night:
		# Morning sun burns surviving weak grunts
		var reg = get_node_or_null("/root/EntityRegistry")
		var enemies: Array[Node] = []
		if reg:
			enemies = reg.get_enemies().duplicate()
		for e in get_tree().get_nodes_in_group("enemies"):
			if not enemies.has(e):
				enemies.append(e)

		for e in enemies:
			if is_instance_valid(e):
				# Sunrise is cleanup, never a kill or XP reward.
				if reg:
					reg.unregister_enemy(e)
				if e is EnemyBase:
					(e as EnemyBase).is_dying = true
				e.remove_from_group("enemies")
				e.queue_free()

var safe_zone_cells: Dictionary = {}

func set_safe_zone_cells(cells: Array[Vector2i]) -> void:
	safe_zone_cells.clear()
	for c in cells:
		safe_zone_cells[c] = true

func try_spawn_wave_enemy() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	var enemy_count: int = reg.get_enemy_count() if reg else get_tree().get_nodes_in_group("enemies").size()
	var has_boss: bool = reg.has_active_boss() if reg else not get_tree().get_nodes_in_group("boss").is_empty()
	var effective_max: int = 4 if has_boss else max_concurrent_enemies
	if enemy_count >= effective_max:
		return

	if not player or not is_instance_valid(player):
		var players: Array[Node] = get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			player = players[0] as Node3D
		else:
			return
	# Select mob archetype based on wave index and roll
	var roll: float = randf()
	var mob_scene: PackedScene = ENEMY_GRUNT

	if current_wave <= 2:
		if roll < 0.15:
			mob_scene = ENEMY_RANGED
		else:
			mob_scene = ENEMY_GRUNT
	else:
		if current_wave >= 4 and roll < 0.15:
			mob_scene = ENEMY_SIEGE
		elif roll < (0.25 if current_wave < 10 else 0.40):
			mob_scene = ENEMY_RANGED
		else:
			mob_scene = ENEMY_GRUNT

	var enemy_instance: Node3D = mob_scene.instantiate()
	var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state if (player and player.is_inside_tree()) else null

	var found_valid_spawn: bool = false
	var valid_spawn_pos: Vector3 = Vector3.ZERO

	# Test up to 8 candidate positions in the annular ring (20m - 28m)
	for attempt in range(8):
		var angle: float = randf() * TAU
		var ring_radius: float = randf_range(20.0, 28.0)
		var candidate_pos: Vector3 = player.global_position + Vector3(cos(angle) * ring_radius, 0.0, sin(angle) * ring_radius)

		# Reject candidate if inside safe zone
		var cell: Vector2i = TerrainCombatRules.world_pos_to_voxel(candidate_pos)
		if safe_zone_cells.has(cell):
			continue

		var terrain_y: float = get_terrain_surface_y(candidate_pos)
		candidate_pos.y = MonsterLocomotion.calculate_spawn_y(terrain_y, enemy_instance)

		# Validate physical clearance and ground support
		if space_state and enemy_instance is CharacterBody3D:
			if not MonsterLocomotion.validate_safe_spawn_point(space_state, enemy_instance as CharacterBody3D, candidate_pos):
				continue

		valid_spawn_pos = candidate_pos
		found_valid_spawn = true
		break

	if not found_valid_spawn:
		# All candidate positions occupied or invalid: safely postpone spawn
		enemy_instance.queue_free()
		return

	# Set position prior to entering tree so _enter_tree registers at authoritative position
	enemy_instance.position = valid_spawn_pos
	get_parent().add_child(enemy_instance)
	if enemy_instance is EnemyBase:
		var enemy: EnemyBase = enemy_instance as EnemyBase
		var elite: bool = current_wave > 5 and randf() < minf(0.18, 0.06 + float(current_wave) * 0.004)
		var health_multiplier: float = (1.0 + float(current_wave - 1) * 0.025) * (2.0 if elite else 1.0)
		enemy.max_health *= health_multiplier
		enemy.current_health = enemy.max_health
		if elite:
			enemy.set_meta("elite", true)
			enemy.move_speed *= 1.12
			var visuals: Node3D = enemy.get_node_or_null("Visuals") as Node3D
			if visuals:
				visuals.scale *= 1.20
			enemy.shield_health = 35.0 + float(current_wave)
		enemy.update_hp_label()
	if reg:
		reg.register_enemy(enemy_instance)

func stop() -> void:
	is_active = false

func spawn_boss(scene: PackedScene, stage: int) -> SiegeBoss:
	if not player or not is_instance_valid(player):
		return null
	var boss: SiegeBoss = scene.instantiate() as SiegeBoss
	if not boss:
		return null
	boss.configure(stage, player)
	var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	for attempt: int in range(16):
		var angle: float = float(attempt) / 16.0 * TAU
		var candidate: Vector3 = player.global_position + Vector3(cos(angle), 0, sin(angle)) * 11.0
		candidate.y = MonsterLocomotion.calculate_spawn_y(get_terrain_surface_y(candidate), boss)
		if not MonsterLocomotion.validate_safe_spawn_point(space_state, boss, candidate, 1.5):
			continue
		boss.position = candidate
		get_parent().add_child(boss)
		var bus: Node = get_node_or_null("/root/EventBus")
		if bus:
			bus.boss_spawned.emit(boss)
		return boss
	boss.queue_free()
	return null

func get_terrain_surface_y(pos: Vector3) -> float:
	var map_gen = get_tree().get_first_node_in_group("map_generator") if is_inside_tree() else null
	if map_gen and map_gen.has_method("get_voxel_height"):
		return float(map_gen.get_voxel_height(TerrainCombatRules.world_to_voxel(pos.x), TerrainCombatRules.world_to_voxel(pos.z)))
	return 0.0

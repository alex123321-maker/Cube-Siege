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

	if not is_night:
		# Morning sun burns surviving weak grunts
		var reg = get_node_or_null("/root/EntityRegistry")
		var enemies: Array[Node] = reg.get_enemies().duplicate() if (reg and not reg.enemies.is_empty()) else get_tree().get_nodes_in_group("enemies")
		for e in enemies:
			if is_instance_valid(e) and e.has_method("die"):
				e.die()

var safe_zone_cells: Dictionary = {}

func set_safe_zone_cells(cells: Array[Vector2i]) -> void:
	safe_zone_cells.clear()
	for c in cells:
		safe_zone_cells[c] = true

func try_spawn_wave_enemy() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	var enemy_count: int = reg.get_enemy_count() if (reg and not reg.enemies.is_empty()) else get_tree().get_nodes_in_group("enemies").size()
	var has_boss: bool = reg.has_active_boss() if (reg and not reg.bosses.is_empty()) else not get_tree().get_nodes_in_group("boss").is_empty()
	var effective_max: int = 4 if has_boss else max_concurrent_enemies
	if enemy_count >= effective_max:
		return

	if not player or not is_instance_valid(player):
		var players: Array[Node] = get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			player = players[0] as Node3D
		else:
			return

	# Annular ring outside camera FOV: Radius 20m - 28m
	var angle: float = randf() * TAU
	var radius: float = randf_range(20.0, 28.0)
	var spawn_pos: Vector3 = player.global_position + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)

	# Clamp within arena ground
	spawn_pos.x = clamp(spawn_pos.x, -36.0, 36.0)
	spawn_pos.z = clamp(spawn_pos.z, -36.0, 36.0)
	spawn_pos.y = 0.9

	# If inside SafeZone, reject spawn!
	var cell: Vector2i = Vector2i(round(spawn_pos.x), round(spawn_pos.z))
	if safe_zone_cells.has(cell):
		return

	# Select mob archetype based on wave index and roll
	var roll: float = randf()
	var mob_scene: PackedScene = ENEMY_GRUNT

	if current_wave == 1:
		if roll < 0.25:
			mob_scene = ENEMY_RANGED
		else:
			mob_scene = ENEMY_GRUNT
	else:
		if roll < 0.25:
			mob_scene = ENEMY_SIEGE
		elif roll < 0.50:
			mob_scene = ENEMY_RANGED
		else:
			mob_scene = ENEMY_GRUNT

	var enemy_instance: Node3D = mob_scene.instantiate()
	get_parent().add_child(enemy_instance)
	enemy_instance.global_position = spawn_pos
	if reg:
		reg.register_enemy(enemy_instance)

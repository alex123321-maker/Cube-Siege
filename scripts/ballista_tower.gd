extends "res://scripts/building_base.gd"

@export var attack_range: float = 14.0
@export var fire_rate: float = 2.4
@export var bolt_damage: float = 120.0

var fire_timer: float = 0.0

const ARROW_SCENE = preload("res://scenes/prefabs/arrow_projectile.tscn")
const TowerTargeting = preload("res://scripts/tower_targeting.gd")

@onready var bow_pivot: Node3D = $Visuals/BowPivot

func _ready() -> void:
	super._ready()
	building_name = "Heavy Ballista"
	max_health = 600.0
	current_health = 600.0
	wood_cost = 0
	stone_cost = 4
	iron_cost = 4
	add_to_group("towers")

func _physics_process(delta: float) -> void:
	fire_timer -= delta
	if fire_timer <= 0.0:
		var target: Node3D = TowerTargeting.find_nearest_enemy(get_tree(), global_position, attack_range)
		if target:
			fire_at(target)
			fire_timer = fire_rate

func fire_at(target: Node3D) -> void:
	var target_pos: Vector3 = target.global_position + Vector3(0, 0.8, 0)
	var spawn_pos: Vector3 = global_position + Vector3(0, 2.4, 0)
	var to_target: Vector3 = target_pos - spawn_pos
	if to_target.length_squared() < 0.01:
		return

	var aim_dir: Vector3 = to_target.normalized()

	if bow_pivot:
		var horiz: Vector3 = Vector3(aim_dir.x, 0, aim_dir.z)
		if horiz.length_squared() > 0.01:
			bow_pivot.look_at(bow_pivot.global_position + horiz.normalized(), Vector3.UP)

	var arrow: Node3D = ARROW_SCENE.instantiate()
	get_parent().add_child(arrow)
	arrow.global_position = spawn_pos + aim_dir * 1.4
	arrow.scale = Vector3(1.8, 1.8, 2.5) # Heavy ballista harpoon
	arrow.setup(aim_dir, bolt_damage, self, 3)

extends "res://scripts/enemy_base.gd"

@export var building_damage: float = 45.0
@export var player_damage: float = 18.0
@export var attack_cooldown: float = 1.8

var target_entity: Node3D = null
var attack_timer: float = 0.0
var retarget_timer: float = 0.0
const RETARGET_INTERVAL: float = 0.8

func _ready() -> void:
	max_health = 220.0
	move_speed = 2.4
	super._ready()

func _get_xp_reward() -> float:
	return 60.0

func _apply_knockback(knockback: Vector3) -> void:
	# Siege breaker resists 60% of knockback due to heavy weight
	knockback_velocity = knockback * 0.4

func _custom_physics(delta: float) -> void:
	if attack_timer > 0.0:
		attack_timer -= delta

	retarget_timer -= delta
	if not target_entity or not is_instance_valid(target_entity) or retarget_timer <= 0.0:
		retarget_timer = RETARGET_INTERVAL
		find_target()

	if target_entity and is_instance_valid(target_entity):
		var to_target: Vector3 = target_entity.global_position - global_position
		to_target.y = 0.0
		var dist: float = to_target.length()

		if dist > 0.1:
			var move_dir: Vector3 = to_target.normalized()
			look_at(global_position + move_dir, Vector3.UP)

			if dist > 1.8:
				velocity.x = move_dir.x * move_speed
				velocity.z = move_dir.z * move_speed
			else:
				velocity.x = 0.0
				velocity.z = 0.0
				if attack_timer <= 0.0:
					perform_attack()

func _on_duel_started() -> void:
	target_entity = duel_opponent as Node3D
	retarget_timer = 9999.0
	spawn_damage_text(0)

func end_duel() -> void:
	super.end_duel()
	target_entity = null
	retarget_timer = 0.0

func find_target() -> void:
	if is_in_duel and duel_opponent and is_instance_valid(duel_opponent):
		target_entity = duel_opponent as Node3D
		return

	# Priority 1: Nearest player building
	var reg = get_node_or_null("/root/EntityRegistry")
	var nearest_b: Node3D = null
	if reg and not reg.buildings.is_empty():
		nearest_b = reg.get_nearest_building(global_position)
	else:
		var buildings: Array[Node] = get_tree().get_nodes_in_group("buildings")
		var min_b_dist_sq: float = INF
		for b in buildings:
			if b is Node3D and is_instance_valid(b):
				var d_sq: float = global_position.distance_squared_to(b.global_position)
				if d_sq < min_b_dist_sq:
					min_b_dist_sq = d_sq
					nearest_b = b as Node3D

	if nearest_b:
		target_entity = nearest_b
		return

	# Priority 2: Player
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty() and is_instance_valid(players[0]):
		target_entity = players[0] as Node3D

func perform_attack() -> void:
	attack_timer = attack_cooldown
	if not target_entity or not is_instance_valid(target_entity):
		return

	if target_entity.is_in_group("buildings"):
		if target_entity.has_node("Hurtbox"):
			var h: Area3D = target_entity.get_node("Hurtbox")
			if h.has_method("take_damage"):
				h.take_damage(building_damage, Vector3.ZERO, "siege", self)
	elif target_entity.has_method("take_damage"):
		target_entity.take_damage(player_damage)

func spawn_damage_text(amount: float, custom_text: String = "", custom_color: Color = Color.WHITE) -> void:
	if custom_text != "":
		super.spawn_damage_text(amount, custom_text, custom_color)
		return
	var popup: Node3D = FLOATING_TEXT_SCENE.instantiate()
	get_parent().add_child(popup)
	popup.global_position = global_position + Vector3(0, 2.2, 0)
	popup.setup(amount, false, Color(1.0, 0.4, 0.2))

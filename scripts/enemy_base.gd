extends CharacterBody3D
class_name EnemyBase

@export var max_health: float = 60.0
@export var move_speed: float = 3.0

var current_health: float = 60.0
var knockback_velocity: Vector3 = Vector3.ZERO
var target_player: Node3D = null

var is_in_duel: bool = false
var duel_opponent: Node = null

@onready var hurtbox: Area3D = $Hurtbox if has_node("Hurtbox") else null
@onready var hp_label: Label3D = $Visuals/HPLabel if has_node("Visuals/HPLabel") else null

const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

func _ready() -> void:
	add_to_group("enemies")
	current_health = max_health
	update_hp_label()
	if hurtbox and hurtbox.has_signal("damaged"):
		if not hurtbox.is_connected("damaged", Callable(self, "_on_damaged")):
			hurtbox.connect("damaged", Callable(self, "_on_damaged"))
	
	_find_player()

func _physics_process(delta: float) -> void:
	_custom_physics(delta)

	if knockback_velocity.length_squared() > 0.01:
		velocity += knockback_velocity
		knockback_velocity = knockback_velocity.lerp(Vector3.ZERO, 10.0 * delta)
	
	# Gravity
	if not is_on_floor():
		velocity.y -= 25.0 * delta
	else:
		if velocity.y < 0.0:
			velocity.y = 0.0
			
	move_and_slide()
	
	# Voxel Step-Up Assist
	var move_h: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
	if move_h.length_squared() > 0.01:
		for i in range(get_slide_collision_count()):
			var col: KinematicCollision3D = get_slide_collision(i)
			var collider: Object = col.get_collider()
			if collider and collider is Node:
				var node: Node = collider as Node
				if node.is_in_group("buildings") or node.is_in_group("walls") or node.is_in_group("resource_nodes"):
					continue
			if col.get_normal().y < 0.3 and col.get_normal().y > -0.3:
				var step_transform: Transform3D = Transform3D(global_transform.basis, global_position + Vector3(0, 1.05, 0))
				if not test_move(step_transform, move_h.normalized() * 0.35):
					global_position.y += 1.05
					break

func _custom_physics(_delta: float) -> void:
	pass

func _find_player() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		target_player = players[0] as Node3D

func _on_damaged(amount: float, knockback: Vector3, _type: String, _attacker: Node) -> void:
	current_health -= amount
	_apply_knockback(knockback)
	update_hp_label()
	_spawn_damage_text_on_damaged(amount)

	if current_health <= 0.0:
		die()

func _apply_knockback(knockback: Vector3) -> void:
	knockback_velocity = knockback

func _spawn_damage_text_on_damaged(amount: float) -> void:
	spawn_damage_text(amount)

func update_hp_label() -> void:
	if hp_label:
		hp_label.text = "%d/%d" % [max(0, int(current_health)), int(max_health)]

func spawn_damage_text(amount: float, custom_text: String = "", custom_color: Color = Color.WHITE) -> void:
	var popup: Node3D = FLOATING_TEXT_SCENE.instantiate()
	get_parent().add_child(popup)
	popup.global_position = global_position + Vector3(0, 1.8, 0)
	if custom_text != "":
		popup.get_node("Label3D").text = custom_text
		popup.get_node("Label3D").modulate = custom_color
	else:
		popup.setup(amount, amount >= 40.0)

func start_duel(warrior: Node) -> void:
	is_in_duel = true
	duel_opponent = warrior
	target_player = warrior as Node3D
	_on_duel_started()

func _on_duel_started() -> void:
	spawn_damage_text(0, "DUEL!", Color.RED)

func end_duel() -> void:
	is_in_duel = false
	duel_opponent = null

func die() -> void:
	if is_in_duel and duel_opponent and is_instance_valid(duel_opponent) and duel_opponent.has_method("end_duel"):
		duel_opponent.end_duel()

	_on_death_effects()

	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty() and is_instance_valid(players[0]) and players[0].has_method("add_xp"):
		players[0].add_xp(_get_xp_reward())

	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.2)
	tween.chain().tween_callback(queue_free)

func _get_xp_reward() -> float:
	return 0.0

func _on_death_effects() -> void:
	pass

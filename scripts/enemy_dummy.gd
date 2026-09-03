extends "res://scripts/enemy_base.gd"

@export var attack_damage: float = 12.0
@export var attack_cooldown: float = 1.5

var is_stunned: bool = false
var stun_timer: float = 0.0
var attack_timer: float = 0.0

@onready var body_mesh: MeshInstance3D = $Visuals/Body if has_node("Visuals/Body") else null

func _ready() -> void:
	max_health = 80.0
	move_speed = 3.2
	super._ready()

func _get_xp_reward() -> float:
	return 25.0

func _custom_physics(delta: float) -> void:
	if is_stunned:
		stun_timer -= delta
		if stun_timer <= 0.0:
			is_stunned = false
		return

	if attack_timer > 0.0:
		attack_timer -= delta

	if not target_player or not is_instance_valid(target_player):
		_find_player()

	if target_player and is_instance_valid(target_player):
		var to_player: Vector3 = target_player.global_position - global_position
		to_player.y = 0.0
		var dist: float = to_player.length()

		if dist > 0.1:
			var move_dir: Vector3 = to_player.normalized()
			look_at(global_position + move_dir, Vector3.UP)

			if dist > 1.3:
				velocity.x = move_dir.x * move_speed
				velocity.z = move_dir.z * move_speed
			else:
				velocity.x = 0.0
				velocity.z = 0.0
				if attack_timer <= 0.0:
					perform_attack()

	# Check if blocked by a building/wall and attack it
	for i in range(get_slide_collision_count()):
		var col: KinematicCollision3D = get_slide_collision(i)
		var collider: Object = col.get_collider()
		if collider and collider is Node and (collider as Node).is_in_group("buildings"):
			if attack_timer <= 0.0:
				attack_building(collider as Node)
				break

func perform_attack() -> void:
	attack_timer = attack_cooldown
	if target_player and target_player.has_method("take_damage"):
		target_player.take_damage(attack_damage)

func attack_building(b: Node) -> void:
	attack_timer = attack_cooldown
	if b.has_node("Hurtbox"):
		var h: Area3D = b.get_node("Hurtbox")
		if h.has_method("take_damage"):
			h.take_damage(attack_damage, Vector3.ZERO, "siege", self)

func apply_stun(duration: float) -> void:
	is_stunned = true
	stun_timer = duration
	velocity = Vector3.ZERO
	spawn_damage_text(0, "STUNNED!", Color.GOLD)

func _on_duel_started() -> void:
	spawn_damage_text(0, "DUEL!", Color.RED)

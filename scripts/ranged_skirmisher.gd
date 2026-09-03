extends "res://scripts/enemy_base.gd"

@export var shoot_interval: float = 2.0
@export var preferred_distance: float = 8.0

var shoot_timer: float = 0.0
const ARROW_SCENE = preload("res://scenes/prefabs/arrow_projectile.tscn")

func _ready() -> void:
	max_health = 60.0
	move_speed = 3.6
	super._ready()

func _get_xp_reward() -> float:
	return 35.0

func _custom_physics(delta: float) -> void:
	shoot_timer -= delta

	if not target_player or not is_instance_valid(target_player):
		_find_player()

	if target_player and is_instance_valid(target_player):
		var to_player: Vector3 = target_player.global_position - global_position
		to_player.y = 0.0
		var dist: float = to_player.length()

		if dist > 0.1:
			var aim_dir: Vector3 = to_player.normalized()
			look_at(global_position + aim_dir, Vector3.UP)

			# Kiting behavior (unless in duel!)
			if is_in_duel:
				velocity.x = aim_dir.x * (move_speed * 1.2)
				velocity.z = aim_dir.z * (move_speed * 1.2)
			elif dist < preferred_distance - 1.5:
				# Retreat from player
				velocity.x = -aim_dir.x * move_speed
				velocity.z = -aim_dir.z * move_speed
			elif dist > preferred_distance + 2.0:
				# Approach player
				velocity.x = aim_dir.x * move_speed
				velocity.z = aim_dir.z * move_speed
			else:
				velocity.x = move_toward(velocity.x, 0.0, move_speed)
				velocity.z = move_toward(velocity.z, 0.0, move_speed)

			if shoot_timer <= 0.0 and dist <= preferred_distance + 3.0:
				shoot_arrow(aim_dir)
				shoot_timer = shoot_interval

func shoot_arrow(aim_dir: Vector3) -> void:
	var arrow: Node3D = ARROW_SCENE.instantiate()
	get_parent().add_child(arrow)
	arrow.global_position = global_position + Vector3(0, 1.2, 0)
	arrow.setup(aim_dir, 15.0, self)

func spawn_damage_text(amount: float, custom_text: String = "", custom_color: Color = Color.WHITE) -> void:
	if custom_text != "":
		super.spawn_damage_text(amount, custom_text, custom_color)
		return
	var popup: Node3D = FLOATING_TEXT_SCENE.instantiate()
	get_parent().add_child(popup)
	popup.global_position = global_position + Vector3(0, 1.8, 0)
	popup.setup(amount, false, Color(0.8, 0.8, 0.8))

func _on_duel_started() -> void:
	spawn_damage_text(0)

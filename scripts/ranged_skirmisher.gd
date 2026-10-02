extends "res://scripts/enemy_base.gd"

@export var shoot_interval: float = 2.0
@export var preferred_distance: float = 8.0

var shoot_timer: float = 0.0
const ARROW_SCENE = preload("res://scenes/prefabs/arrow_projectile.tscn")

func _ready() -> void:
	max_health = 60.0
	move_speed = 3.6
	radius = 0.3
	half_height = 0.9
	super._ready()

func _get_xp_reward() -> float:
	return 35.0

const ARROW_RELEASE_FRAME_SEC: float = 25.0 / 30.0 # Frame 25 @ 30 FPS (0.8333s per metrics.json)

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
			var pref_vel: Vector3 = Vector3.ZERO
			if is_in_duel:
				pref_vel = aim_dir * (move_speed * 1.2)
			elif dist < preferred_distance - 1.5:
				# Retreat from player
				pref_vel = -aim_dir * move_speed
			elif dist > preferred_distance + 2.0:
				# Approach player (using flowfield around obstacles!)
				var reg = get_node_or_null("/root/EntityRegistry")
				var approach_dir: Vector3 = aim_dir
				if reg and "monster_flowfield" in reg and reg.monster_flowfield:
					approach_dir = reg.monster_flowfield.get_flow_direction(global_position, target_player.global_position, radius)
				pref_vel = approach_dir * move_speed
			else:
				pref_vel = Vector3.ZERO

			var final_vel: Vector3 = pref_vel
			var reg = get_node_or_null("/root/EntityRegistry")
			if reg and reg.has_method("get_nearby_enemies") and pref_vel.length_squared() > 0.01:
				var neighbors = reg.get_nearby_enemies(global_position, radius + 1.0, self)
				final_vel = MonsterAvoidance.compute_avoidance_velocity(self, pref_vel, move_speed, radius, neighbors)

			desired_velocity_h = final_vel

			if dist <= preferred_distance + 3.0:
				# Start attack windup ahead of release if within windup window
				if shoot_timer <= ARROW_RELEASE_FRAME_SEC and shoot_timer > 0.0:
					if presentation and presentation.current_action != &"attack":
						var elapsed_windup: float = ARROW_RELEASE_FRAME_SEC - shoot_timer
						presentation.play_attack(elapsed_windup)

				if shoot_timer <= 0.0:
					shoot_arrow(aim_dir)
					shoot_timer = shoot_interval

func shoot_arrow(aim_dir: Vector3) -> void:
	if presentation:
		presentation.advance_to_attack_phase(ARROW_RELEASE_FRAME_SEC)
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

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
			var path_dir: Vector3 = Vector3.ZERO
			var reg = get_node_or_null("/root/EntityRegistry")
			if reg and "monster_flowfield" in reg and reg.monster_flowfield:
				path_dir = reg.monster_flowfield.get_flow_direction(global_position, target_player.global_position, radius, target_player.get_instance_id())
				if path_dir.length_squared() < 0.001 and dist > 1.3 and not is_in_duel and not reg.monster_flowfield.is_query_pending(target_player.global_position, radius):
					var buildings = reg.get_buildings()
					if not buildings.is_empty():
						var candidates: Array[Node3D] = []
						for b in buildings:
							if is_instance_valid(b) and b is Node3D:
								candidates.append(b as Node3D)
						candidates.sort_custom(func(a: Node3D, b_node: Node3D) -> bool:
							return global_position.distance_squared_to(a.global_position) < global_position.distance_squared_to(b_node.global_position)
						)
						var check_count: int = mini(4, candidates.size())
						for idx in range(check_count):
							var b_cand: Node3D = candidates[idx]
							var b_dir: Vector3 = reg.monster_flowfield.get_flow_direction(global_position, b_cand.global_position, radius, b_cand.get_instance_id())
							if b_dir.length_squared() > 0.001:
								path_dir = b_dir
								break
			elif not is_in_duel:
				path_dir = to_player.normalized()

			var pref_vel: Vector3 = Vector3.ZERO
			if dist > 1.3:
				pref_vel = path_dir * move_speed
			else:
				if attack_timer <= 0.0:
					perform_attack()

			var final_vel: Vector3 = pref_vel
			if reg and reg.has_method("get_nearby_enemies"):
				var neighbors = reg.get_nearby_enemies(global_position, radius + 1.2, self)
				final_vel = MonsterAvoidance.compute_avoidance_velocity(self, pref_vel, move_speed, radius, neighbors)

			desired_velocity_h = final_vel
			if final_vel.length_squared() > 0.01:
				var face_dir = Vector3(final_vel.x, 0, final_vel.z).normalized()
				look_at(global_position + face_dir, Vector3.UP)
			else:
				look_at(global_position + to_player.normalized(), Vector3.UP)

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
	if presentation:
		presentation.play_attack()
	if target_player and target_player.has_method("take_damage"):
		target_player.take_damage(attack_damage)

func attack_building(b: Node) -> void:
	attack_timer = attack_cooldown
	if presentation:
		presentation.play_attack()
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

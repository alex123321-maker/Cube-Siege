extends CharacterBody3D

signal boss_health_changed(current: float, max_hp: float)
signal boss_defeated()

@export var max_health: float = 2000.0
@export var base_speed: float = 4.5
@export var charge_speed: float = 22.0
@export var melee_damage: float = 35.0
@export var charge_damage: float = 55.0
@export var radius: float = 1.2
@export var half_height: float = 1.5

var current_health: float = 2000.0
var target_player: Node3D = null
var desired_velocity_h: Vector3 = Vector3.ZERO
var step_smooth_offset_y: float = 0.0

enum BossState { CHASE, TELEGRAPH, CHARGING, RECOVERY }
var current_state: BossState = BossState.CHASE

var state_timer: float = 0.0
var charge_direction: Vector3 = Vector3.ZERO
var charge_distance_traveled: float = 0.0
var charge_cooldown_timer: float = 5.0
var melee_attack_timer: float = 0.0
var has_hit_player_in_charge: bool = false

@onready var telegraph_mesh: MeshInstance3D = $Visuals/TelegraphLine
@onready var visuals: Node3D = $Visuals
@onready var hp_label: Label3D = $HPLabel
@onready var hurtbox: Area3D = $Hurtbox

const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

func _enter_tree() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg:
		reg.register_enemy(self)
		reg.register_boss(self)

func _exit_tree() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg:
		reg.unregister_enemy(self)
		reg.unregister_boss(self)

func _ready() -> void:
	add_to_group("enemies")
	add_to_group("boss")
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg:
		reg.register_enemy(self)
		reg.register_boss(self)
	current_health = max_health
	emit_signal("boss_health_changed", current_health, max_health)
	update_hp_label()

	if telegraph_mesh:
		telegraph_mesh.visible = false

	if hurtbox and hurtbox.has_signal("damaged"):
		hurtbox.connect("damaged", Callable(self, "_on_damaged"))

	find_player()

func find_player() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty() and is_instance_valid(players[0]):
		target_player = players[0] as Node3D

func _physics_process(delta: float) -> void:
	if not target_player or not is_instance_valid(target_player):
		find_player()
		return

	if charge_cooldown_timer > 0.0:
		charge_cooldown_timer -= delta
	if melee_attack_timer > 0.0:
		melee_attack_timer -= delta

	match current_state:
		BossState.CHASE:
			process_chase(delta)
		BossState.TELEGRAPH:
			process_telegraph(delta)
		BossState.CHARGING:
			process_charging(delta)
		BossState.RECOVERY:
			process_recovery(delta)

	var loc_result: Dictionary = MonsterLocomotion.process_locomotion(
		self,
		delta,
		desired_velocity_h,
		Vector3.ZERO,
		half_height,
		radius,
		step_smooth_offset_y
	)
	step_smooth_offset_y = float(loc_result.get("smooth_offset_y", 0.0))

	if visuals:
		visuals.position.y = step_smooth_offset_y

	if current_state == BossState.CHARGING:
		post_charge_collision_check()

	desired_velocity_h = Vector3.ZERO

func process_chase(delta: float) -> void:
	var to_player: Vector3 = target_player.global_position - global_position
	to_player.y = 0.0
	var dist: float = to_player.length()

	# Face player
	if to_player.length_squared() > 0.1:
		var look_dir: Vector3 = to_player.normalized()
		look_at(global_position + look_dir, Vector3.UP)

	# If cooldown ready and in range, start Trample Charge!
	if charge_cooldown_timer <= 0.0 and dist >= 5.0 and dist <= 20.0:
		start_telegraph(to_player.normalized())
		return

	# Movement
	if dist > 3.0:
		var nav_dir: Vector3 = to_player.normalized()
		var reg = get_node_or_null("/root/EntityRegistry")
		if reg and "monster_flowfield" in reg and reg.monster_flowfield:
			nav_dir = reg.monster_flowfield.get_flow_direction(global_position, target_player.global_position, radius)
			if nav_dir.length_squared() < 0.001 and dist > 3.4:
				var nearest_b: Node3D = reg.get_nearest_building(global_position)
				if nearest_b:
					nav_dir = reg.monster_flowfield.get_flow_direction(global_position, nearest_b.global_position, radius)
					if nav_dir.length_squared() < 0.001:
						var to_b: Vector3 = nearest_b.global_position - global_position
						to_b.y = 0.0
						if to_b.length_squared() > 0.01:
							nav_dir = to_b.normalized()

		var pref_vel: Vector3 = nav_dir * base_speed
		var final_vel: Vector3 = pref_vel
		if reg and reg.has_method("get_nearby_enemies"):
			var neighbors = reg.get_nearby_enemies(global_position, radius + 1.2, self)
			final_vel = MonsterAvoidance.compute_avoidance_velocity(self, pref_vel, base_speed, radius, neighbors)
		desired_velocity_h = final_vel
	else:
		desired_velocity_h = Vector3.ZERO

	# Melee hit against player (contact range 3.4m)
	if dist <= 3.4 and melee_attack_timer <= 0.0:
		melee_attack_timer = 1.2
		if target_player.has_method("take_damage"):
			target_player.take_damage(melee_damage, self)
			spawn_damage_text(melee_damage, "BOSS SMASH! (-%d HP)" % int(melee_damage), Color.RED)

	# Smash any buildings blocking melee path
	var buildings: Array[Node] = get_tree().get_nodes_in_group("buildings")
	for b in buildings:
		if b and is_instance_valid(b) and b is Node3D:
			if global_position.distance_to((b as Node3D).global_position) <= 3.2:
				if b.has_method("destroy_building"):
					b.destroy_building()

func start_telegraph(dir: Vector3) -> void:
	current_state = BossState.TELEGRAPH
	state_timer = 1.4 # 1.4s warning
	charge_direction = dir
	has_hit_player_in_charge = false
	desired_velocity_h = Vector3.ZERO
	velocity = Vector3.ZERO
	if telegraph_mesh:
		telegraph_mesh.visible = true
	spawn_damage_text(0, "!! TRAMPLE CHARGE !!", Color.RED)

func process_telegraph(delta: float) -> void:
	desired_velocity_h = Vector3.ZERO
	velocity = Vector3.ZERO
	state_timer -= delta
	# Slight rumble shake
	if visuals:
		visuals.position.x = randf_range(-0.12, 0.12)
		visuals.position.z = randf_range(-0.12, 0.12)

	if state_timer <= 0.0:
		if visuals:
			visuals.position = Vector3(0.0, step_smooth_offset_y, 0.0)
		if telegraph_mesh:
			telegraph_mesh.visible = false
		current_state = BossState.CHARGING
		charge_distance_traveled = 0.0

func process_charging(delta: float) -> void:
	desired_velocity_h = charge_direction * charge_speed
	charge_distance_traveled += charge_speed * delta

	# 1. Damage and launch player if close
	if target_player and is_instance_valid(target_player):
		var p_dist: float = global_position.distance_to(target_player.global_position)
		if p_dist <= 3.4 and not has_hit_player_in_charge:
			has_hit_player_in_charge = true
			if target_player.has_method("take_damage"):
				target_player.take_damage(charge_damage, self)
			if target_player is CharacterBody3D:
				(target_player as CharacterBody3D).velocity += charge_direction * 18.0 + Vector3(0, 6, 0)
			spawn_damage_text(charge_damage, "TRAMPLED! (-%d HP)" % int(charge_damage), Color.CRIMSON)

	# 2. Smash through buildings and walls along charge path
	var buildings: Array[Node] = get_tree().get_nodes_in_group("buildings")
	for b in buildings:
		if b and is_instance_valid(b) and b is Node3D:
			if global_position.distance_to((b as Node3D).global_position) <= 2.8:
				if b.has_method("destroy_building"):
					b.destroy_building()

	if charge_distance_traveled >= 16.0:
		# End charge into recovery
		current_state = BossState.RECOVERY
		state_timer = 1.8 # 1.8s vulnerability window
		desired_velocity_h = Vector3.ZERO
		velocity = Vector3.ZERO
		charge_cooldown_timer = 7.0
		spawn_damage_text(0, "STUNNED!", Color.GOLD)

func post_charge_collision_check() -> void:
	# 3. Check physical slide collisions
	for i in range(get_slide_collision_count()):
		var col: KinematicCollision3D = get_slide_collision(i)
		var collider: Object = col.get_collider()
		if collider and is_instance_valid(collider) and collider is Node:
			var node: Node = collider as Node
			if node.is_in_group("buildings") or node.is_in_group("walls"):
				if node.has_method("destroy_building"):
					node.destroy_building()
			elif node.is_in_group("player"):
				if not has_hit_player_in_charge:
					has_hit_player_in_charge = true
					if node.has_method("take_damage"):
						node.take_damage(charge_damage, self)

func process_recovery(delta: float) -> void:
	desired_velocity_h = Vector3.ZERO
	velocity = Vector3.ZERO
	state_timer -= delta
	if state_timer <= 0.0:
		current_state = BossState.CHASE

func _on_damaged(amount: float, _knockback: Vector3, _type: String, _attacker: Node) -> void:
	var actual_dmg: float = amount
	if current_state == BossState.RECOVERY:
		actual_dmg *= 1.35 # Vulnerable during recovery!

	current_health -= actual_dmg
	emit_signal("boss_health_changed", current_health, max_health)
	update_hp_label()
	spawn_damage_text(actual_dmg)

	if current_health <= 0.0:
		die()

func update_hp_label() -> void:
	if hp_label:
		hp_label.text = "GORGON: %d / %d" % [max(0, int(current_health)), int(max_health)]

func spawn_damage_text(amount: float, custom_text: String = "", custom_color: Color = Color.WHITE) -> void:
	var popup: Node3D = FLOATING_TEXT_SCENE.instantiate()
	get_parent().add_child(popup)
	popup.global_position = global_position + Vector3(0, 3.2, 0)
	if custom_text != "":
		popup.get_node("Label3D").text = custom_text
		popup.get_node("Label3D").modulate = custom_color
	else:
		popup.setup(amount, amount >= 50.0, Color(1.0, 0.4, 0.2))

func die() -> void:
	emit_signal("boss_defeated")

	# Massive XP explosion and resource drop
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty() and is_instance_valid(players[0]):
		if players[0].has_method("add_xp"):
			players[0].add_xp(250.0)
		if "building_system" in players[0] and players[0].building_system:
			var bs: BuildingSystem = players[0].building_system as BuildingSystem
			if bs:
				bs.add_resource(20, 20, 10)

	# Spawn Relic Pedestal
	var relic_scene = preload("res://scenes/prefabs/relic_pedestal.tscn")
	var pedestal = relic_scene.instantiate()
	get_parent().add_child(pedestal)
	pedestal.global_position = global_position

	spawn_damage_text(0, "BOSS DEFEATED! (+250 XP)", Color.GOLD)

	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.4)
	tween.chain().tween_callback(queue_free)

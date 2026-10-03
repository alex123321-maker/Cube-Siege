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
@export var charge_distance: float = 16.0
@export var charge_half_width: float = 1.65

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
var charge_origin: Vector3 = Vector3.ZERO
var charge_previous_position: Vector3 = Vector3.ZERO
var charge_time_remaining: float = 0.0
var is_dying: bool = false
var _event_bus: Node = null

@onready var telegraph_mesh: MeshInstance3D = $Visuals/TelegraphLine
@onready var visuals: Node3D = $Visuals
@onready var hp_label: Label3D = $HPLabel
@onready var hurtbox: Area3D = $Hurtbox
@onready var model: GorgonPresentation = $Visuals/Model

const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")
const ChargeWarning = preload("res://scripts/combat/boss_charge_warning.gd")

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
	_event_bus = get_node_or_null("/root/EventBus")
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
		telegraph_mesh.material_override = telegraph_mesh.mesh.surface_get_material(0)
		# The warning lives in world space: presentation shake and step smoothing
		# must never move the area the player is being asked to avoid.
		telegraph_mesh.top_level = true
		telegraph_mesh.mesh = telegraph_mesh.mesh.duplicate()

	if hurtbox and hurtbox.has_signal("damaged"):
		hurtbox.connect("damaged", Callable(self, "_on_damaged"))

	find_player()

func find_player() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg and reg.has_method("get_player"):
		var p_cand = reg.get_player()
		if is_instance_valid(p_cand) and p_cand is Node3D and p_cand.is_inside_tree():
			target_player = p_cand as Node3D
			return
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	for candidate in players:
		if is_instance_valid(candidate) and candidate is Node3D and candidate.is_inside_tree():
			target_player = candidate as Node3D
			return

func _physics_process(delta: float) -> void:
	if is_dying:
		return
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
	if model:
		var phase: StringName = &"idle"
		var progress: float = 0.0
		match current_state:
			BossState.TELEGRAPH:
				phase = &"windup"
				progress = 1.0 - state_timer / 1.4
			BossState.CHARGING:
				phase = &"charge"
				progress = charge_distance_traveled / charge_distance
			BossState.RECOVERY:
				phase = &"recovery"
				progress = 1.0 - state_timer / 1.8
		model.update_pose(delta, phase, clampf(progress, 0.0, 1.0), desired_velocity_h.length())

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
		var nav_dir: Vector3 = Vector3.ZERO
		var reg = get_node_or_null("/root/EntityRegistry")
		if reg and "monster_flowfield" in reg and reg.monster_flowfield:
			nav_dir = reg.monster_flowfield.get_flow_direction(global_position, target_player.global_position, radius)
			# Fallback when player is enclosed by walls: approach nearest candidate blocking building via flowfield
			if nav_dir.length_squared() < 0.001 and dist > 3.4 and reg.has_method("get_buildings"):
				var buildings: Array[Node3D] = reg.get_buildings()
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
						var b_dir: Vector3 = reg.monster_flowfield.get_flow_direction(global_position, b_cand.global_position, radius)
						if b_dir.length_squared() > 0.001:
							nav_dir = b_dir
							break

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
		if model:
			model.play_smash()
		if target_player.has_method("take_damage"):
			target_player.take_damage(melee_damage, self)
			spawn_damage_text(melee_damage, "BOSS SMASH! (-%d HP)" % int(melee_damage), Color.RED)

	# Smash any buildings blocking melee path
	var reg_b = get_node_or_null("/root/EntityRegistry")
	if reg_b and reg_b.has_method("get_buildings"):
		var buildings: Array[Node3D] = reg_b.get_buildings()
		for b in buildings:
			if b and is_instance_valid(b):
				if global_position.distance_to(b.global_position) <= 3.2:
					if b.has_method("destroy_building"):
						b.destroy_building()

func start_telegraph(dir: Vector3) -> void:
	current_state = BossState.TELEGRAPH
	state_timer = 1.4 # 1.4s warning
	charge_direction = Vector3(dir.x, 0.0, dir.z).normalized()
	charge_origin = global_position
	charge_previous_position = global_position
	has_hit_player_in_charge = false
	desired_velocity_h = Vector3.ZERO
	velocity = Vector3.ZERO
	if telegraph_mesh:
		var terrain: MapGenerator = get_tree().get_first_node_in_group("map_generator") as MapGenerator
		if terrain:
			telegraph_mesh.mesh = ChargeWarning.create_mesh(charge_origin, charge_direction, charge_distance, charge_half_width, terrain)
		else:
			var warning_mesh: BoxMesh = BoxMesh.new()
			warning_mesh.size = Vector3(charge_half_width * 2.0, 0.05, charge_distance + charge_half_width * 2.0)
			telegraph_mesh.mesh = warning_mesh
		telegraph_mesh.global_position = charge_origin + charge_direction * (charge_distance * 0.5) + Vector3.UP * 0.06
		telegraph_mesh.look_at(telegraph_mesh.global_position + charge_direction, Vector3.UP)
		telegraph_mesh.visible = true
	if _event_bus:
		_event_bus.audio_cue_requested.emit(&"boss_windup", global_position)
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
		charge_time_remaining = charge_distance / charge_speed
		if _event_bus:
			_event_bus.audio_cue_requested.emit(&"boss_charge", global_position)

func process_charging(delta: float) -> void:
	charge_previous_position = global_position
	var remaining_distance: float = maxf(0.0, charge_distance - charge_distance_traveled)
	desired_velocity_h = charge_direction * minf(charge_speed, remaining_distance / maxf(delta, 0.0001))
	charge_time_remaining -= delta

	# Break structures reached by the current body footprint before moving.
	var reg = get_node_or_null("/root/EntityRegistry")
	var buildings: Array = reg.get_buildings() if reg else []
	for b in buildings:
		if b and is_instance_valid(b) and b is Node3D:
			if _is_in_charge_sweep((b as Node3D).global_position, global_position, global_position):
				if b.has_method("destroy_building"):
					b.destroy_building()

func post_charge_collision_check() -> void:
	charge_distance_traveled = clampf((global_position - charge_origin).dot(charge_direction), 0.0, charge_distance)
	if target_player and is_instance_valid(target_player) and not has_hit_player_in_charge:
		if _is_in_charge_sweep(target_player.global_position, charge_previous_position, global_position):
			_hit_charge_target(target_player)
	# Physical contacts break walls; player damage uses the same locked warning lane.
	for i in range(get_slide_collision_count()):
		var col: KinematicCollision3D = get_slide_collision(i)
		var collider: Object = col.get_collider()
		if collider and is_instance_valid(collider) and collider is Node:
			var node: Node = collider as Node
			if node.is_in_group("buildings") or node.is_in_group("walls"):
				if node.has_method("destroy_building"):
					node.destroy_building()
			elif node.is_in_group("player"):
				if not has_hit_player_in_charge and node is Node3D and _is_in_charge_sweep((node as Node3D).global_position, charge_previous_position, global_position):
					_hit_charge_target(node as Node3D)
	if charge_distance_traveled >= charge_distance - 0.01 or charge_time_remaining <= 0.0:
		current_state = BossState.RECOVERY
		state_timer = 1.8
		desired_velocity_h = Vector3.ZERO
		velocity = Vector3.ZERO
		charge_cooldown_timer = 7.0
		spawn_damage_text(0, "STUNNED!", Color.GOLD)

func _is_in_charge_sweep(point: Vector3, from: Vector3, to: Vector3) -> bool:
	var relative: Vector3 = point - charge_origin
	var along: float = relative.dot(charge_direction)
	var across: float = relative.dot(Vector3(-charge_direction.z, 0.0, charge_direction.x))
	if absf(across) > charge_half_width or along < -charge_half_width or along > charge_distance + charge_half_width:
		return false
	var from_along: float = (from - charge_origin).dot(charge_direction)
	var to_along: float = (to - charge_origin).dot(charge_direction)
	if along < minf(from_along, to_along) - charge_half_width or along > maxf(from_along, to_along) + charge_half_width:
		return false
	return absf(point.y - to.y) <= half_height + 1.0

func _hit_charge_target(target: Node3D) -> void:
	has_hit_player_in_charge = true
	if _event_bus:
		_event_bus.audio_cue_requested.emit(&"explosion", target.global_position)
	if target.has_method("take_damage"):
		target.take_damage(charge_damage, self)
	if target is CharacterBody3D:
		(target as CharacterBody3D).velocity += charge_direction * 18.0 + Vector3(0, 6, 0)
	spawn_damage_text(charge_damage, "TRAMPLED! (-%d HP)" % int(charge_damage), Color.CRIMSON)

func process_recovery(delta: float) -> void:
	desired_velocity_h = Vector3.ZERO
	velocity = Vector3.ZERO
	state_timer -= delta
	if state_timer <= 0.0:
		current_state = BossState.CHASE

func _on_damaged(amount: float, _knockback: Vector3, _type: String, _attacker: Node) -> void:
	if is_dying:
		return
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
	if is_dying:
		return
	is_dying = true
	if model:
		model.play_death()
	remove_from_group("enemies")
	remove_from_group("boss")
	var registry: Node = get_node_or_null("/root/EntityRegistry")
	if registry:
		registry.unregister_enemy(self)
		registry.unregister_boss(self)
	if telegraph_mesh:
		telegraph_mesh.visible = false
	if _event_bus:
		_event_bus.boss_defeated.emit(self)
	emit_signal("boss_defeated")

	# Massive XP explosion and resource drop
	var reg = get_node_or_null("/root/EntityRegistry")
	var award_player: Node3D = null
	if reg and reg.has_method("get_player"):
		var p_cand = reg.get_player()
		if is_instance_valid(p_cand) and p_cand is Node3D:
			award_player = p_cand as Node3D
	if not award_player:
		var players: Array[Node] = get_tree().get_nodes_in_group("player")
		for candidate in players:
			if is_instance_valid(candidate) and candidate is Node3D:
				award_player = candidate as Node3D
				break
	if award_player and is_instance_valid(award_player):
		if award_player.has_method("add_xp"):
			award_player.add_xp(250.0)
		if "building_system" in award_player and award_player.building_system:
			var bs: BuildingSystem = award_player.building_system as BuildingSystem
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

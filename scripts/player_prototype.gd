extends CharacterBody3D

signal health_changed(current_health: float, max_health: float)
signal xp_changed(current_xp: float, max_xp: float, level: int)
signal level_up_reached(new_level: int)
signal dash_performed()
signal parry_triggered(successful: bool)
signal player_died()

@export var speed: float = 7.0
@export var dash_speed: float = 18.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 3.0
@export var max_health: float = 100.0

@export var attack_damage: float = 25.0
@export var special_damage: float = 60.0

var current_health: float = 100.0
var player_level: int = 1
var current_xp: float = 0.0
var xp_to_next_level: float = 80.0
var vampirism_heal: float = 0.0
var resource_multiplier: int = 1

enum CharacterClass { WARRIOR, ARCHER, ENGINEER }
var current_class: CharacterClass = CharacterClass.WARRIOR
var active_remote_mine: Node3D = null
var is_eagle_eye: bool = false

var is_dashing: bool = false
var dash_timer: float = 0.0
var dash_cooldown_timer: float = 0.0

var is_parrying: bool = false
var parry_timer: float = 0.0
var parry_cooldown_timer: float = 0.0

var attack_cooldown_timer: float = 0.0
var special_cooldown_timer: float = 0.0

var dash_direction: Vector3 = Vector3.ZERO

@onready var hero_warrior: Node3D = $Visuals.get_node_or_null("HeroWarrior")
@onready var anim_player: AnimationPlayer = $Visuals.get_node_or_null("HeroWarrior/AnimationPlayer")
@onready var parry_shield_mesh: Node3D = $Visuals.get_node_or_null("HeroWarrior/root/torso/left_arm/shield") if hero_warrior else $Visuals.get_node_or_null("ParryShield")
@onready var sword_mesh: Node3D = $Visuals.get_node_or_null("HeroWarrior/root/torso/right_arm/sword") if hero_warrior else $Visuals.get_node_or_null("Sword")
@onready var slash_area: Area3D = $SlashHitbox

@onready var portal_compass: Node3D = $PortalCompass
@onready var compass_label_3d: Label3D = $PortalCompass/CompassLabel

const DUEL_TETHER_SCENE = preload("res://scenes/duel_tether.tscn")
const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

var is_dueling: bool = false
var duel_target: Node3D = null
var active_tether: Node3D = null
var ultimate_cooldown_timer: float = 0.0
@export var ultimate_cooldown: float = 25.0

var focused_interactable: Node = null
var interact_hold_timer: float = 0.0
var last_mouse_pos: Vector2 = Vector2(-9999, -9999)
var last_mouse_move_time: float = 0.0

# Cached node references (resolved once in _ready)
var _cached_building_system: Node = null
var _cached_radial_menu: Control = null

func _ready() -> void:
	add_to_group("player")
	apply_mastery_stats()
	var roster = get_node_or_null("/root/RosterManager")
	if roster and roster.has_method("get_active_character"):
		var c_data = roster.get_active_character()
		set_class(c_data.class_id as CharacterClass, false)
	else:
		set_class(CharacterClass.WARRIOR, false)
	current_health = max_health
	emit_signal("health_changed", current_health, max_health)
	emit_signal("xp_changed", current_xp, xp_to_next_level, player_level)
	var bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.player_health_changed.emit(current_health, max_health)
		bus.player_xp_changed.emit(current_xp, xp_to_next_level, player_level)
	if anim_player:
		anim_player.play("idle")
	if parry_shield_mesh and not hero_warrior:
		parry_shield_mesh.visible = false
	if slash_area:
		slash_area.set_owner_entity(self)
		slash_area.monitoring = false
	# Cache frequently-used node references
	_cached_building_system = get_tree().root.find_child("BuildingSystem", true, false)
	_cached_radial_menu = get_tree().root.find_child("RadialMenu", true, false) as Control

func _physics_process(delta: float) -> void:
	update_portal_compass()

	# Cooldowns update
	if dash_cooldown_timer > 0.0:
		dash_cooldown_timer -= delta
	if parry_cooldown_timer > 0.0:
		parry_cooldown_timer -= delta
	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta
	if special_cooldown_timer > 0.0:
		special_cooldown_timer -= delta
	if ultimate_cooldown_timer > 0.0:
		ultimate_cooldown_timer -= delta

	if is_dueling and (not duel_target or not is_instance_valid(duel_target)):
		end_duel()

	if is_dashing:
		dash_timer -= delta
		if dash_timer <= 0.0:
			is_dashing = false

	if is_parrying:
		parry_timer -= delta
		if parry_timer <= 0.0:
			is_parrying = false
			if parry_shield_mesh and not hero_warrior:
				parry_shield_mesh.visible = false

	# Action inputs
	if Input.is_action_just_pressed("dash"):
		perform_dash()

	if Input.is_action_just_pressed("class_utility"):
		perform_utility()

	if not is_in_build_mode():
		if Input.is_action_just_pressed("attack_lmb"):
			perform_attack()

		if Input.is_action_just_pressed("special_rmb"):
			perform_special_attack()

	if Input.is_action_just_pressed("ultimate"):
		perform_ultimate()

	handle_interaction(delta)
	handle_movement(delta)
	handle_aim()
	update_animations()

func handle_movement(delta: float) -> void:
	var move_dir: Vector3 = Vector3.ZERO

	if is_dueling and duel_target and is_instance_valid(duel_target):
		var to_target: Vector3 = duel_target.global_position - global_position
		to_target.y = 0.0
		if to_target.length() > 1.2:
			move_dir = to_target.normalized()
			velocity.x = move_dir.x * (speed * 1.15)
			velocity.z = move_dir.z * (speed * 1.15)
		else:
			velocity.x = 0.0
			velocity.z = 0.0
	elif is_dashing:
		velocity.x = dash_direction.x * dash_speed
		velocity.z = dash_direction.z * dash_speed
		move_dir = dash_direction
	else:
		var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var direction: Vector3 = Vector3(input_dir.x, 0.0, input_dir.y)

		if direction.length_squared() > 0.001:
			move_dir = direction.normalized()
			velocity.x = move_dir.x * speed
			velocity.z = move_dir.z * speed
		else:
			velocity.x = move_toward(velocity.x, 0.0, speed)
			velocity.z = move_toward(velocity.z, 0.0, speed)

	# Gravity
	if not is_on_floor():
		velocity.y -= 25.0 * delta
	else:
		if velocity.y < 0.0:
			velocity.y = 0.0

	move_and_slide()

	# Voxel Step-Up Assist (only on terrain cubes, NEVER on resources, trees, or buildings)
	if move_dir.length_squared() > 0.01:
		for i in range(get_slide_collision_count()):
			var col: KinematicCollision3D = get_slide_collision(i)
			var collider: Object = col.get_collider()
			if collider and collider is Node:
				var node: Node = collider as Node
				if node.is_in_group("resource_nodes") or node.is_in_group("buildings") or node.is_in_group("interactables"):
					continue
			if col.get_normal().y < 0.3 and col.get_normal().y > -0.3:
				var step_transform: Transform3D = Transform3D(global_transform.basis, global_position + Vector3(0, 1.05, 0))
				if not test_move(step_transform, move_dir * 0.35):
					global_position.y += 1.05
					break

func handle_interaction(delta: float) -> void:
	var vp: Viewport = get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp else null
	var mouse_world: Vector3 = global_position

	if cam and vp:
		var m_pos: Vector2 = vp.get_mouse_position()
		var r_orig: Vector3 = cam.project_ray_origin(m_pos)
		var r_norm: Vector3 = cam.project_ray_normal(m_pos)
		var plane: Plane = Plane(Vector3.UP, global_position.y)
		var hit: Variant = plane.intersects_ray(r_orig, r_norm)
		if hit is Vector3:
			mouse_world = hit as Vector3

	# Find interactable nearest to mouse cursor within 4.5m of player
	var interactables: Array[Node] = get_tree().get_nodes_in_group("interactables")
	var best_target: Node = null
	var best_dist: float = 999.0

	for obj in interactables:
		if not is_instance_valid(obj) or not (obj is Node3D):
			continue
		var dist_to_player: float = global_position.distance_to((obj as Node3D).global_position)
		if dist_to_player > 4.5:
			continue
		if obj.has_method("is_ready_for_pickup") and not obj.is_ready_for_pickup():
			continue
		var dist_to_cursor: float = mouse_world.distance_to((obj as Node3D).global_position)
		if dist_to_cursor < best_dist:
			best_dist = dist_to_cursor
			best_target = obj

	# Manage focus & highlight
	if best_target != focused_interactable:
		if focused_interactable and is_instance_valid(focused_interactable) and focused_interactable.has_method("set_focused"):
			focused_interactable.set_focused(false)
		focused_interactable = best_target
		interact_hold_timer = 0.0
		if focused_interactable and focused_interactable.has_method("set_focused"):
			focused_interactable.set_focused(true)

	# Hold [E] for 1.0s or 2.0s for portal extraction
	if Input.is_action_pressed("interact") and focused_interactable:
		interact_hold_timer += delta
		var hold_required: float = 1.0
		if focused_interactable.is_in_group("portal") and focused_interactable.get("current_state") == 2:  # State.ACTIVE
			hold_required = 2.0
		var progress: float = clamp(interact_hold_timer / hold_required, 0.0, 1.0)
		if focused_interactable.has_method("set_interaction_progress"):
			focused_interactable.set_interaction_progress(progress)
		if interact_hold_timer >= hold_required:
			interact_hold_timer = 0.0
			var is_shift: bool = Input.is_key_pressed(KEY_SHIFT)
			if is_shift and focused_interactable.has_method("demolish"):
				focused_interactable.demolish(self)
			elif not is_shift and focused_interactable.has_method("repair") and focused_interactable.get("current_health") != null and focused_interactable.current_health < focused_interactable.max_health:
				var bs: Node = get_tree().root.find_child("BuildingSystem", true, false)
				if bs and bs.get("wood_count") != null and bs.wood_count >= 1:
					bs.wood_count -= 1
					bs.update_hud_counters()
					focused_interactable.repair(100.0)
				else:
					spawn_popup_text("NEED 1 WOOD!", Color.ORANGE)
			elif focused_interactable.has_method("harvest"):
				focused_interactable.harvest(self)
			elif focused_interactable.has_method("interact_portal"):
				focused_interactable.interact_portal(self)
			focused_interactable = null
	else:
		if interact_hold_timer > 0.0:
			interact_hold_timer = 0.0
			if focused_interactable and is_instance_valid(focused_interactable) and focused_interactable.has_method("set_focused"):
				focused_interactable.set_focused(true)

func handle_aim() -> void:
	if is_dueling and duel_target and is_instance_valid(duel_target):
		var aim_dir: Vector3 = (duel_target.global_position - global_position)
		aim_dir.y = 0.0
		if aim_dir.length_squared() > 0.01:
			look_at(global_position + aim_dir.normalized(), Vector3.UP)
		return

	# 1. Keyboard Arrow Keys Aim
	var k_aim_x: float = Input.get_axis("aim_left", "aim_right")
	var k_aim_y: float = Input.get_axis("aim_up", "aim_down")
	if Vector2(k_aim_x, k_aim_y).length_squared() > 0.1:
		var k_dir: Vector3 = Vector3(k_aim_x, 0.0, k_aim_y).normalized()
		look_at(global_position + k_dir, Vector3.UP)
		last_mouse_pos = Vector2(-9999, -9999)
		return

	var vp: Viewport = get_viewport()
	if not vp: return
	var current_mouse_pos: Vector2 = vp.get_mouse_position()
	var mouse_moved: bool = (current_mouse_pos - last_mouse_pos).length_squared() > 4.0

	if mouse_moved:
		last_mouse_pos = current_mouse_pos
		last_mouse_move_time = Time.get_ticks_msec() / 1000.0

	var time_since_mouse_move: float = (Time.get_ticks_msec() / 1000.0) - last_mouse_move_time

	# 2. If mouse/touchpad is idle, auto-aim in walk direction!
	if time_since_mouse_move > 0.35:
		var move_dir_h: Vector3 = Vector3(velocity.x, 0.0, velocity.z)
		if move_dir_h.length_squared() > 0.1:
			look_at(global_position + move_dir_h.normalized(), Vector3.UP)
			return

	# 3. Mouse raycast aiming
	var cam: Camera3D = vp.get_camera_3d()
	if not cam: return
	var ray_origin: Vector3 = cam.project_ray_origin(current_mouse_pos)
	var ray_normal: Vector3 = cam.project_ray_normal(current_mouse_pos)
	var ground_plane: Plane = Plane(Vector3(0, 1, 0), global_position.y)
	var intersect: Variant = ground_plane.intersects_ray(ray_origin, ray_normal)

	if intersect is Vector3:
		var aim_dir: Vector3 = (intersect as Vector3) - global_position
		aim_dir.y = 0.0
		if aim_dir.length_squared() > 0.01:
			look_at(global_position + aim_dir.normalized(), Vector3.UP)

func update_animations() -> void:
	if not anim_player:
		return
	if is_parrying:
		if anim_player.current_animation != "block":
			anim_player.play("block")
		return
	if anim_player.is_playing() and anim_player.current_animation == "attack":
		return

	var is_moving: bool = Vector3(velocity.x, 0.0, velocity.z).length_squared() > 0.1 and not is_dashing
	if is_moving:
		if anim_player.current_animation != "walk":
			anim_player.play("walk")
	else:
		if anim_player.current_animation != "idle":
			anim_player.play("idle")

func perform_attack() -> void:
	if attack_cooldown_timer > 0.0 or is_dashing:
		return

	match current_class:
		CharacterClass.WARRIOR:
			attack_cooldown_timer = 0.35
			trigger_slash(attack_damage, 5.0, 90.0)
		CharacterClass.ARCHER:
			attack_cooldown_timer = 0.38
			trigger_arrow_shot(attack_damage, 1, 28.0)
		CharacterClass.ENGINEER:
			attack_cooldown_timer = 0.48
			trigger_hammer_smash(attack_damage * 1.35)

func perform_special_attack() -> void:
	if special_cooldown_timer > 0.0 or is_dashing:
		return

	match current_class:
		CharacterClass.WARRIOR:
			special_cooldown_timer = 4.0
			trigger_slash(special_damage, 12.0, 180.0)
		CharacterClass.ARCHER:
			special_cooldown_timer = 5.0
			trigger_piercing_arrow(special_damage * 1.3, 6, 36.0)
		CharacterClass.ENGINEER:
			special_cooldown_timer = 5.0
			deploy_temp_turret()

func perform_utility() -> void:
	match current_class:
		CharacterClass.WARRIOR:
			perform_parry()
		CharacterClass.ARCHER:
			deploy_decoy()
		CharacterClass.ENGINEER:
			toggle_remote_mine()

func trigger_slash(dmg: float, knockback: float, arc_degrees: float) -> void:
	if not slash_area:
		return

	var final_dmg: float = dmg
	if is_dueling:
		final_dmg *= 1.2 # +20% damage in Duel of Honor!

	slash_area.damage = final_dmg
	slash_area.knockback_force = knockback
	slash_area.hit_entities.clear()
	slash_area.monitoring = true

	# Check overlaps immediately after physics update
	await get_tree().physics_frame
	if is_instance_valid(slash_area):
		for a in slash_area.get_overlapping_areas():
			if slash_area.has_method("_on_area_entered"):
				slash_area._on_area_entered(a)
		if vampirism_heal > 0.0 and slash_area.hit_entities.size() > 0:
			heal(vampirism_heal)
			spawn_popup_text("+%d HP" % int(vampirism_heal), Color.CRIMSON)

	# Sword swing visual
	if anim_player:
		anim_player.stop()
		anim_player.play("attack", -1, 1.4)
	elif sword_mesh:
		var tween: Tween = create_tween()
		var start_rot: float = deg_to_rad(arc_degrees * 0.5)
		var end_rot: float = -deg_to_rad(arc_degrees * 0.5)
		sword_mesh.rotation.y = start_rot
		tween.tween_property(sword_mesh, "rotation:y", end_rot, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(sword_mesh, "rotation:y", 0.0, 0.1)

	await get_tree().create_timer(0.16).timeout
	if is_instance_valid(slash_area):
		slash_area.monitoring = false

func perform_dash() -> void:
	if dash_cooldown_timer > 0.0 or is_dashing:
		return

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_dir.length_squared() > 0.001:
		dash_direction = Vector3(input_dir.x, 0.0, input_dir.y).normalized()
	else:
		dash_direction = -global_transform.basis.z
		dash_direction.y = 0.0
		dash_direction = dash_direction.normalized()

	is_dashing = true
	dash_timer = dash_duration
	dash_cooldown_timer = dash_cooldown
	emit_signal("dash_performed")

func perform_parry() -> void:
	if parry_cooldown_timer > 0.0 or is_parrying:
		return

	is_parrying = true
	parry_timer = 0.5
	parry_cooldown_timer = 6.0
	if anim_player:
		anim_player.stop()
		anim_player.play("block")
	elif parry_shield_mesh:
		parry_shield_mesh.visible = true
	emit_signal("parry_triggered", false)

func perform_interaction() -> void:
	var nodes: Array[Node] = get_tree().get_nodes_in_group("interactables")
	for n in nodes:
		if n is Node3D and global_position.distance_to(n.global_position) <= 3.2:
			if n.has_method("harvest"):
				n.harvest(self)
				break
			elif n.has_method("interact_portal"):
				n.interact_portal(self)
				break

func take_damage(damage: float, attacker: Node = null) -> void:
	if is_dashing:
		return

	if is_parrying:
		is_parrying = false
		parry_cooldown_timer = 3.0
		if parry_shield_mesh and not hero_warrior:
			parry_shield_mesh.visible = false
		emit_signal("parry_triggered", true)

		# Stun nearby enemies when parrying
		var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
		for e in enemies:
			if e is Node3D and global_position.distance_to(e.global_position) <= 3.5:
				if e.has_method("apply_stun"):
					e.apply_stun(1.0)
					if e.has_method("_on_damaged"):
						e._on_damaged(30.0, (e.global_position - global_position).normalized() * 8.0, "counter", self)
		return

	var final_damage: float = damage
	if is_dueling and attacker and is_instance_valid(attacker) and attacker != duel_target:
		# 40% reduction from 3rd party attackers
		final_damage *= 0.6
		# Reflect 20% damage back to 3rd party
		if attacker.has_method("_on_damaged"):
			attacker._on_damaged(damage * 0.2, Vector3.ZERO, "reflected", self)

	current_health -= final_damage
	emit_signal("health_changed", current_health, max_health)
	var bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.player_health_changed.emit(current_health, max_health)
	if current_health <= 0.0:
		current_health = 0.0
		var cycle = get_tree().root.find_child("DayNightCycle", true, false)
		var day_num: int = cycle.current_day if cycle else 1
		var roster = get_node_or_null("/root/RosterManager")
		if roster and roster.has_method("record_run_end"):
			roster.record_run_end(false, day_num, 0)
		emit_signal("player_died")
		if bus:
			bus.player_died.emit()

func perform_ultimate() -> void:
	if ultimate_cooldown_timer > 0.0:
		return

	match current_class:
		CharacterClass.WARRIOR:
			perform_warrior_ultimate()
		CharacterClass.ARCHER:
			perform_archer_ultimate()
		CharacterClass.ENGINEER:
			perform_engineer_ultimate()

func perform_warrior_ultimate() -> void:
	if is_dueling: return
	var target: Node3D = find_target_near_mouse()
	if not target: return
	is_dueling = true
	duel_target = target
	ultimate_cooldown_timer = ultimate_cooldown
	active_tether = DUEL_TETHER_SCENE.instantiate()
	get_parent().add_child(active_tether)
	active_tether.setup(self, duel_target)
	if duel_target.has_method("start_duel"):
		duel_target.start_duel(self)
	spawn_popup_text("DUEL OF HONOR!", Color.GOLD)

func perform_archer_ultimate() -> void:
	if is_eagle_eye: return
	ultimate_cooldown_timer = 25.0
	is_eagle_eye = true
	spawn_popup_text("EAGLE EYE ACTIVATED! (+50% RANGE)", Color.LIGHT_GREEN)
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam:
		var t = create_tween()
		t.tween_property(cam, "size", 34.0, 0.5)

func perform_engineer_ultimate() -> void:
	# GDD: Tactical Nuke / Orbital Missile Salvo — 10m AoE, 1.2s telegraph, burning ground 5s, CD 60s
	ultimate_cooldown_timer = 60.0
	var target_pos: Vector3 = get_nuke_target_position()
	spawn_popup_text("TACTICAL NUKE INCOMING!", Color.ORANGE_RED)
	_execute_tactical_nuke(target_pos)

func get_nuke_target_position() -> Vector3:
	var vp: Viewport = get_viewport()
	if not vp: return global_position
	var cam: Camera3D = vp.get_camera_3d()
	if not cam: return global_position
	var mouse_pos: Vector2 = vp.get_mouse_position()
	var ray_origin: Vector3 = cam.project_ray_origin(mouse_pos)
	var ray_normal: Vector3 = cam.project_ray_normal(mouse_pos)
	var ground_plane: Plane = Plane(Vector3.UP, 0.0)
	var intersect: Variant = ground_plane.intersects_ray(ray_origin, ray_normal)
	if intersect is Vector3:
		return intersect as Vector3
	return global_position

func _execute_tactical_nuke(target_pos: Vector3) -> void:
	# Phase 1: Telegraph (1.2s warning circle on ground)
	var telegraph: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = 10.0
	cyl.bottom_radius = 10.0
	cyl.height = 0.05
	telegraph.mesh = cyl
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.2, 0.0, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.0)
	mat.emission_energy_multiplier = 2.0
	telegraph.material_override = mat
	get_parent().add_child(telegraph)
	telegraph.global_position = target_pos + Vector3(0, 0.05, 0)

	# Fade in telegraph over 1.2s
	var tween_in: Tween = create_tween()
	tween_in.tween_property(mat, "albedo_color", Color(1.0, 0.2, 0.0, 0.45), 1.2)

	await get_tree().create_timer(1.2).timeout

	# Phase 2: IMPACT — massive AoE damage
	var nuke_damage: float = 300.0
	var nuke_radius: float = 10.0
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e and is_instance_valid(e) and e is Node3D:
			var dist: float = target_pos.distance_to((e as Node3D).global_position)
			if dist <= nuke_radius:
				var kb_dir: Vector3 = ((e as Node3D).global_position - target_pos).normalized()
				if e.has_method("_on_damaged"):
					e._on_damaged(nuke_damage, kb_dir * 15.0, "nuke", self)
				# Strip armor from siege monsters
				if e.is_in_group("siege") and "damage_resist" in e:
					e.damage_resist = 0.0

	# Flash telegraph white on impact
	mat.albedo_color = Color(1.0, 1.0, 0.8, 0.7)
	mat.emission = Color(1.0, 1.0, 0.9)
	mat.emission_energy_multiplier = 5.0

	# Phase 3: Burning ground zone (5 seconds of periodic damage)
	var burn_timer: float = 5.0
	var burn_tick: float = 0.5
	var burn_damage: float = 25.0
	var elapsed: float = 0.0

	# Transition to burning look
	var tween_burn: Tween = create_tween()
	tween_burn.tween_property(mat, "albedo_color", Color(1.0, 0.4, 0.0, 0.35), 0.3)
	tween_burn.parallel().tween_property(mat, "emission", Color(1.0, 0.4, 0.0), 0.3)
	tween_burn.parallel().tween_property(mat, "emission_energy_multiplier", 1.5, 0.3)

	while elapsed < burn_timer:
		await get_tree().create_timer(burn_tick).timeout
		elapsed += burn_tick
		if not is_instance_valid(telegraph):
			break
		var burn_enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
		for e in burn_enemies:
			if e and is_instance_valid(e) and e is Node3D:
				if target_pos.distance_to((e as Node3D).global_position) <= nuke_radius:
					if e.has_method("_on_damaged"):
						e._on_damaged(burn_damage, Vector3.ZERO, "burn", self)

	# Cleanup telegraph
	if is_instance_valid(telegraph):
		var tween_out: Tween = create_tween()
		tween_out.tween_property(mat, "albedo_color:a", 0.0, 0.5)
		tween_out.chain().tween_callback(telegraph.queue_free)

func end_duel() -> void:
	if not is_dueling:
		return
	is_dueling = false
	if active_tether and is_instance_valid(active_tether):
		active_tether.queue_free()
		active_tether = null
	duel_target = null
	spawn_popup_text("DUEL VICTORIOUS!", Color.GREEN)

func find_target_near_mouse() -> Node3D:
	var vp: Viewport = get_viewport()
	if not vp: return null
	var cam: Camera3D = vp.get_camera_3d()
	if not cam: return null

	var mouse_pos: Vector2 = vp.get_mouse_position()
	var ray_origin: Vector3 = cam.project_ray_origin(mouse_pos)
	var ray_normal: Vector3 = cam.project_ray_normal(mouse_pos)
	var ground_plane: Plane = Plane(Vector3.UP, 0.0)
	var intersect: Variant = ground_plane.intersects_ray(ray_origin, ray_normal)
	if not (intersect is Vector3): return null

	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
	var nearest: Node3D = null
	var min_dist: float = 14.0

	for e in enemies:
		if e is Node3D and is_instance_valid(e):
			var d: float = (intersect as Vector3).distance_to(e.global_position)
			if d < min_dist:
				min_dist = d
				nearest = e

	return nearest

func spawn_popup_text(msg: String, col: Color) -> void:
	if not is_inside_tree():
		return
	var p: Node = get_parent()
	if not p:
		return
	var popup: Node3D = FLOATING_TEXT_SCENE.instantiate()
	popup.position = global_position + Vector3(0, 2.2, 0)
	p.call_deferred("add_child", popup)
	if popup.has_node("Label3D"):
		popup.get_node("Label3D").text = msg
		popup.get_node("Label3D").modulate = col

func is_in_build_mode() -> bool:
	if _cached_building_system and _cached_building_system.get("current_prefab_type") != null and _cached_building_system.current_prefab_type != 0:
		return true
	if _cached_radial_menu and _cached_radial_menu.visible:
		return true
	return false

func add_xp(amount: float) -> void:
	current_xp += amount
	spawn_popup_text("+%d XP" % int(amount), Color(0.3, 1.0, 0.4))
	while current_xp >= xp_to_next_level:
		current_xp -= xp_to_next_level
		player_level += 1
		xp_to_next_level = round(xp_to_next_level * 1.5)
		emit_signal("level_up_reached", player_level)
		var bus_lvl = get_node_or_null("/root/EventBus")
		if bus_lvl:
			bus_lvl.player_level_up.emit(player_level)
	emit_signal("xp_changed", current_xp, xp_to_next_level, player_level)
	var bus_xp = get_node_or_null("/root/EventBus")
	if bus_xp:
		bus_xp.player_xp_changed.emit(current_xp, xp_to_next_level, player_level)

func heal(amount: float) -> void:
	current_health = min(max_health, current_health + amount)
	emit_signal("health_changed", current_health, max_health)
	var bus_heal = get_node_or_null("/root/EventBus")
	if bus_heal:
		bus_heal.player_health_changed.emit(current_health, max_health)

func apply_card_upgrade(card_id: String) -> void:
	match card_id:
		"SHARP_EDGE":
			attack_damage = round(attack_damage * 1.25)
			special_damage = round(special_damage * 1.25)
			spawn_popup_text("+25% ATK DAMAGE!", Color(1.0, 0.5, 0.1))
		"VITALITY_STONE":
			max_health += 50.0
			heal(40.0)
			spawn_popup_text("+50 MAX HP!", Color(0.2, 1.0, 0.4))
		"WINDSTRIDER":
			speed *= 1.2
			dash_cooldown *= 0.65
			spawn_popup_text("+20% SPEED!", Color(0.2, 0.9, 1.0))
		"HEAVY_MASONRY":
			var bs: Node = get_tree().root.find_child("BuildingSystem", true, false)
			if bs:
				var placed: Dictionary = bs.get("placed_buildings")
				if placed:
					for b in placed.values():
						if b and is_instance_valid(b) and b.has_method("repair"):
							b.max_health += 150.0
							b.repair(150.0)
			spawn_popup_text("+150 BLDG HP!", Color(0.9, 0.8, 0.3))
		"TOWER_BALLISTICS":
			var towers: Array[Node] = get_tree().get_nodes_in_group("towers")
			for t in towers:
				if t and is_instance_valid(t):
					t.attack_range += 3.0
					t.fire_rate *= 0.7
			spawn_popup_text("TOWERS ENHANCED!", Color(0.8, 0.3, 1.0))
		"GREED_HARVESTER":
			resource_multiplier = 2
			spawn_popup_text("2X RESOURCES!", Color.GOLD)
		"VAMPIRIC_STRIKE":
			vampirism_heal += 4.0
			spawn_popup_text("+4 VAMPIRISM!", Color(1.0, 0.2, 0.4))

func trigger_arrow_shot(dmg: float, pierce: int = 1, spd: float = 28.0) -> void:
	var arrow_scene = preload("res://scenes/prefabs/arrow_projectile.tscn")
	var arrow = arrow_scene.instantiate()
	get_parent().add_child(arrow)
	var spawn_pos = global_position + Vector3(0, 0.8, 0)
	var aim_dir = -global_transform.basis.z
	arrow.global_position = spawn_pos + aim_dir * 1.0
	arrow.speed = spd
	var final_dmg = dmg
	arrow.setup(aim_dir, final_dmg, self, pierce)

func trigger_piercing_arrow(dmg: float, pierce: int = 6, spd: float = 36.0) -> void:
	var arrow_scene = preload("res://scenes/prefabs/arrow_projectile.tscn")
	var arrow = arrow_scene.instantiate()
	get_parent().add_child(arrow)
	var spawn_pos = global_position + Vector3(0, 0.8, 0)
	var aim_dir = -global_transform.basis.z
	arrow.global_position = spawn_pos + aim_dir * 1.0
	arrow.scale = Vector3(1.5, 1.5, 2.2)
	arrow.speed = spd
	var final_dmg = dmg
	arrow.setup(aim_dir, final_dmg, self, pierce)
	spawn_popup_text("PIERCING ARROW!", Color.CYAN)

func trigger_hammer_smash(dmg: float) -> void:
	trigger_slash(dmg, 6.0, 110.0)
	# Free repair to nearby buildings hit by hammer
	var buildings = get_tree().get_nodes_in_group("buildings")
	for b in buildings:
		if b and is_instance_valid(b) and b is Node3D:
			if global_position.distance_to((b as Node3D).global_position) <= 2.8:
				if b.has_method("repair"):
					b.repair(40.0)

func deploy_temp_turret() -> void:
	var turret_scene = preload("res://scenes/prefabs/temp_turret.tscn")
	var turret = turret_scene.instantiate()
	get_parent().add_child(turret)
	turret.global_position = global_position + (-global_transform.basis.z * 1.5)
	spawn_popup_text("TURRET DEPLOYED!", Color.GOLD)

func toggle_remote_mine() -> void:
	if is_instance_valid(active_remote_mine):
		active_remote_mine.detonate(self)
		active_remote_mine = null
		parry_cooldown_timer = 3.5
	else:
		if parry_cooldown_timer > 0.0:
			spawn_popup_text("MINE RECHARGING...", Color.GRAY)
			return
		var mine_scene = preload("res://scenes/prefabs/remote_mine.tscn")
		active_remote_mine = mine_scene.instantiate()
		get_parent().add_child(active_remote_mine)
		active_remote_mine.global_position = global_position
		spawn_popup_text("MINE PLANTED! [Q] DETONATE", Color.INDIAN_RED)

func deploy_decoy() -> void:
	if parry_cooldown_timer > 0.0:
		spawn_popup_text("DECOY RECHARGING...", Color.GRAY)
		return
	parry_cooldown_timer = 12.0
	var decoy_scene = preload("res://scenes/prefabs/decoy_dummy.tscn")
	var decoy = decoy_scene.instantiate()
	get_parent().add_child(decoy)
	decoy.global_position = global_position + (-global_transform.basis.z * 3.0)
	spawn_popup_text("DECOY DEPLOYED! (AGGRO 3.5s)", Color.LIGHT_GREEN)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_C:
			cycle_class()

func cycle_class() -> void:
	var next_idx: int = (int(current_class) + 1) % 3
	set_class(CharacterClass.values()[next_idx])

func set_class(new_class: CharacterClass, show_popup: bool = true) -> void:
	current_class = new_class
	var bus_cls = get_node_or_null("/root/EventBus")
	if bus_cls:
		bus_cls.player_class_changed.emit(int(new_class))
	var torso: MeshInstance3D = $Visuals.get_node_or_null("Torso") as MeshInstance3D
	var sword: Node3D = sword_mesh
	var shield: Node3D = parry_shield_mesh

	match current_class:
		CharacterClass.WARRIOR:
			if torso:
				var m = StandardMaterial3D.new()
				m.albedo_color = Color(0.2, 0.45, 0.85) # Blue Knight
				torso.material_override = m
			if sword: sword.visible = true
			if shield: shield.visible = true
			if show_popup: spawn_popup_text("КЛАСС: ВОИН [МЕЧ & ПАРИРОВАНИЕ]", Color(0.3, 0.6, 1.0))
		CharacterClass.ARCHER:
			if torso:
				var m = StandardMaterial3D.new()
				m.albedo_color = Color(0.2, 0.75, 0.35) # Forest Archer
				torso.material_override = m
			if sword: sword.visible = false
			if shield: shield.visible = false
			if show_popup: spawn_popup_text("КЛАСС: ЛУЧНИК [СТРЕЛЬБА & ПРИМАНКА]", Color(0.3, 1.0, 0.5))
		CharacterClass.ENGINEER:
			if torso:
				var m = StandardMaterial3D.new()
				m.albedo_color = Color(0.9, 0.5, 0.15) # Forge Engineer
				torso.material_override = m
			if sword: sword.visible = false
			if shield: shield.visible = false
			if show_popup: spawn_popup_text("КЛАСС: ИНЖЕНЕР [МОЛОТ & ТУРЕЛИ]", Color(1.0, 0.6, 0.2))

func apply_mastery_stats() -> void:
	var roster = get_node_or_null("/root/RosterManager")
	if roster and roster.has_method("get_character_multipliers"):
		var mults = roster.get_character_multipliers(roster.selected_slot_index)
		attack_damage *= mults.damage_mult
		special_damage *= mults.damage_mult
		max_health += mults.max_hp_bonus
		current_health = max_health
		speed *= mults.speed_mult
		dash_speed *= mults.speed_mult
		resource_multiplier = int(mults.resource_mult)

func update_portal_compass() -> void:
	if not portal_compass:
		return
	var portal = get_tree().root.find_child("Portal", true, false)
	if not portal:
		return

	var to_p: Vector3 = portal.global_position - global_position
	to_p.y = 0.0
	if to_p.length_squared() > 0.1:
		portal_compass.look_at(portal_compass.global_position + to_p.normalized(), Vector3.UP)

	var dist: float = to_p.length()
	var status_str: String = "[РЕМОНТ]"
	var col: Color = Color(0.2, 0.9, 1.0)

	var state: int = portal.get("current_state") if portal.get("current_state") != null else 0
	if state == 1: # CHARGING
		status_str = "[ЗАРЯДКА: %ds]" % int(portal.get("charge_timer"))
		col = Color(1.0, 0.85, 0.2)
	elif state == 2: # ACTIVE
		status_str = "[ЭВАКУАЦИЯ ГОТОВА!]"
		col = Color(0.2, 1.0, 0.4)

	if compass_label_3d:
		compass_label_3d.text = "⮵ ПОРТАЛ: %dm\n%s" % [int(dist), status_str]
		compass_label_3d.modulate = col

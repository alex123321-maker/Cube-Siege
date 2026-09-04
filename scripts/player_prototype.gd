extends CharacterBody3D

## Player Root Controller
## Composed of focused subsystems: Movement, Aim, Health, Progression, Interaction, and Presentation.

signal health_changed(current_health: float, max_health: float)
signal xp_changed(current_xp: float, max_xp: float, level: int)
signal level_up_reached(new_level: int)
signal dash_performed()
signal parry_triggered(successful: bool)
signal player_died()

enum CharacterClass { WARRIOR, ARCHER, ENGINEER }
var current_class: CharacterClass = CharacterClass.WARRIOR

# Subsystem components
var movement: PlayerMovement = PlayerMovement.new()
var aim: PlayerAim = PlayerAim.new()
var health: PlayerHealth = PlayerHealth.new()
var progression: PlayerProgression = PlayerProgression.new()
var interaction: PlayerInteraction = PlayerInteraction.new()
var presentation: PlayerPresentation = PlayerPresentation.new()

# Delegated properties for external API compatibility
var speed: float:
	get: return movement.speed
	set(val): movement.speed = val

var dash_speed: float:
	get: return movement.dash_speed
	set(val): movement.dash_speed = val

var dash_duration: float:
	get: return movement.dash_duration
	set(val): movement.dash_duration = val

var dash_cooldown: float:
	get: return movement.dash_cooldown
	set(val): movement.dash_cooldown = val

var max_health: float:
	get: return health.max_health
	set(val): health.max_health = val

var current_health: float:
	get: return health.current_health
	set(val): health.current_health = val

var player_level: int:
	get: return progression.player_level
	set(val): progression.player_level = val

var current_xp: float:
	get: return progression.current_xp
	set(val): progression.current_xp = val

var xp_to_next_level: float:
	get: return progression.xp_to_next_level
	set(val): progression.xp_to_next_level = val

var vampirism_heal: float:
	get: return progression.vampirism_heal
	set(val): progression.vampirism_heal = val

var resource_multiplier: int:
	get: return progression.resource_multiplier
	set(val): progression.resource_multiplier = val

var is_dashing: bool:
	get: return movement.is_dashing
	set(val): movement.is_dashing = val

var is_parrying: bool:
	get: return health.is_parrying
	set(val): health.is_parrying = val

var focused_interactable: Node:
	get: return interaction.focused_interactable
	set(val): interaction.focused_interactable = val

# Combat parameters
@export var attack_damage: float = 25.0
@export var special_damage: float = 60.0
@export var ultimate_cooldown: float = 25.0

var attack_cooldown_timer: float = 0.0
var special_cooldown_timer: float = 0.0
var ultimate_cooldown_timer: float = 0.0

# Class abilities state
var active_remote_mine: Node3D = null
var is_eagle_eye: bool = false
var is_dueling: bool = false
var duel_target: Node3D = null
var active_tether: Node3D = null

# Visual nodes
@onready var hero_warrior: Node3D = $Visuals.get_node_or_null("HeroWarrior")
@onready var anim_player: AnimationPlayer = $Visuals.get_node_or_null("HeroWarrior/AnimationPlayer")
@onready var parry_shield_mesh: Node3D = $Visuals.get_node_or_null("HeroWarrior/root/torso/left_arm/shield") if hero_warrior else $Visuals.get_node_or_null("ParryShield")
@onready var sword_mesh: Node3D = $Visuals.get_node_or_null("HeroWarrior/root/torso/right_arm/sword") if hero_warrior else $Visuals.get_node_or_null("Sword")
@onready var slash_area: Area3D = $SlashHitbox
@onready var portal_compass: Node3D = $PortalCompass

const DUEL_TETHER_SCENE = preload("res://scenes/duel_tether.tscn")
const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

var _cached_building_system: Node = null
var _cached_radial_menu: Control = null

func _ready() -> void:
	add_to_group("player")
	presentation.setup(self)

	# Connect component signals to root
	health.health_changed.connect(func(cur, mx): health_changed.emit(cur, mx))
	health.parry_triggered.connect(func(succ): parry_triggered.emit(succ))
	health.player_died.connect(func(): player_died.emit())
	progression.xp_changed.connect(func(cur, mx, lvl): xp_changed.emit(cur, mx, lvl))
	progression.level_up_reached.connect(func(lvl): level_up_reached.emit(lvl))
	movement.dash_performed.connect(func(): dash_performed.emit())

	# Interaction sensor setup if present
	var sensor = get_node_or_null("InteractionSensor") as Area3D
	if sensor:
		sensor.area_entered.connect(func(a): interaction.add_candidate(a))
		sensor.area_exited.connect(func(a): interaction.remove_candidate(a))
		sensor.body_entered.connect(func(b): interaction.add_candidate(b))
		sensor.body_exited.connect(func(b): interaction.remove_candidate(b))

	# Initialize class from RosterManager
	apply_mastery_stats()
	var roster = get_node_or_null("/root/RosterManager")
	if roster and roster.has_method("get_active_character"):
		var c_data = roster.get_active_character()
		set_class(c_data.class_id as CharacterClass, false)
	else:
		set_class(CharacterClass.WARRIOR, false)

	current_health = max_health
	health_changed.emit(current_health, max_health)
	xp_changed.emit(current_xp, xp_to_next_level, player_level)

	var bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.player_health_changed.emit(current_health, max_health)
		bus.player_xp_changed.emit(current_xp, xp_to_next_level, player_level)

	if slash_area:
		slash_area.set_owner_entity(self)
		slash_area.monitoring = false

	# Cache UI references
	_cached_building_system = get_tree().root.find_child("BuildingSystem", true, false)
	_cached_radial_menu = get_tree().root.find_child("RadialMenu", true, false) as Control

func _physics_process(delta: float) -> void:
	presentation.update_portal_compass(self)

	# Update component timers
	movement.update_timers(delta)
	health.update_timers(delta)

	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta
	if special_cooldown_timer > 0.0:
		special_cooldown_timer -= delta
	if ultimate_cooldown_timer > 0.0:
		ultimate_cooldown_timer -= delta

	if is_dueling and (not duel_target or not is_instance_valid(duel_target)):
		end_duel()

	# Action inputs
	if Input.is_action_just_pressed("dash"):
		movement.perform_dash(-global_transform.basis.z)

	if Input.is_action_just_pressed("class_utility"):
		perform_utility()

	if not is_in_build_mode():
		if Input.is_action_just_pressed("attack_lmb"):
			perform_attack()
		if Input.is_action_just_pressed("special_rmb"):
			perform_special_attack()

	if Input.is_action_just_pressed("ultimate"):
		perform_ultimate()

	# Subsystem processing
	if interaction.candidate_nodes.is_empty():
		# Maintain fallback candidates from scene group
		interaction.update_candidates(get_tree().get_nodes_in_group("interactables"))

	interaction.process_interaction(self, delta)
	movement.process_movement(self, delta, duel_target if is_dueling else null)
	aim.handle_aim(self, duel_target if is_dueling else null)
	presentation.update_animations(self, health.is_parrying, movement.is_dashing)

func take_damage(damage: float, attacker: Node = null) -> void:
	health.take_damage(damage, attacker, movement.is_dashing, is_dueling, duel_target, self)

func heal(amount: float) -> void:
	health.heal(amount)
	var bus = get_node_or_null("/root/EventBus")
	if bus:
		bus.player_health_changed.emit(current_health, max_health)

func add_xp(amount: float) -> void:
	progression.add_xp(amount, self)
	presentation.spawn_popup_text(self, "+%d XP" % int(amount), Color(0.3, 1.0, 0.4))

func apply_mastery_stats() -> void:
	var mults = progression.apply_mastery_stats(self)
	if mults.has("damage_mult"):
		attack_damage *= mults.damage_mult
		special_damage *= mults.damage_mult
	if mults.has("max_hp_bonus"):
		max_health += mults.max_hp_bonus
		current_health = max_health
	if mults.has("speed_mult"):
		speed *= mults.speed_mult
		dash_speed *= mults.speed_mult

func set_class(new_class: CharacterClass, show_popup: bool = true) -> void:
	current_class = new_class
	var def = CharacterDefinition.get_definition(new_class as int)
	if def:
		max_health = def.base_health
		current_health = max_health
		speed = def.base_speed
		dash_speed = def.dash_speed
		dash_cooldown = def.dash_cooldown
		attack_damage = def.base_attack_damage
		special_damage = def.base_special_damage
		ultimate_cooldown = def.ultimate_cooldown

	# Visual appearance setup
	var torso: MeshInstance3D = find_child("torso", true, false) as MeshInstance3D
	var sword: Node3D = find_child("sword", true, false) as Node3D
	var shield: Node3D = find_child("shield", true, false) as Node3D

	match current_class:
		CharacterClass.WARRIOR:
			if torso:
				var m = StandardMaterial3D.new()
				m.albedo_color = Color(0.2, 0.45, 0.85)
				torso.material_override = m
			if sword: sword.visible = true
			if shield: shield.visible = true
			if show_popup: spawn_popup_text("КЛАСС: ВОИН [МЕЧ & ПАРИРОВАНИЕ]", Color(0.3, 0.6, 1.0))
		CharacterClass.ARCHER:
			if torso:
				var m = StandardMaterial3D.new()
				m.albedo_color = Color(0.2, 0.75, 0.35)
				torso.material_override = m
			if sword: sword.visible = false
			if shield: shield.visible = false
			if show_popup: spawn_popup_text("КЛАСС: ЛУЧНИК [СТРЕЛЬБА & ПРИМАНКА]", Color(0.3, 1.0, 0.5))
		CharacterClass.ENGINEER:
			if torso:
				var m = StandardMaterial3D.new()
				m.albedo_color = Color(0.9, 0.5, 0.15)
				torso.material_override = m
			if sword: sword.visible = false
			if shield: shield.visible = false
			if show_popup: spawn_popup_text("КЛАСС: ИНЖЕНЕР [МОЛОТ & ТУРЕЛИ]", Color(1.0, 0.6, 0.2))

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

func perform_parry() -> void:
	if health.trigger_parry(0.5, 6.0):
		if anim_player:
			anim_player.stop()
			anim_player.play("block")
		elif parry_shield_mesh:
			parry_shield_mesh.visible = true

func perform_dash() -> void:
	movement.perform_dash(-global_transform.basis.z)

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
	var target: Node3D = find_target_near_mouse()
	if not target:
		spawn_popup_text("НЕТ ЦЕЛИ ДЛЯ ДУЭЛИ!", Color.ORANGE)
		return

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

	var tween_in: Tween = create_tween()
	tween_in.tween_property(mat, "albedo_color", Color(1.0, 0.2, 0.0, 0.45), 1.2)

	await get_tree().create_timer(1.2).timeout

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
				if e.is_in_group("siege") and "damage_resist" in e:
					e.damage_resist = 0.0

	mat.albedo_color = Color(1.0, 1.0, 0.8, 0.7)
	mat.emission = Color(1.0, 1.0, 0.9)
	mat.emission_energy_multiplier = 5.0

	var burn_timer: float = 5.0
	var burn_tick: float = 0.5
	var burn_damage: float = 25.0
	var elapsed: float = 0.0

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

func trigger_slash(dmg: float, knockback: float, arc_degrees: float) -> void:
	if not slash_area:
		return

	var final_dmg: float = dmg
	if is_dueling:
		final_dmg *= 1.2

	slash_area.damage = final_dmg
	slash_area.knockback_force = knockback
	slash_area.hit_entities.clear()
	slash_area.monitoring = true

	await get_tree().physics_frame
	if is_instance_valid(slash_area):
		for a in slash_area.get_overlapping_areas():
			if slash_area.has_method("_on_area_entered"):
				slash_area._on_area_entered(a)
		if vampirism_heal > 0.0 and slash_area.hit_entities.size() > 0:
			heal(vampirism_heal)
			spawn_popup_text("+%d HP" % int(vampirism_heal), Color.CRIMSON)

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

func trigger_arrow_shot(dmg: float, pierce: int = 1, spd: float = 28.0) -> void:
	var arrow_scene = preload("res://scenes/prefabs/arrow_projectile.tscn")
	var arrow = arrow_scene.instantiate()
	get_parent().add_child(arrow)
	var spawn_pos = global_position + Vector3(0, 0.8, 0)
	var aim_dir = -global_transform.basis.z
	arrow.global_position = spawn_pos + aim_dir * 1.0
	arrow.speed = spd
	arrow.setup(aim_dir, dmg, self, pierce)

func trigger_piercing_arrow(dmg: float, pierce: int = 6, spd: float = 36.0) -> void:
	var arrow_scene = preload("res://scenes/prefabs/arrow_projectile.tscn")
	var arrow = arrow_scene.instantiate()
	get_parent().add_child(arrow)
	var spawn_pos = global_position + Vector3(0, 0.8, 0)
	var aim_dir = -global_transform.basis.z
	arrow.global_position = spawn_pos + aim_dir * 1.0
	arrow.scale = Vector3(1.5, 1.5, 2.2)
	arrow.speed = spd
	arrow.setup(aim_dir, dmg, self, pierce)
	spawn_popup_text("PIERCING ARROW!", Color.CYAN)

func trigger_hammer_smash(dmg: float) -> void:
	trigger_slash(dmg, 6.0, 110.0)
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
	else:
		var mine_scene = preload("res://scenes/prefabs/remote_mine.tscn")
		active_remote_mine = mine_scene.instantiate()
		get_parent().add_child(active_remote_mine)
		active_remote_mine.global_position = global_position + (-global_transform.basis.z * 1.5)
		spawn_popup_text("MINE ARMED! [Q] TO DETONATE", Color.CORAL)

func deploy_decoy() -> void:
	var decoy_scene = preload("res://scenes/prefabs/decoy_dummy.tscn")
	var decoy = decoy_scene.instantiate()
	get_parent().add_child(decoy)
	decoy.global_position = global_position + (-global_transform.basis.z * 2.0)
	spawn_popup_text("DECOY DEPLOYED!", Color.AQUAMARINE)

func apply_card_upgrade(card_id: String) -> void:
	match card_id:
		"SHARP_EDGE":
			attack_damage = roundf(attack_damage * 1.25)
			special_damage = roundf(special_damage * 1.25)
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

func spawn_popup_text(msg: String, col: Color) -> void:
	presentation.spawn_popup_text(self, msg, col)

func is_in_build_mode() -> bool:
	if _cached_building_system and _cached_building_system.get("current_prefab_type") != null and _cached_building_system.current_prefab_type != 0:
		return true
	if _cached_radial_menu and _cached_radial_menu.visible:
		return true
	return false

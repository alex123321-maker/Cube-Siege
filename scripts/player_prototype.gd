extends CharacterBody3D

## Player Root Controller
## Composed of focused subsystems: Movement, Aim, Health, Progression, Interaction, Presentation, Combat, and Abilities.

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
var combat: PlayerCombat = PlayerCombat.new()
var abilities: PlayerAbilities = PlayerAbilities.new()
var orientation: PlayerOrientation = PlayerOrientation.new()

@export var orientation_settings: PlayerOrientationSettings = null
@export var debug_orientation: bool = false

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

var parry_cooldown_timer: float:
	get: return health.parry_cooldown_timer
	set(val): health.parry_cooldown_timer = val

var forced_target: Node3D:
	get: return movement.forced_target
	set(val): movement.forced_target = val

var focused_interactable: Node:
	get: return interaction.focused_interactable
	set(val): interaction.focused_interactable = val

# Delegated orientation properties
var body_facing_direction: Vector3:
	get: return orientation.body_facing_direction

var aim_direction: Vector3:
	get: return orientation.aim_direction

var move_direction: Vector3:
	get: return orientation.move_direction

var directional_speed_multiplier: float:
	get: return orientation.directional_speed_multiplier

var body_aim_angle: float:
	get: return orientation.body_aim_angle

var body_move_angle: float:
	get: return orientation.body_move_angle

var angular_velocity: float:
	get: return orientation.angular_velocity

var is_turning: bool:
	get: return orientation.is_turning

var is_action_pending: bool:
	get: return orientation.is_action_pending()


# External system paths & resolved references
@export var building_system_path: NodePath = NodePath("../BuildingSystem")
@export var radial_menu_path: NodePath = NodePath("../HUD/RadialMenu")
@export var portal_path: NodePath = NodePath("../Portal")

var building_system: BuildingSystem = null
var radial_menu: Control = null
var portal: Node3D = null

# Delegated combat & ability properties
var attack_damage: float:
	get: return combat.attack_damage
	set(val): combat.attack_damage = val

var special_damage: float:
	get: return combat.special_damage
	set(val): combat.special_damage = val

var attack_cooldown_timer: float:
	get: return combat.attack_cooldown_timer
	set(val): combat.attack_cooldown_timer = val

var special_cooldown_timer: float:
	get: return combat.special_cooldown_timer
	set(val): combat.special_cooldown_timer = val

var ultimate_cooldown: float:
	get: return abilities.ultimate_cooldown
	set(val): abilities.ultimate_cooldown = val

var ultimate_cooldown_timer: float:
	get: return abilities.ultimate_cooldown_timer
	set(val): abilities.ultimate_cooldown_timer = val

var active_remote_mine: Node3D:
	get: return abilities.active_remote_mine
	set(val): abilities.active_remote_mine = val

var is_eagle_eye: bool:
	get: return abilities.is_eagle_eye
	set(val): abilities.is_eagle_eye = val

var is_dueling: bool:
	get: return abilities.is_dueling
	set(val): abilities.is_dueling = val

var duel_target: Node3D:
	get: return abilities.duel_target
	set(val): abilities.duel_target = val

var active_tether: Node3D:
	get: return abilities.active_tether
	set(val): abilities.active_tether = val

# Visual nodes
@onready var hero_warrior: Node3D = $Visuals.get_node_or_null("HeroWarrior") if has_node("Visuals") else null
@onready var hero_archer: Node3D = $Visuals.get_node_or_null("HeroArcher") if has_node("Visuals") else null
@onready var hero_engineer: Node3D = $Visuals.get_node_or_null("HeroEngineer") if has_node("Visuals") else null
@onready var anim_player: AnimationPlayer:
	get:
		if presentation and presentation.anim_player:
			return presentation.anim_player
		if has_node("Visuals"):
			return $Visuals.get_node_or_null("HeroWarrior/AnimationPlayer")
		return null
	set(val):
		if presentation:
			presentation.anim_player = val
@onready var parry_shield_mesh: Node3D = $Visuals.get_node_or_null("HeroWarrior/root/torso/left_arm/shield") if hero_warrior else $Visuals.get_node_or_null("ParryShield")
@onready var sword_mesh: Node3D = $Visuals.get_node_or_null("HeroWarrior/root/torso/right_arm/sword") if hero_warrior else $Visuals.get_node_or_null("Sword")
@onready var slash_area: Area3D = $SlashHitbox
@onready var portal_compass: Node3D = $PortalCompass

const DUEL_TETHER_SCENE = preload("res://scenes/duel_tether.tscn")
const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

func _ready() -> void:
	add_to_group("player")
	presentation.setup(self)

	if orientation_settings:
		orientation.settings = orientation_settings
	var initial_fwd: Vector3 = -global_transform.basis.z
	initial_fwd.y = 0.0
	orientation.setup(initial_fwd if initial_fwd.length_squared() > 0.01 else Vector3(0.0, 0.0, -1.0))
	if debug_orientation:
		orientation.set_debug_enabled(true, self)

	# Connect component signals to root
	health.health_changed.connect(func(cur, mx): health_changed.emit(cur, mx))
	health.parry_triggered.connect(func(succ):
		if succ:
			orientation.cancel_pending_action()
		parry_triggered.emit(succ)
	)
	health.player_died.connect(func():
		orientation.cancel_pending_action()
		player_died.emit()
	)
	progression.xp_changed.connect(func(cur, mx, lvl): xp_changed.emit(cur, mx, lvl))
	progression.level_up_reached.connect(func(lvl): level_up_reached.emit(lvl))
	movement.dash_performed.connect(func():
		orientation.cancel_pending_action()
		dash_performed.emit()
	)

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
		if bus.has_signal("day_started"):
			bus.day_started.connect(func(day: int): health.current_day = day)

	if slash_area:
		slash_area.set_owner_entity(self)
		slash_area.monitoring = false

	# Resolve external system references via explicit NodePaths
	if building_system_path and not building_system_path.is_empty():
		building_system = get_node_or_null(building_system_path) as BuildingSystem

	if radial_menu_path and not radial_menu_path.is_empty():
		radial_menu = get_node_or_null(radial_menu_path) as Control

	if portal_path and not portal_path.is_empty():
		portal = get_node_or_null(portal_path) as Node3D

func _physics_process(delta: float) -> void:
	presentation.update_portal_compass(self)

	# Update component timers
	movement.update_timers(delta)
	health.update_timers(delta)
	combat.update_timers(delta)
	abilities.update_timers(delta, self)

	# Aim computed before movement basis
	var deadzone: float = orientation.settings.aim_deadzone if orientation.settings else 0.6
	var target_aim: Vector3 = aim.handle_aim(self, duel_target if is_dueling else null, deadzone)
	if target_aim.length_squared() > 0.001:
		orientation.aim_direction = Vector3(target_aim.x, 0.0, target_aim.z).normalized()

	# Locomotion direction computed relative to aim or forced target
	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var calculated_move_dir: Vector3 = Vector3.ZERO
	if is_dueling and duel_target and is_instance_valid(duel_target):
		var to_duel: Vector3 = duel_target.global_position - global_position
		to_duel.y = 0.0
		if to_duel.length_squared() > 0.01:
			calculated_move_dir = to_duel.normalized()
	elif input_dir.length_squared() > 0.001:
		calculated_move_dir = movement.compute_move_direction(
			global_position,
			orientation.aim_direction,
			input_dir,
			forced_target
		)

	# Action inputs
	if Input.is_action_just_pressed("dash"):
		movement.perform_dash(orientation.body_facing_direction, calculated_move_dir)

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
	interaction.process_interaction(self, delta)

	var orient_move_dir: Vector3 = movement.dash_direction if movement.is_dashing else calculated_move_dir
	orientation.process_orientation(self, delta, target_aim, orient_move_dir)
	if is_dueling and duel_target and is_instance_valid(duel_target):
		movement.process_duel_movement(self, delta, duel_target)
	else:
		movement.process_movement(self, delta, forced_target, orientation.directional_speed_multiplier, orientation.aim_direction)
	presentation.update_animations(self, health.is_parrying, movement.is_dashing)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			debug_orientation = not debug_orientation
			orientation.set_debug_enabled(debug_orientation, self)

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
	var bus_cls = get_node_or_null("/root/EventBus")
	if bus_cls:
		bus_cls.player_class_changed.emit(int(new_class))

	var m_warrior: Node3D = $Visuals.get_node_or_null("HeroWarrior") if has_node("Visuals") else null
	var m_archer: Node3D = $Visuals.get_node_or_null("HeroArcher") if has_node("Visuals") else null
	var m_engineer: Node3D = $Visuals.get_node_or_null("HeroEngineer") if has_node("Visuals") else null

	match current_class:
		CharacterClass.WARRIOR:
			if m_warrior: m_warrior.visible = true
			if m_archer: m_archer.visible = false
			if m_engineer: m_engineer.visible = false
			if presentation and m_warrior: presentation.set_active_model(m_warrior)
			if show_popup: spawn_popup_text("КЛАСС: ВОИН [МЕЧ & ПАРИРОВАНИЕ]", Color(0.3, 0.6, 1.0))
		CharacterClass.ARCHER:
			if m_warrior: m_warrior.visible = false
			if m_archer: m_archer.visible = true
			if m_engineer: m_engineer.visible = false
			if presentation and m_archer: presentation.set_active_model(m_archer)
			if show_popup: spawn_popup_text("КЛАСС: ЛУЧНИК [СТРЕЛЬБА & ПРИМАНКА]", Color(0.3, 1.0, 0.5))
		CharacterClass.ENGINEER:
			if m_warrior: m_warrior.visible = false
			if m_archer: m_archer.visible = false
			if m_engineer: m_engineer.visible = true
			if presentation and m_engineer: presentation.set_active_model(m_engineer)
			if show_popup: spawn_popup_text("КЛАСС: ИНЖЕНЕР [МОЛОТ & ТУРЕЛИ]", Color(1.0, 0.6, 0.2))

func perform_attack() -> void:
	if combat.attack_cooldown_timer > 0.0 or movement.is_dashing:
		return
	orientation.request_action(
		"attack",
		func(): combat.perform_attack(self, int(current_class), movement.is_dashing, abilities.is_dueling),
		true
	)

func perform_special_attack() -> void:
	if combat.special_cooldown_timer > 0.0 or movement.is_dashing:
		return
	orientation.request_action(
		"special",
		func(): combat.perform_special_attack(self, int(current_class), movement.is_dashing, abilities.is_dueling, abilities),
		true
	)

func perform_utility() -> void:
	# Utility actions (Parry, Decoy, Mine) do not require facing
	orientation.request_action(
		"utility",
		func(): abilities.perform_utility(self, int(current_class)),
		false
	)

func perform_parry() -> void:
	abilities.perform_parry(self)

func perform_dash() -> void:
	movement.perform_dash(-global_transform.basis.z)

func perform_ultimate() -> void:
	if abilities.ultimate_cooldown_timer > 0.0:
		return
	match current_class:
		CharacterClass.WARRIOR:
			var target: Node3D = find_target_near_mouse()
			if not target:
				spawn_popup_text("НЕТ ЦЕЛИ ДЛЯ ДУЭЛИ!", Color.ORANGE)
				return
			var target_id: int = target.get_instance_id()
			var target_dir_provider: Callable = func() -> Vector3:
				var t = instance_from_id(target_id) as Node3D
				if not t or not is_instance_valid(t) or not t.is_inside_tree():
					return Vector3.ZERO
				if "current_health" in t and t.current_health <= 0.0:
					return Vector3.ZERO
				var diff: Vector3 = t.global_position - global_position
				diff.y = 0.0
				return diff.normalized()

			orientation.request_action(
				"ultimate",
				func():
					var resolved_target = instance_from_id(target_id) as Node3D
					abilities.perform_warrior_ultimate(self, resolved_target, true),
				true,
				-1.0,
				Vector3.ZERO,
				target_dir_provider
			)
		CharacterClass.ARCHER:
			# Eagle Eye is a self-buff, does not require facing
			orientation.request_action(
				"ultimate",
				func(): abilities.perform_ultimate(self, int(current_class)),
				false
			)
		CharacterClass.ENGINEER:
			# Tactical Nuke strikes from orbit, does not require body facing
			orientation.request_action(
				"ultimate",
				func(): abilities.perform_ultimate(self, int(current_class)),
				false
			)

func end_duel() -> void:
	abilities.end_duel(self)

func find_target_near_mouse() -> Node3D:
	return abilities.find_target_near_mouse(self)

func trigger_slash(dmg: float, knockback: float, arc_degrees: float) -> void:
	combat.trigger_slash(self, dmg, knockback, arc_degrees, abilities.is_dueling)

func trigger_arrow_shot(dmg: float, pierce: int = 1, spd: float = 28.0) -> void:
	combat.trigger_arrow_shot(self, dmg, pierce, spd)

func trigger_piercing_arrow(dmg: float, pierce: int = 6, spd: float = 36.0) -> void:
	combat.trigger_piercing_arrow(self, dmg, pierce, spd)

func trigger_hammer_smash(dmg: float) -> void:
	combat.trigger_hammer_smash(self, dmg, abilities.is_dueling)

func deploy_temp_turret() -> void:
	abilities.deploy_temp_turret(self)

func toggle_remote_mine() -> void:
	abilities.toggle_remote_mine(self)

func deploy_decoy() -> void:
	abilities.deploy_decoy(self)

func apply_card_upgrade(card_id: String) -> void:
	abilities.apply_card_upgrade(card_id, self)

func spawn_popup_text(msg: String, col: Color) -> void:
	presentation.spawn_popup_text(self, msg, col)

func is_in_build_mode() -> bool:
	if building_system and building_system.get("current_prefab_type") != null and building_system.current_prefab_type != 0:
		return true
	if radial_menu and radial_menu.visible:
		return true
	return false

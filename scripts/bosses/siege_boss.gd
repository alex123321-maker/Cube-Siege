extends EnemyBase
class_name SiegeBoss

signal defeated(boss: SiegeBoss)
signal boss_health_changed(current: float, max_hp: float)
signal attack_started(title: String, warning: float)
signal phase_changed(phase: int)

enum State { APPROACH, WARNING, ACTIVE, RECOVERY }
const RegistryClass = preload("res://scripts/core/entity_registry.gd")
@export_range(1, 6) var stage: int = 1
var display_name: String = ""
var profile: BossEncounterProfile
var state: State = State.APPROACH
var phase: int = 1
var _timer: float = 1.0
var _clock: float = 0.0
var _attack_index: int = -1
var _attack: BossAttackSpec
var _direction: Vector3 = Vector3.FORWARD
var _origin: Vector3
var _height_lookup: Callable
var _animation: AnimationPlayer
var _death_sent: bool = false

func configure(p_stage: int, p_target: Node3D) -> void:
	stage = clampi(p_stage, 1, 6)
	target_player = p_target
	profile = BossEncounterCatalog.build(stage)
	display_name = profile.title
	max_health = profile.health
	move_speed = profile.speed
	if is_node_ready():
		current_health = max_health
		boss_health_changed.emit(current_health, max_health)

func _enter_tree() -> void:
	super._enter_tree()
	add_to_group("boss")
	var registry: RegistryClass = get_node_or_null("/root/EntityRegistry") as RegistryClass
	if registry:
		registry.register_boss(self)

func _exit_tree() -> void:
	var registry: RegistryClass = get_node_or_null("/root/EntityRegistry") as RegistryClass
	if registry:
		registry.unregister_boss(self)
	super._exit_tree()

func _ready() -> void:
	if not profile:
		configure(stage, target_player)
	radius = 1.1
	half_height = 1.5
	super._ready()
	_animation = $Visuals/Model/AnimationPlayer as AnimationPlayer
	var map: MapGenerator = get_tree().get_first_node_in_group("map_generator") as MapGenerator
	if map:
		_height_lookup = Callable(map, "get_voxel_height")
	boss_health_changed.emit(current_health, max_health)

func _physics_process(delta: float) -> void:
	if is_dying:
		return
	status_effects.advance(delta)
	_custom_physics(delta)
	desired_velocity_h *= status_effects.movement_multiplier()
	var motion: Dictionary = MonsterLocomotion.process_locomotion(self, delta, desired_velocity_h, Vector3.ZERO, half_height, radius, step_smooth_offset_y)
	step_smooth_offset_y = float(motion.get("smooth_offset_y", 0.0))
	$Visuals.position.y = step_smooth_offset_y
	if state == State.APPROACH:
		presentation.update(delta, velocity, move_speed)
	else:
		_pose_attack()
	desired_velocity_h = Vector3.ZERO

func _custom_physics(delta: float) -> void:
	if not is_instance_valid(target_player):
		_find_player()
		return
	if target_player is PlayerPrototype and (target_player as PlayerPrototype).health.current_health <= 0.0:
		return
	_timer -= delta
	_clock += delta
	match state:
		State.APPROACH:
			var offset: Vector3 = target_player.global_position - global_position
			offset.y = 0.0
			if offset.length_squared() > 0.01:
				look_at(global_position + offset.normalized(), Vector3.UP)
				if offset.length() > 5.0:
					var registry: RegistryClass = get_node_or_null("/root/EntityRegistry") as RegistryClass
					var travel: Vector3 = offset.normalized()
					if registry and registry.monster_flowfield:
						travel = registry.monster_flowfield.get_flow_direction(global_position, target_player.global_position, radius, target_player.get_instance_id())
					desired_velocity_h = travel * move_speed
			if _timer <= 0.0:
				begin_next_attack()
		State.WARNING:
			if _timer <= 0.0:
				state = State.ACTIVE
				_timer = _attack.active
				_clock = 0.0
				if _attack.shape == BossAttackSpec.Shape.FAN:
					_release_projectiles()
		State.ACTIVE:
			if _attack.charge:
				desired_velocity_h = _direction * (_attack.reach / maxf(_attack.active, 0.01))
			if _timer <= 0.0:
				state = State.RECOVERY
				_timer = _attack.recovery
				_clock = 0.0
		State.RECOVERY:
			if _timer <= 0.0:
				state = State.APPROACH
				_timer = 0.65
				_clock = 0.0
				if _animation:
					_animation.play("idle", 0.15)

func begin_next_attack() -> void:
	if is_dying or not is_instance_valid(target_player):
		return
	var next_phase: int = profile.phase_for_health(current_health, max_health)
	if next_phase != phase:
		phase = next_phase
		phase_changed.emit(phase)
	_attack_index = (_attack_index + 1) % profile.attacks.size()
	_attack = profile.attacks[_attack_index].duplicate() as BossAttackSpec
	var acceleration: float = 1.0 - float(phase - 1) * 0.12
	_attack.windup *= acceleration
	_attack.recovery *= acceleration
	_attack.damage *= 1.0 + float(phase - 1) * 0.12
	_attack.projectile_speed *= 1.0 + float(phase - 1) * 0.12
	_direction = target_player.global_position - global_position
	_direction.y = 0.0
	_direction = _direction.normalized() if _direction.length_squared() > 0.001 else Vector3.FORWARD
	look_at(global_position + _direction, Vector3.UP)
	_origin = target_player.global_position if _attack.target_centered else global_position
	_origin.y = _surface_height(_origin)
	state = State.WARNING
	_timer = _attack.windup
	_clock = 0.0
	if _attack.teleport:
		# Reposition only before the visible warning; destination uses locomotion's clearance check.
		var destination: Vector3 = target_player.global_position - _direction * 5.0
		destination.y = MonsterLocomotion.calculate_spawn_y(_surface_height(destination), self)
		if MonsterLocomotion.validate_safe_spawn_point(get_world_3d().direct_space_state, self, destination):
			global_position = destination
	var hazard: BossAttackHazard = BossAttackHazard.new()
	add_child(hazard)
	hazard.setup(_attack, self, target_player, _origin, _direction, profile.color, _height_lookup)
	if _animation:
		_animation.play("attack_%d" % _attack_index)
		_animation.pause()
	attack_started.emit(_attack.title, _attack.windup)

func _pose_attack() -> void:
	if not _animation or not _attack:
		return
	var position: float = 0.0
	match state:
		State.WARNING:
			position = 0.65 * clampf(_clock / _attack.windup, 0.0, 1.0)
		State.ACTIVE:
			position = 0.65 + 0.15 * clampf(_clock / maxf(_attack.active, 0.01), 0.0, 1.0)
		State.RECOVERY:
			position = 0.8 + 0.2 * clampf(_clock / _attack.recovery, 0.0, 1.0)
	var animation_name: StringName = StringName("attack_%d" % _attack_index)
	if _animation.current_animation != animation_name:
		_animation.play(animation_name)
		_animation.pause()
	_animation.seek(position, true)

func _release_projectiles() -> void:
	# One committed fan is one attack, even where neighbouring lanes overlap.
	var hit_ledger: Dictionary = {}
	for index: int in range(_attack.projectile_count):
		var fraction: float = float(index) / maxi(1, _attack.projectile_count - 1)
		var angle: float = lerpf(-_attack.arc_degrees * 0.5, _attack.arc_degrees * 0.5, fraction)
		var direction: Vector3 = _direction.rotated(Vector3.UP, deg_to_rad(angle))
		var projectile: BossProjectile = BossProjectile.new()
		add_child(projectile)
		projectile.top_level = true
		projectile.global_position = global_position + direction * 1.5
		projectile.global_position.y = _surface_height(projectile.global_position) + 0.8
		projectile.setup(self, target_player, direction, _attack.projectile_speed, _attack.damage, profile.color, _height_lookup, maxf(0.0, _attack.reach - 1.5), hit_ledger)

func _surface_height(position: Vector3) -> float:
	return float(_height_lookup.call(TerrainCombatRules.world_to_voxel(position.x), TerrainCombatRules.world_to_voxel(position.z))) if _height_lookup.is_valid() else position.y - half_height

func _on_damaged(amount: float, knockback: Vector3, damage_type: String, attacker: Node) -> void:
	if is_dying:
		return
	super._on_damaged(amount, knockback, damage_type, attacker)
	boss_health_changed.emit(maxf(current_health, 0.0), max_health)
	if not is_dying and state != State.APPROACH:
		_pose_attack()

func _apply_knockback(_knockback: Vector3) -> void:
	# A boss's committed action and preparation cannot be interrupted by a hit.
	knockback_velocity = Vector3.ZERO

func apply_stun(_duration: float) -> void:
	pass

func die() -> void:
	if is_dying or _death_sent:
		return
	_death_sent = true
	for child: Node in get_children():
		if child is BossAttackHazard:
			(child as BossAttackHazard).cancel()
		elif child is BossProjectile:
			child.queue_free()
	var registry: RegistryClass = get_node_or_null("/root/EntityRegistry") as RegistryClass
	if registry:
		registry.unregister_boss(self)
	remove_from_group("boss")
	super.die()
	defeated.emit(self)
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus:
		bus.boss_defeated.emit(self)

func _get_xp_reward() -> float:
	return 0.0

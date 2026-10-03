extends Node
class_name EliteSkillController

## Typed EnemyBase component. Basic archetype AI runs only outside committed casts.
enum State { COOLDOWN, WARNING, ACTIVE, RECOVERY }

const RegistryScript = preload("res://scripts/core/entity_registry.gd")

var enemy: EnemyBase
var spec: EliteSkillSpec
var state: State = State.COOLDOWN
var timer: float = 1.5
var target: Node3D
var direction: Vector3 = Vector3.FORWARD
var origin: Vector3
var locked_target: Vector3
var height_lookup: Callable
var hazards: Array[EliteSkillHazard] = []
var cast_count: int = 0
var _active_elapsed: float = 0.0
var _throws: int = 0
var _leap_start: Vector3
var _leap_finish: Vector3
var _custom_motion_frame: bool = false
var _released: bool = false
var _backswung: bool = false

static func attach(actor: EnemyBase, skill_id: String, p_height: Callable = Callable()) -> EliteSkillController:
	if not is_instance_valid(actor):
		return null
	var definition: EliteSkillSpec = EliteSkillCatalog.create_spec(skill_id)
	if not definition:
		return null
	if is_instance_valid(actor.elite_skill_controller):
		actor.elite_skill_controller.cancel_attack()
		actor.elite_skill_controller.queue_free()
	var controller: EliteSkillController = EliteSkillController.new()
	controller.name = "EliteSkillController"
	controller.enemy = actor
	controller.spec = definition
	controller.height_lookup = p_height
	if not controller.height_lookup.is_valid():
		var registry: RegistryScript = actor.get_node_or_null("/root/EntityRegistry") as RegistryScript
		if registry:
			controller.height_lookup = registry.monster_flowfield.height_lookup
	actor.add_child(controller)
	actor.elite_skill_controller = controller
	actor.add_to_group("elite")
	actor.set_meta("elite", true)
	actor.set_meta("elite_skill", skill_id)
	return controller

func _exit_tree() -> void:
	cancel_attack()
	height_lookup = Callable()
	target = null
	enemy = null

## Called by EnemyBase after status time advances; true consumes ordinary AI.
func advance(delta: float) -> bool:
	_custom_motion_frame = false
	if not is_instance_valid(enemy) or enemy.is_dying or enemy.is_queued_for_deletion():
		cancel_attack()
		return true
	if enemy.status_effects.is_stunned():
		interrupt_attack()
		return true
	for index: int in range(hazards.size() - 1, -1, -1):
		if not is_instance_valid(hazards[index]) or hazards[index].is_queued_for_deletion():
			hazards.remove_at(index)
	if state == State.COOLDOWN:
		timer = maxf(0.0, timer - delta)
		if timer <= 0.0 and is_instance_valid(enemy.target_player) and enemy.global_position.distance_to(enemy.target_player.global_position) <= spec.trigger_range:
			start_attack()
		else:
			return false
	if state in [State.WARNING, State.ACTIVE, State.RECOVERY]:
		enemy.desired_velocity_h = Vector3.ZERO
		enemy.look_at(enemy.global_position + direction, Vector3.UP)
	if state == State.WARNING:
		timer = maxf(0.0, timer - delta)
		if timer <= 0.0:
			_release_attack()
	elif state == State.ACTIVE:
		_active_elapsed += maxf(delta, 0.0)
		match spec.kind:
			EliteSkillSpec.Kind.TRIPLE_THROW:
				while _throws < 3 and _active_elapsed >= float(_throws) * spec.interval:
					_throw_lob()
				if _active_elapsed >= 2.0 * spec.interval + spec.flight_time:
					_begin_recovery()
			EliteSkillSpec.Kind.LEAP_STRIKE:
				_advance_leap()
			EliteSkillSpec.Kind.SHORT_LUNGE:
				enemy.desired_velocity_h = direction * spec.speed
				if _active_elapsed >= spec.reach / spec.speed:
					enemy.desired_velocity_h = Vector3.ZERO
					_begin_recovery()
			EliteSkillSpec.Kind.BACKSWING:
				if not _backswung and _active_elapsed >= spec.interval:
					_backswung = true
					if enemy.presentation:
						enemy.presentation.play_attack()
						if is_instance_valid(enemy.presentation.anim_player) and enemy.presentation.anim_player.has_animation("attack"):
							enemy.presentation.anim_player.play("attack", 0.06, -1.0, true)
				timer -= delta
				if timer <= 0.0:
					_begin_recovery()
			_:
				timer -= delta
				if timer <= 0.0:
					_begin_recovery()
	elif state == State.RECOVERY:
		timer -= delta
		if timer <= 0.0:
			state = State.COOLDOWN
			timer = spec.cooldown
	return true

func uses_custom_motion() -> bool:
	return _custom_motion_frame

func start_attack() -> bool:
	if not is_instance_valid(enemy) or enemy.is_dying or enemy.status_effects.is_stunned() or not spec or state != State.COOLDOWN:
		return false
	target = enemy.target_player
	if not is_instance_valid(target) or not target.is_inside_tree():
		return false
	origin = enemy.global_position - Vector3.UP * enemy.half_height
	locked_target = target.global_position
	locked_target.y = _ground_y(locked_target)
	direction = target.global_position - enemy.global_position
	direction.y = 0.0
	direction = direction.normalized() if direction.length_squared() > 0.001 else Vector3.FORWARD
	state = State.WARNING
	timer = spec.windup
	_active_elapsed = 0.0
	_throws = 0
	_released = false
	_backswung = false
	cast_count += 1
	if enemy.presentation:
		enemy.presentation.play_attack()
	match spec.kind:
		EliteSkillSpec.Kind.TRIPLE_THROW:
			_release_attack()
		EliteSkillSpec.Kind.BACKSWING:
			var first: BossAttackSpec = spec.footprint(BossAttackSpec.Shape.SECTOR)
			_spawn(EliteSkillHazard.Mode.IMPACT, first, origin, spec.windup)
			var second: BossAttackSpec = spec.footprint(BossAttackSpec.Shape.SECTOR, spec.reach * 0.75)
			second.arc_degrees = 70.0
			var back: EliteSkillHazard = _spawn(EliteSkillHazard.Mode.IMPACT, second, origin, spec.windup + spec.interval)
			back.swing_reverse = true
		EliteSkillSpec.Kind.UNDERGROUND_SPIKE:
			_spawn(EliteSkillHazard.Mode.SPIKE, spec.footprint(BossAttackSpec.Shape.CIRCLE, spec.radius), locked_target)
		EliteSkillSpec.Kind.RETURNING_BLADE:
			_spawn(EliteSkillHazard.Mode.BLADE, spec.footprint(BossAttackSpec.Shape.LINE), origin)
		EliteSkillSpec.Kind.LEAP_STRIKE:
			_leap_start = enemy.global_position
			_leap_finish = locked_target + Vector3.UP * enemy.half_height
			var landing: EliteSkillHazard = _spawn(EliteSkillHazard.Mode.IMPACT, spec.footprint(BossAttackSpec.Shape.CIRCLE, spec.radius), locked_target, spec.windup + spec.flight_time)
			landing.externally_triggered = true
		EliteSkillSpec.Kind.FIRE_BREATH:
			_spawn(EliteSkillHazard.Mode.FIRE, spec.footprint(BossAttackSpec.Shape.SECTOR), origin)
		EliteSkillSpec.Kind.SPIT_PUDDLE:
			_spawn(EliteSkillHazard.Mode.SPIT, spec.footprint(BossAttackSpec.Shape.LINE), origin)
		EliteSkillSpec.Kind.FOOT_MINE:
			_spawn(EliteSkillHazard.Mode.MINE, spec.footprint(BossAttackSpec.Shape.CIRCLE, spec.radius), locked_target)
		EliteSkillSpec.Kind.SHORT_LUNGE:
			_spawn(EliteSkillHazard.Mode.IMPACT, spec.footprint(BossAttackSpec.Shape.LINE), origin, 999.0) # Harmless lane; only body contact damages.
	return true

func _release_attack() -> void:
	if _released:
		return
	_released = true
	state = State.ACTIVE
	_active_elapsed = 0.0
	if enemy.presentation:
		enemy.presentation.play_attack()
	match spec.kind:
		EliteSkillSpec.Kind.TRIPLE_THROW:
			_throw_lob()
		EliteSkillSpec.Kind.BACKSWING:
			timer = spec.interval + 0.24
		EliteSkillSpec.Kind.RETURNING_BLADE:
			timer = 2.0 * spec.reach / spec.speed + spec.interval
		EliteSkillSpec.Kind.FIRE_BREATH:
			timer = spec.duration
		EliteSkillSpec.Kind.SPIT_PUDDLE:
			timer = spec.reach / spec.speed
		EliteSkillSpec.Kind.SHORT_LUNGE:
			_spawn(EliteSkillHazard.Mode.LUNGE, spec.footprint(BossAttackSpec.Shape.LINE), origin, 0.0)
		_:
			timer = 0.25

func _throw_lob() -> void:
	if not is_instance_valid(target):
		return
	var point: Vector3 = target.global_position
	point.y = _ground_y(point)
	_spawn(EliteSkillHazard.Mode.LOB, spec.footprint(BossAttackSpec.Shape.CIRCLE, spec.radius), point, spec.flight_time)
	_throws += 1
	if enemy.presentation:
		enemy.presentation.play_attack()

func _spawn(mode: EliteSkillHazard.Mode, footprint: BossAttackSpec, point: Vector3, windup: float = -1.0) -> EliteSkillHazard:
	var hazard: EliteSkillHazard = EliteSkillHazard.new()
	enemy.get_parent().add_child(hazard)
	hazard.setup(spec, enemy, target, mode, footprint, point, direction, height_lookup, windup)
	hazards.append(hazard)
	return hazard

func _advance_leap() -> void:
	_custom_motion_frame = true
	var progress: float = clampf(_active_elapsed / maxf(0.01, spec.flight_time), 0.0, 1.0)
	var intended: Vector3 = _leap_start.lerp(_leap_finish, progress) + Vector3.UP * sin(progress * PI) * 3.0
	var motion: Vector3 = intended - enemy.global_position
	var collision: KinematicCollision3D = enemy.move_and_collide(motion)
	enemy.velocity = motion / maxf(get_physics_process_delta_time(), 0.0001)
	if collision and collision.get_normal().y < 0.5:
		# An intercepted leap cannot remotely strike its original landing marker.
		_cancel_hazards()
		_begin_recovery()
	elif progress >= 1.0:
		enemy.velocity = Vector3.ZERO
		for hazard: EliteSkillHazard in hazards:
			if is_instance_valid(hazard) and hazard.externally_triggered:
				hazard.trigger_impact()
		_begin_recovery()

func _begin_recovery() -> void:
	state = State.RECOVERY
	timer = spec.recovery
	if spec.kind == EliteSkillSpec.Kind.SHORT_LUNGE:
		_cancel_hazards()

func cancel_attack() -> void:
	_cancel_hazards()
	_custom_motion_frame = false
	if spec:
		state = State.COOLDOWN
		timer = spec.cooldown
	if is_instance_valid(enemy):
		enemy.desired_velocity_h = Vector3.ZERO

func interrupt_attack() -> void:
	var committed: Array[EliteSkillHazard] = []
	for hazard: EliteSkillHazard in hazards:
		if not is_instance_valid(hazard):
			continue
		if hazard.is_committed_independent():
			committed.append(hazard)
		else:
			hazard.cancel()
	hazards = committed
	_custom_motion_frame = false
	if spec:
		state = State.COOLDOWN
		timer = spec.cooldown
	if is_instance_valid(enemy):
		enemy.desired_velocity_h = Vector3.ZERO

func _cancel_hazards() -> void:
	for hazard: EliteSkillHazard in hazards:
		if is_instance_valid(hazard):
			hazard.cancel()
	hazards.clear()

func _ground_y(point: Vector3) -> float:
	if height_lookup.is_valid():
		return float(height_lookup.call(int(floorf(point.x)), int(floorf(point.z))))
	return enemy.global_position.y - enemy.half_height

func get_debug_state() -> Dictionary:
	return {"skill": spec.id if spec else "", "state": state, "timer": timer, "casts": cast_count, "throws": _throws, "locked_target": locked_target, "direction": direction, "hazards": hazards.size(), "custom_motion": _custom_motion_frame}

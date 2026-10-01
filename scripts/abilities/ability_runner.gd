extends Node
class_name AbilityRunner

## Shared runtime for the laboratory and opt-in player loadouts.
## Owns cast state, never authored data, health, UI, or normal locomotion.
signal trace_emitted(event: AbilityTrace)
signal area_changed(slot: String, center: Vector3, facing: Vector3, step: AbilityStep, active: bool)
signal cast_finished(cancelled: bool)
signal hit_applied(amount: float)

class ActionState extends RefCounted:
	var action: AbilityPlan.Action
	var begun: bool = false
	var ended: bool = false
	var anchor: Vector3
	var last_hits: Dictionary[int, float] = {}
	var reported: Dictionary[String, bool] = {}
	var query: PhysicsShapeQueryParameters3D

const MAX_TRACE: int = 2000
const QUERY_LIMIT: int = 512
var automatic: bool = true
var running: bool = false
var elapsed: float = 0.0
var cooldown_remaining: float = 0.0
var moved_this_advance: bool = false
var traces: Array[AbilityTrace] = []
var plan: AbilityPlan
var actor: CharacterBody3D
var alive_predicate: Callable
var height_lookup: Callable
var facing: Vector3 = Vector3.FORWARD
var _states: Array[ActionState] = []
var _cast_id: int = 0
var _slice: float = 1.0 / 60.0

func start_cast(definition: AbilityDefinition, caster: CharacterBody3D, direction: Vector3, lookup: Callable = Callable(), allow_draft: bool = false) -> bool:
	if running or cooldown_remaining > 0.0 or not is_instance_valid(caster) or not caster.is_inside_tree():
		return false
	var compiled: AbilityPlan = AbilityCompiler.compile(definition)
	if not compiled.valid() or (compiled.draft and not allow_draft):
		return false
	if not direction.is_finite() or Vector2(direction.x, direction.z).length_squared() < 0.0001:
		return false
	if alive_predicate.is_valid() and not alive_predicate.call():
		return false
	plan = compiled
	actor = caster
	height_lookup = lookup
	facing = Vector3(direction.x, 0.0, direction.z).normalized()
	elapsed = 0.0
	_cast_id += 1
	traces.clear()
	_states.clear()
	_slice = 1.0 / 60.0
	for action: AbilityPlan.Action in plan.actions:
		var state: ActionState = ActionState.new()
		state.action = action
		if action.step.kind == AbilityStep.Kind.AREA:
			var shape: CylinderShape3D = CylinderShape3D.new()
			shape.radius = action.step.radius
			shape.height = 4096.0
			state.query = PhysicsShapeQueryParameters3D.new()
			state.query.shape = shape
			state.query.collision_mask = 8
			state.query.collide_with_areas = true
			state.query.collide_with_bodies = false
		_states.append(state)
		if action.step.kind == AbilityStep.Kind.MOVE:
			var speed: float = absf(action.step.distance) / action.step.duration
			_slice = minf(_slice, 0.2 / maxf(speed, 0.001))
	cooldown_remaining = plan.cooldown
	running = true
	_record("Применение", "", "Начало: " + plan.title)
	return true

func _physics_process(delta: float) -> void:
	if automatic:
		advance(delta)

func advance(delta: float) -> void:
	moved_this_advance = false
	if not is_finite(delta) or delta <= 0.0 or delta > 1.0:
		return
	cooldown_remaining = maxf(0.0, cooldown_remaining - delta)
	if not running:
		return
	if not is_instance_valid(actor) or not actor.is_inside_tree() or (alive_predicate.is_valid() and not alive_predicate.call()):
		cancel("Владелец исчез или погиб")
		return
	var remaining: float = delta
	while running and remaining > 0.000001:
		var dt: float = minf(remaining, _slice)
		var consumed: float = _tick(dt)
		remaining -= consumed

func _tick(delta: float) -> float:
	var previous_time: float = elapsed
	var next_time: float = minf(elapsed + delta, plan.duration)
	# Cut at every authored boundary so adjacent actions never move simultaneously.
	for state: ActionState in _states:
		for boundary: float in [state.action.start, state.action.start + state.action.step.duration]:
			if boundary > elapsed + 0.000001 and boundary < next_time:
				next_time = boundary
	for state: ActionState in _states:
		if not state.begun and state.action.start <= elapsed + 0.000001:
			state.begun = true
			state.anchor = actor.global_position
			_record(state.action.path, "", "Начало · " + state.action.source)
			if state.action.step.kind == AbilityStep.Kind.AREA:
				_sample_area(state)
				if not running:
					return next_time - previous_time
	# Movement precedes area sampling, including swept samples along the path.
	for state: ActionState in _states:
		if _active(state) and state.action.step.kind == AbilityStep.Kind.MOVE:
			moved_this_advance = true
			var motion: Vector3 = facing * state.action.step.distance * (next_time - elapsed) / state.action.step.duration
			var collision: KinematicCollision3D = actor.move_and_collide(motion)
			if collision:
				_report_once(state, "movement", "", "Перемещение остановлено препятствием")
	for state: ActionState in _states:
		if _active(state) and state.action.step.kind == AbilityStep.Kind.AREA:
			_sample_area(state)
			if not running:
				return next_time - previous_time
	elapsed = next_time
	for state: ActionState in _states:
		if state.begun and not state.ended and elapsed >= state.action.start + state.action.step.duration - 0.000001:
			state.ended = true
			area_changed.emit(state.action.path, state.anchor, facing, state.action.step, false)
			_record(state.action.path, "", "Завершено")
	if elapsed >= plan.duration - 0.000001:
		running = false
		_record("Применение", "", "Завершено")
		cast_finished.emit(false)
	return next_time - previous_time

func _active(state: ActionState) -> bool:
	return state.begun and not state.ended and elapsed < state.action.start + state.action.step.duration - 0.000001

func _sample_area(state: ActionState) -> void:
	var step: AbilityStep = state.action.step
	var center: Vector3 = actor.global_position if step.follow_actor else state.anchor
	area_changed.emit(state.action.path, center, facing, step, true)
	state.query.transform = Transform3D(Basis.IDENTITY, center)
	var space: PhysicsDirectSpaceState3D = actor.get_world_3d().direct_space_state
	var candidates: Array[Dictionary] = space.intersect_shape(state.query, QUERY_LIMIT)
	if candidates.size() >= QUERY_LIMIT:
		cancel("Превышен лимит кандидатов области; результат не считается полным")
		return
	for candidate: Dictionary in candidates:
		var hurtbox: HurtboxArea = candidate.get("collider") as HurtboxArea
		if hurtbox == null:
			continue
		var target: EnemyBase = hurtbox.get_target_node() as EnemyBase
		if target == null or target.is_dying or target == actor:
			continue
		var offset: Vector3 = target.global_position - center
		offset.y = 0.0
		var reason: String = ""
		if offset.length() > step.radius:
			reason = "Вне радиуса (по центру цели)"
		elif offset.length_squared() > 0.0001 and facing.dot(offset.normalized()) < cos(deg_to_rad(step.arc_degrees * 0.5)) - 0.00001:
			reason = "Вне сектора"
		elif not TerrainCombatRules.can_ability_hit_target(center, target.global_position, step.terrain_mode, step.radius, height_lookup):
			reason = "Рельеф блокирует попадание"
		elif step.terrain_mode == TerrainCombatRules.TerrainMode.TERRAIN_DEPENDENT and _blocked(space, center, target.global_position):
			reason = "Препятствие блокирует попадание"
		var id: int = target.get_instance_id()
		if reason.is_empty() and state.last_hits.has(id):
			if step.repeat_interval == 0.0:
				reason = "Уже поражён этим действием"
			elif elapsed - state.last_hits[id] < step.repeat_interval - 0.000001:
				reason = "Интервал повторного попадания ещё не истёк"
		if not reason.is_empty():
			_report_once(state, "%d:%s" % [id, reason], target.name, reason)
			continue
		state.last_hits[id] = elapsed
		var before: float = maxf(target.current_health, 0.0)
		hurtbox.take_damage(step.damage, offset.normalized() * step.knockback, "physical", actor)
		var dealt: float = before - maxf(target.current_health, 0.0) if is_instance_valid(target) else before
		hit_applied.emit(dealt)
		_record(state.action.path, str(target.name) if is_instance_valid(target) else "Удалённая цель", "Попадание: %.1f урона" % dealt, dealt)

func _blocked(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1)
	ray.exclude = [actor.get_rid()]
	return not space.intersect_ray(ray).is_empty()

func _report_once(state: ActionState, key: String, target: String, reason: String) -> void:
	if not state.reported.has(key):
		state.reported[key] = true
		_record(state.action.path, target, reason)

func _record(slot: String, target: String, reason: String, amount: float = 0.0) -> void:
	if traces.size() >= MAX_TRACE:
		return
	var event: AbilityTrace = AbilityTrace.new()
	event.sequence = traces.size() + 1
	event.cast_id = _cast_id
	event.time = elapsed
	event.slot = slot
	event.target = target
	event.reason = reason
	if traces.size() == MAX_TRACE - 1:
		event.reason = "Журнал ограничен %d событиями; симуляция и счётчики продолжаются" % MAX_TRACE
	event.amount = amount
	traces.append(event)
	trace_emitted.emit(event)

func cancel(reason: String = "Прервано") -> void:
	if not running:
		return
	running = false
	for state: ActionState in _states:
		area_changed.emit(state.action.path, state.anchor, facing, state.action.step, false)
	_record("Применение", "", reason)
	cast_finished.emit(true)

func owns_movement() -> bool:
	if running:
		for state: ActionState in _states:
			if state.action.step.kind == AbilityStep.Kind.MOVE and elapsed >= state.action.start - 0.000001 and elapsed < state.action.start + state.action.step.duration - 0.000001:
				return true
	return false

func _exit_tree() -> void:
	cancel("Исполнитель удалён")

extends Node3D
class_name BossAttackHazard

signal hit_confirmed(target: Node3D)

var spec: BossAttackSpec
var boss: SiegeBoss
var target: Node3D
var direction: Vector3 = Vector3.FORWARD
var height_lookup: Callable
var warning_left: float = 0.0
var active_left: float = 0.0
var hit_once: bool = false
var cancelled: bool = false
var armed_trap: bool = false
var marks: Array[BossAttackMark] = []
var _activated: bool = false
var _visual: BossAttackVFX
var _hurtbox: HurtboxArea
var _time: float = 0.0
var _tint: Color
var _flight: MeshInstance3D
var _launch: Vector3
var _last_body_position: Vector3
var _carrying: bool = false
var _trap_trigger_time: float = -1.0
var _planned: PackedVector3Array = PackedVector3Array()
var _cadence: ContinuousDamageCadence = ContinuousDamageCadence.new()

func setup(p_spec: BossAttackSpec, p_boss: SiegeBoss, p_target: Node3D, origin: Vector3, p_direction: Vector3, color: Color, p_height: Callable) -> void:
	spec = p_spec
	boss = p_boss
	target = p_target
	direction = p_direction
	height_lookup = p_height
	_tint = color
	top_level = true
	global_position = origin
	process_physics_priority = 100 # Observe collision-resolved boss movement.
	warning_left = spec.windup
	active_left = spec.active
	_last_body_position = boss.global_position
	_hurtbox = target.get_node_or_null("Hurtbox") as HurtboxArea if is_instance_valid(target) else null
	if spec.kind == BossAttackSpec.Kind.CHAIN:
		for index: int in range(spec.mark_count):
			var angle: float = float(index) * 2.399963
			var distance: float = 0.0 if index == 0 else spec.spread_radius * (0.45 + 0.55 * float(index) / maxi(1, spec.mark_count - 1))
			_planned.append(_ground(origin + Vector3(cos(angle), 0.0, sin(angle)) * distance))
	if spec.kind == BossAttackSpec.Kind.CHAIN or spec.kind == BossAttackSpec.Kind.CHASE:
		_spawn_due_marks()
	else:
		_visual = _new_visual(spec, Vector3.ZERO)
	if spec.kind == BossAttackSpec.Kind.LOBBED:
		_launch = boss.global_position + Vector3.UP * 1.3
		_flight = MeshInstance3D.new()
		var crystal: PrismMesh = PrismMesh.new()
		crystal.size = Vector3(0.65, 0.85, 0.65)
		_flight.mesh = crystal
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.albedo_color = color
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 1.4
		_flight.material_override = material
		add_child(_flight)
		_update_flight(0.0)

func _exit_tree() -> void:
	_release_carry()

func cancel() -> void:
	if cancelled:
		return
	cancelled = true
	_cadence.cancel()
	_release_carry()
	queue_free()

func _live() -> bool:
	return not cancelled and is_instance_valid(boss) and not boss.is_dying and not boss.is_queued_for_deletion() and is_instance_valid(target) and not target.is_queued_for_deletion() and (not target is PlayerPrototype or (target as PlayerPrototype).current_health > 0.0)

func _physics_process(delta: float) -> void:
	if not _live():
		cancel()
		return
	var previous: float = _time
	_time += maxf(delta, 0.0)
	warning_left = maxf(0.0, spec.windup - _time)
	active_left = maxf(0.0, spec.windup + spec.active - _time)
	if spec.kind == BossAttackSpec.Kind.CHAIN or spec.kind == BossAttackSpec.Kind.CHASE:
		_spawn_due_marks()
		_advance_marks()
		if _time >= spec.windup + spec.active:
			cancel()
		return
	if previous < spec.windup:
		_visual.set_warning_progress(minf(_time / maxf(spec.windup, 0.01), 1.0))
		if spec.kind == BossAttackSpec.Kind.LOBBED:
			_update_flight(minf(_time / maxf(spec.windup, 0.01), 1.0))
		if _time < spec.windup:
			return
	if not _activated:
		_activated = true
		_visual.show_impact()
		if is_instance_valid(_flight):
			_flight.queue_free()
		match spec.kind:
			BossAttackSpec.Kind.BURST:
				_try_hit()
			BossAttackSpec.Kind.LOBBED:
				# Occupied landings are consumed even when parried or invulnerable.
				if spec.contains_point(global_position, direction, target.global_position):
					_try_hit()
				else:
					armed_trap = true
					_visual.show_armed_trap()
	var active_from: float = clampf(previous - spec.windup, 0.0, spec.active)
	var active_to: float = clampf(_time - spec.windup, 0.0, spec.active)
	match spec.kind:
		BossAttackSpec.Kind.LINE_BEAM:
			_line_damage(active_from, active_to)
		BossAttackSpec.Kind.RADIAL_BEAM:
			_radial_damage(active_from, active_to)
		BossAttackSpec.Kind.LOBBED:
			if armed_trap and not hit_once and _time < spec.windup + spec.trap_lifetime:
				if _try_hit():
					armed_trap = false
					_trap_trigger_time = _time
					_visual.show_impact()
		BossAttackSpec.Kind.SWEEP:
			_sweep_contact()
	if not _live():
		cancel()
		return
	if not armed_trap:
		_visual.set_impact_progress(clampf(active_to / maxf(spec.active, 0.01), 0.0, 1.0))
	if spec.kind == BossAttackSpec.Kind.SWEEP:
		if boss.state == SiegeBoss.State.RECOVERY:
			cancel()
	elif _trap_trigger_time >= 0.0:
		_visual.set_impact_progress(clampf((_time - _trap_trigger_time) / 0.30, 0.0, 1.0))
		if _time >= _trap_trigger_time + 0.30:
			cancel()
	elif _time >= spec.windup + (spec.trap_lifetime if armed_trap else spec.active):
		cancel()

func _new_visual(visual_spec: BossAttackSpec, local_position: Vector3) -> BossAttackVFX:
	var result: BossAttackVFX = BossAttackVFX.new()
	add_child(result)
	result.position = local_position
	result.setup(visual_spec, direction, _tint, height_lookup)
	return result

func _ground(point: Vector3) -> Vector3:
	var result: Vector3 = point
	result.y = float(height_lookup.call(TerrainCombatRules.world_to_voxel(point.x), TerrainCombatRules.world_to_voxel(point.z))) if height_lookup.is_valid() else global_position.y
	return result

func _update_flight(progress: float) -> void:
	_flight.global_position = _launch.lerp(global_position + Vector3.UP * 0.3, progress) + Vector3.UP * (4.0 * spec.flight_height * progress * (1.0 - progress))
	_flight.rotation.y = progress * TAU

func _spawn_due_marks() -> void:
	var count: int = 6 if spec.kind == BossAttackSpec.Kind.CHASE else spec.mark_count
	while marks.size() < count and float(marks.size()) * spec.mark_gap <= _time and _live():
		var mark: BossAttackMark = BossAttackMark.new()
		mark.born = float(marks.size()) * spec.mark_gap
		mark.detonate = mark.born + spec.windup
		# Sample the real target now, never extrapolate a predicted trail.
		mark.centre = _ground(target.global_position) if spec.kind == BossAttackSpec.Kind.CHASE else _planned[marks.size()]
		mark.visual = _new_visual(spec, mark.centre - global_position)
		marks.append(mark)

func _advance_marks() -> void:
	for mark: BossAttackMark in marks:
		if not _live():
			return
		if not mark.exploded:
			mark.visual.set_warning_progress(clampf((_time - mark.born) / maxf(spec.windup, 0.01), 0.0, 1.0))
			if _time >= mark.detonate:
				mark.exploded = true
				mark.visual.show_impact()
				if spec.contains_point(mark.centre, direction, target.global_position) and _connected(mark.centre):
					_deliver(spec.damage)
		elif is_instance_valid(mark.visual):
			mark.visual.set_impact_progress(clampf((_time - mark.detonate) / 0.30, 0.0, 1.0))
			if _time >= mark.detonate + 0.30:
				mark.visual.queue_free()

func _connected(origin: Vector3) -> bool:
	return TerrainCombatRules.can_ability_hit_target(origin, target.global_position, spec.terrain_mode, maxf(spec.reach * 1.5, spec.spread_radius + spec.reach), height_lookup)

func _line_damage(from: float, to: float) -> void:
	if to <= from or not spec.contains_point(global_position, direction, target.global_position) or not _connected(global_position):
		_continuous_damage(0.0, to >= spec.active)
		return
	var offset: Vector3 = target.global_position - global_position
	offset.y = 0.0
	var arrival: float = clampf(offset.dot(direction) / maxf(spec.reach, 0.01), 0.0, 1.0) * spec.active
	var exposure: float = maxf(0.0, to - maxf(from, arrival))
	_continuous_damage(exposure, to >= spec.active)

func _radial_damage(from: float, to: float) -> void:
	var offset: Vector3 = target.global_position - global_position
	offset.y = 0.0
	if to <= from or offset.length() > spec.reach or not _connected(global_position):
		_continuous_damage(0.0, to >= spec.active)
		return
	if offset.length() < 0.001:
		_continuous_damage(to - from, to >= spec.active)
		return
	var angle: float = rad_to_deg(direction.signed_angle_to(offset.normalized(), Vector3.UP)) if offset.length() > 0.001 else 0.0
	if absf(angle) > spec.arc_degrees * 0.5:
		_continuous_damage(0.0, to >= spec.active)
		return
	var starts: PackedFloat32Array = spec.radial_angles(from / spec.active)
	var ends: PackedFloat32Array = spec.radial_angles(to / spec.active)
	var first_begin: float = INF
	var first_end: float = -INF
	var exposure: float = 0.0
	for index: int in range(starts.size()):
		var speed: float = spec.radial_speed()
		var sign: float = 1.0 if ends[index] >= starts[index] else -1.0
		var begin: float = from + clampf((angle - sign * spec.ray_half_angle_degrees - starts[index]) / (sign * speed), 0.0, to - from)
		var finish: float = from + clampf((angle + sign * spec.ray_half_angle_degrees - starts[index]) / (sign * speed), 0.0, to - from)
		if finish <= begin:
			continue
		exposure += finish - begin
		if first_begin != INF:
			exposure -= maxf(0.0, minf(first_end, finish) - maxf(first_begin, begin))
		first_begin = begin
		first_end = finish
	_continuous_damage(exposure, to >= spec.active)

func _continuous_damage(exposure: float, finished: bool) -> void:
	for seconds: float in _cadence.sample(exposure):
		if not _live():
			return
		_deliver(spec.damage * seconds)
	if finished:
		var residual: float = _cadence.end_contact()
		if residual > 0.0 and _live():
			_deliver(spec.damage * residual)

func _sweep_contact() -> void:
	var current: Vector3 = boss.global_position
	if boss.state == SiegeBoss.State.WARNING:
		_last_body_position = current
		return
	var delta: Vector3 = current - _last_body_position
	delta.y = 0.0
	if not hit_once and delta.length_squared() > 0.000001:
		var offset: Vector3 = target.global_position - _last_body_position
		offset.y = 0.0
		var fraction: float = clampf(offset.dot(delta) / delta.length_squared(), 0.0, 1.0)
		var nearest: Vector3 = _last_body_position + delta * fraction
		var horizontal: Vector3 = target.global_position - nearest
		horizontal.y = 0.0
		if horizontal.length() <= boss.radius + 0.6 and TerrainCombatRules.is_melee_connected(nearest, target.global_position, height_lookup):
			_deliver(spec.damage)
			hit_once = true
			if _live() and target is PlayerPrototype:
				_carrying = (target as PlayerPrototype).begin_enemy_carry(self)
	if _carrying and _live():
		var anchor: Vector3 = current + direction * (boss.radius + 0.65)
		var displacement: Vector3 = anchor - target.global_position
		displacement.y = 0.0
		if not (target as PlayerPrototype).apply_enemy_carry_motion(self, displacement):
			_release_carry()
	_last_body_position = current

func _release_carry() -> void:
	if _carrying and is_instance_valid(target) and target is PlayerPrototype:
		(target as PlayerPrototype).end_enemy_carry(self)
	_carrying = false

func _try_hit() -> bool:
	if not _live() or hit_once or not spec.contains_point(global_position, direction, target.global_position) or not _connected(global_position):
		return false
	hit_once = _deliver(spec.damage)
	return hit_once

func _deliver(amount: float) -> bool:
	if not _live() or amount <= 0.0:
		return false
	var consumed: bool = false
	var damaged: bool = false
	if target is PlayerPrototype:
		var player: PlayerPrototype = target as PlayerPrototype
		var before: float = player.current_health + player.health.shield_health
		player.take_damage(amount, boss)
		consumed = true
		damaged = is_instance_valid(player) and player.current_health + player.health.shield_health < before
	elif is_instance_valid(_hurtbox):
		consumed = _hurtbox.take_damage(amount, Vector3.ZERO, "boss", boss, CombatRules.Team.ENEMY)
		damaged = consumed
	if consumed and is_instance_valid(target):
		hit_confirmed.emit(target)
		if damaged and spec.slowing > 0.0 and _live() and target is PlayerPrototype:
			(target as PlayerPrototype).apply_slow("boss_%s_%s" % [boss.get_instance_id(), spec.title], spec.slowing, 2.5)
	return consumed

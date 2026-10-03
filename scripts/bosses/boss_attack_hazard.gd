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
var _activated: bool = false
var _visual: BossAttackVFX
var _hurtbox: HurtboxArea

func setup(p_spec: BossAttackSpec, p_boss: SiegeBoss, p_target: Node3D, origin: Vector3, p_direction: Vector3, color: Color, p_height: Callable) -> void:
	spec = p_spec
	boss = p_boss
	target = p_target
	direction = p_direction
	height_lookup = p_height
	top_level = true
	global_position = origin
	warning_left = spec.windup
	active_left = spec.active
	_hurtbox = target.get_node_or_null("Hurtbox") as HurtboxArea if is_instance_valid(target) else null
	_visual = BossAttackVFX.new()
	add_child(_visual)
	_visual.setup(spec, direction, color, height_lookup)

func cancel() -> void:
	cancelled = true
	queue_free()

func _physics_process(delta: float) -> void:
	if cancelled or not is_instance_valid(boss) or boss.is_dying:
		cancel()
		return
	if warning_left > 0.0:
		warning_left = maxf(0.0, warning_left - delta)
		_visual.set_warning_progress(1.0 - warning_left / maxf(spec.windup, 0.01))
		return
	if not _activated:
		_activated = true
		_visual.show_impact()
	if active_left > 0.0:
		active_left -= delta
		_try_hit()
		_visual.set_impact_progress(1.0 - maxf(active_left, 0.0) / maxf(spec.active, 0.01))
	else:
		queue_free()

func _try_hit() -> bool:
	if cancelled or not is_instance_valid(boss) or boss.is_dying or hit_once or not is_instance_valid(target):
		return false
	if not spec.contains_point(global_position, direction, target.global_position):
		return false
	if spec.charge and Vector2(target.global_position.x - boss.global_position.x, target.global_position.z - boss.global_position.z).length() > boss.radius + 0.6:
		return false
	if not TerrainCombatRules.can_ability_hit_target(global_position, target.global_position, spec.terrain_mode, spec.reach * 1.5, height_lookup):
		return false
	var damaged: bool = false
	if target is PlayerPrototype:
		var player: PlayerPrototype = target as PlayerPrototype
		var before: float = player.current_health + player.health.shield_health
		player.take_damage(spec.damage, boss)
		hit_once = true
		damaged = player.current_health + player.health.shield_health < before
	elif is_instance_valid(_hurtbox):
		hit_once = _hurtbox.take_damage(spec.damage, Vector3.ZERO, "boss", boss, CombatRules.Team.ENEMY)
		damaged = hit_once
	if hit_once:
		hit_confirmed.emit(target)
		if damaged and spec.slowing > 0.0 and target is PlayerPrototype:
			(target as PlayerPrototype).apply_slow("boss_%s_%s" % [boss.get_instance_id(), spec.title], spec.slowing, 2.5)
	return hit_once

extends Node3D
class_name EliteSkillHazard

## An owner-bound, finite skill effect. Warning geometry and impact use one spec.
enum Mode { IMPACT, LOB, SPIKE, BLADE, FIRE, SPIT, MINE, LUNGE }

const RegistryScript = preload("res://scripts/core/entity_registry.gd")

signal hit_confirmed(target: Node3D, amount: float)

var spec: EliteSkillSpec
var enemy: EnemyBase
var target: Node3D
var mode: Mode = Mode.IMPACT
var footprint: BossAttackSpec
var direction: Vector3 = Vector3.FORWARD
var height_lookup: Callable
var warning_duration: float = 1.0
var elapsed: float = 0.0
var activated: bool = false
var cancelled: bool = false
var hit_count: int = 0
var projectile_position: Vector3 = Vector3.ZERO
var _visual: BossAttackVFX
var _projectile: MeshInstance3D
var _solid: StaticBody3D
var _registry: RegistryScript
var _origin: Vector3
var _launch: Vector3
var _last_target: Vector3
var _last_enemy: Vector3
var _hurtbox: HurtboxArea
var _hit_passes: PackedInt32Array = []
var _spit_landed: bool = false
var _spit_landed_at: float = 0.0
var _spit_land_position: Vector3
var _armed: bool = false
var _mine_marker: MeshInstance3D
var _impact_at: float = -1.0
var swing_reverse: bool = false
var externally_triggered: bool = false
var _cadence: ContinuousDamageCadence = ContinuousDamageCadence.new()

func setup(p_spec: EliteSkillSpec, p_enemy: EnemyBase, p_target: Node3D, p_mode: Mode, p_footprint: BossAttackSpec, origin: Vector3, p_direction: Vector3, p_height: Callable, p_warning: float = -1.0) -> void:
	spec = p_spec
	enemy = p_enemy
	target = p_target
	mode = p_mode
	footprint = p_footprint
	direction = p_direction
	height_lookup = p_height
	warning_duration = spec.windup if p_warning < 0.0 else p_warning
	top_level = true
	global_position = origin
	_origin = origin
	_launch = enemy.global_position + Vector3(0.0, 0.2, 0.0)
	_last_target = target.global_position if is_instance_valid(target) else origin
	_last_enemy = enemy.global_position
	_hurtbox = target.get_node_or_null("Hurtbox") as HurtboxArea if is_instance_valid(target) else null
	_registry = get_node_or_null("/root/EntityRegistry") as RegistryScript
	_visual = BossAttackVFX.new()
	add_child(_visual)
	_visual.setup(footprint, direction, spec.color, height_lookup)
	if mode in [Mode.LOB, Mode.BLADE, Mode.SPIT]:
		_projectile = MeshInstance3D.new()
		if mode == Mode.BLADE:
			var blade: BoxMesh = BoxMesh.new()
			blade.size = Vector3(0.9, 0.12, 0.28)
			_projectile.mesh = blade
		else:
			var ball: SphereMesh = SphereMesh.new()
			ball.radius = 0.20
			ball.height = 0.40
			_projectile.mesh = ball
		var material: StandardMaterial3D = StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = spec.color
		material.emission_enabled = true
		material.emission = spec.color
		_projectile.material_override = material
		add_child(_projectile)
		_projectile.visible = mode == Mode.LOB
		_projectile.global_position = _launch
	if mode == Mode.LUNGE:
		_visual.visible = false # The real mob silhouette, rather than its route, is dangerous.
		activated = true

func cancel() -> void:
	if cancelled:
		return
	cancelled = true
	_cadence.cancel()
	_release_obstacle()
	queue_free()

func _exit_tree() -> void:
	_release_obstacle()
	height_lookup = Callable()
	target = null
	enemy = null

func _physics_process(delta: float) -> void:
	if cancelled or not is_instance_valid(enemy) or enemy.is_dying or enemy.is_queued_for_deletion() or not enemy.is_inside_tree():
		cancel()
		return
	var before: float = elapsed
	elapsed += maxf(0.0, delta)
	if mode == Mode.LOB and is_instance_valid(_projectile):
		var progress: float = clampf(elapsed / maxf(warning_duration, 0.01), 0.0, 1.0)
		projectile_position = _launch.lerp(_origin + Vector3.UP * 0.2, progress) + Vector3.UP * sin(progress * PI) * 3.5
		_projectile.global_position = projectile_position
	if elapsed < warning_duration:
		_visual.set_warning_progress(elapsed / maxf(warning_duration, 0.01))
		return
	if externally_triggered and not activated:
		_visual.set_warning_progress(1.0)
		return
	var active_delta: float = elapsed - maxf(before, warning_duration)
	if not activated:
		activated = true
		if mode in [Mode.BLADE, Mode.SPIT, Mode.MINE]:
			_visual.set_warning_progress(1.0) # The route itself always remains harmless.
		else:
			_visual.show_impact()
		match mode:
			Mode.IMPACT, Mode.LOB:
				_impact_once()
			Mode.SPIKE:
				_impact_once()
				_create_spike()
			Mode.MINE:
				_armed = true
				_create_mine_visual()
				return # Arming is an observable state; it is never itself an explosion.
			Mode.BLADE, Mode.SPIT:
				_visual.visible = true # The lane remains a harmless route guide.
				_projectile.visible = true
	var active_time: float = elapsed - warning_duration
	match mode:
		Mode.IMPACT, Mode.LOB:
			_visual.set_impact_progress(clampf(active_time / 0.24, 0.0, 1.0))
			if active_time >= 0.24:
				cancel()
		Mode.SPIKE:
			if active_time >= 0.24:
				_visual.visible = false
			if active_time >= spec.lifetime:
				cancel()
		Mode.MINE:
			if _impact_at >= 0.0:
				_visual.set_impact_progress(clampf((elapsed - _impact_at) / 0.12, 0.0, 1.0))
				if elapsed - _impact_at >= 0.12:
					cancel()
			elif _armed and _contains(target.global_position if is_instance_valid(target) else Vector3.INF, false):
				_armed = false
				_visual.show_impact()
				_mine_marker.visible = false
				_impact_once()
			elif active_time >= spec.lifetime:
				cancel()
		Mode.FIRE:
			if before - warning_duration < spec.duration:
				var exposure: float = minf(active_delta, spec.duration - maxf(0.0, before - warning_duration)) if _contains(target.global_position if is_instance_valid(target) else Vector3.INF, true) else 0.0
				_sample_continuous(exposure, spec.damage)
				_visual.set_impact_progress(0.2 + 0.12 * sin(elapsed * 18.0))
			if active_time >= spec.duration:
				_flush_continuous(spec.damage)
				cancel()
		Mode.BLADE:
			_advance_blade(before - warning_duration, active_time)
		Mode.SPIT:
			_advance_spit(active_delta, active_time)
		Mode.LUNGE:
			_advance_lunge()
	if is_instance_valid(target):
		_last_target = target.global_position
	_last_enemy = enemy.global_position

## Leap landing is owned by the real CharacterBody motion, not a parallel clock.
func trigger_impact() -> void:
	if cancelled or activated or not is_instance_valid(enemy) or enemy.is_dying:
		return
	activated = true
	elapsed = warning_duration
	_visual.show_impact()
	_impact_once()

func is_committed_independent() -> bool:
	# A launched projectile is already an attack; stun only stops future releases.
	return mode == Mode.LOB or (activated and mode in [Mode.BLADE, Mode.SPIT, Mode.SPIKE, Mode.MINE])

func _contains(point: Vector3, terrain_dependent: bool) -> bool:
	if not footprint.contains_point(_origin, direction, point):
		return false
	if not terrain_dependent and absf(point.y - _origin.y) > 2.0:
		return false
	return not terrain_dependent or TerrainCombatRules.is_melee_connected(_origin, point, height_lookup)

func _impact_once() -> void:
	if _impact_at >= 0.0:
		return
	_impact_at = elapsed
	var terrain_dependent: bool = mode == Mode.IMPACT and spec.kind == EliteSkillSpec.Kind.BACKSWING
	if is_instance_valid(target) and _contains(target.global_position, terrain_dependent):
		_deal_damage(spec.damage)
	if is_instance_valid(_projectile):
		_projectile.visible = false

func _deal_damage(amount: float) -> void:
	if cancelled or amount <= 0.0 or not is_instance_valid(target) or target.is_queued_for_deletion() or not is_instance_valid(enemy) or enemy.is_dying or enemy.is_queued_for_deletion():
		return
	if target is PlayerPrototype:
		var player: PlayerPrototype = target as PlayerPrototype
		var before: float = player.current_health + player.health.shield_health
		player.take_damage(amount, enemy)
		if player.current_health + player.health.shield_health >= before:
			return
	elif is_instance_valid(_hurtbox):
		if not _hurtbox.take_damage(amount, Vector3.ZERO, "elite", enemy, CombatRules.Team.ENEMY):
			return
	else:
		return
	hit_count += 1
	hit_confirmed.emit(target, amount)

func _sample_continuous(exposure: float, damage_per_second: float) -> void:
	for dose: float in _cadence.sample(exposure if exposure > 0.0000001 else 0.0):
		if cancelled:
			return
		_deal_damage(damage_per_second * dose)

func _flush_continuous(damage_per_second: float) -> void:
	var residual: float = _cadence.end_contact()
	if residual > 0.0000001:
		_deal_damage(damage_per_second * residual)

func _create_spike() -> void:
	_solid = StaticBody3D.new()
	_solid.collision_layer = 1
	_solid.collision_mask = 0
	add_child(_solid)
	_solid.global_position = _origin
	var collision: CollisionShape3D = CollisionShape3D.new()
	var cylinder: CylinderShape3D = CylinderShape3D.new()
	cylinder.radius = spec.radius * 0.4
	cylinder.height = 2.0
	collision.shape = cylinder
	collision.position.y = 1.0
	_solid.add_child(collision)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var cone: CylinderMesh = CylinderMesh.new()
	cone.top_radius = 0.03
	cone.bottom_radius = cylinder.radius
	cone.height = cylinder.height
	mesh.mesh = cone
	mesh.position.y = 1.0
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = spec.color.darkened(0.25)
	mesh.material_override = material
	_solid.add_child(mesh)
	if is_instance_valid(_registry):
		var cells: Array[Vector2i] = []
		for x: int in range(int(floorf(_origin.x - cylinder.radius)), int(floorf(_origin.x + cylinder.radius)) + 1):
			for z: int in range(int(floorf(_origin.z - cylinder.radius)), int(floorf(_origin.z + cylinder.radius)) + 1):
				cells.append(Vector2i(x, z))
		_registry.register_temporary_obstacle(_solid, cells)

func _release_obstacle() -> void:
	if is_instance_valid(_solid) and is_instance_valid(_registry):
		_registry.unregister_temporary_obstacle(_solid)
	if is_instance_valid(_solid):
		_solid.collision_layer = 0

func _create_mine_visual() -> void:
	var marker: MeshInstance3D = MeshInstance3D.new()
	_mine_marker = marker
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = spec.radius * 0.35
	mesh.bottom_radius = mesh.top_radius
	mesh.height = 0.20
	marker.mesh = mesh
	marker.position.y = 0.14
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = spec.color
	material.emission_enabled = true
	material.emission = spec.color
	marker.material_override = material
	add_child(marker)

func _advance_blade(before: float, active_time: float) -> void:
	var travel: float = spec.reach / spec.speed
	var returning_at: float = travel + spec.interval
	var finished_at: float = returning_at + travel
	# Split a long tick at the turnaround so both actual passes are collision checked.
	for pass_index: int in range(2):
		var start_time: float = 0.0 if pass_index == 0 else returning_at
		var end_time: float = travel if pass_index == 0 else finished_at
		var left: float = maxf(before, start_time)
		var right: float = minf(active_time, end_time)
		if right > left:
			var a: Vector3 = _blade_position(left)
			var b: Vector3 = _blade_position(right)
			if not _hit_passes.has(pass_index) and _swept_contact(a, b, spec.width * 0.5):
				_hit_passes.append(pass_index)
				_deal_damage(spec.damage)
	projectile_position = _blade_position(minf(active_time, finished_at))
	_projectile.global_position = projectile_position
	_projectile.rotation.y += 0.3
	if active_time >= finished_at:
		cancel()

func _blade_position(active_time: float) -> Vector3:
	var travel: float = spec.reach / spec.speed
	var distance: float = clampf(active_time * spec.speed, 0.0, spec.reach)
	if active_time > travel + spec.interval:
		distance = maxf(0.0, spec.reach - (active_time - travel - spec.interval) * spec.speed)
	return _launch + direction * distance

func _swept_contact(a: Vector3, b: Vector3, contact_radius: float) -> bool:
	if not is_instance_valid(target):
		return false
	var relative_a: Vector3 = a - _last_target
	var relative_b: Vector3 = b - target.global_position
	var step: Vector3 = relative_b - relative_a
	var fraction: float = clampf(-relative_a.dot(step) / maxf(step.length_squared(), 0.00001), 0.0, 1.0)
	var nearest: Vector3 = relative_a.lerp(relative_b, fraction)
	return Vector2(nearest.x, nearest.z).length() <= contact_radius and absf(nearest.y) <= 1.0

func _advance_spit(active_delta: float, active_time: float) -> void:
	if not _spit_landed:
		var previous: Vector3 = _launch + direction * minf(spec.reach, maxf(0.0, active_time - active_delta) * spec.speed)
		var next: Vector3 = _launch + direction * minf(spec.reach, active_time * spec.speed)
		var environment_hit: Dictionary = {}
		if is_inside_tree():
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(previous, next, 1)
			query.exclude = [enemy.get_rid()]
			environment_hit = get_world_3d().direct_space_state.intersect_ray(query)
		if not environment_hit.is_empty():
			next = environment_hit.position
		var contact: bool = _swept_contact(previous, next, spec.width * 0.5)
		projectile_position = next
		_projectile.global_position = next
		if contact:
			_deal_damage(spec.damage)
			var offset: Vector3 = next - previous
			var fraction: float = clampf((target.global_position - previous).dot(offset) / maxf(offset.length_squared(), 0.00001), 0.0, 1.0)
			next = previous.lerp(next, fraction)
		if contact or not environment_hit.is_empty() or active_time >= spec.reach / spec.speed:
			_spit_landed = true
			_spit_landed_at = elapsed
			_spit_land_position = next
			_spit_land_position.y = _ground_y(next)
			_projectile.visible = false
			_visual.queue_free()
			_visual = BossAttackVFX.new()
			add_child(_visual)
			_visual.global_position = _spit_land_position
			_visual.setup(spec.footprint(BossAttackSpec.Shape.CIRCLE, spec.radius), direction, spec.color, height_lookup)
			_visual.show_impact()
		return
	var puddle_time: float = elapsed - _spit_landed_at
	var inside: bool = is_instance_valid(target) and Vector2(target.global_position.x - _spit_land_position.x, target.global_position.z - _spit_land_position.z).length() <= spec.radius and absf(target.global_position.y - _spit_land_position.y) <= 2.0
	var exposure: float = minf(active_delta, maxf(0.0, spec.lifetime - (puddle_time - active_delta))) if inside else 0.0
	_sample_continuous(exposure, spec.residue_damage_per_second)
	_visual.set_impact_progress(clampf(puddle_time / spec.lifetime, 0.0, 1.0) * 0.65)
	if puddle_time >= spec.lifetime:
		_flush_continuous(spec.residue_damage_per_second)
		cancel()

func _ground_y(point: Vector3) -> float:
	if height_lookup.is_valid():
		return float(height_lookup.call(int(floorf(point.x)), int(floorf(point.z))))
	return _origin.y

func _advance_lunge() -> void:
	if not _hit_passes.is_empty() or not is_instance_valid(target):
		return
	# Damage follows the moving body, never the harmless length of its warning lane.
	if _swept_contact(_last_enemy, enemy.global_position, enemy.radius + 0.5) and TerrainCombatRules.is_melee_connected(enemy.global_position, target.global_position, height_lookup):
		_hit_passes.append(0)
		_deal_damage(spec.damage)

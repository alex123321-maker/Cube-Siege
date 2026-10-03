extends Node3D
class_name BossProjectile

var boss: SiegeBoss
var target: Node3D
var direction: Vector3
var speed: float = 12.0
var damage: float = 25.0
var lifetime: float = 3.0
var height_lookup: Callable
var _hurtbox: HurtboxArea
var _over_drop: bool = false
var _hit: bool = false
var _distance_left: float = 30.0
var _hit_ledger: Dictionary = {}

func setup(p_boss: SiegeBoss, p_target: Node3D, p_direction: Vector3, p_speed: float, p_damage: float, color: Color, p_height: Callable, travel_distance: float = 30.0, shared_hits: Dictionary = {}) -> void:
	boss = p_boss
	target = p_target
	direction = p_direction.normalized()
	speed = p_speed
	damage = p_damage
	height_lookup = p_height
	_distance_left = travel_distance
	_hit_ledger = shared_hits
	lifetime = travel_distance / maxf(speed, 0.01) + 0.05
	top_level = true
	_hurtbox = target.get_node_or_null("Hurtbox") as HurtboxArea if is_instance_valid(target) else null
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var prism: PrismMesh = PrismMesh.new()
	prism.size = Vector3(0.45, 0.45, 1.2)
	mesh.mesh = prism
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 1.4
	mesh.material_override = material
	add_child(mesh)
	look_at(global_position + direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	if _hit or not is_instance_valid(boss) or boss.is_dying:
		queue_free()
		return
	var start: Vector3 = global_position
	var distance: float = minf(speed * delta, _distance_left)
	var finish: Vector3 = start + direction * distance
	if height_lookup.is_valid():
		var from_height: float = float(height_lookup.call(TerrainCombatRules.world_to_voxel(start.x), TerrainCombatRules.world_to_voxel(start.z)))
		var to_height: float = float(height_lookup.call(TerrainCombatRules.world_to_voxel(finish.x), TerrainCombatRules.world_to_voxel(finish.z)))
		var step: Dictionary = TerrainCombatRules.update_projectile_height(start, finish, from_height, to_height, 0.8, _over_drop)
		if bool(step.get("collided", false)):
			queue_free()
			return
		_over_drop = bool(step.get("is_over_drop", false))
		finish.y = float(step.get("new_y", finish.y))
	if is_instance_valid(target) and not _hit_ledger.has(target.get_instance_id()) and (target is PlayerPrototype or is_instance_valid(_hurtbox)):
		var player_point: Vector3 = target.global_position
		var segment: Vector3 = finish - start
		var fraction: float = clampf((player_point - start).dot(segment) / maxf(segment.length_squared(), 0.001), 0.0, 1.0)
		if player_point.distance_to(start + segment * fraction) < 0.75:
			if target is PlayerPrototype:
				(target as PlayerPrototype).take_damage(damage, boss)
				_hit = true
			else:
				_hit = _hurtbox.take_damage(damage, Vector3.ZERO, "projectile", boss, CombatRules.Team.ENEMY)
			if _hit:
				_hit_ledger[target.get_instance_id()] = true
				queue_free()
				return
	global_position = finish
	_distance_left -= distance
	lifetime -= delta
	if lifetime <= 0.0 or _distance_left <= 0.0:
		queue_free()

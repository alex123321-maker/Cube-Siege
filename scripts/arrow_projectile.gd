extends Node3D

@export var speed: float = 24.0
@export var damage: float = 30.0
@export var pierce_count: int = 1

var direction: Vector3 = Vector3.FORWARD
var lifetime: float = 2.5
var shooter_entity: Node = null
var source_team: CombatRules.Team = CombatRules.Team.NONE
var hit_targets: Array[Node] = []
var is_flying_over_drop: bool = false
var _uses_archer_impact: bool = false

@onready var hitbox: HitboxArea = $Hitbox as HitboxArea

func _ready() -> void:
	if has_node("Hitbox"):
		hitbox = $Hitbox as HitboxArea
		if not hitbox.hit_confirmed.is_connected(_on_hit_confirmed):
			hitbox.hit_confirmed.connect(_on_hit_confirmed)
		if source_team != CombatRules.Team.NONE:
			hitbox.source_team = source_team

func setup(p_direction: Vector3, p_damage: float, p_owner: Node, p_pierce: int = 1) -> void:
	direction = p_direction.normalized()
	damage = p_damage
	shooter_entity = p_owner
	var audio_bus: Node = get_node_or_null("/root/EventBus")
	if audio_bus and is_instance_valid(p_owner):
		if p_owner is PlayerPrototype:
			audio_bus.audio_cue_requested.emit(&"piercing" if p_pierce > 1 else &"bow", global_position)
		elif p_owner is EnemyBase:
			audio_bus.audio_cue_requested.emit(&"bow", global_position)
	source_team = CombatRules.get_team(p_owner) if is_instance_valid(p_owner) else CombatRules.Team.PLAYER
	pierce_count = p_pierce
	_uses_archer_impact = p_pierce == 1 and is_instance_valid(p_owner) and p_owner.is_in_group("player")
	if direction.length_squared() > 0.01:
		look_at(global_position + direction, Vector3.UP)
	if has_node("Hitbox"):
		hitbox = $Hitbox as HitboxArea
		hitbox.damage = damage
		hitbox.damage_type = "projectile"
		hitbox.knockback_force = 4.0
		hitbox.can_hit_multiple = pierce_count > 1
		hitbox.terrain_mode = TerrainCombatRules.TerrainMode.TERRAIN_INDEPENDENT
		hitbox.set_owner_entity(p_owner, source_team)
		if not hitbox.hit_confirmed.is_connected(_on_hit_confirmed):
			hitbox.hit_confirmed.connect(_on_hit_confirmed)

	# Attach flight trail VFX
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx:
		if pierce_count > 1:
			vfx.attach_piercing_trail(self)
		else:
			vfx.attach_arrow_trail(self)

func _physics_process(delta: float) -> void:
	var current_pos: Vector3 = global_position
	var next_pos: Vector3 = current_pos + direction * speed * delta

	var cur_x: int = TerrainCombatRules.world_to_voxel(current_pos.x)
	var cur_z: int = TerrainCombatRules.world_to_voxel(current_pos.z)
	var next_x: int = TerrainCombatRules.world_to_voxel(next_pos.x)
	var next_z: int = TerrainCombatRules.world_to_voxel(next_pos.z)

	var h_curr: float = _get_terrain_height(cur_x, cur_z)
	var h_next: float = _get_terrain_height(next_x, next_z)

	var step_info: Dictionary = TerrainCombatRules.update_projectile_height(
		current_pos,
		next_pos,
		h_curr,
		h_next,
		0.8,
		is_flying_over_drop
	)

	is_flying_over_drop = step_info.get("is_over_drop", false)

	if step_info.get("collided", false):
		_on_terrain_collision(next_pos)
		return

	next_pos.y = step_info.get("new_y", next_pos.y)
	global_position = next_pos


	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _get_terrain_height(x: int, z: int) -> float:
	if not is_inside_tree():
		return 0.0
	var map_gen: Node = get_tree().get_first_node_in_group("map_generator")
	if map_gen and map_gen.has_method("get_voxel_height"):
		return float(map_gen.get_voxel_height(x, z))
	return 0.0

func _on_terrain_collision(hit_pos: Vector3) -> void:
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx:
		if _uses_archer_impact:
			# The proposed next position is inside the blocked step. Keep the
			# visual on the last reachable side of the surface.
			vfx.spawn_arrow_impact(global_position, direction, true)
		else:
			vfx.spawn_sparks(hit_pos, -direction, Color(0.8, 0.8, 0.8), 6, 3.0)
	queue_free()


func _on_hit_confirmed(target: Node, _hit_dir: Vector3) -> void:
	hit_targets.append(target)

	# Hit feedback VFX
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx:
		if _uses_archer_impact:
			vfx.spawn_arrow_impact(global_position, direction)
		elif pierce_count > 1:
			vfx.spawn_pierce_ripple(global_position, direction)
		else:
			vfx.spawn_sparks(global_position, -direction, Color(1.0, 0.9, 0.4), 8, 4.0)

	pierce_count -= 1
	if pierce_count <= 0:
		call_deferred("queue_free")

func _on_hitbox_area_entered(area: Area3D) -> void:
	# Single authoritative path: delegate to HitboxArea.
	# If area_entered was already handled by HitboxArea via signal,
	# HitboxArea's target tracking will prevent duplicate execution.
	if hitbox and is_instance_valid(hitbox):
		hitbox._on_area_entered(area)

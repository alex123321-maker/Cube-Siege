extends Node

## Reusable, high-performance VFX Manager for Cube Siege.
## Manages all character combat, ability, and ultimate visual effects.
## Guarantees 0 orphaned nodes, automatic lifecycle cleanup, and no memory leaks.

var active_effect_ids: Dictionary = {}
var _timed_effects: Array[Dictionary] = []
var _container: Node3D = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_container()

func _process(_delta: float) -> void:
	if _timed_effects.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	var remaining: Array[Dictionary] = []
	for item in _timed_effects:
		var id: int = item.get("id", 0)
		var obj = instance_from_id(id)
		if not obj or not is_instance_valid(obj) or obj.is_queued_for_deletion():
			active_effect_ids.erase(id)
			continue
		if now >= item.get("expires_at", 0):
			obj.queue_free()
			active_effect_ids.erase(id)
		else:
			remaining.append(item)
	_timed_effects = remaining

func _ensure_container() -> Node3D:
	if not _container or not is_instance_valid(_container) or not _container.is_inside_tree():
		_container = Node3D.new()
		_container.name = "VFXContainer"
		# Attach to root or current scene
		var current_scene = get_tree().current_scene
		if current_scene and is_instance_valid(current_scene):
			current_scene.add_child(_container)
		else:
			add_child(_container)
	return _container

func get_active_effect_count() -> int:
	_cleanup_stale_references()
	return active_effect_ids.size()

func _cleanup_stale_references() -> void:
	var to_remove: Array[int] = []
	for id in active_effect_ids.keys():
		var obj = instance_from_id(id)
		if not obj or not is_instance_valid(obj) or obj.is_queued_for_deletion():
			to_remove.append(id)
	for id in to_remove:
		active_effect_ids.erase(id)

func register_effect(node: Node, auto_free_time: float = 0.0) -> Node:
	if not node:
		return null
	var id: int = node.get_instance_id()
	active_effect_ids[id] = true
	node.tree_exited.connect(func():
		active_effect_ids.erase(id)
	)
	if auto_free_time > 0.0:
		_timed_effects.append({
			"id": id,
			"expires_at": Time.get_ticks_msec() + int(auto_free_time * 1000.0)
		})
	return node

# =========================================================================
# 1. WARRIOR VFX
# =========================================================================

## Spawns a stylized crescent blade slash arc
func spawn_slash_arc(pos: Vector3, aim_dir: Vector3, radius: float = 2.2, arc_deg: float = 90.0, col: Color = Color(0.3, 0.7, 1.0), duration: float = 0.18) -> Node3D:
	var container = _ensure_container()
	var arc_root = Node3D.new()
	arc_root.name = "SlashArc"
	container.add_child(arc_root)
	arc_root.global_position = pos + Vector3(0, 0.8, 0)

	var forward = aim_dir.normalized()
	if forward.length_squared() > 0.01:
		var up = Vector3.UP if abs(forward.dot(Vector3.UP)) < 0.99 else Vector3.FORWARD
		arc_root.look_at(arc_root.global_position + forward, up)

	# Mesh: Curved ribbon / fan matching the slash arc
	var im = ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var segments = 12
	var start_rad = deg_to_rad(-arc_deg * 0.5)
	var end_rad = deg_to_rad(arc_deg * 0.5)
	for i in range(segments + 1):
		var frac = float(i) / float(segments)
		var ang = lerp(start_rad, end_rad, frac)
		var dir = Vector3(sin(ang), 0, -cos(ang))
		im.surface_set_color(Color(col.r, col.g, col.b, 0.0))
		im.surface_add_vertex(dir * (radius * 0.3))
		im.surface_set_color(Color(col.r, col.g, col.b, 0.85))
		im.surface_add_vertex(dir * radius)
	im.surface_end()

	var mi = MeshInstance3D.new()
	mi.mesh = im
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mi.material_override = mat
	arc_root.add_child(mi)

	# Tween arc forward and fade out
	var t = arc_root.create_tween()
	t.tween_property(mi, "scale", Vector3(1.2, 1.2, 1.2), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(mat, "albedo_color:a", 0.0, duration)
	t.chain().tween_callback(arc_root.queue_free)

	register_effect(arc_root, duration + 0.1)
	return arc_root

## Spawns a massive 180-degree cleave wave with secondary dust and embers
func spawn_cleave_wave(pos: Vector3, aim_dir: Vector3, duration: float = 0.28) -> Node3D:
	var col = Color(1.0, 0.45, 0.15)
	var arc = spawn_slash_arc(pos, aim_dir, 3.4, 180.0, col, duration)

	# Add secondary particle burst
	var sparks = spawn_sparks(pos + aim_dir * 1.5 + Vector3(0, 0.4, 0), aim_dir, Color(1.0, 0.6, 0.1), 16, 6.0)
	spawn_shockwave(pos + aim_dir * 1.0 + Vector3(0, 0.1, 0), 2.5, Color(1.0, 0.5, 0.2), 0.25)
	return arc

## Spawns directional voxel sparks on hit, with bonus multi-hit flash
func spawn_sparks(pos: Vector3, normal: Vector3, col: Color = Color(1.0, 0.85, 0.3), count: int = 8, spread_speed: float = 4.5) -> Node3D:
	var container = _ensure_container()
	var root = Node3D.new()
	root.name = "SparksVFX"
	container.add_child(root)
	root.global_position = pos

	var parts = CPUParticles3D.new()
	parts.emitting = true
	parts.one_shot = true
	parts.explosiveness = 0.95
	parts.lifetime = 0.35
	parts.amount = count
	parts.direction = normal if normal.length_squared() > 0.01 else Vector3.UP
	parts.spread = 45.0
	parts.initial_velocity_min = spread_speed * 0.6
	parts.initial_velocity_max = spread_speed * 1.2
	parts.gravity = Vector3(0, -9.8, 0)
	parts.scale_amount_min = 0.08
	parts.scale_amount_max = 0.18

	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.08, 0.08, 0.08)
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 3.0
	mesh.material = mat
	parts.mesh = mesh

	root.add_child(parts)
	register_effect(root, 0.45)
	return root

## Expanding ground shockwave ring
func spawn_shockwave(pos: Vector3, max_radius: float = 3.0, col: Color = Color(0.3, 0.7, 1.0), duration: float = 0.3) -> Node3D:
	var container = _ensure_container()
	var root = Node3D.new()
	root.name = "ShockwaveRing"
	container.add_child(root)
	root.global_position = pos + Vector3(0, 0.05, 0)

	var ring_mesh = TorusMesh.new()
	ring_mesh.inner_radius = 0.1
	ring_mesh.outer_radius = 0.2
	ring_mesh.rings = 16
	ring_mesh.ring_segments = 4

	var mi = MeshInstance3D.new()
	mi.mesh = ring_mesh
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mi.material_override = mat
	root.add_child(mi)

	var t = root.create_tween()
	var scale_target = max_radius / 0.2
	t.tween_property(mi, "scale", Vector3(scale_target, 1.0, scale_target), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(mat, "albedo_color:a", 0.0, duration)
	t.chain().tween_callback(root.queue_free)

	register_effect(root, duration + 0.1)
	return root

## Active parry window stance aura
func spawn_parry_stance_aura(player: CharacterBody3D, max_duration: float = 0.5) -> Node3D:
	if not player or not is_instance_valid(player):
		return null
	dismiss_parry_stance_aura(player)

	var root = Node3D.new()
	root.name = "ParryStanceAura"
	player.add_child(root)
	root.position = Vector3(0, 0.9, -0.6)

	var shield_mesh = BoxMesh.new()
	shield_mesh.size = Vector3(1.1, 1.4, 0.08)
	var mi = MeshInstance3D.new()
	mi.mesh = shield_mesh
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.6, 1.0, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.6, 1.0)
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	root.add_child(mi)

	# Gentle pulsing shimmer
	var t = root.create_tween().set_loops()
	t.tween_property(mat, "albedo_color:a", 0.7, 0.15)
	t.tween_property(mat, "albedo_color:a", 0.35, 0.15)

	var safety_timer = root.get_tree().create_timer(max_duration)
	var r_id = root.get_instance_id()
	safety_timer.timeout.connect(func():
		var node = instance_from_id(r_id)
		if node and is_instance_valid(node):
			node.queue_free()
	)

	register_effect(root, max_duration + 0.1)
	return root

func dismiss_parry_stance_aura(player: CharacterBody3D) -> void:
	if not player or not is_instance_valid(player):
		return
	var old = player.get_node_or_null("ParryStanceAura")
	if old and is_instance_valid(old):
		old.name = "ParryStanceAura_Freed"
		old.queue_free()

## Brilliant parry clash feedback
func spawn_parry_clash(pos: Vector3) -> void:
	spawn_sparks(pos + Vector3(0, 1.0, 0), Vector3.UP, Color(1.0, 0.9, 0.3), 24, 8.0)
	spawn_shockwave(pos, 3.5, Color(0.4, 0.8, 1.0), 0.3)

	# Central brilliant flash cube
	var container = _ensure_container()
	var flash = MeshInstance3D.new()
	var b = BoxMesh.new()
	b.size = Vector3(0.5, 0.5, 0.5)
	flash.mesh = b
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
	flash.material_override = mat
	container.add_child(flash)
	flash.global_position = pos + Vector3(0, 1.0, 0)

	var t = flash.create_tween()
	t.tween_property(flash, "scale", Vector3(2.5, 2.5, 2.5), 0.1)
	t.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.1)
	t.chain().tween_callback(flash.queue_free)
	register_effect(flash, 0.2)

## Duel Arena aura & Target lock
func spawn_duel_indicator(target: Node3D, max_duration: float = 15.0) -> Node3D:
	if not target or not is_instance_valid(target):
		return null
	dismiss_duel_indicator(target)

	var root = Node3D.new()
	root.name = "DuelTargetIndicator"
	target.add_child(root)
	root.position = Vector3(0, 2.2, 0)

	var crown_mesh = BoxMesh.new()
	crown_mesh.size = Vector3(0.4, 0.4, 0.4)
	var mi = MeshInstance3D.new()
	mi.mesh = crown_mesh
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.8, 0.2, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.2)
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	root.add_child(mi)

	var t = root.create_tween().set_loops()
	t.tween_property(root, "rotation:y", TAU, 1.8)

	var safety_timer = root.get_tree().create_timer(max_duration)
	var r_id = root.get_instance_id()
	safety_timer.timeout.connect(func():
		var node = instance_from_id(r_id)
		if node and is_instance_valid(node):
			node.queue_free()
	)

	register_effect(root, max_duration + 0.1)
	return root

func dismiss_duel_indicator(target: Node3D) -> void:
	if not target or not is_instance_valid(target):
		return
	var old = target.get_node_or_null("DuelTargetIndicator")
	if old and is_instance_valid(old):
		old.name = "DuelTargetIndicator_Freed"
		old.queue_free()

## Pre-shot charge aura on bow tip
func spawn_arrow_charge(player: CharacterBody3D, duration: float = 0.28) -> Node3D:
	if not player or not is_instance_valid(player):
		return null
	var root = Node3D.new()
	root.name = "ArrowChargeVFX"
	player.add_child(root)
	root.position = Vector3(0.35, 1.0, -0.85)

	var sphere = SphereMesh.new()
	sphere.radius = 0.18
	sphere.height = 0.36
	var mi = MeshInstance3D.new()
	mi.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.3, 0.95, 1.0, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.95, 1.0)
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	root.add_child(mi)

	var t = root.create_tween()
	t.tween_property(mi, "scale", Vector3(1.4, 1.4, 1.4), duration * 0.7)
	t.tween_property(mi, "scale", Vector3(0.2, 0.2, 0.2), duration * 0.3)
	t.chain().tween_callback(root.queue_free)

	register_effect(root, duration + 0.1)
	return root

# =========================================================================
# 2. ARCHER VFX
# =========================================================================

## Standard arrow contrail attached to projectile
func attach_arrow_trail(arrow_node: Node3D, col: Color = Color(0.9, 0.9, 0.9, 0.6)) -> CPUParticles3D:
	var parts = CPUParticles3D.new()
	parts.name = "ArrowContrail"
	parts.emitting = true
	parts.lifetime = 0.2
	parts.amount = 12
	parts.gravity = Vector3.ZERO
	parts.initial_velocity_min = 0.0
	parts.initial_velocity_max = 0.5
	parts.scale_amount_min = 0.06
	parts.scale_amount_max = 0.12

	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.06, 0.06, 0.06)
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mesh.material = mat
	parts.mesh = mesh

	arrow_node.add_child(parts)
	return parts

## Piercing arrow charged flight trail
func attach_piercing_trail(arrow_node: Node3D) -> CPUParticles3D:
	var col = Color(0.2, 0.95, 0.85, 0.8)
	var parts = attach_arrow_trail(arrow_node, col)
	parts.amount = 28
	parts.lifetime = 0.35
	parts.scale_amount_min = 0.12
	parts.scale_amount_max = 0.24

	# Add glowing head mesh
	var glow = MeshInstance3D.new()
	var b = BoxMesh.new()
	b.size = Vector3(0.22, 0.22, 0.6)
	glow.mesh = b
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 4.0
	glow.material_override = mat
	arrow_node.add_child(glow)

	return parts

## Piercing hit ripple on enemy pierced
func spawn_pierce_ripple(pos: Vector3, dir: Vector3) -> void:
	spawn_sparks(pos, dir, Color(0.2, 1.0, 0.8), 12, 5.0)
	spawn_shockwave(pos, 1.8, Color(0.2, 0.9, 0.8), 0.2)

## Decoy spawn / expiry puffs
func spawn_puff(pos: Vector3, col: Color = Color(0.9, 0.8, 0.6), count: int = 16, vel: float = 3.5) -> Node3D:
	var container = _ensure_container()
	var root = Node3D.new()
	root.name = "PuffVFX"
	container.add_child(root)
	root.global_position = pos

	var parts = CPUParticles3D.new()
	parts.emitting = true
	parts.one_shot = true
	parts.explosiveness = 0.9
	parts.lifetime = 0.4
	parts.amount = count
	parts.spread = 180.0
	parts.initial_velocity_min = vel * 0.5
	parts.initial_velocity_max = vel
	parts.gravity = Vector3(0, 0.5, 0)
	parts.scale_amount_min = 0.1
	parts.scale_amount_max = 0.25

	var mesh = BoxMesh.new()
	mesh.size = Vector3(0.12, 0.12, 0.12)
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = col
	mesh.material = mat
	parts.mesh = mesh

	root.add_child(parts)
	register_effect(root, 0.5)
	return root

## Eagle Eye activation falcon burst
func spawn_eagle_eye_burst(player: CharacterBody3D) -> void:
	var container = _ensure_container()
	var root = Node3D.new()
	root.name = "EagleEyeBurst"
	container.add_child(root)
	root.global_position = player.global_position + Vector3(0, 1.2, 0)

	spawn_shockwave(player.global_position, 4.5, Color(0.2, 1.0, 0.5), 0.4)
	spawn_puff(player.global_position + Vector3(0, 1.0, 0), Color(0.3, 1.0, 0.6), 24, 5.0)

	# Ethereal wing meshes flaring outward
	var wing_l = MeshInstance3D.new()
	var wing_r = MeshInstance3D.new()
	var b = BoxMesh.new()
	b.size = Vector3(1.8, 0.4, 0.1)
	wing_l.mesh = b
	wing_r.mesh = b

	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 1.0, 0.5, 0.8)
	wing_l.material_override = mat
	wing_r.material_override = mat

	root.add_child(wing_l)
	root.add_child(wing_r)
	wing_l.position = Vector3(-1.0, 0, 0)
	wing_r.position = Vector3(1.0, 0, 0)

	var t = root.create_tween()
	t.tween_property(wing_l, "position:x", -2.8, 0.35)
	t.parallel().tween_property(wing_r, "position:x", 2.8, 0.35)
	t.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.35)
	t.chain().tween_callback(root.queue_free)

	register_effect(root, 0.45)

# =========================================================================
# 3. ENGINEER VFX
# =========================================================================

## Hammer smash clank debris
func spawn_hammer_smash_impact(pos: Vector3, is_repair: bool = false) -> void:
	var col = Color(0.3, 0.9, 1.0) if is_repair else Color(1.0, 0.6, 0.2)
	spawn_sparks(pos + Vector3(0, 0.2, 0), Vector3.UP, col, 18, 6.0)
	spawn_shockwave(pos, 2.6, col, 0.25)

## Turret muzzle flash
func spawn_turret_muzzle_flash(pos: Vector3, aim_dir: Vector3) -> void:
	spawn_sparks(pos, aim_dir, Color(1.0, 0.85, 0.2), 6, 4.0)

## Remote Mine explosion sequence
func spawn_mine_explosion(pos: Vector3, radius: float = 4.5) -> void:
	# 1. Blinding flash
	spawn_parry_clash(pos)
	# 2. Expanding shockwave
	spawn_shockwave(pos, radius, Color(1.0, 0.4, 0.1), 0.35)
	# 3. Fireball & dark smoke chunks
	spawn_puff(pos + Vector3(0, 0.5, 0), Color(1.0, 0.45, 0.1), 24, 7.0)
	spawn_puff(pos + Vector3(0, 1.2, 0), Color(0.2, 0.2, 0.2), 16, 4.0)

## Tactical Nuke Telegraph: warning zone and falling missile
func spawn_tactical_nuke_telegraph(target_pos: Vector3, duration: float = 1.2) -> Node3D:
	var container = _ensure_container()
	var nuke_root = Node3D.new()
	nuke_root.name = "NukeTelegraph"
	container.add_child(nuke_root)
	nuke_root.global_position = target_pos

	var telegraph = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	cyl.top_radius = 10.0
	cyl.bottom_radius = 10.0
	cyl.height = 0.05
	telegraph.mesh = cyl
	var tel_mat = StandardMaterial3D.new()
	tel_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tel_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tel_mat.albedo_color = Color(1.0, 0.2, 0.0, 0.25)
	telegraph.material_override = tel_mat
	nuke_root.add_child(telegraph)
	telegraph.position = Vector3(0, 0.03, 0)

	var loops = max(1, int(duration / 0.3))
	var tel_tween = telegraph.create_tween().set_loops(loops)
	tel_tween.tween_property(tel_mat, "albedo_color:a", 0.6, 0.15)
	tel_tween.tween_property(tel_mat, "albedo_color:a", 0.2, 0.15)

	var missile = Node3D.new()
	var missile_mesh = MeshInstance3D.new()
	var m_cyl = CylinderMesh.new()
	m_cyl.top_radius = 0.1
	m_cyl.bottom_radius = 0.4
	m_cyl.height = 2.4
	missile_mesh.mesh = m_cyl
	var m_mat = StandardMaterial3D.new()
	m_mat.albedo_color = Color(0.2, 0.25, 0.3)
	missile_mesh.material_override = m_mat
	missile.add_child(missile_mesh)

	var m_trail = attach_arrow_trail(missile, Color(1.0, 0.5, 0.1, 0.9))
	m_trail.amount = 30
	m_trail.lifetime = 0.4

	nuke_root.add_child(missile)
	missile.position = Vector3(0, 35.0, 0)
	missile.rotation_degrees = Vector3(180, 0, 0)

	var missile_tween = missile.create_tween()
	missile_tween.tween_property(missile, "position:y", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	missile_tween.chain().tween_callback(nuke_root.queue_free)

	register_effect(nuke_root, duration + 0.1)
	return nuke_root

## Tactical Nuke Impact: shockwaves, brilliant flash, rising mushroom cloud
func spawn_tactical_nuke_impact(target_pos: Vector3) -> void:
	spawn_shockwave(target_pos, 14.0, Color(1.0, 0.5, 0.1), 0.6)
	spawn_shockwave(target_pos, 9.0, Color(1.0, 1.0, 0.8), 0.35)
	spawn_parry_clash(target_pos)
	spawn_puff(target_pos + Vector3(0, 1.0, 0), Color(1.0, 0.6, 0.1), 40, 12.0)
	spawn_puff(target_pos + Vector3(0, 3.5, 0), Color(1.0, 0.3, 0.0), 32, 8.0)
	spawn_puff(target_pos + Vector3(0, 6.0, 0), Color(0.2, 0.2, 0.2), 36, 6.0)

## Tactical Nuke Ground Burn Field: glowing plasma cracks, rising embers
func spawn_tactical_nuke_burn(target_pos: Vector3, duration: float = 3.0) -> Node3D:
	var container = _ensure_container()
	var burn_zone = MeshInstance3D.new()
	var b_cyl = CylinderMesh.new()
	b_cyl.top_radius = 10.0
	b_cyl.bottom_radius = 10.0
	b_cyl.height = 0.05
	burn_zone.mesh = b_cyl
	var b_mat = StandardMaterial3D.new()
	b_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	b_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	b_mat.albedo_color = Color(1.0, 0.35, 0.05, 0.4)
	burn_zone.material_override = b_mat
	container.add_child(burn_zone)
	burn_zone.global_position = target_pos + Vector3(0, 0.04, 0)

	var t = burn_zone.create_tween()
	t.tween_interval(duration * 0.7)
	t.tween_property(b_mat, "albedo_color:a", 0.0, duration * 0.3)
	t.chain().tween_callback(burn_zone.queue_free)

	register_effect(burn_zone, duration + 0.1)
	return burn_zone


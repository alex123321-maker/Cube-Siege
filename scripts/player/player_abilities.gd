extends RefCounted
class_name PlayerAbilities

## Manages player class-specific utilities (Parry, Decoy, Mine, Turret), ultimates (Duel, Eagle Eye, Nuke), and card upgrades.

var ultimate_cooldown: float = 25.0
var ultimate_cooldown_timer: float = 0.0

var active_remote_mine: Node3D = null
var is_eagle_eye: bool = false
var is_dueling: bool = false
var duel_target: Node3D = null
var active_tether: Node3D = null
var active_duel_indicator: Node3D = null
var active_parry_aura: Node3D = null

class OwnedAbilityTimer extends Timer:
	var actor: CharacterBody3D
	var burn_ticks: int = 0
	func _on_actor_died() -> void:
		stop()
		queue_free()
	func _on_build_changed() -> void:
		if actor is PlayerPrototype and not actor.progression.run_build.active:
			stop()
			queue_free()

func _owned_timer(player: CharacterBody3D, duration: float, single: bool) -> OwnedAbilityTimer:
	var timer: OwnedAbilityTimer = OwnedAbilityTimer.new()
	timer.actor = player
	timer.wait_time = duration
	timer.one_shot = single
	timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
	player.add_child(timer)
	if player is PlayerPrototype:
		player.player_died.connect(timer._on_actor_died)
		player.progression.run_build.build_changed.connect(timer._on_build_changed)
	return timer

const DECOY_COOLDOWN: float = 12.0
const MINE_RELOAD: float = 3.5
const NUKE_COOLDOWN: float = 60.0
const NUKE_DAMAGE: float = 300.0
const NUKE_RADIUS: float = 10.0
const NUKE_WINDUP: float = 1.2
const NUKE_BURN_DAMAGE: float = 25.0
const NUKE_BURN_INTERVAL: float = 0.5
const NUKE_BURN_TICKS: int = 10

const DUEL_TETHER_SCENE = preload("res://scenes/duel_tether.tscn")
const TEMP_TURRET_SCENE = preload("res://scenes/prefabs/temp_turret.tscn")
const REMOTE_MINE_SCENE = preload("res://scenes/prefabs/remote_mine.tscn")
const DECOY_DUMMY_SCENE = preload("res://scenes/prefabs/decoy_dummy.tscn")

func update_timers(delta: float, player: CharacterBody3D) -> void:
	if ultimate_cooldown_timer > 0.0:
		ultimate_cooldown_timer -= delta

	if is_dueling and (not duel_target or not is_instance_valid(duel_target)):
		end_duel(player)

func perform_utility(player: CharacterBody3D, current_class: int) -> void:
	match current_class:
		0: # CharacterClass.WARRIOR
			perform_parry(player)
		1: # CharacterClass.ARCHER
			deploy_decoy(player)
		2: # CharacterClass.ENGINEER
			toggle_remote_mine(player)

func perform_parry(player: CharacterBody3D) -> void:
	var duration: float = player.talents.parry_duration() if player is PlayerPrototype else PlayerHealth.PARRY_WINDOW
	var cooldown: float = PlayerHealth.PARRY_COOLDOWN * (player.talents.multiplier("parry_cooldown") if player is PlayerPrototype else 1.0)
	if player.health.trigger_parry(duration, cooldown):
		if player.orientation:
			player.orientation.cancel_pending_action()
		var vfx = player.get_node_or_null("/root/VFXManager")
		if vfx:
			active_parry_aura = vfx.spawn_parry_stance_aura(player, duration)

		if player.presentation:
			player.presentation.play_utility_animation()
		else:
			var anim_player: AnimationPlayer = player.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if anim_player:
				anim_player.stop()
				anim_player.play("block")

func perform_ultimate(player: CharacterBody3D, current_class: int, locked_target: Node3D = null, target_was_locked: bool = false) -> void:
	if ultimate_cooldown_timer > 0.0:
		return

	match current_class:
		0: # CharacterClass.WARRIOR
			perform_warrior_ultimate(player, locked_target, target_was_locked or (locked_target != null))
		1: # CharacterClass.ARCHER
			perform_archer_ultimate(player)
		2: # CharacterClass.ENGINEER
			perform_engineer_ultimate(player)

func perform_warrior_ultimate(player: CharacterBody3D, locked_target: Node3D = null, target_was_locked: bool = false) -> void:
	# A long boss fight can outlast the cooldown. One Duel owns one target
	# and one tether until completion; recasting must not orphan the old pair.
	if is_dueling:
		return
	var is_locked: bool = target_was_locked or (locked_target != null)
	var target: Node3D = locked_target
	if is_locked:
		# If a locked target was specified, it must remain valid and alive; automatic retarget is strictly forbidden
		if not _is_actor_alive(locked_target):
			player.spawn_popup_text("ЦЕЛЬ ПОТЕРЯНА!", Color.ORANGE)
			return
		target = locked_target
	else:
		target = find_target_near_mouse(player)
		if not target:
			player.spawn_popup_text("НЕТ ЦЕЛИ ДЛЯ ДУЭЛИ!", Color.ORANGE)
			return

	if not _is_actor_alive(target):
		player.spawn_popup_text("НЕТ ЦЕЛИ ДЛЯ ДУЭЛИ!", Color.ORANGE)
		return

	if player.orientation:
		player.orientation.cancel_pending_action()

	is_dueling = true
	duel_target = target
	ultimate_cooldown_timer = ultimate_cooldown
	active_tether = DUEL_TETHER_SCENE.instantiate()
	player.get_parent().add_child(active_tether)
	active_tether.setup(player, duel_target)
	if duel_target.has_method("start_duel"):
		duel_target.start_duel(player)

	var vfx = player.get_node_or_null("/root/VFXManager")
	if vfx:
		active_duel_indicator = vfx.spawn_duel_indicator(duel_target)
		vfx.spawn_shockwave(player.global_position, 4.0, Color.GOLD, 0.4)

	if player.presentation:
		player.presentation.play_ultimate_animation()

	player.spawn_popup_text("DUEL OF HONOR!", Color.GOLD)

func perform_archer_ultimate(player: CharacterBody3D) -> void:
	if is_eagle_eye:
		return
	if player.orientation:
		player.orientation.cancel_pending_action()
	ultimate_cooldown_timer = 25.0
	is_eagle_eye = true

	var vfx = player.get_node_or_null("/root/VFXManager")
	if vfx:
		vfx.spawn_eagle_eye_burst(player)

	if player.presentation:
		player.presentation.play_ultimate_animation()

	player.spawn_popup_text("EAGLE EYE ACTIVATED! (+50% RANGE)", Color.LIGHT_GREEN)
	var vp = player.get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp else null
	if cam:
		var t = player.create_tween()
		t.tween_property(cam, "size", 34.0, 0.5)

func perform_engineer_ultimate(player: CharacterBody3D, target_override: Vector3 = Vector3.INF) -> void:
	if player.orientation:
		player.orientation.cancel_pending_action()
	ultimate_cooldown_timer = NUKE_COOLDOWN
	var target_pos: Vector3 = target_override if target_override.is_finite() else get_nuke_target_position(player)

	if player.presentation:
		player.presentation.play_ultimate_animation()

	player.spawn_popup_text("TACTICAL NUKE INCOMING!", Color.ORANGE_RED)
	_execute_tactical_nuke(player, target_pos)

func get_nuke_target_position(player: CharacterBody3D) -> Vector3:
	var vp: Viewport = player.get_viewport()
	if not vp: return player.global_position
	var cam: Camera3D = vp.get_camera_3d()
	if not cam: return player.global_position
	var mouse_pos: Vector2 = vp.get_mouse_position()
	var ray_origin: Vector3 = cam.project_ray_origin(mouse_pos)
	var ray_normal: Vector3 = cam.project_ray_normal(mouse_pos)

	if player.is_inside_tree():
		var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_normal * 1000.0, 1)
		var hit: Dictionary = space_state.intersect_ray(query)
		if not hit.is_empty():
			return hit.position

	var ground_plane: Plane = Plane(Vector3.UP, player.global_position.y)
	var intersect: Variant = ground_plane.intersects_ray(ray_origin, ray_normal)
	if intersect is Vector3:
		var inter_pos: Vector3 = intersect as Vector3
		if player.is_inside_tree():
			var map_gen: Node = player.get_tree().get_first_node_in_group("map_generator")
			if map_gen and map_gen.has_method("get_voxel_height"):
				inter_pos.y = float(map_gen.get_voxel_height(TerrainCombatRules.world_to_voxel(inter_pos.x), TerrainCombatRules.world_to_voxel(inter_pos.z)))
		return inter_pos
	return player.global_position

func _execute_tactical_nuke(player: CharacterBody3D, target_pos: Vector3) -> void:
	var nuke_damage: float = NUKE_DAMAGE
	var nuke_radius: float = NUKE_RADIUS

	var vfx = player.get_node_or_null("/root/VFXManager")
	if vfx:
		vfx.spawn_tactical_nuke_telegraph(target_pos, NUKE_WINDUP)

	if not player.is_inside_tree():
		_apply_nuke_impact_damage(player, target_pos, nuke_damage, nuke_radius)
		return

	var windup: OwnedAbilityTimer = _owned_timer(player, NUKE_WINDUP, true)
	windup.name = "NukeWindup"
	windup.timeout.connect(_release_tactical_nuke.bind(player, target_pos))
	windup.timeout.connect(windup.queue_free, CONNECT_ONE_SHOT)
	windup.start()

func _release_tactical_nuke(player: CharacterBody3D, target_pos: Vector3) -> void:
	if not _is_actor_alive(player) or (player is PlayerPrototype and not player.progression.run_build.active):
		return
	_apply_nuke_impact_damage(player, target_pos, NUKE_DAMAGE, NUKE_RADIUS)
	if not _is_actor_alive(player):
		return
	var vfx: Node = player.get_node_or_null("/root/VFXManager")
	if vfx:
		vfx.spawn_tactical_nuke_impact(target_pos)
		vfx.spawn_tactical_nuke_burn(target_pos, 5.0)
	var burn: OwnedAbilityTimer = _owned_timer(player, NUKE_BURN_INTERVAL, false)
	burn.name = "NukeBurn"
	burn.burn_ticks = NUKE_BURN_TICKS
	burn.timeout.connect(_advance_nuke_burn.bind(player, target_pos, burn))
	burn.start()

func _advance_nuke_burn(player: CharacterBody3D, target_pos: Vector3, timer: OwnedAbilityTimer) -> void:
	if not _is_actor_alive(player) or (player is PlayerPrototype and not player.progression.run_build.active):
		timer.queue_free()
		return
	_apply_nuke_burn_damage(player, target_pos, NUKE_BURN_DAMAGE, NUKE_RADIUS)
	timer.burn_ticks -= 1
	if timer.burn_ticks <= 0:
		timer.stop()
		timer.queue_free()

func _apply_nuke_impact_damage(player: CharacterBody3D, target_pos: Vector3, damage: float, radius: float) -> void:
	if not _is_actor_alive(player):
		return
	var enemies: Array[Node] = player.get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if not _is_actor_alive(player):
			break
		if e and is_instance_valid(e) and e is Node3D:
			var can_hit: bool = TerrainCombatRules.can_ability_hit_target(
				target_pos,
				(e as Node3D).global_position,
				TerrainCombatRules.TerrainMode.TERRAIN_INDEPENDENT,
				radius
			)
			if can_hit:
				var kb_dir: Vector3 = ((e as Node3D).global_position - target_pos).normalized()
				if e.has_method("_on_damaged"):
					e._on_damaged(damage, kb_dir * 15.0, "nuke", player)
				if e.is_in_group("siege") and "damage_resist" in e:
					e.damage_resist = 0.0

func _apply_nuke_burn_damage(player: CharacterBody3D, target_pos: Vector3, damage: float, radius: float) -> void:
	if not _is_actor_alive(player):
		return
	var burn_enemies: Array[Node] = player.get_tree().get_nodes_in_group("enemies")
	for e in burn_enemies:
		if not _is_actor_alive(player):
			break
		if e and is_instance_valid(e) and e is Node3D:
			var can_hit: bool = TerrainCombatRules.can_ability_hit_target(
				target_pos,
				(e as Node3D).global_position,
				TerrainCombatRules.TerrainMode.TERRAIN_INDEPENDENT,
				radius
			)
			if can_hit:
				if e.has_method("_on_damaged"):
					e._on_damaged(damage, Vector3.ZERO, "burn", player)

func end_duel(player: CharacterBody3D) -> void:
	if not is_dueling:
		return
	var target_hp: Variant = duel_target.get("current_health") if is_instance_valid(duel_target) else null
	var won: bool = target_hp is float or target_hp is int
	won = won and float(target_hp) <= 0.0
	if won and player is PlayerPrototype and duel_target is Node3D:
		player.talents.on_duel_victory(duel_target.global_position)
	is_dueling = false
	if active_tether and is_instance_valid(active_tether):
		active_tether.queue_free()
		active_tether = null
	if active_duel_indicator and is_instance_valid(active_duel_indicator):
		active_duel_indicator.queue_free()
		active_duel_indicator = null
	var vfx = player.get_node_or_null("/root/VFXManager")
	if vfx and duel_target and is_instance_valid(duel_target):
		vfx.dismiss_duel_indicator(duel_target)
	if is_instance_valid(duel_target) and duel_target.has_method("end_duel"):
		duel_target.end_duel()
	duel_target = null
	player.spawn_popup_text("ДУЭЛЬ ВЫИГРАНА!" if won else "ДУЭЛЬ ЗАВЕРШЕНА", Color.GREEN)

func find_target_near_mouse(player: CharacterBody3D) -> Node3D:
	var vp: Viewport = player.get_viewport()
	if not vp: return null
	var cam: Camera3D = vp.get_camera_3d()
	if not cam: return null

	var mouse_pos: Vector2 = vp.get_mouse_position()
	if "mouse_override" in cam and cam.mouse_override.x >= 0.0:
		mouse_pos = cam.mouse_override

	var ray_origin: Vector3 = cam.project_ray_origin(mouse_pos)
	var ray_normal: Vector3 = cam.project_ray_normal(mouse_pos)

	# 1. First, attempt direct physics raycast (terrain & enemies)
	var direct_target: Node3D = null
	var terrain_hit_pos: Variant = null
	if player.is_inside_tree() and player.get_world_3d():
		var space_state: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
		if space_state:
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
				ray_origin,
				ray_origin + ray_normal * 1000.0,
				1 | 4 | 8 # terrain (1), enemy body (4), hurtbox (8)
			)
			query.collide_with_areas = true
			query.collide_with_bodies = true
			var hit: Dictionary = space_state.intersect_ray(query)
			if not hit.is_empty():
				var col: Object = hit.get("collider")
				if col and col is Node:
					var node: Node = col as Node
					var enemy_candidate: Node = node
					if not enemy_candidate.is_in_group("enemies") and enemy_candidate.get_parent() and enemy_candidate.get_parent().is_in_group("enemies"):
						enemy_candidate = enemy_candidate.get_parent()
					if enemy_candidate.is_in_group("enemies") and _is_actor_alive(enemy_candidate):
						direct_target = enemy_candidate as Node3D
				terrain_hit_pos = hit.get("position")

	if direct_target:
		return direct_target

	# 2. Query enemies list (via EntityRegistry if available, fallback to group)
	var enemies: Array = []
	var reg = player.get_node_or_null("/root/EntityRegistry")
	if reg and reg.has_method("get_enemies") and not reg.get_enemies().is_empty():
		enemies = reg.get_enemies()
	elif player.is_inside_tree():
		enemies = player.get_tree().get_nodes_in_group("enemies")

	var closest: Node3D = null
	var min_dist: float = 14.0

	for e in enemies:
		if e and is_instance_valid(e) and e is Node3D and _is_actor_alive(e):
			var enemy_pos: Vector3 = (e as Node3D).global_position
			var candidate_dist: float = INF

			# A. If we had a direct terrain hit under cursor, measure distance to terrain hit point
			if terrain_hit_pos is Vector3:
				candidate_dist = (terrain_hit_pos as Vector3).distance_to(enemy_pos)

			# B. Also project cursor ray onto the horizontal plane at this enemy's altitude!
			# This works on high mountains (Y=50+ or 100+) and in unit tests without physics world
			var enemy_plane: Plane = Plane(Vector3.UP, enemy_pos.y)
			var plane_hit: Variant = enemy_plane.intersects_ray(ray_origin, ray_normal)
			if plane_hit is Vector3:
				var plane_dist: float = (plane_hit as Vector3).distance_to(enemy_pos)
				if plane_dist < candidate_dist:
					candidate_dist = plane_dist

			if candidate_dist < min_dist:
				min_dist = candidate_dist
				closest = e as Node3D

	return closest

func _is_actor_alive(actor: Variant) -> bool:
	if not is_instance_valid(actor) or not (actor is Node) or not actor.is_inside_tree():
		return false
	if actor.is_queued_for_deletion():
		return false
	if actor is PlayerPrototype and not actor.progression.run_build.active:
		return false
	var hp = actor.get("current_health")
	if hp != null and float(hp) <= 0.0:
		return false
	var dead = actor.get("is_dead")
	if dead != null and bool(dead):
		return false
	return true

func deploy_temp_turret(player: CharacterBody3D) -> void:
	if not _is_actor_alive(player):
		return
	var turret = TEMP_TURRET_SCENE.instantiate()
	player.get_parent().add_child(turret)
	turret.global_position = player.global_position + (-player.global_transform.basis.z * 1.5)
	player.spawn_popup_text("TURRET DEPLOYED!", Color.GOLD)

func toggle_remote_mine(player: CharacterBody3D) -> void:
	if not _is_actor_alive(player):
		return
	if is_instance_valid(active_remote_mine):
		if player.orientation:
			player.orientation.cancel_pending_action()
		if player.presentation:
			player.presentation.play_utility_animation()
		active_remote_mine.detonate(player)
		active_remote_mine = null
		player.parry_cooldown_timer = MINE_RELOAD
	else:
		if player.parry_cooldown_timer > 0.0:
			player.spawn_popup_text("MINE RECHARGING...", Color.GRAY)
			return
		if player.orientation:
			player.orientation.cancel_pending_action()
		if player.presentation:
			player.presentation.play_utility_animation()
		active_remote_mine = REMOTE_MINE_SCENE.instantiate()
		player.get_parent().add_child(active_remote_mine)
		active_remote_mine.global_position = player.global_position
		player.spawn_popup_text("MINE PLANTED! [Q] DETONATE", Color.INDIAN_RED)

func deploy_decoy(player: CharacterBody3D) -> void:
	if not _is_actor_alive(player) or player.parry_cooldown_timer > 0.0:
		if _is_actor_alive(player):
			player.spawn_popup_text("DECOY RECHARGING...", Color.GRAY)
		return
	if player.orientation:
		player.orientation.cancel_pending_action()
	player.parry_cooldown_timer = DECOY_COOLDOWN
	if player.presentation:
		player.presentation.play_utility_animation()
	if not player.is_inside_tree():
		var decoy = DECOY_DUMMY_SCENE.instantiate()
		player.get_parent().add_child(decoy)
		decoy.global_position = player.global_position + (-player.global_transform.basis.z * 3.0)
		player.spawn_popup_text("DECOY DEPLOYED! (AGGRO 3.5s)", Color.LIGHT_GREEN)
		return
	# The windup belongs to the actor. Removing a preview or returning to the
	# menu must destroy it without leaving a global coroutine continuation.
	var windup: OwnedAbilityTimer = _owned_timer(player, 0.14, true)
	windup.name = "DecoyWindup"
	windup.timeout.connect(_release_decoy.bind(player))
	windup.timeout.connect(windup.queue_free, CONNECT_ONE_SHOT)
	windup.start()

func _release_decoy(player: CharacterBody3D) -> void:
	if not _is_actor_alive(player):
		return
	var decoy = DECOY_DUMMY_SCENE.instantiate()
	player.get_parent().add_child(decoy)
	decoy.global_position = player.global_position + (-player.global_transform.basis.z * 3.0)
	player.spawn_popup_text("DECOY DEPLOYED! (AGGRO 3.5s)", Color.LIGHT_GREEN)

func apply_card_upgrade(card_id: String, player: CharacterBody3D) -> void:
	match card_id:
		"SHARP_EDGE":
			player.attack_damage = roundf(player.attack_damage * 1.25)
			player.special_damage = roundf(player.special_damage * 1.25)
			player.spawn_popup_text("+25% ATK DAMAGE!", Color(1.0, 0.5, 0.1))
		"VITALITY_STONE":
			player.max_health += 50.0
			player.heal(40.0)
			player.spawn_popup_text("+50 MAX HP!", Color(0.2, 1.0, 0.4))
		"WINDSTRIDER":
			player.speed *= 1.2
			player.dash_cooldown *= 0.65
			player.spawn_popup_text("+20% SPEED!", Color(0.2, 0.9, 1.0))
		"HEAVY_MASONRY":
			var bs: BuildingSystem = player.building_system as BuildingSystem if player.building_system else null
			if bs:
				for b in bs.placed_buildings.values():
					if b and is_instance_valid(b) and b is BuildingBase:
						var bb: BuildingBase = b as BuildingBase
						bb.max_health += 150.0
						bb.repair(150.0)
			else:
				push_warning("PlayerAbilities: cannot apply HEAVY_MASONRY because player.building_system is not wired.")
			player.spawn_popup_text("+150 BLDG HP!", Color(0.9, 0.8, 0.3))
		"TOWER_BALLISTICS":
			var towers: Array[Node] = player.get_tree().get_nodes_in_group("towers")
			for t in towers:
				if t and is_instance_valid(t):
					t.attack_range += 3.0
					t.fire_rate *= 0.7
			player.spawn_popup_text("TOWERS ENHANCED!", Color(0.8, 0.3, 1.0))
		"GREED_HARVESTER":
			player.resource_multiplier = 2
			player.spawn_popup_text("2X RESOURCES!", Color.GOLD)
		"VAMPIRIC_STRIKE":
			player.vampirism_heal += 4.0
			player.spawn_popup_text("+4 VAMPIRISM!", Color(1.0, 0.2, 0.4))

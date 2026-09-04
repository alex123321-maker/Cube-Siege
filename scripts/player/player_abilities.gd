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
	if player.health.trigger_parry(0.5, 6.0):
		var vfx = player.get_node_or_null("/root/VFXManager")
		if vfx:
			active_parry_aura = vfx.spawn_parry_stance_aura(player, 0.5)

		if player.presentation:
			player.presentation.play_utility_animation()
		else:
			var anim_player: AnimationPlayer = player.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if anim_player:
				anim_player.stop()
				anim_player.play("block")

func perform_ultimate(player: CharacterBody3D, current_class: int) -> void:
	if ultimate_cooldown_timer > 0.0:
		return

	match current_class:
		0: # CharacterClass.WARRIOR
			perform_warrior_ultimate(player)
		1: # CharacterClass.ARCHER
			perform_archer_ultimate(player)
		2: # CharacterClass.ENGINEER
			perform_engineer_ultimate(player)

func perform_warrior_ultimate(player: CharacterBody3D) -> void:
	var target: Node3D = find_target_near_mouse(player)
	if not target:
		player.spawn_popup_text("НЕТ ЦЕЛИ ДЛЯ ДУЭЛИ!", Color.ORANGE)
		return

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

func perform_engineer_ultimate(player: CharacterBody3D) -> void:
	ultimate_cooldown_timer = 60.0
	var target_pos: Vector3 = get_nuke_target_position(player)

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
	var ground_plane: Plane = Plane(Vector3.UP, 0.0)
	var intersect: Variant = ground_plane.intersects_ray(ray_origin, ray_normal)
	if intersect is Vector3:
		return intersect as Vector3
	return player.global_position

func _execute_tactical_nuke(player: CharacterBody3D, target_pos: Vector3) -> void:
	var nuke_damage: float = 300.0
	var nuke_radius: float = 10.0
	var burn_damage: float = 25.0

	var vfx = player.get_node_or_null("/root/VFXManager")
	if vfx:
		vfx.spawn_tactical_nuke_telegraph(target_pos, 1.2)

	if not player.is_inside_tree():
		_apply_nuke_impact_damage(player, target_pos, nuke_damage, nuke_radius)
		return

	# Explicit gameplay timing: 1.2s to impact
	await player.get_tree().create_timer(1.2).timeout
	if not is_instance_valid(player) or not player.is_inside_tree():
		return

	_apply_nuke_impact_damage(player, target_pos, nuke_damage, nuke_radius)

	if vfx:
		vfx.spawn_tactical_nuke_impact(target_pos)
		vfx.spawn_tactical_nuke_burn(target_pos, 3.0)

	# Ground plasma burn loop (6 ticks, every 0.5s for 3.0s total)
	for i in range(6):
		await player.get_tree().create_timer(0.5).timeout
		if not is_instance_valid(player) or not player.is_inside_tree():
			return
		_apply_nuke_burn_damage(player, target_pos, burn_damage, nuke_radius)

func _apply_nuke_impact_damage(player: CharacterBody3D, target_pos: Vector3, damage: float, radius: float) -> void:
	var enemies: Array[Node] = player.get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e and is_instance_valid(e) and e is Node3D:
			var dist: float = target_pos.distance_to((e as Node3D).global_position)
			if dist <= radius:
				var kb_dir: Vector3 = ((e as Node3D).global_position - target_pos).normalized()
				if e.has_method("_on_damaged"):
					e._on_damaged(damage, kb_dir * 15.0, "nuke", player)
				if e.is_in_group("siege") and "damage_resist" in e:
					e.damage_resist = 0.0

func _apply_nuke_burn_damage(player: CharacterBody3D, target_pos: Vector3, damage: float, radius: float) -> void:
	var burn_enemies: Array[Node] = player.get_tree().get_nodes_in_group("enemies")
	for e in burn_enemies:
		if e and is_instance_valid(e) and e is Node3D:
			if target_pos.distance_to((e as Node3D).global_position) <= radius:
				if e.has_method("_on_damaged"):
					e._on_damaged(damage, Vector3.ZERO, "burn", player)

func end_duel(player: CharacterBody3D) -> void:
	if not is_dueling:
		return
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
	duel_target = null
	player.spawn_popup_text("DUEL VICTORIOUS!", Color.GREEN)

func find_target_near_mouse(player: CharacterBody3D) -> Node3D:
	var vp: Viewport = player.get_viewport()
	if not vp: return null
	var cam: Camera3D = vp.get_camera_3d()
	if not cam: return null

	var mouse_pos: Vector2 = vp.get_mouse_position()
	var ray_origin: Vector3 = cam.project_ray_origin(mouse_pos)
	var ray_normal: Vector3 = cam.project_ray_normal(mouse_pos)
	var ground_plane: Plane = Plane(Vector3.UP, 0.0)
	var intersect: Variant = ground_plane.intersects_ray(ray_origin, ray_normal)
	if not (intersect is Vector3):
		return null

	var target_pos: Vector3 = intersect as Vector3
	var enemies: Array[Node] = player.get_tree().get_nodes_in_group("enemies")
	var closest: Node3D = null
	var min_dist: float = 6.0
	for e in enemies:
		if e and is_instance_valid(e) and e is Node3D:
			var d = target_pos.distance_to((e as Node3D).global_position)
			if d < min_dist:
				min_dist = d
				closest = e as Node3D
	return closest

func deploy_temp_turret(player: CharacterBody3D) -> void:
	var turret = TEMP_TURRET_SCENE.instantiate()
	player.get_parent().add_child(turret)
	turret.global_position = player.global_position + (-player.global_transform.basis.z * 1.5)
	if player.presentation:
		player.presentation.play_special_animation()
	player.spawn_popup_text("TURRET DEPLOYED!", Color.GOLD)

func toggle_remote_mine(player: CharacterBody3D) -> void:
	if is_instance_valid(active_remote_mine):
		if player.presentation:
			player.presentation.play_utility_animation()
		active_remote_mine.detonate(player)
		active_remote_mine = null
		player.parry_cooldown_timer = 3.5
	else:
		if player.parry_cooldown_timer > 0.0:
			player.spawn_popup_text("MINE RECHARGING...", Color.GRAY)
			return
		if player.presentation:
			player.presentation.play_utility_animation()
		active_remote_mine = REMOTE_MINE_SCENE.instantiate()
		player.get_parent().add_child(active_remote_mine)
		active_remote_mine.global_position = player.global_position
		player.spawn_popup_text("MINE PLANTED! [Q] DETONATE", Color.INDIAN_RED)

func deploy_decoy(player: CharacterBody3D) -> void:
	if player.parry_cooldown_timer > 0.0:
		player.spawn_popup_text("DECOY RECHARGING...", Color.GRAY)
		return
	player.parry_cooldown_timer = 12.0
	if player.presentation:
		player.presentation.play_utility_animation()
	if not player.is_inside_tree():
		var decoy = DECOY_DUMMY_SCENE.instantiate()
		player.get_parent().add_child(decoy)
		decoy.global_position = player.global_position + (-player.global_transform.basis.z * 3.0)
		player.spawn_popup_text("DECOY DEPLOYED! (AGGRO 3.5s)", Color.LIGHT_GREEN)
		return
	await player.get_tree().create_timer(0.14).timeout
	if not is_instance_valid(player) or not player.is_inside_tree():
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

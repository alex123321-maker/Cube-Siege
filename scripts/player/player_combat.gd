extends RefCounted
class_name PlayerCombat

## Manages player attack dispatch, attack/special cooldowns, weapon swings, and projectile spawning.

var attack_damage: float = 25.0
var special_damage: float = 60.0
var attack_cooldown_timer: float = 0.0
var special_cooldown_timer: float = 0.0

const ARROW_PROJECTILE_SCENE = preload("res://scenes/prefabs/arrow_projectile.tscn")

func update_timers(delta: float) -> void:
	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta
	if special_cooldown_timer > 0.0:
		special_cooldown_timer -= delta

func perform_attack(player: CharacterBody3D, current_class: int, is_dashing: bool, is_dueling: bool) -> void:
	if attack_cooldown_timer > 0.0 or is_dashing:
		return

	match current_class:
		0: # CharacterClass.WARRIOR
			attack_cooldown_timer = 0.35
			if player.presentation:
				player.presentation.play_attack_animation()
			if not player.is_inside_tree():
				trigger_slash(player, attack_damage, 5.0, 90.0, is_dueling)
				return
			await player.get_tree().create_timer(0.06).timeout
			if is_instance_valid(player) and player.is_inside_tree():
				trigger_slash(player, attack_damage, 5.0, 90.0, is_dueling)
		1: # CharacterClass.ARCHER
			attack_cooldown_timer = 0.38
			if player.presentation:
				player.presentation.play_attack_animation()
			if not player.is_inside_tree():
				trigger_arrow_shot(player, attack_damage, 1, 28.0)
				return
			await player.get_tree().create_timer(0.08).timeout
			if is_instance_valid(player) and player.is_inside_tree():
				trigger_arrow_shot(player, attack_damage, 1, 28.0)
		2: # CharacterClass.ENGINEER
			attack_cooldown_timer = 0.48
			if player.presentation:
				player.presentation.play_attack_animation()
			if not player.is_inside_tree():
				trigger_hammer_smash(player, attack_damage * 1.35, is_dueling)
				return
			await player.get_tree().create_timer(0.12).timeout
			if is_instance_valid(player) and player.is_inside_tree():
				trigger_hammer_smash(player, attack_damage * 1.35, is_dueling)

func perform_special_attack(player: CharacterBody3D, current_class: int, is_dashing: bool, is_dueling: bool, abilities: PlayerAbilities) -> void:
	if special_cooldown_timer > 0.0 or is_dashing:
		return

	match current_class:
		0: # CharacterClass.WARRIOR
			special_cooldown_timer = 4.0
			if player.presentation:
				player.presentation.play_special_animation()
			if not player.is_inside_tree():
				trigger_slash(player, special_damage, 12.0, 180.0, is_dueling)
				return
			await player.get_tree().create_timer(0.15).timeout
			if is_instance_valid(player) and player.is_inside_tree():
				trigger_slash(player, special_damage, 12.0, 180.0, is_dueling)
		1: # CharacterClass.ARCHER
			special_cooldown_timer = 5.0
			if player.presentation:
				player.presentation.play_special_animation()
			var vfx = player.get_node_or_null("/root/VFXManager")
			if vfx:
				vfx.spawn_arrow_charge(player, 0.28)
			if not player.is_inside_tree():
				trigger_piercing_arrow(player, special_damage * 1.3, 6, 36.0)
				return
			await player.get_tree().create_timer(0.28).timeout
			if is_instance_valid(player) and player.is_inside_tree():
				trigger_piercing_arrow(player, special_damage * 1.3, 6, 36.0)
		2: # CharacterClass.ENGINEER
			special_cooldown_timer = 5.0
			if player.presentation:
				player.presentation.play_special_animation()
			if abilities:
				if not player.is_inside_tree():
					abilities.deploy_temp_turret(player)
					return
				await player.get_tree().create_timer(0.15).timeout
				if is_instance_valid(player) and player.is_inside_tree():
					abilities.deploy_temp_turret(player)
			else:
				push_warning("PlayerCombat: cannot deploy temp turret because abilities dependency is missing.")

func trigger_slash(player: CharacterBody3D, dmg: float, knockback: float, arc_degrees: float, is_dueling: bool) -> void:
	var slash_area: Area3D = player.get_node_or_null("SlashHitbox") as Area3D
	if not slash_area:
		return

	var final_dmg: float = dmg
	if is_dueling:
		final_dmg *= 1.2

	slash_area.damage = final_dmg
	slash_area.knockback_force = knockback
	slash_area.hit_entities.clear()
	slash_area.monitoring = true

	var aim_dir = -player.global_transform.basis.z
	var vfx = player.get_node_or_null("/root/VFXManager")
	if vfx:
		if arc_degrees > 120.0:
			vfx.spawn_cleave_wave(player.global_position, aim_dir, 0.25)
		else:
			vfx.spawn_slash_arc(player.global_position, aim_dir, 2.4, arc_degrees, Color(0.35, 0.7, 1.0), 0.18)

	await_slash_hit(player, slash_area)
	play_slash_animation(player, arc_degrees)
	finish_slash(player, slash_area)

func await_slash_hit(player: CharacterBody3D, slash_area: Area3D) -> void:
	if not player.is_inside_tree():
		return
	await player.get_tree().physics_frame
	if is_instance_valid(slash_area):
		for a in slash_area.get_overlapping_areas():
			if slash_area.has_method("_on_area_entered"):
				slash_area._on_area_entered(a)

		var hit_count = slash_area.hit_entities.size()
		if hit_count > 0:
			var vfx = player.get_node_or_null("/root/VFXManager")
			if vfx:
				var hit_pos = player.global_position - player.global_transform.basis.z * 1.5 + Vector3(0, 0.8, 0)
				vfx.spawn_sparks(hit_pos, -player.global_transform.basis.z, Color(1.0, 0.85, 0.3), 10, 4.5)
				if hit_count >= 2:
					vfx.spawn_shockwave(hit_pos, 2.2, Color(1.0, 0.9, 0.2), 0.2)

		if player.vampirism_heal > 0.0 and hit_count > 0:
			player.heal(player.vampirism_heal)
			player.spawn_popup_text("+%d HP" % int(player.vampirism_heal), Color.CRIMSON)

func play_slash_animation(player: CharacterBody3D, arc_degrees: float) -> void:
	if player.presentation and player.presentation.anim_player:
		var ap: AnimationPlayer = player.presentation.anim_player
		if ap.is_playing() and (ap.current_animation in ["attack", "special"]):
			return
		if arc_degrees > 120.0:
			player.presentation.play_special_animation()
		else:
			player.presentation.play_attack_animation()
		return

	var anim_player: AnimationPlayer = player.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var sword_mesh: Node3D = player.find_child("sword", true, false) as Node3D
	if not sword_mesh:
		sword_mesh = player.find_child("Sword", true, false) as Node3D

	if anim_player:
		anim_player.stop()
		anim_player.play("attack", -1, 1.4)
	elif sword_mesh:
		var tween: Tween = player.create_tween()
		var start_rot: float = deg_to_rad(arc_degrees * 0.5)
		var end_rot: float = -deg_to_rad(arc_degrees * 0.5)
		sword_mesh.rotation.y = start_rot
		tween.tween_property(sword_mesh, "rotation:y", end_rot, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.chain().tween_property(sword_mesh, "rotation:y", 0.0, 0.1)

func finish_slash(player: CharacterBody3D, slash_area: Area3D) -> void:
	if not player.is_inside_tree():
		if is_instance_valid(slash_area):
			slash_area.monitoring = false
		return
	await player.get_tree().create_timer(0.16).timeout
	if is_instance_valid(slash_area):
		slash_area.monitoring = false

func trigger_arrow_shot(player: CharacterBody3D, dmg: float, pierce: int = 1, spd: float = 28.0) -> void:
	var arrow = ARROW_PROJECTILE_SCENE.instantiate()
	player.get_parent().add_child(arrow)
	var spawn_pos = player.global_position + Vector3(0, 0.8, 0)
	var aim_dir = -player.global_transform.basis.z
	arrow.global_position = spawn_pos + aim_dir * 1.0
	arrow.speed = spd
	arrow.setup(aim_dir, dmg, player, pierce)

func trigger_piercing_arrow(player: CharacterBody3D, dmg: float, pierce: int = 6, spd: float = 36.0) -> void:
	var arrow = ARROW_PROJECTILE_SCENE.instantiate()
	player.get_parent().add_child(arrow)
	var spawn_pos = player.global_position + Vector3(0, 0.8, 0)
	var aim_dir = -player.global_transform.basis.z
	arrow.global_position = spawn_pos + aim_dir * 1.0
	arrow.scale = Vector3(1.5, 1.5, 2.2)
	arrow.speed = spd
	arrow.setup(aim_dir, dmg, player, pierce)
	player.spawn_popup_text("PIERCING ARROW!", Color.CYAN)

func trigger_hammer_smash(player: CharacterBody3D, dmg: float, is_dueling: bool) -> void:
	trigger_slash(player, dmg, 6.0, 110.0, is_dueling)
	var aim_dir = -player.global_transform.basis.z
	var impact_pos = player.global_position + aim_dir * 1.4

	var vfx = player.get_node_or_null("/root/VFXManager")
	if vfx:
		vfx.spawn_hammer_smash_impact(impact_pos, false)

	if not player.is_inside_tree():
		return
	var buildings = player.get_tree().get_nodes_in_group("buildings")
	for b in buildings:
		if b and is_instance_valid(b) and b is BuildingBase:
			var bb: BuildingBase = b as BuildingBase
			if player.global_position.distance_to(bb.global_position) <= 2.8:
				bb.repair(40.0)
				if vfx:
					vfx.spawn_hammer_smash_impact(bb.global_position, true)

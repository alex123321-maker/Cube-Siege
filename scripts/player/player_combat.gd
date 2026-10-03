extends RefCounted
class_name PlayerCombat

## Manages player attack dispatch, attack/special cooldowns, weapon swings, and projectile spawning.

var attack_damage: float = 25.0
var special_damage: float = 60.0
var attack_cooldown_timer: float = 0.0
var special_cooldown_timer: float = 0.0
var _sword_contacts_remaining: int = 0
var _cleave_contacts_remaining: int = 0
var _cleave_hit_window: bool = false
var _slash_serial: int = 0
var _driver: ExecutionDriver
var _pending_casts: Array[PendingCast] = []
var _active_slash: HitboxArea
var _slash_remaining: float = 0.0
var _initial_sample_pending: bool = false
var _sword_contact: bool = false
var _cleave: bool = false

class PendingCast extends RefCounted:
	enum Kind { ATTACK, SPECIAL }
	var kind: Kind
	var class_id: int
	var remaining: float
	var dueling: bool
	var abilities: PlayerAbilities

## All execution is owned by the actor's subtree. No global timer or frame
## coroutine can keep an attack alive after a menu transition or shutdown.
class ExecutionDriver extends Node:
	var combat: PlayerCombat
	var actor: CharacterBody3D
	func _physics_process(delta: float) -> void:
		combat._advance_execution(actor, delta)
	func _exit_tree() -> void:
		combat.cancel_pending_casts(actor)
	func _on_actor_died() -> void:
		combat.cancel_pending_casts(actor)
	func _on_build_changed() -> void:
		if actor is PlayerPrototype and not actor.progression.run_build.active:
			combat.cancel_pending_casts(actor)

## Shared execution/inspection values. The viewer never owns gameplay tuning.
const ATTACK_COOLDOWNS: Array[float] = [0.35, 0.38, 0.48]
const ATTACK_WINDUPS: Array[float] = [0.06, 0.08, 0.12]
const SPECIAL_COOLDOWNS: Array[float] = [4.0, 5.0, 5.0]
const SPECIAL_WINDUPS: Array[float] = [0.28, 0.28, 0.15]
const HAMMER_DAMAGE_MULTIPLIER: float = 1.35
const PIERCING_DAMAGE_MULTIPLIER: float = 1.3
const DUEL_DAMAGE_MULTIPLIER: float = 1.2
const ARROW_SPEED: float = 28.0
const PIERCING_SPEED: float = 36.0
const PIERCING_TARGETS: int = 6
const SLASH_ACTIVE_DURATION: float = 0.16

const ARROW_PROJECTILE_SCENE = preload("res://scenes/prefabs/arrow_projectile.tscn")
const CLEAVE_SPEC: WarriorCleaveSpec = preload("res://assets/abilities/warrior_cleave.tres")
const TALENT_VFX: Script = preload("res://scripts/effects/warrior/warrior_talent_vfx.gd")
var _regular_slash_shape: Shape3D
var _regular_slash_transform: Transform3D
var _cleave_shape: CylinderShape3D

func update_timers(delta: float) -> void:
	if attack_cooldown_timer > 0.0:
		attack_cooldown_timer -= delta
	if special_cooldown_timer > 0.0:
		special_cooldown_timer -= delta

func _is_actor_alive(player: Variant) -> bool:
	if not is_instance_valid(player) or not (player is Node) or not player.is_inside_tree() or player.is_queued_for_deletion():
		return false
	if "current_health" in player and player.current_health <= 0.0:
		return false
	if player is PlayerPrototype and not player.progression.run_build.active:
		return false
	return true

func _ensure_driver(player: CharacterBody3D) -> void:
	if is_instance_valid(_driver):
		_driver.set_physics_process(true)
		return
	_driver = ExecutionDriver.new()
	_driver.name = "CombatExecution"
	_driver.combat = self
	_driver.actor = player
	# Sample after locomotion, including scripted viewer/capture movement.
	_driver.process_physics_priority = 100
	player.add_child(_driver)
	if player is PlayerPrototype:
		player.player_died.connect(_driver._on_actor_died)
		player.progression.run_build.build_changed.connect(_driver._on_build_changed)

func _schedule_cast(player: CharacterBody3D, kind: PendingCast.Kind, class_id: int, delay: float, dueling: bool, abilities: PlayerAbilities = null) -> void:
	_ensure_driver(player)
	var cast: PendingCast = PendingCast.new()
	cast.kind = kind
	cast.class_id = class_id
	cast.remaining = delay
	cast.dueling = dueling
	cast.abilities = abilities
	_pending_casts.append(cast)

func _advance_execution(player: CharacterBody3D, delta: float) -> void:
	if not _is_actor_alive(player):
		cancel_pending_casts(player)
		return
	if player.get_tree().paused:
		return
	if _pending_casts.is_empty() and not is_instance_valid(_active_slash):
		return
	var ready: Array[PendingCast] = []
	for index: int in range(_pending_casts.size() - 1, -1, -1):
		_pending_casts[index].remaining -= delta
		if _pending_casts[index].remaining <= 0.0:
			ready.push_front(_pending_casts.pop_at(index))
	var serial_before: int = _slash_serial
	for cast: PendingCast in ready:
		if not _is_actor_alive(player) or player.get_tree().paused:
			return
		if player.current_class == cast.class_id:
			_release_cast(player, cast)
	# A freshly enabled broad-phase shape is sampled on the next physics tick.
	if serial_before != _slash_serial:
		return
	if not is_instance_valid(_active_slash) or _slash_remaining <= 0.0:
		return
	_sample_slash(player)
	if not _is_actor_alive(player) or player.get_tree().paused:
		return
	_slash_remaining = maxf(0.0, _slash_remaining - delta)
	if _slash_remaining <= 0.0:
		_close_slash()

func _release_cast(player: CharacterBody3D, cast: PendingCast) -> void:
	if cast.kind == PendingCast.Kind.ATTACK:
		match cast.class_id:
			0: trigger_slash(player, attack_damage, 5.0, 90.0, cast.dueling, player.talents.has("sweeping_strike"))
			1: trigger_arrow_shot(player, attack_damage, 1, ARROW_SPEED)
			2: trigger_hammer_smash(player, attack_damage * HAMMER_DAMAGE_MULTIPLIER, cast.dueling)
	else:
		match cast.class_id:
			0: _start_warrior_cleave(player, cast.dueling)
			1: trigger_piercing_arrow(player, special_damage * PIERCING_DAMAGE_MULTIPLIER, PIERCING_TARGETS, PIERCING_SPEED)
			2:
				if cast.abilities:
					cast.abilities.deploy_temp_turret(player)

func _close_slash() -> void:
	if is_instance_valid(_active_slash):
		_active_slash.set_deferred("monitoring", false)
	_active_slash = null
	_slash_remaining = 0.0
	_initial_sample_pending = false
	_cleave_hit_window = false

func cancel_pending_casts(player: CharacterBody3D = null) -> void:
	_pending_casts.clear()
	_slash_serial += 1
	_close_slash()
	if is_instance_valid(_driver):
		_driver.set_physics_process(false)
	if is_instance_valid(player) and player is PlayerPrototype:
		player.movement.is_lunging = false
		player.movement.lunge_timer = 0.0
		player.presentation.cancel_combat_pose()

func perform_attack(player: CharacterBody3D, current_class: int, is_dashing: bool, is_dueling: bool) -> void:
	if not _is_actor_alive(player) or attack_cooldown_timer > 0.0 or is_dashing:
		return

	match current_class:
		0: # CharacterClass.WARRIOR
			attack_cooldown_timer = ATTACK_COOLDOWNS[0] * player.talents.multiplier("attack_speed")
			if player.presentation:
				player.presentation.play_attack_animation()
			_schedule_cast(player, PendingCast.Kind.ATTACK, current_class, ATTACK_WINDUPS[0], is_dueling)
		1: # CharacterClass.ARCHER
			attack_cooldown_timer = ATTACK_COOLDOWNS[1]
			if player.presentation:
				player.presentation.play_attack_animation()
			_schedule_cast(player, PendingCast.Kind.ATTACK, current_class, ATTACK_WINDUPS[1], is_dueling)
		2: # CharacterClass.ENGINEER
			attack_cooldown_timer = ATTACK_COOLDOWNS[2]
			if player.presentation:
				player.presentation.play_attack_animation()
			_schedule_cast(player, PendingCast.Kind.ATTACK, current_class, ATTACK_WINDUPS[2], is_dueling)

func perform_special_attack(player: CharacterBody3D, current_class: int, is_dashing: bool, is_dueling: bool, abilities: PlayerAbilities) -> void:
	if not _is_actor_alive(player) or special_cooldown_timer > 0.0 or is_dashing:
		return

	match current_class:
		0: # CharacterClass.WARRIOR
			special_cooldown_timer = SPECIAL_COOLDOWNS[0] * player.talents.multiplier("cleave_cooldown")
			attack_cooldown_timer = maxf(attack_cooldown_timer, CLEAVE_SPEC.recovery)
			if player.presentation:
				player.presentation.play_special_animation()
			var vfx: Node = player.get_node_or_null("/root/VFXManager")
			if _uses_talent_cleave_visual(player):
				TALENT_VFX.spawn_cleave(player, CLEAVE_SPEC.radius * player.talents.multiplier("cleave_radius"), 360.0 if player.talents.has("whirlwind_cleave") else 180.0, CLEAVE_SPEC.windup, true)
			elif vfx:
				vfx.spawn_cleave_charge(player, CLEAVE_SPEC.windup, player.presentation.blade_tip_anchor)
			_schedule_cast(player, PendingCast.Kind.SPECIAL, current_class, CLEAVE_SPEC.windup, is_dueling)
		1: # CharacterClass.ARCHER
			special_cooldown_timer = SPECIAL_COOLDOWNS[current_class]
			if player.presentation:
				player.presentation.play_special_animation()
			var vfx = player.get_node_or_null("/root/VFXManager")
			if vfx:
				vfx.spawn_arrow_charge(player, SPECIAL_WINDUPS[current_class])
			_schedule_cast(player, PendingCast.Kind.SPECIAL, current_class, SPECIAL_WINDUPS[current_class], is_dueling)
		2: # CharacterClass.ENGINEER
			special_cooldown_timer = SPECIAL_COOLDOWNS[current_class]
			if player.presentation:
				player.presentation.play_special_animation()
			if abilities:
				_schedule_cast(player, PendingCast.Kind.SPECIAL, current_class, SPECIAL_WINDUPS[current_class], is_dueling, abilities)
			else:
				push_warning("PlayerCombat: cannot deploy temp turret because abilities dependency is missing.")

func _start_warrior_cleave(player: CharacterBody3D, is_dueling: bool) -> void:
	if player.talents.has("wide_lunge"):
		player.movement.start_lunge(-player.global_transform.basis.z, WarriorTalentCatalog.LUNGE_DISTANCE * player.talents.multiplier("lunge_distance"), WarriorTalentCatalog.LUNGE_DURATION)
	if player.talents.has("whirlwind_cleave") and player.presentation:
		player.presentation.start_whirlwind_spin(WarriorTalentCatalog.LUNGE_DURATION if player.talents.has("wide_lunge") else SLASH_ACTIVE_DURATION)
	trigger_slash(player, special_damage, 12.0, 360.0 if player.talents.has("whirlwind_cleave") else 180.0, is_dueling, true)

func _uses_talent_cleave_visual(player: CharacterBody3D) -> bool:
	return player is PlayerPrototype and player.current_class == 0 and (player.talents.has("whirlwind_cleave") or player.talents.has("wide_lunge") or not is_equal_approx(player.talents.multiplier("cleave_radius"), 1.0))

func trigger_slash(player: CharacterBody3D, dmg: float, knockback: float, arc_degrees: float, is_dueling: bool, can_hit_multiple: bool = true) -> void:
	if not _is_actor_alive(player):
		return
	var slash_area: HitboxArea = player.get_node_or_null("SlashHitbox") as HitboxArea
	if not slash_area:
		return

	var final_dmg: float = dmg
	slash_area.duel_target = player.abilities.duel_target if is_dueling else null
	slash_area.duel_damage_multiplier = 1.0 + 0.2 * (player.talents.multiplier("duel_bonus") if player is PlayerPrototype else 1.0)

	slash_area.damage = final_dmg
	slash_area.damage_type = "cleave" if player.current_class == 0 and arc_degrees > 120.0 else "physical"
	slash_area.knockback_force = knockback
	slash_area.can_hit_multiple = can_hit_multiple
	slash_area.reset_hits()
	_configure_slash_shape(slash_area, player.current_class == 0 and arc_degrees > 120.0, player.talents.multiplier("cleave_radius") if player is PlayerPrototype else 1.0, arc_degrees)
	_slash_serial += 1
	_cleave_hit_window = player.current_class == 0 and arc_degrees > 120.0
	_sword_contacts_remaining = 1 if (player.current_class == 0 and not can_hit_multiple) else (3 if player.current_class == 0 and arc_degrees <= 120.0 else 0)
	_cleave_contacts_remaining = 6 if player.current_class == 0 and arc_degrees > 120.0 else 0
	var on_hit: Callable = _on_sword_hit.bind(player)
	if not slash_area.hit_confirmed.is_connected(on_hit):
		slash_area.hit_confirmed.connect(on_hit)
	slash_area.monitoring = true

	var aim_dir = -player.global_transform.basis.z
	var vfx = player.get_node_or_null("/root/VFXManager")
	if vfx:
		if arc_degrees > 120.0:
			if _uses_talent_cleave_visual(player):
				TALENT_VFX.spawn_cleave(player, CLEAVE_SPEC.radius * player.talents.multiplier("cleave_radius"), arc_degrees, WarriorTalentCatalog.LUNGE_DURATION if player.talents.has("wide_lunge") else SLASH_ACTIVE_DURATION)
			else:
				vfx.spawn_cleave_wave(player.global_position, aim_dir, 0.25)
		elif player.current_class == 0:
			vfx.spawn_warrior_slash(player.global_position, aim_dir, 2.4, arc_degrees)
		else:
			vfx.spawn_slash_arc(player.global_position, aim_dir, 2.4, arc_degrees, Color(0.35, 0.7, 1.0), 0.18)

	_ensure_driver(player)
	_active_slash = slash_area
	_slash_remaining = WarriorTalentCatalog.LUNGE_DURATION if player.current_class == 0 and arc_degrees > 120.0 and player.talents.has("wide_lunge") else SLASH_ACTIVE_DURATION
	_initial_sample_pending = true
	_sword_contact = player.current_class == 0
	_cleave = player.current_class == 0 and arc_degrees > 120.0
	play_slash_animation(player, arc_degrees)

func _on_sword_hit(target: Node, direction: Vector3, player: CharacterBody3D) -> void:
	if not is_instance_valid(target) or not target is Node3D:
		return
	if not is_instance_valid(player) or not player.is_inside_tree():
		return
	if _cleave_hit_window and target is EnemyBase and (target as EnemyBase).presentation:
		(target as EnemyBase).presentation.play_cleave_recoil(direction)
	if _sword_contacts_remaining <= 0 and _cleave_contacts_remaining <= 0:
		return
	var vfx: Node = player.get_node_or_null("/root/VFXManager")
	if vfx:
		if _cleave_contacts_remaining > 0:
			vfx.spawn_cleave_contact((target as Node3D).global_position + Vector3(0, 0.65, 0), direction, target as Node3D)
			_cleave_contacts_remaining -= 1
		else:
			vfx.spawn_sword_contact((target as Node3D).global_position + Vector3(0, 0.35, 0), direction)
			_sword_contacts_remaining -= 1

func _configure_slash_shape(area: HitboxArea, cleave: bool, radius_multiplier: float = 1.0, arc_degrees: float = 180.0) -> void:
	var collider: CollisionShape3D = area.get_node("CollisionShape3D") as CollisionShape3D
	if not _regular_slash_shape:
		_regular_slash_shape = collider.shape
		_regular_slash_transform = collider.transform
	if cleave:
		if not _cleave_shape:
			_cleave_shape = CylinderShape3D.new()
			_cleave_shape.height = 2.6
		_cleave_shape.radius = CLEAVE_SPEC.radius * radius_multiplier
		collider.shape = _cleave_shape
		collider.position = Vector3(0.0, 0.4, 0.0)
		area.frontal_radius = CLEAVE_SPEC.radius * radius_multiplier
		area.frontal_arc_degrees = arc_degrees
	else:
		collider.shape = _regular_slash_shape
		collider.transform = _regular_slash_transform
		area.frontal_radius = 0.0

func _sample_slash(player: CharacterBody3D) -> void:
	var slash_area: HitboxArea = _active_slash
	var serial: int = _slash_serial
	if is_instance_valid(slash_area) and not player.get_tree().paused:
		for a in slash_area.get_overlapping_areas():
			if not _is_actor_alive(player) or player.get_tree().paused or serial != _slash_serial:
				break
			slash_area._on_area_entered(a)
		if not _is_actor_alive(player) or serial != _slash_serial or not _initial_sample_pending:
			return
		_initial_sample_pending = false

		var hit_count: int = slash_area.hits_landed if ("hits_landed" in slash_area) else slash_area.hit_entities.size()
		if hit_count > 0:
			var vfx = player.get_node_or_null("/root/VFXManager")
			if vfx:
				var hit_pos = player.global_position - player.global_transform.basis.z * 1.5 + Vector3(0, 0.8, 0)
				if not _sword_contact:
					vfx.spawn_sparks(hit_pos, -player.global_transform.basis.z, Color(1.0, 0.85, 0.3), 10, 4.5)
				if hit_count >= 2 and not _cleave:
					vfx.spawn_shockwave(hit_pos, 2.2, Color(1.0, 0.9, 0.2), 0.2)

		if player.current_class != 0 and player.vampirism_heal > 0.0 and hit_count > 0:
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
	trigger_slash(player, dmg, 6.0, 110.0, is_dueling, true)
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

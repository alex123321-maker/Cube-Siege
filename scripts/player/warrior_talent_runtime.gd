extends RefCounted
class_name WarriorTalentRuntime

## The production talent effects are shared by gameplay and Ability Lab.
var actor: PlayerPrototype
var statuses: StatusEffectState = StatusEffectState.new()
var triumph_stacks: int = 0
var regeneration_remaining: float = 0.0
var morale_remaining: float = 0.0
var morale_duration: float = 0.0
var _dash_hits: Dictionary = {}
var _previous_position: Vector3
var _meta: Dictionary = {}

func setup(player: PlayerPrototype) -> void:
	actor = player
	_meta = actor.progression.apply_mastery_stats(actor) if actor.uses_meta_progression() else {}
	actor.progression.run_build.build_changed.connect(refresh_stats)
	actor.progression.run_build.synergy_discovered.connect(_on_synergy_discovered)
	actor.health.parry_triggered.connect(_on_parry)
	actor.movement.dash_performed.connect(_on_dash)
	refresh_stats()

func build() -> WarriorRunBuild:
	return actor.progression.run_build

func has(talent: String) -> bool:
	return actor.current_class == PlayerPrototype.CharacterClass.WARRIOR and build().has_talent(talent)

func multiplier(axis: String) -> float:
	return build().get_property_multiplier(axis) if actor.current_class == PlayerPrototype.CharacterClass.WARRIOR else 1.0

func refresh_stats() -> void:
	if not actor or actor.current_class != PlayerPrototype.CharacterClass.WARRIOR:
		return
	# Recompute from bases; free respec must never compound bonuses or heal.
	actor.combat.attack_damage = 25.0 * float(_meta.get("damage_mult", 1.0)) * multiplier("attack_damage") * (1.0 + triumph_stacks * WarriorTalentCatalog.TRIUMPH_BONUS * multiplier("triumph_power"))
	actor.combat.special_damage = 60.0 * multiplier("cleave_damage")
	actor.movement.speed = 7.0 * float(_meta.get("speed_mult", 1.0))
	actor.movement.dash_speed = 18.0
	actor.movement.dash_duration = 0.15 * multiplier("dash_distance") * (WarriorTalentCatalog.PERFECT_DASH_DISTANCE_MULTIPLIER if has("perfect_dash") else 1.0)
	actor.movement.dash_cooldown = 3.0 * multiplier("dash_cooldown")
	actor.health.max_health = 100.0 + float(_meta.get("max_hp_bonus", 0.0))
	actor.health.current_health = minf(actor.health.current_health, actor.health.max_health)

func refresh_meta() -> void:
	_meta = actor.progression.apply_mastery_stats(actor) if actor.uses_meta_progression() else {}
	refresh_stats()

func attack_based_ability_damage(target: Node = null) -> float:
	# Permanent Bloodlust openings strengthen the basic attack only. Counter
	# and dash retain their attack-property scaling without this meta bonus.
	var damage: float = actor.attack_damage / maxf(1.0, float(_meta.get("damage_mult", 1.0)))
	if actor.is_dueling and is_instance_valid(actor.duel_target) and target == actor.duel_target:
		damage *= 1.0 + 0.2 * multiplier("duel_bonus")
	return damage

func advance(delta: float) -> void:
	statuses.advance(delta)
	if regeneration_remaining > 0.0 and actor.current_health > 0.0:
		actor.heal(WarriorTalentCatalog.HOT_BLOOD_RATE * multiplier("hot_blood_healing") * minf(delta, regeneration_remaining))
		regeneration_remaining = maxf(0.0, regeneration_remaining - delta)
	morale_remaining = maxf(0.0, morale_remaining - delta)

func movement_multiplier() -> float:
	return statuses.movement_multiplier(0.8 if has("dismemberment") else 0.0) * (1.0 + WarriorTalentCatalog.MORALE_SPEED if morale_remaining > 0.0 else 1.0)

func parry_duration() -> float:
	return (WarriorTalentCatalog.COUNTER_PARRY_WINDOW if has("counterattack") else PlayerHealth.PARRY_WINDOW) * multiplier("parry_window")

func dodge() -> bool:
	return morale_remaining > 0.0 and randf() < WarriorTalentCatalog.MORALE_DODGE

func on_damage_dealt(health_loss: float, target: EnemyBase, damage_type: String) -> void:
	if not has("tempered_blade") or health_loss <= 0.0 or not target:
		return
	if damage_type in ["physical", "cleave", "dash"] or (damage_type == "counter" and build().has_synergy("blood_tempering")):
		actor.heal(health_loss * WarriorTalentCatalog.VAMPIRISM_FRACTION * multiplier("vampirism"))

func on_enemy_killed(target: EnemyBase, damage_type: String) -> void:
	if build().has_synergy("carnage") and damage_type == "cleave" and randf() < WarriorTalentCatalog.CARNAGE_CHANCE:
		_dismember(target.global_position)

func on_duel_victory(position: Vector3) -> void:
	if has("loud_triumph"):
		triumph_stacks += 1
		refresh_stats()
		actor.spawn_popup_text("ТРИУМФ ×%d" % triumph_stacks, Color.GOLD)
	if has("dismemberment"):
		_dismember(position)

func _dismember(position: Vector3) -> void:
	morale_duration = WarriorTalentCatalog.MORALE_DURATION * multiplier("morale_duration")
	morale_remaining = morale_duration
	var registry: Node = actor.get_node_or_null("/root/EntityRegistry")
	if registry:
		for enemy: Node3D in registry.get_nearby_enemies(position, WarriorTalentCatalog.DISMEMBER_RADIUS, null):
			if enemy is EnemyBase:
				(enemy as EnemyBase).apply_slow("dismemberment:%d" % actor.get_instance_id(), WarriorTalentCatalog.DISMEMBER_SLOW, morale_remaining)
	var talent_vfx: Script = preload("res://scripts/effects/warrior/warrior_talent_vfx.gd")
	talent_vfx.spawn_dismember(actor, position, WarriorTalentCatalog.DISMEMBER_RADIUS)
	actor.spawn_popup_text("МОРАЛЬ ПОВЫШЕНА", Color(0.5, 0.9, 1.0))

func _on_parry(success: bool) -> void:
	# A forwarded actor signal can synchronously delete/end the owner before
	# this second component listener receives the same parry notification.
	if success and is_instance_valid(actor) and actor.is_inside_tree() and not actor.is_queued_for_deletion() and build().active and has("hot_blood"):
		regeneration_remaining = WarriorTalentCatalog.HOT_BLOOD_DURATION

func _on_dash() -> void:
	_dash_hits.clear()
	_previous_position = actor.global_position

func after_movement() -> void:
	if not _dash_can_hit():
		if is_instance_valid(actor) and actor.is_inside_tree():
			_previous_position = actor.global_position
		return
	var registry: Node = actor.get_node_or_null("/root/EntityRegistry")
	var finish: Vector3 = actor.global_position
	if registry:
		var distance: float = _previous_position.distance_to(finish)
		for enemy: Node3D in registry.get_nearby_enemies((_previous_position + finish) * 0.5, distance * 0.5 + 2.0, null):
			# Damage callbacks can synchronously end the run or free its owner.
			# Disabling future physics cannot stop the current contact loop.
			if not _dash_can_hit():
				return
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or not enemy is EnemyBase or _dash_hits.has(enemy.get_instance_id()):
				continue
			var closest: Vector3 = Geometry3D.get_closest_point_to_segment(enemy.global_position, _previous_position, finish)
			if closest.distance_to(enemy.global_position) <= 1.0 + (enemy as EnemyBase).radius:
				_dash_hits[enemy.get_instance_id()] = true
				(enemy as EnemyBase)._on_damaged(attack_based_ability_damage(enemy), actor.movement.dash_direction * 5.0, "dash", actor)
				if not _dash_can_hit():
					return
	_previous_position = finish

func _dash_can_hit() -> bool:
	return is_instance_valid(actor) and actor.is_inside_tree() and not actor.is_queued_for_deletion() and actor.current_health > 0.0 and build().active and actor.is_dashing and build().has_synergy("dangerous_movement") and not actor.get_tree().paused

func _on_synergy_discovered(id: String) -> void:
	actor.spawn_popup_text("СИНЕРГИЯ: " + WarriorTalentCatalog.SYNERGY_TITLES[id], Color.GOLD)

func reset_for_viewer(unlocked: Array = []) -> void:
	triumph_stacks = 0
	regeneration_remaining = 0.0
	morale_remaining = 0.0
	morale_duration = 0.0
	statuses.clear()
	_dash_hits.clear()
	_meta = {}
	actor.progression.initialize_run(unlocked)
	refresh_stats()
	actor.health.current_health = actor.health.max_health

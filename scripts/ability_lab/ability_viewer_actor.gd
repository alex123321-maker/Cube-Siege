extends "res://scripts/player_prototype.gd"
class_name AbilityViewerActor

## The native player, driven by preview commands instead of gameplay input.
func apply_mastery_stats() -> void:
	pass

func uses_meta_progression() -> bool:
	return false

func configure_talents(ids: Array[String]) -> void:
	talents.reset_for_viewer(WarriorTalentCatalog.TALENT_IDS)
	progression.run_build.selected_talents = WarriorTalentCatalog.sanitize_ids(ids)
	progression.run_build._reveal_synergies()
	progression.run_build.build_changed.emit()

func _unhandled_input(_event: InputEvent) -> void:
	pass

func show_warrior_model() -> void:
	hero_warrior.visible = true
	hero_archer.visible = false
	hero_engineer.visible = false
	presentation.set_active_model(hero_warrior, PlayerPresentation.WARRIOR_PROFILE)
	portal_compass.visible = false

func _physics_process(delta: float) -> void:
	talents.advance(delta)
	movement.update_timers(delta)
	health.update_timers(delta)
	combat.update_timers(delta)
	abilities.update_timers(delta, self)
	orientation.process_orientation(self, delta, Vector3.FORWARD, Vector3.ZERO)
	if is_dueling and is_instance_valid(duel_target) and not movement.is_dashing and not movement.is_lunging:
		movement.process_duel_movement(self, delta, duel_target)
	elif movement.is_dashing or movement.is_lunging:
		movement.process_movement(self, delta)
	else:
		velocity.x = 0.0
		velocity.z = 0.0
		velocity.y = 0.0 if is_on_floor() else velocity.y - 25.0 * delta
		move_and_slide()
	talents.after_movement()
	presentation.update_animations(self, health.is_parrying, movement.is_dashing, delta, orientation)

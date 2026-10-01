extends "res://scripts/enemy_dummy.gd"
class_name AbilityLabTarget

signal damage_observed(amount: float, damage_type: String)

## Native zombie health, hitboxes, knockback, stun and animations, without rewards.
func _ready() -> void:
	super._ready()
	max_health = 1000.0
	current_health = max_health
	update_hp_label()

func _custom_physics(delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	if is_in_duel or (is_instance_valid(target_player) and target_player.is_in_group("decoy")) or is_stunned:
		super._custom_physics(delta)

func perform_attack() -> void:
	# A preview never creates an uncontrolled combat encounter.
	pass

func demonstrate_attack() -> void:
	super.perform_attack()

func _on_damaged(amount: float, knockback: Vector3, type: String, attacker: Node) -> void:
	if is_dying:
		return
	super._on_damaged(amount, knockback, type, attacker)
	damage_observed.emit(amount, type)

func die() -> void:
	is_dying = true
	remove_from_group("enemies")
	presentation.play_death()
	update_hp_label()

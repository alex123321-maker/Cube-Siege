extends "res://scripts/building_base.gd"

@export var reflect_percent: float = 0.25

func _ready() -> void:
	building_name = "Iron Spiked Wall"
	max_health = 1200.0
	current_health = 1200.0
	stone_cost = 2
	iron_cost = 2
	wood_cost = 0
	super._ready()
	add_to_group("walls")

func _on_damaged(amount: float, knockback: Vector3, type: String, attacker: Node) -> void:
	super._on_damaged(amount, knockback, type, attacker)

	# Reflect 25% thorns damage back to attacker!
	if attacker and is_instance_valid(attacker) and attacker.has_method("take_damage"):
		var reflected: float = amount * reflect_percent
		if reflected > 0.5:
			attacker.take_damage(reflected)
			spawn_damage_text(reflected, "%d REFLECT" % int(reflected), Color.INDIAN_RED)

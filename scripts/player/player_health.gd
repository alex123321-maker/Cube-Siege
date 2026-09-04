extends RefCounted
class_name PlayerHealth

## Handles Player HP, damage reception, parry mechanics, and death.

signal health_changed(current_health: float, max_health: float)
signal parry_triggered(successful: bool)
signal player_died()

var max_health: float = 100.0
var current_health: float = 100.0

var is_parrying: bool = false
var parry_timer: float = 0.0
var parry_cooldown_timer: float = 0.0

var current_day: int = 1

func update_timers(delta: float) -> void:
	if parry_cooldown_timer > 0.0:
		parry_cooldown_timer -= delta
	if is_parrying:
		parry_timer -= delta
		if parry_timer <= 0.0:
			is_parrying = false

func trigger_parry(duration: float = 0.5, cooldown: float = 6.0) -> bool:
	if parry_cooldown_timer > 0.0 or is_parrying:
		return false
	is_parrying = true
	parry_timer = duration
	parry_cooldown_timer = cooldown
	parry_triggered.emit(false)
	return true

func take_damage(damage: float, attacker: Node = null, is_dashing: bool = false, is_dueling: bool = false, duel_target: Node = null, player_node: Node = null) -> void:
	if is_dashing:
		return

	if is_parrying:
		is_parrying = false
		parry_cooldown_timer = 3.0
		parry_triggered.emit(true)

		# Stun nearby enemies on successful parry
		if player_node and is_instance_valid(player_node):
			var enemies: Array[Node] = player_node.get_tree().get_nodes_in_group("enemies")
			for e in enemies:
				if e is Node3D and player_node.global_position.distance_to(e.global_position) <= 3.5:
					if e.has_method("apply_stun"):
						e.apply_stun(1.0)
						if e.has_method("_on_damaged"):
							e._on_damaged(30.0, (e.global_position - player_node.global_position).normalized() * 8.0, "counter", player_node)
		return

	var final_damage: float = damage
	if is_dueling and attacker and is_instance_valid(attacker) and attacker != duel_target:
		final_damage *= 0.6
		if attacker.has_method("_on_damaged"):
			attacker._on_damaged(damage * 0.2, Vector3.ZERO, "reflected", player_node)

	current_health -= final_damage
	health_changed.emit(current_health, max_health)

	var bus = player_node.get_node_or_null("/root/EventBus") if player_node else null
	if bus:
		bus.player_health_changed.emit(current_health, max_health)

	if current_health <= 0.0:
		current_health = 0.0

		var roster = player_node.get_node_or_null("/root/RosterManager") if player_node else null
		if roster and roster.has_method("record_run_end"):
			roster.record_run_end(false, current_day, 0)

		player_died.emit()
		if bus:
			bus.player_died.emit()

func heal(amount: float) -> void:
	if current_health <= 0.0:
		return
	current_health = minf(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

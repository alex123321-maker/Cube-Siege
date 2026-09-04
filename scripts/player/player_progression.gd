extends RefCounted
class_name PlayerProgression

## Handles Player level, XP, leveling up, and meta-progression stat multipliers.

signal xp_changed(current_xp: float, max_xp: float, level: int)
signal level_up_reached(new_level: int)

var player_level: int = 1
var current_xp: float = 0.0
var xp_to_next_level: float = 80.0
var vampirism_heal: float = 0.0
var resource_multiplier: int = 1

func add_xp(amount: float, player_node: Node = null) -> void:
	current_xp += amount

	while current_xp >= xp_to_next_level:
		current_xp -= xp_to_next_level
		player_level += 1
		xp_to_next_level = roundf(xp_to_next_level * 1.5)

		level_up_reached.emit(player_level)
		if player_node:
			var bus = player_node.get_node_or_null("/root/EventBus")
			if bus:
				bus.player_level_up.emit(player_level)

	xp_changed.emit(current_xp, xp_to_next_level, player_level)
	if player_node:
		var bus_xp = player_node.get_node_or_null("/root/EventBus")
		if bus_xp:
			bus_xp.player_xp_changed.emit(current_xp, xp_to_next_level, player_level)

func apply_mastery_stats(player_node: Node = null) -> Dictionary:
	var roster = player_node.get_node_or_null("/root/RosterManager") if player_node else null
	if not roster or not roster.has_method("get_character_multipliers"):
		return {}

	var slot_idx: int = roster.selected_slot_index if "selected_slot_index" in roster else 0
	var mults: Dictionary = roster.get_character_multipliers(slot_idx)
	if mults.has("resource_mult"):
		resource_multiplier = maxi(1, int(roundf(mults.resource_mult)))
	return mults

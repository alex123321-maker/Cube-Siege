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
var run_build: WarriorRunBuild = WarriorRunBuild.new()
var collected_resources: int = 0

func initialize_run(unlocked_ids: Array) -> void:
	player_level = 1
	current_xp = 0.0
	xp_to_next_level = 80.0
	collected_resources = 0
	run_build.initialize(unlocked_ids)

func add_xp(amount: float, player_node: Node = null) -> void:
	if amount <= 0.0 or not run_build.active:
		return
	current_xp += amount

	while current_xp >= xp_to_next_level:
		current_xp -= xp_to_next_level
		grant_level(player_node, false)

	_emit_xp(player_node)

func grant_level(player_node: Node = null, emit_xp: bool = true) -> void:
	if not run_build.active:
		return
	player_level += 1
	xp_to_next_level = 80.0 + float(player_level - 1) * 20.0
	run_build.grant_specialization_point()
	level_up_reached.emit(player_level)
	if player_node:
		var bus: Node = player_node.get_node_or_null("/root/EventBus")
		if bus:
			bus.player_level_up.emit(player_level)
	if emit_xp:
		_emit_xp(player_node)

func record_resource_gathered(amount: int) -> void:
	if run_build.active:
		collected_resources += maxi(0, amount)

func get_extraction_xp() -> int:
	return 80 + maxi(0, player_level - 1) * 60 + collected_resources * 2

func _emit_xp(player_node: Node = null) -> void:
	xp_changed.emit(current_xp, xp_to_next_level, player_level)
	if player_node:
		var bus_xp = player_node.get_node_or_null("/root/EventBus")
		if bus_xp:
			bus_xp.player_xp_changed.emit(current_xp, xp_to_next_level, player_level)

func apply_mastery_stats(player_node: Node = null) -> Dictionary:
	var roster = player_node.get_node_or_null("/root/RosterManager") if player_node else null
	if not roster or not roster.has_method("get_character_multipliers"):
		return {}

	var slot_idx: int = roster.selected_slot_index
	var mults: Dictionary = roster.get_character_multipliers(slot_idx)
	if mults.has("resource_mult"):
		resource_multiplier = maxi(1, int(roundf(mults.resource_mult)))
	return mults

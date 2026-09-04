class_name PortalController
extends Area3D

signal portal_repaired()
signal extraction_started(duration: float)
signal extraction_ready()
signal evacuated()

enum State { BROKEN, CHARGING, ACTIVE, EVACUATED }

@export var required_wood: int = 25
@export var required_stone: int = 25
@export var charge_duration: float = 45.0

var extraction_hold_time: float = 2.0
var extraction_progress: float = 0.0

var current_state: State = State.BROKEN
var charge_timer: float = 0.0

@onready var prompt_label: Label3D = $PromptLabel
@onready var pad_mesh: MeshInstance3D = $PortalPad

const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("portal")
	update_visuals()

func _process(delta: float) -> void:
	if current_state == State.CHARGING:
		charge_timer -= delta
		if prompt_label:
			prompt_label.text = "PORTAL CHARGING: %02ds" % int(charge_timer)
			prompt_label.modulate = Color(1.0, 0.85, 0.2)

		if charge_timer <= 0.0:
			current_state = State.ACTIVE
			emit_signal("extraction_ready")
			update_visuals()

func update_visuals() -> void:
	if not prompt_label:
		return

	match current_state:
		State.BROKEN:
			prompt_label.text = "[E] REPAIR PORTAL\n(%d Wood, %d Stone)" % [required_wood, required_stone]
			prompt_label.modulate = Color(0.3, 0.8, 1.0)
		State.CHARGING:
			prompt_label.text = "PORTAL CHARGING..."
			prompt_label.modulate = Color(1.0, 0.85, 0.2)
		State.ACTIVE:
			prompt_label.text = "[E] EVACUATE NOW!"
			prompt_label.modulate = Color(0.2, 1.0, 0.4)
		State.EVACUATED:
			prompt_label.text = "EVACUATED!"
			prompt_label.modulate = Color.GOLD

func is_ready_for_pickup() -> bool:
	return current_state == State.BROKEN or current_state == State.ACTIVE

func is_interactable() -> bool:
	return is_ready_for_pickup()

func interact(player: Node, _is_shift: bool = false) -> void:
	interact_portal(player)

func set_focused(focused: bool) -> void:
	if not prompt_label:
		return
	if focused:
		update_visuals()
		prompt_label.scale = Vector3(1.2, 1.2, 1.2)
	else:
		prompt_label.scale = Vector3(1.0, 1.0, 1.0)

func set_interaction_progress(progress: float) -> void:
	if not prompt_label:
		return
	var bars: int = int(progress * 10.0)
	var bar_str: String = ""
	for i in range(10):
		bar_str += "█" if i < bars else "░"
	var action_text: String = "REPAIRING" if current_state == State.BROKEN else "EVACUATING"
	prompt_label.text = "[E] %s [%s] %d%%" % [action_text, bar_str, int(progress * 100)]
	prompt_label.modulate = Color(0.2, 1.0, 0.4)

func interact_portal(player: Node) -> void:
	match current_state:
		State.BROKEN:
			attempt_repair(player)
		State.ACTIVE:
			advance_extraction(extraction_hold_time, player)

func advance_extraction(delta: float, player: Node) -> bool:
	extraction_progress += delta
	if extraction_progress >= extraction_hold_time:
		evacuate_player(player)
		return true
	return false

func reset_extraction() -> void:
	extraction_progress = 0.0

func attempt_repair(player: Node = null) -> void:
	var building_system: BuildingSystem = null
	if player and "building_system" in player and player.building_system:
		building_system = player.building_system as BuildingSystem
	if not building_system:
		push_warning("PortalController: cannot repair because Player.building_system is not wired.")
		return

	if building_system.spend_resources(required_wood, required_stone, 0):
		current_state = State.CHARGING
		charge_timer = charge_duration
		emit_signal("portal_repaired")
		emit_signal("extraction_started", charge_duration)
		spawn_floating_text("PORTAL REPAIRED! SURVIVE 45s!", Color.CYAN)
		update_visuals()
	else:
		spawn_floating_text("NEED %dW / %dS!" % [required_wood, required_stone], Color.RED)

func evacuate_player(player: Node) -> void:
	if current_state != State.ACTIVE:
		return

	current_state = State.EVACUATED
	emit_signal("evacuated")
	update_visuals()

	# Award Battle XP to RosterManager
	var cycle: Node = get_tree().root.find_child("DayNightCycle", true, false)
	var day_num: int = cycle.current_day if cycle else 1
	var earned_xp: int = 150
	if player and "player_level" in player:
		earned_xp += int(player.player_level) * 50

	var roster: Node = get_node_or_null("/root/RosterManager")
	if roster and roster.has_method("record_run_end"):
		roster.record_run_end(true, day_num, earned_xp)

	spawn_floating_text("EVACUATED! +%d BATTLE XP" % earned_xp, Color.GOLD)

	# Notify HUD or Game Manager to show Victory screen
	var main_node: Node = get_tree().root.find_child("Main", true, false)
	if main_node and main_node.has_method("show_victory"):
		main_node.show_victory()

func spawn_floating_text(msg: String, col: Color) -> void:
	var popup: Node3D = FLOATING_TEXT_SCENE.instantiate()
	get_parent().add_child(popup)
	popup.global_position = global_position + Vector3(0, 3.0, 0)
	if popup.has_node("Label3D"):
		popup.get_node("Label3D").text = msg
		popup.get_node("Label3D").modulate = col

extends HBoxContainer

const CLASS_ACTIONS: Dictionary = {
	0: [
		["warrior_sword_attack", "МЕЧ"], ["warrior_cleave", "РАССЕК"],
		["warrior_dash", "РЫВОК"], ["warrior_parry", "ПАРИР"], ["warrior_duel", "ДУЭЛЬ"]
	],
	1: [
		["archer_shot", "ВЫСТРЕЛ"], ["archer_piercing_shot", "ПРОБОЙ"],
		["archer_roll", "КУВЫРОК"], ["archer_decoy", "ПРИМАНКА"], ["archer_sniper", "СНАЙПЕР"]
	],
	2: [
		["engineer_hammer", "МОЛОТ"], ["engineer_turret", "ТУРЕЛЬ"],
		["engineer_dash", "РЫВОК"], ["engineer_mine", "МИНА"], ["engineer_overclock", "РАЗГОН"]
	]
}
const ACTION_KEYS: Array[String] = ["ЛКМ", "ПКМ", "SPACE", "Q", "F"]
const ACTION_SLOTS: Array[String] = ["SlotLMB", "SlotRMB", "SlotSpace", "SlotQ", "SlotF"]
const BUILD_ICON: Texture2D = preload("res://assets/ui/hud_visual_kit/icons/global_build_64.png")

var player: Node3D = null
var action_slots: Array[HUDActionSlot] = []
var build_slot: HUDActionSlot
var event_bus: Node

func _ready() -> void:
	for slot_name in ACTION_SLOTS:
		action_slots.append(get_node(slot_name) as HUDActionSlot)
	build_slot = get_node("SlotTab") as HUDActionSlot
	build_slot.set_action(BUILD_ICON, "СТРОЙКА", "TAB")
	event_bus = get_node_or_null("/root/EventBus")
	if event_bus and event_bus.player_class_changed.is_connected(_on_player_class_changed) == false:
		event_bus.player_class_changed.connect(_on_player_class_changed)
	_find_player()
	if not player:
		await get_tree().process_frame
		_find_player()
	_refresh_action_set()

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	var movement := player.get("movement") as PlayerMovement
	var cooldowns: Array[float] = [
		float(player.get("attack_cooldown_timer")),
		float(player.get("special_cooldown_timer")),
		movement.dash_cooldown_timer if movement else 0.0,
		float(player.get("parry_cooldown_timer")),
		float(player.get("ultimate_cooldown_timer"))
	]
	for index in action_slots.size():
		action_slots[index].set_cooldown(cooldowns[index])

func _find_player() -> void:
	var players := get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		player = players[0] as Node3D

func _on_player_class_changed(new_class: int) -> void:
	if not is_instance_valid(player):
		_find_player()
	_apply_class_actions(new_class)

func _refresh_action_set() -> void:
	if not is_instance_valid(player):
		for slot in action_slots:
			slot.set_unavailable(true)
		return
	_apply_class_actions(int(player.get("current_class")))

func _apply_class_actions(class_id: int) -> void:
	var actions: Array = CLASS_ACTIONS.get(class_id, [])
	if actions.is_empty():
		for slot in action_slots:
			slot.set_unavailable(true)
		return
	for index in action_slots.size():
		var action: Array = actions[index]
		var texture_path := "res://assets/ui/hud_visual_kit/icons/%s_64.png" % action[0]
		action_slots[index].set_action(load(texture_path) as Texture2D, action[1], ACTION_KEYS[index])

func _exit_tree() -> void:
	if is_instance_valid(event_bus) and event_bus.player_class_changed.is_connected(_on_player_class_changed):
		event_bus.player_class_changed.disconnect(_on_player_class_changed)

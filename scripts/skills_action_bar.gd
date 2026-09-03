extends HBoxContainer

var player: Node3D = null

@onready var slot_lmb: Panel = $SlotLMB
@onready var slot_rmb: Panel = $SlotRMB
@onready var slot_space: Panel = $SlotSpace
@onready var slot_q: Panel = $SlotQ
@onready var slot_f: Panel = $SlotF
@onready var slot_tab: Panel = $SlotTab

func _ready() -> void:
	find_player()

func find_player() -> void:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if not players.is_empty():
		player = players[0] as Node3D

func _process(_delta: float) -> void:
	if not player or not is_instance_valid(player):
		find_player()
		if not player:
			return

	update_slots_for_class()
	update_cooldowns()

func update_slots_for_class() -> void:
	var c: int = player.get("current_class") if player.get("current_class") != null else 0
	match c:
		0: # WARRIOR
			set_slot_info(slot_lmb, "⚔", "МЕЧ", "[ЛКМ]")
			set_slot_info(slot_rmb, "⚡", "РАССЕЧ", "[ПКМ]")
			set_slot_info(slot_space, "💨", "РЫВОК", "[SPACE]")
			set_slot_info(slot_q, "🛡", "ПАРИР", "[Q]")
			set_slot_info(slot_f, "👑", "ДУЭЛЬ", "[F]")
		1: # ARCHER
			set_slot_info(slot_lmb, "🏹", "ВЫСТРЕЛ", "[ЛКМ]")
			set_slot_info(slot_rmb, "⚡", "СКВОЗНАЯ", "[ПКМ]")
			set_slot_info(slot_space, "💨", "КУВЫРОК", "[SPACE]")
			set_slot_info(slot_q, "🎯", "ПРИМАНКА", "[Q]")
			set_slot_info(slot_f, "👁", "СНАЙПЕР", "[F]")
		2: # ENGINEER
			set_slot_info(slot_lmb, "🔨", "МОЛОТ", "[ЛКМ]")
			set_slot_info(slot_rmb, "⚙", "ТУРЕЛЬ", "[ПКМ]")
			set_slot_info(slot_space, "💨", "РЫВОК", "[SPACE]")
			set_slot_info(slot_q, "💣", "МИНА", "[Q]")
			set_slot_info(slot_f, "⚡", "ОВЕРКЛОК", "[F]")

	set_slot_info(slot_tab, "🏗", "СТРОЙКА", "[TAB]")

func set_slot_info(slot: Panel, icon_str: String, name_str: String, key_str: String) -> void:
	if not slot: return
	var icon_lbl: Label = slot.get_node_or_null("IconLabel") as Label
	var name_lbl: Label = slot.get_node_or_null("NameLabel") as Label
	var key_lbl: Label = slot.get_node_or_null("KeyLabel") as Label
	if icon_lbl: icon_lbl.text = icon_str
	if name_lbl: name_lbl.text = name_str
	if key_lbl: key_lbl.text = key_str

func update_cooldowns() -> void:
	update_slot_cd(slot_lmb, player.get("attack_cooldown_timer"))
	update_slot_cd(slot_rmb, player.get("special_cooldown_timer"))
	update_slot_cd(slot_space, player.get("dash_cooldown_timer"))
	update_slot_cd(slot_q, player.get("parry_cooldown_timer"))
	update_slot_cd(slot_f, player.get("ultimate_cooldown_timer"))
	update_slot_cd(slot_tab, 0.0)

func update_slot_cd(slot: Panel, cd: Variant) -> void:
	if not slot: return
	var timer: float = float(cd) if cd != null else 0.0
	var overlay: ColorRect = slot.get_node_or_null("CDOverlay") as ColorRect
	var cd_lbl: Label = slot.get_node_or_null("CDLabel") as Label

	if timer > 0.08:
		if overlay: overlay.visible = true
		if cd_lbl:
			cd_lbl.visible = true
			cd_lbl.text = "%.1fs" % timer
	else:
		if overlay: overlay.visible = false
		if cd_lbl: cd_lbl.visible = false

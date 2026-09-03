extends Control

@onready var tabs: TabContainer = $Panel/TabContainer
@onready var mastery_mgr: Node = get_node_or_null("/root/MasteryManager")

# Crafting state
var has_weapon: bool = false
var has_armor: bool = false
var has_boots: bool = false

@onready var btn_weapon: Button = $Panel/TabContainer/Crafting/VBox/BtnWeapon
@onready var btn_armor: Button = $Panel/TabContainer/Crafting/VBox/BtnArmor
@onready var btn_boots: Button = $Panel/TabContainer/Crafting/VBox/BtnBoots

@onready var mastery_label: Label = $Panel/TabContainer/Mastery/VBox/PointsLabel
@onready var btn_blood: Button = $Panel/TabContainer/Mastery/VBox/Grid/BtnBlood
@onready var btn_surv: Button = $Panel/TabContainer/Mastery/VBox/Grid/BtnSurv
@onready var btn_agil: Button = $Panel/TabContainer/Mastery/VBox/Grid/BtnAgil
@onready var btn_craft: Button = $Panel/TabContainer/Mastery/VBox/Grid/BtnCraft

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	update_ui()

func open() -> void:
	visible = true
	Engine.time_scale = 0.05
	update_ui()

func close() -> void:
	visible = false
	Engine.time_scale = 1.0

func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()

func update_ui() -> void:
	var bs = get_tree().root.find_child("BuildingSystem", true, false)
	var wood: int = bs.wood_count if bs else 0
	var stone: int = bs.stone_count if bs else 0
	var iron: int = bs.iron_count if bs else 0

	# Equipment Crafting buttons
	if btn_weapon:
		btn_weapon.text = "⚔ ОРУЖИЕ (+15 УРОНА) [КУПЛЕНО]" if has_weapon else "⚔ Острый клинок (+15 Урона)\n[4 Камня + 4 Железа] (У вас: " + str(stone) + "S " + str(iron) + "I)"
		btn_weapon.disabled = has_weapon or stone < 4 or iron < 4
	if btn_armor:
		btn_armor.text = "🛡 БРОНЯ (+60 HP, 15% БРОНИ) [КУПЛЕНО]" if has_armor else "🛡 Латный доспех (+60 HP, -15% урона)\n[6 Железа] (У вас: " + str(iron) + "I)"
		btn_armor.disabled = has_armor or iron < 6
	if btn_boots:
		btn_boots.text = "👢 САПОГИ (+25% СКОРОСТИ) [КУПЛЕНО]" if has_boots else "👢 Сапоги странника (+25% Скорости, +2м рывок)\n[4 Дерева + 2 Железа] (У вас: " + str(wood) + "W " + str(iron) + "I)"
		btn_boots.disabled = has_boots or wood < 4 or iron < 2

	# Mastery UI
	if mastery_mgr:
		if mastery_label:
			mastery_label.text = "ДОСТУПНО ОЧКОВ МАСТЕРСТВА: " + str(mastery_mgr.available_points) + "  (Боевой Опыт: " + str(mastery_mgr.total_battle_xp) + ")"
		if btn_blood:
			btn_blood.text = "🩸 Кровожадность (" + str(mastery_mgr.bloodlust) + "/25)\n[+2% Урона per rank]"
		if btn_surv:
			btn_surv.text = "🛡 Выживаемость (" + str(mastery_mgr.survival) + "/25)\n[+4 HP, +1% Защита]"
		if btn_agil:
			btn_agil.text = "⚡ Проворство (" + str(mastery_mgr.agility) + "/25)\n[+1.5% Скорость, -1.5% Кулдауны]"
		if btn_craft:
			btn_craft.text = "🔨 Ремесло (" + str(mastery_mgr.crafting) + "/25)\n[+3% Сбор, +4% HP Зданий]"

func _on_craft_weapon_pressed() -> void:
	var bs = get_tree().root.find_child("BuildingSystem", true, false)
	if bs and bs.stone_count >= 4 and bs.iron_count >= 4:
		bs.stone_count -= 4
		bs.iron_count -= 4
		bs.update_hud_counters()
		has_weapon = true
		var player = get_tree().get_first_node_in_group("player")
		if player:
			player.attack_damage += 15.0
			player.special_damage += 25.0
		update_ui()

func _on_craft_armor_pressed() -> void:
	var bs = get_tree().root.find_child("BuildingSystem", true, false)
	if bs and bs.iron_count >= 6:
		bs.iron_count -= 6
		bs.update_hud_counters()
		has_armor = true
		var player = get_tree().get_first_node_in_group("player")
		if player:
			player.max_health += 60.0
			player.current_health += 60.0
			if player.has_signal("health_changed"):
				player.emit_signal("health_changed", player.current_health, player.max_health)
		update_ui()

func _on_craft_boots_pressed() -> void:
	var bs = get_tree().root.find_child("BuildingSystem", true, false)
	if bs and bs.wood_count >= 4 and bs.iron_count >= 2:
		bs.wood_count -= 4
		bs.iron_count -= 2
		bs.update_hud_counters()
		has_boots = true
		var player = get_tree().get_first_node_in_group("player")
		if player:
			player.speed *= 1.25
			player.dash_speed *= 1.25
		update_ui()

# Salvage actions
func _on_salvage_wood_pressed() -> void:
	var bs = get_tree().root.find_child("BuildingSystem", true, false)
	if bs and bs.wood_count >= 10:
		bs.wood_count -= 10
		bs.iron_count += 1
		bs.update_hud_counters()
		update_ui()

func _on_salvage_stone_pressed() -> void:
	var bs = get_tree().root.find_child("BuildingSystem", true, false)
	if bs and bs.stone_count >= 10:
		bs.stone_count -= 10
		bs.iron_count += 1
		bs.update_hud_counters()
		update_ui()

# Mastery points
func _on_invest_blood_pressed() -> void:
	if mastery_mgr and mastery_mgr.invest_point("bloodlust"):
		apply_mastery_to_player()
		update_ui()

func _on_invest_surv_pressed() -> void:
	if mastery_mgr and mastery_mgr.invest_point("survival"):
		apply_mastery_to_player()
		update_ui()

func _on_invest_agil_pressed() -> void:
	if mastery_mgr and mastery_mgr.invest_point("agility"):
		apply_mastery_to_player()
		update_ui()

func _on_invest_craft_pressed() -> void:
	if mastery_mgr and mastery_mgr.invest_point("crafting"):
		apply_mastery_to_player()
		update_ui()

func _on_reset_mastery_pressed() -> void:
	if mastery_mgr:
		mastery_mgr.reset_points()
		apply_mastery_to_player()
		update_ui()

func apply_mastery_to_player() -> void:
	var player = get_tree().get_first_node_in_group("player")
	if not player or not mastery_mgr:
		return
	var mults = mastery_mgr.get_stat_multipliers()
	if player.get("resource_multiplier") != null:
		player.resource_multiplier = int(mults.resource_mult)

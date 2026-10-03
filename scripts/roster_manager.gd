extends Node

var return_to_character_select: bool = false
var run_active: bool = false
var last_error: String = ""

var _local_selected_slot_index: int = 0
var _local_slots: Array = []

var selected_slot_index: int:
	get:
		var save_mgr = get_node_or_null("/root/SaveManager")
		if save_mgr:
			return save_mgr.selected_slot_index
		return _local_selected_slot_index
	set(val):
		var save_mgr = get_node_or_null("/root/SaveManager")
		if save_mgr:
			save_mgr.selected_slot_index = val
		_local_selected_slot_index = val

var slots: Array:
	get:
		var save_mgr = get_node_or_null("/root/SaveManager")
		if save_mgr and not save_mgr.roster_slots.is_empty():
			return save_mgr.roster_slots
		if _local_slots.is_empty():
			_local_slots = _create_default_slots()
		return _local_slots
	set(val):
		var save_mgr = get_node_or_null("/root/SaveManager")
		if save_mgr:
			save_mgr.roster_slots = val
		_local_slots = val

func _create_default_slots() -> Array:
	var save_cls = load("res://scripts/save_manager.gd")
	if save_cls and save_cls.has_method("get_default_roster_slots"):
		return save_cls.get_default_roster_slots()
	return [
		{
			"class_id": 0, "class_name": "Воин", "title": "Рыцарь Авангарда",
			"is_alive": true, "level": 1, "max_day": 0, "battle_xp": 0,
			"available_points": 5, "bloodlust": 0, "survival": 0, "agility": 0, "crafting": 0
		},
		{
			"class_id": 1, "class_name": "Лучник", "title": "Следопыт Лесов",
			"is_alive": true, "level": 1, "max_day": 0, "battle_xp": 0,
			"available_points": 5, "bloodlust": 0, "survival": 0, "agility": 0, "crafting": 0
		},
		{
			"class_id": 2, "class_name": "Инженер", "title": "Мастер Фортификаций",
			"is_alive": true, "level": 1, "max_day": 0, "battle_xp": 0,
			"available_points": 5, "bloodlust": 0, "survival": 0, "agility": 0, "crafting": 0
		}
	]

func _ready() -> void:
	load_roster()

func get_active_character() -> Dictionary:
	if selected_slot_index >= 0 and selected_slot_index < slots.size():
		return slots[selected_slot_index]
	return slots[0]

func get_character_multipliers(slot_idx: int) -> Dictionary:
	var s: Dictionary = slots[slot_idx] if (slot_idx >= 0 and slot_idx < slots.size()) else slots[0]
	if int(s.get("class_id", 0)) == 0:
		var branch_counts: Dictionary = {"bloodlust": 0, "endurance": 0, "mobility": 0}
		for talent_id: String in get_unlocked_talents(slot_idx):
			var definition: WarriorTalentDefinition = WarriorTalentCatalog.get_talent(talent_id)
			branch_counts[definition.branch] += 1
		return {
			"damage_mult": 1.0 + float(branch_counts.bloodlust) * 0.03,
			"max_hp_bonus": float(branch_counts.endurance) * 5.0,
			"speed_mult": 1.0 + float(branch_counts.mobility) * 0.02,
			"resistance_mult": 1.0, "cooldown_mult": 1.0,
			"resource_mult": 1.0, "building_hp_mult": 1.0
		}
	return {
		"damage_mult": 1.0 + (s.bloodlust * 0.02),
		"max_hp_bonus": s.survival * 4.0,
		"resistance_mult": 1.0 - (s.survival * 0.01),
		"speed_mult": 1.0 + (s.agility * 0.015),
		"cooldown_mult": 1.0 - (s.agility * 0.015),
		"resource_mult": 1.0 + (s.crafting * 0.03),
		"building_hp_mult": 1.0 + (s.crafting * 0.04)
	}

func invest_talent(slot_idx: int, branch: String) -> bool:
	if slot_idx < 0 or slot_idx >= slots.size():
		return false
	if int(slots[slot_idx].get("class_id", 0)) == 0:
		return false # Warrior progression uses stable talent IDs, never legacy ranks.
	var s: Dictionary = slots[slot_idx]
	if s.available_points <= 0:
		return false

	match branch:
		"bloodlust":
			if s.bloodlust >= 25: return false
			s.bloodlust += 1
		"survival":
			if s.survival >= 25: return false
			s.survival += 1
		"agility":
			if s.agility >= 25: return false
			s.agility += 1
		"crafting":
			if s.crafting >= 25: return false
			s.crafting += 1
		_:
			return false

	s.available_points -= 1
	save_roster()
	return true

func reset_talents(slot_idx: int) -> void:
	if slot_idx < 0 or slot_idx >= slots.size():
		return
	if int(slots[slot_idx].get("class_id", 0)) == 0:
		return # Permanent openings belong to this hero until death.
	var s: Dictionary = slots[slot_idx]
	s.available_points += s.bloodlust + s.survival + s.agility + s.crafting
	s.bloodlust = 0
	s.survival = 0
	s.agility = 0
	s.crafting = 0
	save_roster()

func begin_run() -> void:
	run_active = true

func record_run_end(evacuated: bool, day: int, gained_xp: int, victory: bool = false) -> bool:
	var save_mgr: Node = get_node_or_null("/root/SaveManager")
	if not save_mgr:
		return false
	var saved: bool = save_mgr.record_run_end(evacuated, day, gained_xp, selected_slot_index, "", victory)
	if saved:
		run_active = false
		return_to_character_select = true
	return saved

func get_unlocked_talents(slot_idx: int = -1) -> Array[String]:
	var index: int = selected_slot_index if slot_idx < 0 else slot_idx
	if index < 0 or index >= slots.size() or int(slots[index].get("class_id", -1)) != 0:
		return []
	return WarriorTalentCatalog.sanitize_ids(slots[index].get("unlocked_talents", []), true)

func can_unlock_talent(slot_idx: int, talent_id: String) -> bool:
	if run_active or slot_idx < 0 or slot_idx >= slots.size():
		return false
	var slot: Dictionary = slots[slot_idx]
	var definition: WarriorTalentDefinition = WarriorTalentCatalog.get_talent(talent_id)
	if int(slot.get("class_id", -1)) != 0 or not definition or not definition.implemented:
		return false
	var opened: Array[String] = get_unlocked_talents(slot_idx)
	return not opened.has(talent_id) and (definition.parent_id.is_empty() or opened.has(definition.parent_id)) and int(slot.get("talent_xp", 0)) >= definition.unlock_cost

func unlock_talent(slot_idx: int, talent_id: String) -> bool:
	last_error = ""
	if not can_unlock_talent(slot_idx, talent_id):
		last_error = "Талант уже открыт, недоступен или не хватает опыта."
		return false
	var save_mgr: Node = get_node_or_null("/root/SaveManager")
	if not save_mgr:
		last_error = "Не удалось сохранить открытие."
		return false
	var before: Dictionary = save_mgr.snapshot_state()
	var slot: Dictionary = slots[slot_idx]
	var definition: WarriorTalentDefinition = WarriorTalentCatalog.get_talent(talent_id)
	slot.talent_xp = int(slot.get("talent_xp", 0)) - definition.unlock_cost
	var opened: Array[String] = get_unlocked_talents(slot_idx)
	opened.append(talent_id)
	slot.unlocked_talents = opened
	var purchased: Array[String] = WarriorTalentCatalog.sanitize_ids(slot.get("purchased_talents", []))
	purchased.append(talent_id)
	slot.purchased_talents = purchased
	if not save_mgr.save_to_disk():
		save_mgr.restore_state(before)
		last_error = "Не удалось сохранить открытие. Опыт возвращён."
		return false
	return true

func save_roster() -> void:
	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr:
		save_mgr.save_to_disk()

func load_roster() -> void:
	# SaveManager is authoritative and loads during startup
	pass

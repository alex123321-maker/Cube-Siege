extends Node

var return_to_character_select: bool = false

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
	var s: Dictionary = slots[slot_idx]
	s.available_points += s.bloodlust + s.survival + s.agility + s.crafting
	s.bloodlust = 0
	s.survival = 0
	s.agility = 0
	s.crafting = 0
	save_roster()

func record_run_end(evacuated: bool, day: int, gained_xp: int) -> void:
	var s: Dictionary = get_active_character()
	if evacuated:
		s.is_alive = true
		if day > s.max_day:
			s.max_day = day
		s.battle_xp += gained_xp
		var added_pts: int = int(gained_xp / 50.0)
		s.available_points += added_pts
		s.level = max(s.level, int(1 + s.battle_xp / 200.0))
	else:
		# Permadeath: reset character stats for next run
		s.is_alive = true
		s.level = 1
		s.battle_xp = 0
		s.available_points = 5
		s.bloodlust = 0
		s.survival = 0
		s.agility = 0
		s.crafting = 0
	return_to_character_select = true
	save_roster()

func save_roster() -> void:
	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr:
		save_mgr.save_to_disk()

func load_roster() -> void:
	# SaveManager is authoritative and loads during startup
	pass

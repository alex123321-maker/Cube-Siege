extends Node

const ROSTER_PATH = "user://character_roster.json"

var selected_slot_index: int = 0
var return_to_character_select: bool = false

var slots: Array[Dictionary] = [
	{
		"class_id": 0,
		"class_name": "Воин",
		"title": "Рыцарь Авангарда",
		"is_alive": true,
		"level": 1,
		"max_day": 0,
		"battle_xp": 0,
		"available_points": 5,
		"bloodlust": 0,
		"survival": 0,
		"agility": 0,
		"crafting": 0
	},
	{
		"class_id": 1,
		"class_name": "Лучник",
		"title": "Следопыт Лесов",
		"is_alive": true,
		"level": 1,
		"max_day": 0,
		"battle_xp": 0,
		"available_points": 5,
		"bloodlust": 0,
		"survival": 0,
		"agility": 0,
		"crafting": 0
	},
	{
		"class_id": 2,
		"class_name": "Инженер",
		"title": "Мастер Фортификаций",
		"is_alive": true,
		"level": 1,
		"max_day": 0,
		"battle_xp": 0,
		"available_points": 5,
		"bloodlust": 0,
		"survival": 0,
		"agility": 0,
		"crafting": 0
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
	var file = FileAccess.open(ROSTER_PATH, FileAccess.WRITE)
	if not file:
		return
	var data = {
		"selected_slot": selected_slot_index,
		"slots": slots
	}
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func load_roster() -> void:
	if not FileAccess.file_exists(ROSTER_PATH):
		return
	var file = FileAccess.open(ROSTER_PATH, FileAccess.READ)
	if not file:
		return
	var text = file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		selected_slot_index = parsed.get("selected_slot", 0)
		var loaded_slots = parsed.get("slots", [])
		if loaded_slots is Array and loaded_slots.size() == 3:
			slots.clear()
			for item in loaded_slots:
				if item is Dictionary:
					slots.append(item)

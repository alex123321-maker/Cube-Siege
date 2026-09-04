extends Node

const SAVE_FILE_PATH = "user://cube_siege_save.json"
const LEGACY_ROSTER_PATH = "user://character_roster.json"
const LEGACY_MASTERY_PATH = "user://mastery_save.json"
const SAVE_VERSION = 2

var meta_xp: int = 0
var survived_runs: int = 0
var heroes_roster: Array = []
var unlocked_classes: Array = ["warrior", "archer"]

var selected_slot_index: int = 0
var roster_slots: Array = []
var mastery: Dictionary = {}
var run_history: Array = []

@export var auto_load: bool = true

func _ready() -> void:
	if roster_slots.is_empty():
		roster_slots = get_default_roster_slots()
	if mastery.is_empty():
		mastery = get_default_mastery()
	if auto_load:
		load_from_disk()

static func get_default_roster_slots() -> Array:
	return [
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

static func get_default_mastery() -> Dictionary:
	return {
		"total_battle_xp": 0,
		"available_points": 5,
		"bloodlust": 0,
		"survival": 0,
		"agility": 0,
		"crafting": 0
	}

func record_victory(char_name: String, char_class: String, days: int, save_path: String = "") -> void:
	meta_xp += 500
	survived_runs += 1
	var hero_entry: Dictionary = {
		"name": char_name,
		"class": char_class,
		"days_survived": days,
		"outcome": "victory",
		"timestamp": Time.get_datetime_string_from_system()
	}
	heroes_roster.append(hero_entry)
	run_history.append(hero_entry)
	save_to_disk(save_path)

func record_defeat(char_name: String, save_path: String = "") -> void:
	# Log run defeat to history
	var hero_entry: Dictionary = {
		"name": char_name,
		"class": char_name,
		"days_survived": 0,
		"outcome": "defeat",
		"timestamp": Time.get_datetime_string_from_system()
	}
	run_history.append(hero_entry)

	# Clean up active heroes roster entry if present
	for i in range(heroes_roster.size() - 1, -1, -1):
		var hero = heroes_roster[i]
		if hero is Dictionary and hero.get("name", "") == char_name:
			heroes_roster.remove_at(i)

	save_to_disk(save_path)

func record_run_end(evacuated: bool, day: int, gained_xp: int, slot_idx: int = -1, save_path: String = "") -> void:
	var idx: int = selected_slot_index if slot_idx < 0 else slot_idx
	if idx < 0 or idx >= roster_slots.size():
		idx = 0

	var s: Dictionary = roster_slots[idx]
	if evacuated:
		s.is_alive = true
		if day > s.get("max_day", 0):
			s.max_day = day
		s.battle_xp = s.get("battle_xp", 0) + gained_xp
		var added_pts: int = int(gained_xp / 50.0)
		s.available_points = s.get("available_points", 0) + added_pts
		s.level = max(s.get("level", 1), int(1 + s.battle_xp / 200.0))
		record_victory(s.get("class_name", "Hero"), s.get("class_name", "Warrior"), day, save_path)
	else:
		# Permadeath: reset slot progression to baseline
		s.is_alive = true
		s.level = 1
		s.battle_xp = 0
		s.available_points = 5
		s.bloodlust = 0
		s.survival = 0
		s.agility = 0
		s.crafting = 0
		record_defeat(s.get("class_name", "Hero"), save_path)

func serialize_to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"meta_xp": meta_xp,
		"survived_runs": survived_runs,
		"heroes_roster": heroes_roster,
		"unlocked_classes": unlocked_classes,
		"selected_slot": selected_slot_index,
		"roster_slots": roster_slots,
		"mastery": mastery,
		"run_history": run_history
	}

func save_to_disk(custom_path: String = "") -> bool:
	var path: String = custom_path if custom_path != "" else SAVE_FILE_PATH
	var data: Dictionary = serialize_to_dict()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		return true
	else:
		push_error("SaveManager: Failed to open save file for writing at %s. Error: %d" % [path, FileAccess.get_open_error()])
		return false

func load_from_disk(custom_path: String = "") -> bool:
	var path: String = custom_path if custom_path != "" else SAVE_FILE_PATH
	if not FileAccess.file_exists(path):
		# If primary save file is missing, migrate from legacy files if present
		if custom_path == "":
			_check_and_migrate_legacy_files()
		save_to_disk(path)
		return true

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("SaveManager: Failed to open save file at %s. Error: %d" % [path, FileAccess.get_open_error()])
		return false

	var content: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var err: Error = json.parse(content)
	if err == OK and json.data is Dictionary:
		_migrate_and_load_data(json.data)
		if custom_path == "":
			_check_and_migrate_legacy_files()
		return true
	else:
		push_warning("SaveManager: Failed to parse save JSON at %s. Using default safe state." % path)
		# Corrupted save: keep default safe state, save backup
		return false

func _migrate_and_load_data(d: Dictionary) -> void:
	var version: int = d.get("version", 0)

	# Safe extraction of common fields
	if d.has("meta_xp") and (d["meta_xp"] is int or d["meta_xp"] is float):
		meta_xp = int(d["meta_xp"])
	if d.has("survived_runs") and (d["survived_runs"] is int or d["survived_runs"] is float):
		survived_runs = int(d["survived_runs"])
	if d.has("heroes_roster") and d["heroes_roster"] is Array:
		heroes_roster = d["heroes_roster"]
	if d.has("unlocked_classes") and d["unlocked_classes"] is Array:
		unlocked_classes = d["unlocked_classes"]

	# Schema Version 2 additions
	if version < 2:
		_migrate_v1_to_v2(d)
	else:
		if d.has("selected_slot") and (d["selected_slot"] is int or d["selected_slot"] is float):
			selected_slot_index = int(d["selected_slot"])
		if d.has("roster_slots") and d["roster_slots"] is Array and d["roster_slots"].size() == 3:
			roster_slots = d["roster_slots"]
		if d.has("mastery") and d["mastery"] is Dictionary:
			mastery = d["mastery"]
		if d.has("run_history") and d["run_history"] is Array:
			run_history = d["run_history"]

func _migrate_v1_to_v2(d: Dictionary) -> void:
	# Ensure roster_slots exist
	if roster_slots.is_empty():
		roster_slots = get_default_roster_slots()
	if mastery.is_empty():
		mastery = get_default_mastery()
	if d.has("heroes_roster") and d["heroes_roster"] is Array:
		run_history = d["heroes_roster"].duplicate(true)

func _check_and_migrate_legacy_files() -> void:
	# Migrate legacy character_roster.json if exists
	if FileAccess.file_exists(LEGACY_ROSTER_PATH):
		var file = FileAccess.open(LEGACY_ROSTER_PATH, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				var slots = parsed.get("slots", [])
				if slots is Array and slots.size() == 3:
					roster_slots = slots
				selected_slot_index = parsed.get("selected_slot", 0)

	# Migrate legacy mastery_save.json if exists
	if FileAccess.file_exists(LEGACY_MASTERY_PATH):
		var file = FileAccess.open(LEGACY_MASTERY_PATH, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				mastery = parsed

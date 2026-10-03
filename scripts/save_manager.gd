extends Node

const SAVE_FILE_NAME = "cube_siege_save.json"
const LEGACY_ROSTER_NAME = "character_roster.json"
const LEGACY_MASTERY_NAME = "mastery_save.json"
const DEFAULT_TEST_PROFILE_DIR = "user://test_profile/"

# Backwards compatibility constants
const SAVE_FILE_PATH = "user://cube_siege_save.json"
const LEGACY_ROSTER_PATH = "user://character_roster.json"
const LEGACY_MASTERY_PATH = "user://mastery_save.json"
const SAVE_VERSION = 3

var storage_dir: String = "user://"
var save_file_path: String = "user://cube_siege_save.json"
var legacy_roster_path: String = "user://character_roster.json"
var legacy_mastery_path: String = "user://mastery_save.json"

var meta_xp: int = 0
var survived_runs: int = 0
var heroes_roster: Array = []
var unlocked_classes: Array = ["warrior", "archer"]

var selected_slot_index: int = 0
var roster_slots: Array = []
var mastery: Dictionary = {}
var run_history: Array = []

@export var auto_load: bool = true

func _init() -> void:
	_init_storage_paths()

func _init_storage_paths() -> void:
	var env_test = OS.get_environment("CUBE_SIEGE_TEST_PROFILE")
	if env_test != "":
		set_storage_dir(env_test)
		return
	var env_save_dir = OS.get_environment("CUBE_SIEGE_SAVE_DIR")
	if env_save_dir != "":
		set_storage_dir(env_save_dir)
		return

	var all_args: Array = OS.get_cmdline_args() + OS.get_cmdline_user_args()
	for arg in all_args:
		var s_arg: String = str(arg)
		if s_arg.contains("gameplay_sandbox.tscn") or s_arg == "--gameplay-sandbox":
			set_storage_dir("user://gameplay_sandbox/profile/")
			return
		if s_arg.contains("ability_lab.tscn") or s_arg == "--ability-lab":
			set_storage_dir("user://ability_lab/profile/")
			return
		if s_arg.begins_with("--test-profile="):
			set_storage_dir(s_arg.substr("--test-profile=".length()))
			return
		if s_arg == "--test-profile":
			set_storage_dir(DEFAULT_TEST_PROFILE_DIR)
			return
		if s_arg.contains("gut_cmdln.gd") or s_arg.begins_with("-gconfig") or s_arg.begins_with("-gtest") or s_arg.contains("gameplay_smoke_harness"):
			set_storage_dir(DEFAULT_TEST_PROFILE_DIR)
			return

	set_storage_dir("user://")

func set_storage_dir(new_dir: String) -> void:
	var dir = new_dir.replace("\\", "/")
	if not dir.ends_with("/"):
		dir += "/"
	storage_dir = dir
	save_file_path = storage_dir + SAVE_FILE_NAME
	legacy_roster_path = storage_dir + LEGACY_ROSTER_NAME
	legacy_mastery_path = storage_dir + LEGACY_MASTERY_NAME
	if not DirAccess.dir_exists_absolute(storage_dir):
		DirAccess.make_dir_recursive_absolute(storage_dir)

func is_test_environment() -> bool:
	return storage_dir != "user://"

func snapshot_state() -> Dictionary:
	return {
		"meta_xp": meta_xp,
		"survived_runs": survived_runs,
		"heroes_roster": heroes_roster.duplicate(true),
		"unlocked_classes": unlocked_classes.duplicate(true),
		"selected_slot_index": selected_slot_index,
		"roster_slots": roster_slots.duplicate(true),
		"mastery": mastery.duplicate(true),
		"run_history": run_history.duplicate(true)
	}

func restore_state(snapshot: Dictionary) -> void:
	meta_xp = snapshot.get("meta_xp", 0)
	survived_runs = snapshot.get("survived_runs", 0)
	heroes_roster = snapshot.get("heroes_roster", []).duplicate(true)
	unlocked_classes = snapshot.get("unlocked_classes", ["warrior", "archer"]).duplicate(true)
	selected_slot_index = snapshot.get("selected_slot_index", 0)
	roster_slots = snapshot.get("roster_slots", get_default_roster_slots()).duplicate(true)
	mastery = snapshot.get("mastery", get_default_mastery()).duplicate(true)
	run_history = snapshot.get("run_history", []).duplicate(true)

func reset_to_defaults() -> void:
	meta_xp = 0
	survived_runs = 0
	heroes_roster = []
	unlocked_classes = ["warrior", "archer"]
	selected_slot_index = 0
	roster_slots = get_default_roster_slots()
	mastery = get_default_mastery()
	run_history = []

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
			"crafting": 0,
			"talent_xp": 0,
			"unlocked_talents": WarriorTalentCatalog.STARTER_IDS.duplicate(),
			"purchased_talents": [],
			"completed_runs": 0,
			"victories": 0
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

func record_run_end(evacuated: bool, day: int, gained_xp: int, slot_idx: int = -1, save_path: String = "", victory: bool = false) -> bool:
	var before: Dictionary = snapshot_state()
	var idx: int = selected_slot_index if slot_idx < 0 else slot_idx
	if idx < 0 or idx >= roster_slots.size():
		idx = 0

	var s: Dictionary = roster_slots[idx]
	if evacuated:
		s.is_alive = true
		if day > s.get("max_day", 0):
			s.max_day = day
		gained_xp = maxi(0, gained_xp)
		s.battle_xp = s.get("battle_xp", 0) + gained_xp
		s.talent_xp = s.get("talent_xp", 0) + gained_xp
		s.completed_runs = s.get("completed_runs", 0) + 1
		if victory:
			s.victories = s.get("victories", 0) + 1
		s.level = max(s.get("level", 1), int(1 + s.battle_xp / 200.0))
		meta_xp += gained_xp
		survived_runs += 1
	else:
		# A new playable hero replaces the dead character; no unlock survives.
		roster_slots[idx] = get_default_roster_slots()[idx].duplicate(true)
	var entry: Dictionary = {
		"name": s.get("class_name", "Hero"), "class": s.get("class_name", "Warrior"),
		"days_survived": day, "earned_xp": gained_xp if evacuated else 0,
		"outcome": ("victory" if victory else "evacuated") if evacuated else "defeat",
		"timestamp": Time.get_datetime_string_from_system()
	}
	run_history.append(entry)
	if evacuated:
		heroes_roster.append(entry.duplicate(true))
	if not save_to_disk(save_path):
		restore_state(before)
		return false
	return true

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
	var path: String = custom_path if custom_path != "" else save_file_path
	var data: Dictionary = serialize_to_dict()
	var temporary_path: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temporary_path, FileAccess.WRITE)
	if file:
		var write_error: Error = _store_and_flush(file, JSON.stringify(data, "\t"))
		file.close()
		if write_error != OK:
			DirAccess.remove_absolute(temporary_path)
			push_error("SaveManager: Failed to write save file at %s. Error: %d" % [path, write_error])
			return false
		var backup_path: String = path + ".bak"
		var had_original: bool = FileAccess.file_exists(path)
		if had_original and DirAccess.rename_absolute(path, backup_path) != OK:
			DirAccess.remove_absolute(temporary_path)
			return false
		if DirAccess.rename_absolute(temporary_path, path) != OK:
			if had_original:
				DirAccess.rename_absolute(backup_path, path)
			DirAccess.remove_absolute(temporary_path)
			return false
		if had_original:
			DirAccess.remove_absolute(backup_path)
		return true
	else:
		push_error("SaveManager: Failed to open save file for writing at %s. Error: %d" % [path, FileAccess.get_open_error()])
		return false

func _store_and_flush(file: FileAccess, content: String) -> Error:
	file.store_string(content)
	var write_error: Error = file.get_error()
	if write_error != OK:
		return write_error
	file.flush()
	return file.get_error()

func load_from_disk(custom_path: String = "") -> bool:
	var path: String = custom_path if custom_path != "" else save_file_path
	if not FileAccess.file_exists(path):
		# The process may stop after primary -> .bak and before .tmp -> primary.
		# Prefer the last durable snapshot, then a complete first-save temporary
		# file. Never replace an existing recovery artifact with fresh defaults.
		var had_recovery_artifact: bool = false
		for suffix: String in [".bak", ".tmp"]:
			var recovery_path: String = path + suffix
			if not FileAccess.file_exists(recovery_path):
				continue
			had_recovery_artifact = true
			var recovered: Dictionary = _read_recovery_candidate(recovery_path)
			if recovered.is_empty():
				continue
			if DirAccess.rename_absolute(recovery_path, path) != OK:
				push_warning("SaveManager: Could not restore interrupted save at %s." % path)
				return false
			_migrate_and_load_data(recovered)
			return true
		if had_recovery_artifact:
			push_warning("SaveManager: Interrupted save artifacts are invalid; preserved for recovery at %s." % path)
			return false
		# If primary save file is missing, migrate from legacy files if present
		if custom_path == "":
			_check_and_migrate_legacy_files()
		return save_to_disk(path)

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
		# The primary file is authoritative. Legacy sidecars are imported once,
		# only when it does not exist, never over a saved v3 character.
		return true
	else:
		push_warning("SaveManager: Failed to parse save JSON at %s. Using default safe state." % path)
		return false

func _read_recovery_candidate(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		return {}
	var parser: JSON = JSON.new()
	var text: String = file.get_as_text()
	file.close()
	if parser.parse(text) != OK or not parser.data is Dictionary:
		return {}
	var data: Dictionary = parser.data
	var version: Variant = data.get("version", null)
	if not (version is int or version is float) or float(version) != float(int(version)) or int(version) < 2 or int(version) > SAVE_VERSION:
		return {}
	var slots: Variant = data.get("roster_slots", null)
	if not slots is Array or slots.size() != 3:
		return {}
	for index: int in range(3):
		if not slots[index] is Dictionary:
			return {}
		var class_id: Variant = slots[index].get("class_id", null)
		if not (class_id is int or class_id is float) or float(class_id) != float(index):
			return {}
	return data

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
	_normalize_roster(version < 3)
	selected_slot_index = clampi(selected_slot_index, 0, roster_slots.size() - 1)

func _normalize_roster(migrate_legacy: bool) -> void:
	var defaults: Array = get_default_roster_slots()
	if roster_slots.size() != defaults.size():
		roster_slots = defaults
	for index: int in range(roster_slots.size()):
		if not roster_slots[index] is Dictionary:
			roster_slots[index] = defaults[index].duplicate(true)
		var slot: Dictionary = roster_slots[index]
		for key: String in defaults[index]:
			if not slot.has(key):
				slot[key] = defaults[index][key]
		if index != 0:
			continue
		if migrate_legacy and not slot.has("legacy_progression"):
			var legacy: Dictionary = {}
			var points: int = 0
			for key: String in ["available_points", "bloodlust", "survival", "agility", "crafting"]:
				legacy[key] = maxi(0, int(slot.get(key, 0))) if slot.get(key, 0) is float or slot.get(key, 0) is int else 0
				points += legacy[key]
			slot.legacy_progression = legacy
			slot.talent_xp = maxi(0, int(slot.get("talent_xp", 0))) + points * 50
		slot.unlocked_talents = WarriorTalentCatalog.sanitize_ids(slot.get("unlocked_talents", []), true)
		slot.purchased_talents = WarriorTalentCatalog.sanitize_ids(slot.get("purchased_talents", []))
		var purchased: Array[String] = []
		for talent_id: String in slot.purchased_talents:
			if slot.unlocked_talents.has(talent_id) and not WarriorTalentCatalog.STARTER_IDS.has(talent_id):
				purchased.append(talent_id)
		slot.purchased_talents = purchased
		for key: String in ["talent_xp", "completed_runs", "victories"]:
			slot[key] = maxi(0, int(slot[key])) if slot[key] is float or slot[key] is int else 0

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
	if FileAccess.file_exists(legacy_roster_path):
		var file = FileAccess.open(legacy_roster_path, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				var slots = parsed.get("slots", [])
				if slots is Array and slots.size() == 3:
					roster_slots = slots
				selected_slot_index = parsed.get("selected_slot", 0)

	# Migrate legacy mastery_save.json if exists
	if FileAccess.file_exists(legacy_mastery_path):
		var file = FileAccess.open(legacy_mastery_path, FileAccess.READ)
		if file:
			var parsed = JSON.parse_string(file.get_as_text())
			file.close()
			if parsed is Dictionary:
				mastery = parsed
	_normalize_roster(true)

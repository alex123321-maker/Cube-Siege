extends Node
class_name SaveManager

const SAVE_FILE_PATH = "user://cube_siege_save.json"
const SAVE_VERSION = 1

var meta_xp: int = 0
var survived_runs: int = 0
var heroes_roster: Array = []
var unlocked_classes: Array = ["warrior", "archer"]

func _ready() -> void:
	load_from_disk()

func record_victory(char_name: String, char_class: String, days: int) -> void:
	meta_xp += 500
	survived_runs += 1
	var hero_entry: Dictionary = {
		"name": char_name,
		"class": char_class,
		"days_survived": days,
		"timestamp": Time.get_datetime_string_from_system()
	}
	heroes_roster.append(hero_entry)
	save_to_disk()

func record_defeat(char_name: String) -> void:
	for i in range(heroes_roster.size() - 1, -1, -1):
		var hero = heroes_roster[i]
		if hero is Dictionary and hero.get("name", "") == char_name:
			heroes_roster.remove_at(i)
	save_to_disk()

func save_to_disk() -> void:
	var data: Dictionary = {
		"version": SAVE_VERSION,
		"meta_xp": meta_xp,
		"survived_runs": survived_runs,
		"heroes_roster": heroes_roster,
		"unlocked_classes": unlocked_classes
	}
	var file: FileAccess = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
	else:
		push_error("SaveManager: Failed to open save file for writing. Error code: %d" % FileAccess.get_open_error())

func load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_FILE_PATH):
		save_to_disk()
		return

	var file: FileAccess = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)
	if file:
		var content: String = file.get_as_text()
		file.close()
		var json: JSON = JSON.new()
		var err: Error = json.parse(content)
		if err == OK:
			if json.data is Dictionary:
				_migrate_and_load_data(json.data)
			else:
				push_error("SaveManager: Parsed JSON data is not a Dictionary.")
		else:
			push_error("SaveManager: Failed to parse save file JSON. Error line: %d, Error message: %s" % [json.get_error_line(), json.get_error_message()])
	else:
		push_error("SaveManager: Failed to open save file for reading. Error code: %d" % FileAccess.get_open_error())

func _migrate_and_load_data(d: Dictionary) -> void:
	var version: int = d.get("version", 0)
	
	if version < SAVE_VERSION:
		# Add migration logic here for future versions
		# Example: if version == 0: migrate_v0_to_v1(d)
		pass
		
	if d.has("meta_xp"):
		var val = d["meta_xp"]
		if val is int or val is float:
			meta_xp = int(val)
		else:
			push_error("SaveManager: Invalid type for meta_xp")
			meta_xp = 0
			
	if d.has("survived_runs"):
		var val = d["survived_runs"]
		if val is int or val is float:
			survived_runs = int(val)
		else:
			push_error("SaveManager: Invalid type for survived_runs")
			survived_runs = 0
			
	if d.has("heroes_roster"):
		if d["heroes_roster"] is Array:
			heroes_roster = d["heroes_roster"]
		else:
			push_error("SaveManager: Invalid type for heroes_roster")
			heroes_roster = []
			
	if d.has("unlocked_classes"):
		if d["unlocked_classes"] is Array:
			unlocked_classes = d["unlocked_classes"]
		else:
			push_error("SaveManager: Invalid type for unlocked_classes")
			unlocked_classes = ["warrior", "archer"]

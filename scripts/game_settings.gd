extends Node

## Manages persistent user preferences (e.g. Camera Distance preset).
## Independent of player runs and character permadeath.

const CameraMath = preload("res://scripts/camera/camera_math.gd")
const SETTINGS_FILE_PATH: String = "user://game_settings.json"

signal camera_distance_changed(preset: int, offset: Vector3)

var camera_distance: int = CameraMath.DEFAULT_PRESET
var auto_load: bool = true

func _ready() -> void:
	if auto_load:
		load_settings()

func get_camera_distance() -> int:
	return camera_distance

func set_camera_distance(preset: int, save: bool = true) -> void:
	if not CameraMath.PRESET_OFFSETS.has(preset):
		preset = CameraMath.DEFAULT_PRESET

	camera_distance = preset
	var offset: Vector3 = CameraMath.get_preset_offset(camera_distance)
	camera_distance_changed.emit(camera_distance, offset)

	var eb = get_node_or_null("/root/EventBus")
	if eb and eb.has_signal("camera_distance_changed"):
		eb.emit_signal("camera_distance_changed", camera_distance, offset)

	if save:
		save_settings()

func get_camera_offset(preset: int = -1) -> Vector3:
	var p: int = camera_distance if preset < 0 else preset
	return CameraMath.get_preset_offset(p)

func get_camera_preset_name(preset: int = -1) -> String:
	var p: int = camera_distance if preset < 0 else preset
	return CameraMath.get_preset_name(p)

func serialize_to_dict() -> Dictionary:
	return {
		"version": 1,
		"camera_distance": camera_distance
	}

func save_settings(custom_path: String = "") -> bool:
	var path: String = custom_path if custom_path != "" else SETTINGS_FILE_PATH
	var data: Dictionary = serialize_to_dict()
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		return true
	else:
		push_warning("GameSettings: Failed to save settings at %s" % path)
		return false

func load_settings(custom_path: String = "") -> bool:
	var path: String = custom_path if custom_path != "" else SETTINGS_FILE_PATH
	if not FileAccess.file_exists(path):
		camera_distance = CameraMath.DEFAULT_PRESET
		return true

	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if not file:
		push_warning("GameSettings: Failed to open settings file at %s" % path)
		return false

	var content: String = file.get_as_text()
	file.close()

	var json: JSON = JSON.new()
	var err: Error = json.parse(content)
	if err == OK and json.data is Dictionary:
		var d: Dictionary = json.data
		if d.has("camera_distance") and (d["camera_distance"] is int or d["camera_distance"] is float):
			var val: int = int(d["camera_distance"])
			if CameraMath.PRESET_OFFSETS.has(val):
				camera_distance = val
			else:
				camera_distance = CameraMath.DEFAULT_PRESET
		return true
	else:
		push_warning("GameSettings: Failed to parse settings JSON at %s. Using default safe state." % path)
		camera_distance = CameraMath.DEFAULT_PRESET
		return false

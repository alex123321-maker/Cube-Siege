extends Node

## Manages persistent user preferences (e.g. Camera Distance preset).
## Independent of player runs and character permadeath.

const CameraMath = preload("res://scripts/camera/camera_math.gd")
const SETTINGS_FILE_PATH: String = "user://game_settings.json"

signal camera_distance_changed(preset: int, offset: Vector3)

var camera_distance: int = CameraMath.DEFAULT_PRESET
var auto_load: bool = true

const AUDIO_BUSES: Array[StringName] = [&"Master", &"Music", &"SFX", &"Ambience"]
const OUTPUT_LIMITER_NAME: String = "CubeSiegeOutputLimiter"
var audio_levels: Dictionary[StringName, float] = {
	&"Master": 0.85, &"Music": 0.75, &"SFX": 0.9, &"Ambience": 0.65
}

func _ready() -> void:
	ensure_audio_buses()
	if auto_load:
		load_settings()
	apply_audio_levels()

func ensure_audio_buses() -> void:
	for audio_bus: StringName in AUDIO_BUSES:
		if AudioServer.get_bus_index(audio_bus) >= 0:
			continue
		var index: int = AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, audio_bus)
		AudioServer.set_bus_send(index, &"Master")
	# Simultaneous spatial impacts can exceed full scale even when each source
	# is clean. Keep one final limiter across settings reloads and new runs.
	var master: int = AudioServer.get_bus_index(&"Master")
	for effect_index: int in range(AudioServer.get_bus_effect_count(master)):
		var effect: AudioEffect = AudioServer.get_bus_effect(master, effect_index)
		if effect is AudioEffectHardLimiter and effect.resource_name == OUTPUT_LIMITER_NAME:
			return
	var limiter: AudioEffectHardLimiter = AudioEffectHardLimiter.new()
	limiter.resource_name = OUTPUT_LIMITER_NAME
	limiter.ceiling_db = -1.0
	AudioServer.add_bus_effect(master, limiter)

func get_audio_level(audio_bus: StringName) -> float:
	return audio_levels.get(audio_bus, 1.0)

func set_audio_level(audio_bus: StringName, level: float, save: bool = true) -> void:
	if audio_bus not in AUDIO_BUSES or not is_finite(level):
		return
	audio_levels[audio_bus] = clampf(level, 0.0, 1.0)
	apply_audio_levels()
	if save:
		save_settings()

func apply_audio_levels() -> void:
	ensure_audio_buses()
	for audio_bus: StringName in AUDIO_BUSES:
		var index: int = AudioServer.get_bus_index(audio_bus)
		var level: float = audio_levels[audio_bus]
		AudioServer.set_bus_mute(index, level <= 0.001)
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(level, 0.0001)))

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
		"camera_distance": camera_distance,
		"audio_levels": audio_levels
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
		if d.get("audio_levels") is Dictionary:
			var saved_levels: Dictionary = d["audio_levels"]
			for audio_bus: StringName in AUDIO_BUSES:
				var value: Variant = saved_levels.get(String(audio_bus))
				if (value is int or value is float) and is_finite(float(value)):
					audio_levels[audio_bus] = clampf(float(value), 0.0, 1.0)
		apply_audio_levels()
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

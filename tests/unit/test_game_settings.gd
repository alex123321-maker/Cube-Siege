extends GutTest

const GameSettingsScript = preload("res://scripts/game_settings.gd")
const CameraMath = preload("res://scripts/camera/camera_math.gd")
const TEST_SETTINGS_PATH = "user://test_game_settings.json"

func before_each() -> void:
	if FileAccess.file_exists(TEST_SETTINGS_PATH):
		DirAccess.remove_absolute(TEST_SETTINGS_PATH)

func after_each() -> void:
	if FileAccess.file_exists(TEST_SETTINGS_PATH):
		DirAccess.remove_absolute(TEST_SETTINGS_PATH)

func test_default_camera_distance_is_medium() -> void:
	var settings = GameSettingsScript.new()
	settings.auto_load = false
	add_child_autoqfree(settings)
	assert_eq(settings.get_camera_distance(), CameraMath.Preset.MEDIUM, "Default camera distance must be Medium")
	assert_eq(settings.get_camera_offset(), Vector3(15.0, 20.0, 15.0), "Default camera offset must be (15, 20, 15)")
	assert_eq(settings.get_camera_preset_name(), "Средне", "Default preset name must be 'Средне'")

func test_save_and_load_camera_distance_presets() -> void:
	var settings = GameSettingsScript.new()
	settings.auto_load = false
	add_child_autoqfree(settings)

	# Set Close
	settings.set_camera_distance(CameraMath.Preset.CLOSE, false)
	assert_eq(settings.get_camera_distance(), CameraMath.Preset.CLOSE)
	assert_eq(settings.get_camera_offset(), Vector3(12.0, 16.0, 12.0))
	assert_eq(settings.get_camera_preset_name(), "Близко")

	var saved = settings.save_settings(TEST_SETTINGS_PATH)
	assert_true(saved, "Saving settings to disk should succeed")
	assert_true(FileAccess.file_exists(TEST_SETTINGS_PATH), "Settings file must exist on disk")

	# Load with a new instance
	var settings2 = GameSettingsScript.new()
	settings2.auto_load = false
	add_child_autoqfree(settings2)
	var loaded = settings2.load_settings(TEST_SETTINGS_PATH)
	assert_true(loaded, "Loading settings from disk should succeed")
	assert_eq(settings2.get_camera_distance(), CameraMath.Preset.CLOSE, "Loaded preset should be Close")
	assert_eq(settings2.get_camera_offset(), Vector3(12.0, 16.0, 12.0))

	# Test Far preset
	settings.set_camera_distance(CameraMath.Preset.FAR, false)
	settings.save_settings(TEST_SETTINGS_PATH)
	settings2.load_settings(TEST_SETTINGS_PATH)
	assert_eq(settings2.get_camera_distance(), CameraMath.Preset.FAR, "Loaded preset should be Far")
	assert_eq(settings2.get_camera_offset(), Vector3(18.0, 24.0, 18.0))
	assert_eq(settings2.get_camera_preset_name(), "Далеко")

func test_signal_emitted_on_camera_distance_change() -> void:
	var settings = GameSettingsScript.new()
	settings.auto_load = false
	add_child_autoqfree(settings)

	var signal_received = [false, -1, Vector3.ZERO]
	settings.camera_distance_changed.connect(func(preset: int, offset: Vector3):
		signal_received[0] = true
		signal_received[1] = preset
		signal_received[2] = offset
	)

	settings.set_camera_distance(CameraMath.Preset.CLOSE, false)
	assert_true(signal_received[0], "camera_distance_changed signal must be emitted")
	assert_eq(signal_received[1], CameraMath.Preset.CLOSE)
	assert_eq(signal_received[2], Vector3(12.0, 16.0, 12.0))

func test_corrupt_settings_fallback_to_medium() -> void:
	var file = FileAccess.open(TEST_SETTINGS_PATH, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string("corrupt not json content")
	file.close()

	var settings = GameSettingsScript.new()
	settings.auto_load = false
	add_child_autoqfree(settings)
	var loaded = settings.load_settings(TEST_SETTINGS_PATH)
	assert_false(loaded, "Loading corrupt file should return false")
	assert_eq(settings.get_camera_distance(), CameraMath.Preset.MEDIUM, "Fallback should remain Medium")

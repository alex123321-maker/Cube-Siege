extends GutTest

const SETTINGS = preload("res://scripts/game_settings.gd")
const SETTINGS_PATH: String = "user://demo_audio_settings_test.json"

func after_each() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)
	GameSettings.apply_audio_levels()

func test_audio_settings_round_trip_and_zero_mutes_bus() -> void:
	var settings: Node = SETTINGS.new()
	settings.auto_load = false
	add_child_autofree(settings)
	settings.set_audio_level(&"Music", 0.37, false)
	settings.set_audio_level(&"Ambience", 0.0, false)
	assert_true(AudioServer.is_bus_mute(AudioServer.get_bus_index(&"Ambience")))
	assert_true(settings.save_settings(SETTINGS_PATH))
	var loaded: Node = SETTINGS.new()
	loaded.auto_load = false
	add_child_autofree(loaded)
	assert_true(loaded.load_settings(SETTINGS_PATH))
	assert_almost_eq(loaded.get_audio_level(&"Music"), 0.37, 0.0001)
	assert_eq(loaded.get_audio_level(&"Ambience"), 0.0)

func test_legacy_settings_keep_audio_defaults() -> void:
	var file: FileAccess = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	file.store_string('{"version":1,"camera_distance":0}')
	file.close()
	var settings: Node = SETTINGS.new()
	settings.auto_load = false
	add_child_autofree(settings)
	assert_true(settings.load_settings(SETTINGS_PATH))
	assert_eq(settings.get_camera_distance(), 0)
	assert_eq(settings.get_audio_level(&"Music"), 0.75)

func test_out_of_range_audio_settings_are_clamped() -> void:
	var settings: Node = SETTINGS.new()
	settings.auto_load = false
	add_child_autofree(settings)
	settings.set_audio_level(&"SFX", 9.0, false)
	assert_eq(settings.get_audio_level(&"SFX"), 1.0)
	settings.set_audio_level(&"Music", -1.0, false)
	assert_eq(settings.get_audio_level(&"Music"), 0.0)
	settings.set_audio_level(&"Music", NAN, false)
	assert_eq(settings.get_audio_level(&"Music"), 0.0)

func test_run_audio_loops_and_voice_budget_without_device() -> void:
	var run: RunAudio = RunAudio.new()
	run.playback_enabled = false
	add_child_autofree(run)
	assert_eq(run._voices.size(), RunAudio.VOICE_LIMIT)
	assert_true((run._day_music.stream as AudioStreamOggVorbis).loop)
	assert_true((run._night_music.stream as AudioStreamOggVorbis).loop)
	assert_gt(run._day_music.stream.get_length(), 40.0)
	assert_gt(run._night_music.stream.get_length(), 30.0)
	assert_eq(run._streams.size(), RunAudio.CUES.size())
	EventBus.night_started.emit(1)
	assert_not_null(run._fade)
	run._set_phase(true, true)
	assert_eq(run._day_music.volume_db, RunAudio.SILENCE_DB)
	assert_eq(run._night_music.volume_db, -14.0)
	assert_eq(run._crickets.volume_db, -24.0)
	EventBus.player_died.emit()
	assert_true(run._ended)

func test_terminal_run_keeps_score_fade_when_late_phase_events_arrive() -> void:
	var run: RunAudio = RunAudio.new()
	run.playback_enabled = false
	add_child_autofree(run)
	run.finish_run()
	var ending_fade: Tween = run._fade
	EventBus.day_started.emit(31)
	EventBus.boss_defeated.emit(null)
	run.finish_run()
	assert_true(run._ended)
	assert_eq(run._fade, ending_fade, "Late boss defeat and phase events must not restart terminal music")

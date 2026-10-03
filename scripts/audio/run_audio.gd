class_name RunAudio
extends Node3D

## Run-scoped score, atmosphere and bounded spatial foley. Domain stays silent
## about audio players: presentation requests cues through _event_bus.
const AUDIO_ROOT: String = "res://assets/audio/demo/"
const VOICE_LIMIT: int = 24
const SILENCE_DB: float = -60.0
const AUDIBLE_RADIUS: float = 44.0
const CUES: Dictionary[StringName, String] = {
	&"sword": "sword", &"bow": "bow", &"piercing": "piercing", &"dash": "dash",
	&"hit": "hit", &"hammer": "hammer", &"stone": "stone", &"wood": "wood",
	&"build": "build", &"turret": "turret", &"enemy_attack": "enemy_attack",
	&"explosion": "explosion", &"nuke": "nuke", &"parry": "parry", &"magic": "magic",
	&"level_up": "level_up", &"portal_ready": "portal_ready", &"duel": "duel",
	&"mine_arm": "mine_arm", &"enemy_groan": "enemy_groan", &"boss_roar": "boss_roar",
	&"boss_windup": "boss_windup", &"hurt": "hurt", &"death": "death", &"birds": "birds",
	&"rooster": "rooster", &"footstep_grass": "footstep_grass", &"footstep_stone": "footstep_stone"
}

var _event_bus: Node
var _registry: Node
var player: PlayerPrototype
var cycle: DayNightCycle
var _day_music: AudioStreamPlayer
var _night_music: AudioStreamPlayer
var _leaves: AudioStreamPlayer
var _crickets: AudioStreamPlayer
var _fire: AudioStreamPlayer3D
var _listener: AudioListener3D
var _voices: Array[AudioStreamPlayer3D] = []
var _streams: Dictionary[StringName, AudioStream] = {}
var _last_played: Dictionary[StringName, int] = {}
var _fade: Tween
var _step_distance: float = 0.0
var _last_position: Vector3
var _ambient_timer: float = 7.0
var _fire_timer: float = 0.0
var _ended: bool = false
var _boss_music: bool = false
var _last_health: float = -1.0
var playback_enabled: bool = true

func setup(run_player: PlayerPrototype, run_cycle: DayNightCycle) -> void:
	player = run_player
	cycle = run_cycle

func _ready() -> void:
	_event_bus = get_node("/root/EventBus")
	_registry = get_node("/root/EntityRegistry")
	# Tests exercise events/state without requiring an audio device.
	playback_enabled = playback_enabled and DisplayServer.get_name() != "headless"
	for cue: StringName in CUES:
		_streams[cue] = load(AUDIO_ROOT + CUES[cue] + ".wav") as AudioStream
	_day_music = _add_loop("day_theme", &"Music", -15.0)
	_night_music = _add_loop("night_theme", &"Music", SILENCE_DB)
	_leaves = _add_loop("leaves", &"Ambience", -23.0)
	_crickets = _add_loop("crickets", &"Ambience", SILENCE_DB)
	_listener = AudioListener3D.new()
	add_child(_listener)
	if playback_enabled:
		_listener.make_current()
	for index: int in range(VOICE_LIMIT):
		var voice: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		voice.bus = &"SFX"
		voice.unit_size = 12.0
		voice.max_distance = 65.0
		voice.attenuation_filter_cutoff_hz = 9000.0
		add_child(voice)
		_voices.append(voice)
	_fire = AudioStreamPlayer3D.new()
	_fire.stream = _loop_stream("campfire")
	_fire.bus = &"Ambience"
	_fire.unit_size = 3.0
	_fire.max_distance = 16.0
	_fire.volume_db = -13.0
	add_child(_fire)
	_event_bus.audio_cue_requested.connect(play_cue)
	_event_bus.day_started.connect(_on_day_started)
	_event_bus.night_started.connect(_on_night_started)
	_event_bus.enemy_killed.connect(_on_enemy_killed)
	_event_bus.building_placed.connect(_on_building_placed)
	_event_bus.building_destroyed.connect(_on_building_destroyed)
	_event_bus.resource_gathered.connect(_on_resource_gathered)
	_event_bus.player_health_changed.connect(_on_health_changed)
	_event_bus.player_level_up.connect(_on_level_up)
	_event_bus.player_died.connect(_on_player_died)
	_event_bus.boss_spawned.connect(_on_boss_spawned)
	_event_bus.boss_defeated.connect(_on_boss_defeated)
	_event_bus.portal_repair_complete.connect(_on_portal_ready)
	_event_bus.portal_evacuated.connect(_on_evacuated)
	if is_instance_valid(player):
		_last_position = player.global_position
		_last_health = player.current_health
		player.dash_performed.connect(_on_dash)
	_set_phase(cycle.is_night if is_instance_valid(cycle) else false, true)
	if playback_enabled:
		_day_music.play()
		_night_music.play()
		_leaves.play()
		_crickets.play()

func _loop_stream(name: String) -> AudioStreamOggVorbis:
	var stream: AudioStreamOggVorbis = (load(AUDIO_ROOT + name + ".ogg") as AudioStreamOggVorbis).duplicate() as AudioStreamOggVorbis
	stream.loop = true
	return stream

func _add_loop(name: String, audio_bus: StringName, volume: float) -> AudioStreamPlayer:
	var audio: AudioStreamPlayer = AudioStreamPlayer.new()
	audio.name = name
	audio.stream = _loop_stream(name)
	audio.bus = audio_bus
	audio.volume_db = volume
	add_child(audio)
	return audio

func _process(delta: float) -> void:
	if not is_instance_valid(player) or not player.is_inside_tree():
		return
	_listener.global_position = player.global_position + Vector3.UP
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera:
		_listener.global_basis = camera.global_basis
	var at: Vector3 = player.global_position
	var walked: float = Vector2(at.x - _last_position.x, at.z - _last_position.z).length()
	_last_position = at
	if _ended:
		return
	if player.is_on_floor() and not player.is_dashing and walked < 1.0 and walked > 0.001:
		_step_distance += walked
		if _step_distance >= 1.7:
			_step_distance = fmod(_step_distance, 1.7)
			var map: MapGenerator = get_tree().get_first_node_in_group("map_generator") as MapGenerator
			var stone: bool = map != null and BiomeSystem.sample_biome_weights(at.x, at.z, map.actual_seed)["primary"] == BiomeSystem.BiomeType.MOUNTAINS
			play_cue(&"footstep_stone" if stone else &"footstep_grass", at)
	else:
		_step_distance = 0.0
	_ambient_timer -= delta
	if _ambient_timer <= 0.0:
		_ambient_timer = randf_range(9.0, 18.0)
		if is_instance_valid(cycle) and cycle.is_night:
			var enemies: Array[Node] = _registry.get_enemies()
			if not enemies.is_empty() and enemies[0] is Node3D:
				play_cue(&"enemy_groan", (enemies[0] as Node3D).global_position)
		else:
			play_cue(&"birds", at + Vector3(randf_range(-8, 8), 3, -6))
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		_fire_timer = 0.6
		_update_campfire_audio()

func _update_campfire_audio() -> void:
	var nearest: Node3D
	var nearest_distance: float = 16.0 * 16.0
	for building: Node3D in _registry.get_buildings():
		if not building.is_in_group("campfires"):
			continue
		var distance: float = player.global_position.distance_squared_to(building.global_position)
		if distance < nearest_distance:
			nearest_distance = distance
			nearest = building
	if is_instance_valid(nearest) and playback_enabled:
		_fire.global_position = nearest.global_position + Vector3.UP * 0.3
		if not _fire.playing:
			_fire.play()
	else:
		_fire.stop()

func play_cue(cue: StringName, position: Vector3) -> void:
	if not _streams.has(cue) or not playback_enabled or _ended and cue != &"death" and cue != &"portal_ready":
		return
	if is_instance_valid(player) and Vector2(position.x - player.global_position.x, position.z - player.global_position.z).length() > AUDIBLE_RADIUS:
		return
	var now: int = Time.get_ticks_msec()
	var spacing: int = 140 if cue in [&"hit", &"enemy_attack", &"turret", &"stone"] else 65
	if now - _last_played.get(cue, -10000) < spacing:
		return
	var voice: AudioStreamPlayer3D
	for candidate: AudioStreamPlayer3D in _voices:
		if not candidate.playing:
			voice = candidate
			break
	# Preserve active cues when the budget is exhausted; no unbounded allocations.
	if not voice:
		return
	_last_played[cue] = now
	voice.global_position = position
	voice.stream = _streams[cue]
	voice.pitch_scale = randf_range(0.94, 1.06) if cue not in [&"level_up", &"portal_ready", &"duel"] else 1.0
	voice.volume_db = -7.0
	if cue in [&"footstep_grass", &"footstep_stone", &"birds", &"enemy_groan"]:
		voice.volume_db = -18.0
	elif cue in [&"explosion", &"nuke", &"boss_roar"]:
		voice.volume_db = -4.0
	voice.play()

func _set_phase(night: bool, immediate: bool = false) -> void:
	if _fade and _fade.is_valid():
		_fade.kill()
	var day_db: float = SILENCE_DB if night else -15.0
	var night_db: float = (-11.0 if _boss_music else -14.0) if night else SILENCE_DB
	var leaves_db: float = -30.0 if night else -23.0
	var crickets_db: float = -24.0 if night else SILENCE_DB
	if immediate:
		_day_music.volume_db = day_db
		_night_music.volume_db = night_db
		_leaves.volume_db = leaves_db
		_crickets.volume_db = crickets_db
		return
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(_day_music, "volume_db", day_db, 2.6)
	_fade.tween_property(_night_music, "volume_db", night_db, 2.6)
	_fade.tween_property(_leaves, "volume_db", leaves_db, 2.6)
	_fade.tween_property(_crickets, "volume_db", crickets_db, 2.6)

func _on_day_started(_day: int) -> void:
	_set_phase(false)
	play_cue(&"rooster", player.global_position if is_instance_valid(player) else Vector3.ZERO)

func _on_night_started(_night: int) -> void:
	_set_phase(true)
	play_cue(&"boss_windup", player.global_position if is_instance_valid(player) else Vector3.ZERO)

func _on_dash() -> void:
	play_cue(&"dash", player.global_position)

func _on_enemy_killed(_enemy: Node, at: Vector3) -> void:
	play_cue(&"enemy_groan", at)

func _on_building_placed(_id: String, _cell: Vector2i, building: Node) -> void:
	if building is Node3D:
		play_cue(&"build", (building as Node3D).global_position)

func _on_building_destroyed(_cell: Vector2i, building: Node) -> void:
	if building is Node3D:
		play_cue(&"wood", (building as Node3D).global_position)

func _on_resource_gathered(type: String, _amount: int, gatherer: Node) -> void:
	if gatherer is Node3D:
		play_cue(&"wood" if type.to_upper() == "WOOD" else &"stone", (gatherer as Node3D).global_position)

func _on_health_changed(current: float, _maximum: float) -> void:
	if _last_health >= 0.0 and current < _last_health and is_instance_valid(player):
		play_cue(&"hurt", player.global_position)
	_last_health = current

func _on_level_up(_level: int) -> void:
	play_cue(&"level_up", player.global_position if is_instance_valid(player) else Vector3.ZERO)

func _on_boss_spawned(boss: Node) -> void:
	_boss_music = true
	if boss is Node3D:
		play_cue(&"boss_roar", (boss as Node3D).global_position)
	_set_phase(true)

func _on_boss_defeated(_boss: Node) -> void:
	_boss_music = false
	play_cue(&"level_up", player.global_position if is_instance_valid(player) else Vector3.ZERO)
	_set_phase(cycle.is_night if is_instance_valid(cycle) else true)

func _on_portal_ready() -> void:
	play_cue(&"portal_ready", player.global_position if is_instance_valid(player) else Vector3.ZERO)

func _end_run() -> void:
	_ended = true
	if _fade and _fade.is_valid():
		_fade.kill()
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(_day_music, "volume_db", SILENCE_DB, 1.4)
	_fade.tween_property(_night_music, "volume_db", SILENCE_DB, 1.4)
	_fire.stop()

func _on_player_died() -> void:
	play_cue(&"death", player.global_position if is_instance_valid(player) else Vector3.ZERO)
	_end_run()

func _on_evacuated(_day: int, _xp: int) -> void:
	_on_portal_ready()
	_end_run()

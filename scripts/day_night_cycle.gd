extends Node
class_name DayNightCycle

signal phase_changed(is_night: bool, day_number: int)
signal time_updated(seconds_left: float, total_duration: float, is_night: bool)
signal wave_completed(wave_number: int)

@export var day_duration: float = 30.0
@export var night_duration: float = 120.0 # Upper bound; early nights grow with wave.
@export var escalating_nights: bool = true

@export var sun_light_path: NodePath
@export var world_env_path: NodePath
@export var lighting_profile: LightingProfile = null

var current_day: int = 1
var is_night: bool = false
var time_left: float = 30.0
var running: bool = true
var boss_pending: bool = false
var active_night_duration: float = 22.0

var sun_light: DirectionalLight3D = null
var world_env: WorldEnvironment = null

var _lighting_tween: Tween = null

func _ready() -> void:
	if not lighting_profile:
		lighting_profile = LightingProfile.new()

	if has_node(sun_light_path):
		sun_light = get_node(sun_light_path)
	if has_node(world_env_path):
		world_env = get_node(world_env_path)

	if lighting_profile:
		lighting_profile.apply_base_setup(sun_light, world_env)

	time_left = day_duration
	is_night = false
	apply_lighting_state()
func _process(delta: float) -> void:
	if not running:
		return
	time_left = maxf(0.0, time_left - delta)
	var total_duration: float = active_night_duration if is_night else day_duration
	emit_signal("time_updated", time_left, total_duration, is_night)
	var eb = get_node_or_null("/root/EventBus")
	if eb and eb.has_signal("cycle_time_updated"):
		eb.cycle_time_updated.emit(time_left, total_duration, is_night, current_day)
	update_ambient_lighting(delta)

	if time_left <= 0.0:
		if not is_night:
			start_night()
		elif not boss_pending:
			complete_night()

func start_night() -> void:
	if not running or is_night:
		return
	is_night = true
	boss_pending = current_day % 5 == 0
	active_night_duration = get_night_duration(current_day)
	time_left = active_night_duration
	emit_signal("phase_changed", true, current_day)
	var eb = get_node_or_null("/root/EventBus")
	if eb and eb.has_signal("night_started"):
		eb.night_started.emit(current_day)
	transition_lighting(true)

func start_day() -> void:
	is_night = false
	boss_pending = false
	current_day += 1
	time_left = day_duration
	emit_signal("phase_changed", false, current_day)
	var eb = get_node_or_null("/root/EventBus")
	if eb and eb.has_signal("day_started"):
		eb.day_started.emit(current_day)
	transition_lighting(false)

func get_night_duration(wave: int) -> float:
	return minf(night_duration, 20.0 + float(wave) * 2.0) if escalating_nights else night_duration

func complete_night() -> void:
	if not running or not is_night or boss_pending:
		return
	wave_completed.emit(current_day)
	var bus: Node = get_node_or_null("/root/EventBus")
	if bus:
		bus.wave_cleared.emit(current_day)
	if running and current_day < 30:
		start_day()
	else:
		running = false

func finish_boss_night(wave: int) -> bool:
	if not running or not is_night or not boss_pending or wave != current_day:
		return false
	boss_pending = false
	complete_night()
	return true

func stop() -> void:
	running = false

func skip_to_night() -> void:
	if not is_night:
		start_night()

func transition_lighting(to_night: bool) -> void:
	if not sun_light:
		return
	if is_instance_valid(_lighting_tween) and _lighting_tween.is_running():
		_lighting_tween.kill()
	if not lighting_profile:
		lighting_profile = LightingProfile.new()
	_lighting_tween = lighting_profile.create_transition_tween(self, sun_light, world_env, to_night, 3.0)

func update_ambient_lighting(_delta: float) -> void:
	if not is_night and time_left <= 30.0 and sun_light:
		# If a transition tween is running, let it complete
		if is_instance_valid(_lighting_tween) and _lighting_tween.is_running():
			return
		# Gradual sunset shift in last 30 seconds of day
		var sunset_t: float = 1.0 - (time_left / 30.0)
		if lighting_profile:
			lighting_profile.apply_sunset_lerp(sun_light, world_env, sunset_t)

func apply_lighting_state() -> void:
	if is_instance_valid(_lighting_tween) and _lighting_tween.is_running():
		_lighting_tween.kill()
	if not lighting_profile:
		lighting_profile = LightingProfile.new()
	if is_night:
		lighting_profile.apply_night_instant(sun_light, world_env)
	else:
		lighting_profile.apply_day_instant(sun_light, world_env)

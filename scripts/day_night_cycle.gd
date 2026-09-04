extends Node
class_name DayNightCycle

signal phase_changed(is_night: bool, day_number: int)
signal time_updated(seconds_left: float, total_duration: float, is_night: bool)

@export var day_duration: float = 180.0    # 180s (3 min) — GDD v1.2.0
@export var night_duration: float = 120.0  # 120s (2 min) siege — GDD v1.2.0

@export var sun_light_path: NodePath
@export var world_env_path: NodePath

var current_day: int = 1
var is_night: bool = false
var time_left: float = 180.0

var sun_light: DirectionalLight3D = null
var world_env: WorldEnvironment = null

# Colors for day/sunset/night
const COLOR_DAY_SUN = Color(1.0, 0.96, 0.9, 1.0)
const COLOR_SUNSET_SUN = Color(1.0, 0.45, 0.15, 1.0)
const COLOR_NIGHT_MOON = Color(0.25, 0.35, 0.6, 1.0)

const COLOR_DAY_SKY = Color(0.35, 0.55, 0.85, 1.0)
const COLOR_NIGHT_SKY = Color(0.04, 0.05, 0.12, 1.0)

func _ready() -> void:
	if has_node(sun_light_path):
		sun_light = get_node(sun_light_path)
	if has_node(world_env_path):
		world_env = get_node(world_env_path)

	time_left = day_duration
	is_night = false
	apply_lighting_state()

func _process(delta: float) -> void:
	time_left -= delta
	var total_duration: float = night_duration if is_night else day_duration
	emit_signal("time_updated", time_left, total_duration, is_night)
	if get_node_or_null("/root/EventBus"):
		EventBus.cycle_time_updated.emit(time_left, total_duration, is_night, current_day)
	update_ambient_lighting(delta)

	if time_left <= 0.0:
		if not is_night:
			start_night()
		else:
			start_day()

func start_night() -> void:
	is_night = true
	time_left = night_duration
	emit_signal("phase_changed", true, current_day)
	if get_node_or_null("/root/EventBus"):
		EventBus.night_started.emit(current_day)
	transition_lighting(true)

func start_day() -> void:
	is_night = false
	current_day += 1
	var roster = get_node_or_null("/root/RosterManager")
	if roster and roster.has_method("get_active_character"):
		var c = roster.get_active_character()
		if current_day > c.max_day:
			c.max_day = current_day
			roster.save_roster()
	time_left = day_duration
	emit_signal("phase_changed", false, current_day)
	if get_node_or_null("/root/EventBus"):
		EventBus.day_started.emit(current_day)
	transition_lighting(false)

func skip_to_night() -> void:
	if not is_night:
		start_night()


func transition_lighting(to_night: bool) -> void:
	if not sun_light:
		return

	var tween: Tween = create_tween()
	tween.set_parallel(true)

	if to_night:
		# Sunset to Moon
		tween.tween_property(sun_light, "light_color", COLOR_NIGHT_MOON, 3.0)
		tween.tween_property(sun_light, "light_energy", 0.3, 3.0)
		if world_env and world_env.environment:
			tween.tween_property(world_env.environment, "ambient_light_energy", 0.25, 3.0)
	else:
		# Sunrise to Day
		tween.tween_property(sun_light, "light_color", COLOR_DAY_SUN, 3.0)
		tween.tween_property(sun_light, "light_energy", 1.0, 3.0)
		if world_env and world_env.environment:
			tween.tween_property(world_env.environment, "ambient_light_energy", 1.0, 3.0)

func update_ambient_lighting(_delta: float) -> void:
	if not is_night and time_left <= 30.0 and sun_light:
		# Gradual sunset shift in last 20 seconds of day
		var sunset_t: float = 1.0 - (time_left / 30.0)
		sun_light.light_color = COLOR_DAY_SUN.lerp(COLOR_SUNSET_SUN, sunset_t)
		sun_light.light_energy = lerp(1.0, 0.6, sunset_t)

func apply_lighting_state() -> void:
	if sun_light:
		sun_light.light_color = COLOR_DAY_SUN
		sun_light.light_energy = 1.0
	if world_env and world_env.environment:
		world_env.environment.ambient_light_energy = 1.0

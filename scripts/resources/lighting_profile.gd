extends Resource
class_name LightingProfile

## Centralized data-driven configuration for lighting, shadows, and WorldEnvironment.
## Controls Forward+ directional shadows, SSAO, depth fog, HDR glow, and day/sunset/night states.

# ------------------------------------------------------------------------------
# Directional Light & Shadow Settings (Forward+)
# ------------------------------------------------------------------------------
@export_group("Directional Light & Shadows")
@export var light_rotation_degrees: Vector3 = Vector3(-64.0, 28.0, 0.0)
@export var shadow_enabled: bool = true
@export var shadow_bias: float = 0.03
@export var shadow_normal_bias: float = 2.0
@export var shadow_blur: float = 1.2
@export var shadow_max_distance: float = 70.0
@export var shadow_mode: int = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
@export var shadow_split_1: float = 0.12
@export var shadow_split_2: float = 0.28
@export var shadow_split_3: float = 0.55
@export var shadow_blend_splits: bool = true
@export var shadow_fade_start: float = 0.8

# ------------------------------------------------------------------------------
# WorldEnvironment: Tonemap & Post-Processing
# ------------------------------------------------------------------------------
@export_group("Tonemap & Camera")
@export var tonemap_mode: int = Environment.TONE_MAPPER_ACES
@export var tonemap_exposure: float = 1.10

@export_group("SSAO (Screen Space Ambient Occlusion)")
@export var ssao_enabled: bool = true
@export var ssao_radius: float = 1.0
@export var ssao_intensity: float = 1.4
@export var ssao_power: float = 1.5
@export var ssao_detail: float = 0.5
@export var ssao_horizon: float = 0.06
@export var ssao_sharpness: float = 0.98
@export var ssao_light_affect: float = 0.20

@export_group("Depth Fog")
@export var fog_enabled: bool = true
@export var fog_mode: int = Environment.FOG_MODE_DEPTH
@export var fog_depth_begin: float = 40.0
@export var fog_depth_end: float = 110.0
@export var fog_depth_curve: float = 1.2

@export_group("Glow (HDR)")
@export var glow_enabled: bool = true
@export var glow_normalized: bool = true
@export var glow_intensity: float = 0.35
@export var glow_bloom: float = 0.12
@export var glow_hdr_threshold: float = 1.0

# ------------------------------------------------------------------------------
# Phase: Day
# ------------------------------------------------------------------------------
@export_group("Phase: Day")
@export var day_sun_color: Color = Color(1.0, 0.96, 0.90, 1.0)
@export var day_sun_energy: float = 1.05
@export var day_ambient_color: Color = Color(0.68, 0.76, 0.88, 1.0)
@export var day_ambient_energy: float = 0.82
@export var day_fog_color: Color = Color(0.62, 0.72, 0.86, 1.0)
@export var day_fog_energy: float = 0.85
@export var day_sky_top: Color = Color(0.26, 0.50, 0.86, 1.0)
@export var day_sky_horizon: Color = Color(0.66, 0.76, 0.88, 1.0)
@export var day_ground_bottom: Color = Color(0.15, 0.18, 0.22, 1.0)
@export var day_ground_horizon: Color = Color(0.58, 0.68, 0.78, 1.0)

# ------------------------------------------------------------------------------
# Phase: Sunset
# ------------------------------------------------------------------------------
@export_group("Phase: Sunset")
@export var sunset_sun_color: Color = Color(1.0, 0.55, 0.22, 1.0)
@export var sunset_sun_energy: float = 0.75
@export var sunset_ambient_color: Color = Color(0.58, 0.46, 0.60, 1.0)
@export var sunset_ambient_energy: float = 0.62
@export var sunset_fog_color: Color = Color(0.72, 0.46, 0.35, 1.0)
@export var sunset_fog_energy: float = 0.80
@export var sunset_sky_top: Color = Color(0.18, 0.24, 0.52, 1.0)
@export var sunset_sky_horizon: Color = Color(0.92, 0.52, 0.32, 1.0)
@export var sunset_ground_bottom: Color = Color(0.10, 0.12, 0.15, 1.0)
@export var sunset_ground_horizon: Color = Color(0.48, 0.35, 0.28, 1.0)

# ------------------------------------------------------------------------------
# Phase: Night
# ------------------------------------------------------------------------------
@export_group("Phase: Night")
@export var night_sun_color: Color = Color(0.58, 0.72, 0.96, 1.0)
@export var night_sun_energy: float = 0.40
@export var night_ambient_color: Color = Color(0.28, 0.38, 0.56, 1.0)
@export var night_ambient_energy: float = 0.48
@export var night_fog_color: Color = Color(0.08, 0.12, 0.24, 1.0)
@export var night_fog_energy: float = 0.60
@export var night_sky_top: Color = Color(0.02, 0.04, 0.10, 1.0)
@export var night_sky_horizon: Color = Color(0.08, 0.14, 0.26, 1.0)
@export var night_ground_bottom: Color = Color(0.01, 0.02, 0.04, 1.0)
@export var night_ground_horizon: Color = Color(0.06, 0.10, 0.18, 1.0)

# ------------------------------------------------------------------------------
# Application Methods
# ------------------------------------------------------------------------------

func apply_base_setup(sun: DirectionalLight3D, env_node: WorldEnvironment) -> void:
	if sun:
		sun.rotation_degrees = light_rotation_degrees
		sun.shadow_enabled = shadow_enabled
		sun.shadow_bias = shadow_bias
		sun.shadow_normal_bias = shadow_normal_bias
		sun.shadow_blur = shadow_blur
		sun.directional_shadow_max_distance = shadow_max_distance
		sun.directional_shadow_mode = shadow_mode as DirectionalLight3D.ShadowMode
		sun.directional_shadow_split_1 = shadow_split_1
		sun.directional_shadow_split_2 = shadow_split_2
		sun.directional_shadow_split_3 = shadow_split_3
		sun.directional_shadow_blend_splits = shadow_blend_splits
		sun.directional_shadow_fade_start = shadow_fade_start

	if env_node and env_node.environment:
		var env: Environment = env_node.environment
		env.background_mode = Environment.BG_SKY
		env.tonemap_mode = tonemap_mode as Environment.ToneMapper
		env.tonemap_exposure = tonemap_exposure

		# Ambient Light
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR

		# SSAO
		env.ssao_enabled = ssao_enabled
		env.ssao_radius = ssao_radius
		env.ssao_intensity = ssao_intensity
		env.ssao_power = ssao_power
		env.ssao_detail = ssao_detail
		env.ssao_horizon = ssao_horizon
		env.ssao_sharpness = ssao_sharpness
		env.ssao_light_affect = ssao_light_affect

		# Depth Fog
		env.fog_enabled = fog_enabled
		env.fog_mode = fog_mode as Environment.FogMode
		env.fog_depth_begin = fog_depth_begin
		env.fog_depth_end = fog_depth_end
		env.fog_depth_curve = fog_depth_curve

		# Glow
		env.glow_enabled = glow_enabled
		env.glow_normalized = glow_normalized
		env.glow_intensity = glow_intensity
		env.glow_bloom = glow_bloom
		env.glow_hdr_threshold = glow_hdr_threshold

func apply_day_instant(sun: DirectionalLight3D, env_node: WorldEnvironment) -> void:
	if sun:
		sun.light_color = day_sun_color
		sun.light_energy = day_sun_energy

	if env_node and env_node.environment:
		var env: Environment = env_node.environment
		env.ambient_light_color = day_ambient_color
		env.ambient_light_energy = day_ambient_energy
		env.fog_light_color = day_fog_color
		env.fog_light_energy = day_fog_energy
		_apply_sky_colors(env, day_sky_top, day_sky_horizon, day_ground_bottom, day_ground_horizon)

func apply_night_instant(sun: DirectionalLight3D, env_node: WorldEnvironment) -> void:
	if sun:
		sun.light_color = night_sun_color
		sun.light_energy = night_sun_energy

	if env_node and env_node.environment:
		var env: Environment = env_node.environment
		env.ambient_light_color = night_ambient_color
		env.ambient_light_energy = night_ambient_energy
		env.fog_light_color = night_fog_color
		env.fog_light_energy = night_fog_energy
		_apply_sky_colors(env, night_sky_top, night_sky_horizon, night_ground_bottom, night_ground_horizon)

func apply_sunset_lerp(sun: DirectionalLight3D, env_node: WorldEnvironment, t: float) -> void:
	var ct: float = clampf(t, 0.0, 1.0)
	if sun:
		sun.light_color = day_sun_color.lerp(sunset_sun_color, ct)
		sun.light_energy = lerpf(day_sun_energy, sunset_sun_energy, ct)

	if env_node and env_node.environment:
		var env: Environment = env_node.environment
		env.ambient_light_color = day_ambient_color.lerp(sunset_ambient_color, ct)
		env.ambient_light_energy = lerpf(day_ambient_energy, sunset_ambient_energy, ct)
		env.fog_light_color = day_fog_color.lerp(sunset_fog_color, ct)
		env.fog_light_energy = lerpf(day_fog_energy, sunset_fog_energy, ct)
		_apply_sky_colors(
			env,
			day_sky_top.lerp(sunset_sky_top, ct),
			day_sky_horizon.lerp(sunset_sky_horizon, ct),
			day_ground_bottom.lerp(sunset_ground_bottom, ct),
			day_ground_horizon.lerp(sunset_ground_horizon, ct)
		)

func create_transition_tween(
	caller: Node,
	sun: DirectionalLight3D,
	env_node: WorldEnvironment,
	to_night: bool,
	duration: float = 3.0
) -> Tween:
	if not caller or not caller.is_inside_tree():
		return null

	var tween: Tween = caller.create_tween()
	tween.set_parallel(true)

	var target_sun_color: Color = night_sun_color if to_night else day_sun_color
	var target_sun_energy: float = night_sun_energy if to_night else day_sun_energy
	var target_ambient_color: Color = night_ambient_color if to_night else day_ambient_color
	var target_ambient_energy: float = night_ambient_energy if to_night else day_ambient_energy
	var target_fog_color: Color = night_fog_color if to_night else day_fog_color
	var target_fog_energy: float = night_fog_energy if to_night else day_fog_energy

	var target_sky_top: Color = night_sky_top if to_night else day_sky_top
	var target_sky_horizon: Color = night_sky_horizon if to_night else day_sky_horizon
	var target_ground_bottom: Color = night_ground_bottom if to_night else day_ground_bottom
	var target_ground_horizon: Color = night_ground_horizon if to_night else day_ground_horizon

	if sun:
		tween.tween_property(sun, "light_color", target_sun_color, duration)
		tween.tween_property(sun, "light_energy", target_sun_energy, duration)

	if env_node and env_node.environment:
		var env: Environment = env_node.environment
		tween.tween_property(env, "ambient_light_color", target_ambient_color, duration)
		tween.tween_property(env, "ambient_light_energy", target_ambient_energy, duration)
		tween.tween_property(env, "fog_light_color", target_fog_color, duration)
		tween.tween_property(env, "fog_light_energy", target_fog_energy, duration)

		var sky_mat: ProceduralSkyMaterial = _get_procedural_sky(env)
		if sky_mat:
			tween.tween_property(sky_mat, "sky_top_color", target_sky_top, duration)
			tween.tween_property(sky_mat, "sky_horizon_color", target_sky_horizon, duration)
			tween.tween_property(sky_mat, "ground_bottom_color", target_ground_bottom, duration)
			tween.tween_property(sky_mat, "ground_horizon_color", target_ground_horizon, duration)

	return tween

func _get_procedural_sky(env: Environment) -> ProceduralSkyMaterial:
	if env and env.sky and env.sky.sky_material is ProceduralSkyMaterial:
		return env.sky.sky_material as ProceduralSkyMaterial
	return null

func _apply_sky_colors(
	env: Environment,
	top: Color,
	horizon: Color,
	ground_bot: Color,
	ground_horiz: Color
) -> void:
	var sky_mat: ProceduralSkyMaterial = _get_procedural_sky(env)
	if sky_mat:
		sky_mat.sky_top_color = top
		sky_mat.sky_horizon_color = horizon
		sky_mat.ground_bottom_color = ground_bot
		sky_mat.ground_horizon_color = ground_horiz

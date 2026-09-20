extends GutTest

## Unit tests for LightingProfile resource and data-driven parameters.

var profile: LightingProfile
var sun: DirectionalLight3D
var env_node: WorldEnvironment
var env: Environment

func before_each() -> void:
	profile = LightingProfile.new()
	sun = DirectionalLight3D.new()
	add_child_autoqfree(sun)

	env_node = WorldEnvironment.new()
	env = Environment.new()
	var sky = Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	env.sky = sky
	env_node.environment = env
	add_child_autoqfree(env_node)

func test_lighting_profile_defaults() -> void:
	assert_true(profile.shadow_enabled, "Shadows should be enabled by default")
	assert_eq(profile.shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "Default shadow mode should be 4 splits")
	assert_almost_eq(profile.shadow_bias, 0.03, 0.001, "Shadow bias should be 0.03 to eliminate peter-panning")
	assert_almost_eq(profile.shadow_normal_bias, 2.0, 0.001, "Normal bias should be 2.0 to eliminate surface acne")
	assert_true(profile.shadow_blend_splits, "Blend splits must be enabled to prevent cascade seam popping")
	assert_gt(profile.shadow_max_distance, 60.0, "Shadow max distance must cover isometric frustum")

	assert_eq(profile.tonemap_mode, Environment.TONE_MAPPER_ACES, "Tonemapper should be ACES for stylized color handling")
	assert_true(profile.ssao_enabled, "SSAO must be enabled for volumetric contact cues")
	assert_true(profile.fog_enabled, "Depth fog must be enabled for atmospheric horizon depth")
	assert_true(profile.glow_enabled, "HDR glow must be enabled for emissive VFX/UI")
	assert_almost_eq(profile.glow_hdr_threshold, 1.0, 0.01, "Glow threshold should prevent normal terrain from blooming")

func test_apply_base_setup() -> void:
	profile.apply_base_setup(sun, env_node)

	assert_almost_eq(sun.rotation_degrees.x, profile.light_rotation_degrees.x, 0.01)
	assert_almost_eq(sun.rotation_degrees.y, profile.light_rotation_degrees.y, 0.01)
	assert_true(sun.shadow_enabled)
	assert_eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS)
	assert_true(sun.directional_shadow_blend_splits)
	assert_almost_eq(sun.directional_shadow_max_distance, profile.shadow_max_distance, 0.01)

	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_ACES)
	assert_true(env.ssao_enabled)
	assert_almost_eq(env.ssao_radius, profile.ssao_radius, 0.01)
	assert_almost_eq(env.ssao_intensity, profile.ssao_intensity, 0.01)
	assert_true(env.fog_enabled)
	assert_eq(env.fog_mode, Environment.FOG_MODE_DEPTH)
	assert_true(env.glow_enabled)

func test_apply_day_instant() -> void:
	profile.apply_base_setup(sun, env_node)
	profile.apply_day_instant(sun, env_node)

	assert_almost_eq(sun.light_color.r, profile.day_sun_color.r, 0.01)
	assert_almost_eq(sun.light_color.g, profile.day_sun_color.g, 0.01)
	assert_almost_eq(sun.light_color.b, profile.day_sun_color.b, 0.01)
	assert_almost_eq(sun.light_energy, profile.day_sun_energy, 0.01)
	assert_almost_eq(env.ambient_light_energy, profile.day_ambient_energy, 0.01)
	assert_almost_eq(env.fog_light_energy, profile.day_fog_energy, 0.01)

func test_apply_night_instant() -> void:
	profile.apply_base_setup(sun, env_node)
	profile.apply_night_instant(sun, env_node)

	assert_almost_eq(sun.light_color.r, profile.night_sun_color.r, 0.01)
	assert_almost_eq(sun.light_color.g, profile.night_sun_color.g, 0.01)
	assert_almost_eq(sun.light_color.b, profile.night_sun_color.b, 0.01)
	assert_almost_eq(sun.light_energy, profile.night_sun_energy, 0.01)
	assert_almost_eq(env.ambient_light_energy, profile.night_ambient_energy, 0.01)
	assert_almost_eq(env.fog_light_energy, profile.night_fog_energy, 0.01)

func test_apply_sunset_lerp() -> void:
	profile.apply_base_setup(sun, env_node)

	# Midpoint lerp t = 0.5
	profile.apply_sunset_lerp(sun, env_node, 0.5)
	var expected_energy: float = lerpf(profile.day_sun_energy, profile.sunset_sun_energy, 0.5)
	assert_almost_eq(sun.light_energy, expected_energy, 0.01)

	var expected_ambient: float = lerpf(profile.day_ambient_energy, profile.sunset_ambient_energy, 0.5)
	assert_almost_eq(env.ambient_light_energy, expected_ambient, 0.01)

func test_create_transition_tween() -> void:
	profile.apply_base_setup(sun, env_node)
	var tween: Tween = profile.create_transition_tween(self, sun, env_node, true, 1.0)
	assert_not_null(tween, "Transition tween should be created successfully")
	assert_true(tween.is_running(), "Tween should be running")
	tween.kill()

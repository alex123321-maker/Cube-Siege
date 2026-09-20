extends GutTest

## Integration tests for Issue #24: Lighting, shadows, and WorldEnvironment.

const MAIN_SCENE_PATH = "res://scenes/main.tscn"

func test_main_scene_lighting_and_environment_wiring() -> void:
	var main_res = load(MAIN_SCENE_PATH)
	assert_not_null(main_res, "main.tscn must exist and load cleanly")

	var main = main_res.instantiate()
	add_child_autoqfree(main)

	var sun: DirectionalLight3D = main.get_node_or_null("SunLight") as DirectionalLight3D
	assert_not_null(sun, "SunLight node must exist in main.tscn")
	assert_true(sun.shadow_enabled, "SunLight must have shadows enabled")
	assert_gt(sun.directional_shadow_max_distance, 60.0, "Shadow max distance must be >= 60.0m")
	assert_eq(sun.directional_shadow_mode, DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS, "Directional shadow must use 4 cascades")
	assert_true(sun.directional_shadow_blend_splits, "Blend splits must be enabled")
	assert_lt(sun.rotation_degrees.x, -50.0, "Sun elevation pitch must be steep enough for 3D step readability")
	assert_ne(sun.rotation_degrees.y, 0.0, "Sun azimuth must be asymmetric relative to isometric axes")

	var world_env: WorldEnvironment = main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	assert_not_null(world_env, "WorldEnvironment node must exist in main.tscn")
	assert_not_null(world_env.environment, "WorldEnvironment must define an Environment resource")

	var env: Environment = world_env.environment
	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_ACES, "ACES Tonemapper must be active")
	assert_true(env.ssao_enabled, "SSAO must be enabled in main environment")
	assert_true(env.fog_enabled, "Fog must be enabled in main environment")
	assert_eq(env.fog_mode, Environment.FOG_MODE_DEPTH, "Fog mode must be depth fog")
	assert_true(env.glow_enabled, "HDR glow must be enabled")

func test_day_night_cycle_gameplay_timings_preserved() -> void:
	var cycle: DayNightCycle = DayNightCycle.new()
	add_child_autoqfree(cycle)

	assert_almost_eq(cycle.day_duration, 180.0, 0.001, "Day duration must remain 180s (GDD canonical)")
	assert_almost_eq(cycle.night_duration, 120.0, 0.001, "Night duration must remain 120s (GDD canonical)")
	assert_false(cycle.is_night, "DayNightCycle must start at day")

func test_day_night_cycle_transitions_profile() -> void:
	var main_res = load(MAIN_SCENE_PATH)
	var main = main_res.instantiate()
	add_child_autoqfree(main)

	var cycle: DayNightCycle = main.get_node_or_null("DayNightCycle") as DayNightCycle
	var sun: DirectionalLight3D = main.get_node_or_null("SunLight") as DirectionalLight3D
	var world_env: WorldEnvironment = main.get_node_or_null("WorldEnvironment") as WorldEnvironment

	assert_not_null(cycle, "DayNightCycle must exist")
	assert_not_null(cycle.lighting_profile, "DayNightCycle must possess a LightingProfile")

	# Initial day state
	cycle.apply_lighting_state()
	assert_almost_eq(sun.light_energy, cycle.lighting_profile.day_sun_energy, 0.01)

	# Transition to night
	cycle.start_night()
	assert_true(cycle.is_night)
	assert_eq(cycle.time_left, cycle.night_duration)

	# Transition to day
	cycle.start_day()
	assert_false(cycle.is_night)
	assert_eq(cycle.time_left, cycle.day_duration)

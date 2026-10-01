extends GutTest

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

var arena: AbilityLabArena

func before_each() -> void:
	arena = AbilityLabArena.new()
	add_child_autoqfree(arena)
	arena.paused = true
	await wait_physics_frames(2)

func _definition() -> AbilityDefinition:
	var definition: AbilityDefinition = AbilityLibrary.examples()[0]
	definition.steps[0].start = 0.0
	return definition

func test_sector_uses_real_enemy_health_and_excludes_targets_behind() -> void:
	assert_true(arena.play(_definition()))
	arena.runner.advance(0.3)
	assert_eq(arena.targets[0].current_health, 440.0)
	assert_eq(arena.targets[1].current_health, 440.0)
	assert_eq(arena.targets[3].current_health, 500.0)
	assert_false(arena.runner.running)

func test_repeat_policy_and_reentrant_cast_rejection() -> void:
	var definition: AbilityDefinition = _definition()
	definition.steps[0].duration = 0.5
	definition.steps[0].repeat_interval = 0.25
	assert_true(arena.play(definition))
	assert_false(arena.play(definition))
	arena.runner.advance(0.5)
	assert_eq(arena.targets[0].current_health, 380.0)
	assert_false(arena.play(definition), "Cooldown remains after completion")

func test_cancel_removes_future_hits_and_motion() -> void:
	var definition: AbilityDefinition = AbilityLibrary.examples()[1]
	assert_true(arena.play(definition))
	arena.runner.advance(0.1)
	var position_before: Vector3 = arena.actor.position
	arena.runner.cancel()
	arena.runner.advance(0.5)
	assert_eq(arena.actor.position, position_before)
	assert_eq(arena.targets[0].current_health, 500.0)

func test_running_cast_has_a_snapshot_of_authored_parameters() -> void:
	var definition: AbilityDefinition = _definition()
	assert_true(arena.play(definition))
	definition.steps[0].damage = 999.0
	arena.runner.advance(0.3)
	assert_eq(arena.targets[0].current_health, 440.0)

func test_terrain_and_world_obstacles_explain_rejections() -> void:
	arena.scenario = 1
	arena.reset()
	await wait_physics_frames(2)
	var definition: AbilityDefinition = _definition()
	definition.steps[0].radius = 4.0
	assert_true(arena.play(definition))
	arena.runner.advance(0.3)
	assert_eq(arena.targets[0].current_health, 500.0)
	var reasons: String = ""
	for event: AbilityTrace in arena.runner.traces:
		reasons += event.reason
	assert_string_contains(reasons, "Препятствие")
	arena.scenario = 2
	arena.reset()
	await wait_physics_frames(2)
	assert_true(arena.play(definition))
	arena.runner.advance(0.3)
	assert_eq(arena.targets[0].current_health, 500.0)

func test_owner_death_cancels_and_drafts_require_explicit_lab_mode() -> void:
	var definition: AbilityDefinition = _definition()
	assert_false(arena.runner.start_cast(definition, arena.actor, Vector3.FORWARD))
	assert_true(arena.play(definition))
	arena.runner.alive_predicate = func() -> bool: return false
	arena.runner.advance(0.1)
	assert_false(arena.runner.running)
	assert_eq(arena.targets[0].current_health, 500.0)

func test_editor_opens_and_rebuilds_after_undo() -> void:
	var lab: AbilityLab = load("res://scenes/tools/ability_lab.tscn").instantiate() as AbilityLab
	add_child_autoqfree(lab)
	await wait_physics_frames(2)
	assert_not_null(lab.arena)
	lab.document.checkpoint()
	lab.document.definition.steps[0].radius = 4.0
	lab.document.undo()
	assert_eq(lab.document.definition.steps[0].radius, 2.5)
	assert_true(lab.arena.play(lab.document.definition))

func test_opt_in_player_uses_the_same_runner_and_cancels_on_dash() -> void:
	var player: CharacterBody3D = PLAYER_SCENE.instantiate() as CharacterBody3D
	add_child_autoqfree(player)
	player.set_physics_process(false)
	player.global_position = arena.actor.global_position
	player.constructed_special = _definition()
	player.constructed_special.draft = false
	player.orientation.aim_direction = Vector3.FORWARD
	player.orientation.body_facing_direction = Vector3.FORWARD
	player.perform_special_attack()
	assert_true(player.constructed_runner.running)
	player.constructed_runner.advance(0.1)
	assert_eq(arena.targets[0].current_health, 440.0)
	assert_almost_eq(player.special_cooldown_timer, 3.9, 0.0001)
	player.perform_dash()
	assert_false(player.constructed_runner.running)

func test_temporal_boundaries_preserve_motion_distance() -> void:
	var definition: AbilityDefinition = AbilityDefinition.new()
	var move: AbilityStep = AbilityStep.new()
	move.kind = AbilityStep.Kind.MOVE
	move.start = 0.017
	move.duration = 0.137
	move.distance = 1.0
	definition.steps.append(move)
	assert_true(arena.play(definition))
	arena.runner.advance(0.2)
	assert_almost_eq(arena.actor.position.z, 0.0, 0.0001)
	assert_almost_eq(arena.runner.elapsed, 0.154, 0.0001)
	assert_true(arena.runner.moved_this_advance, "Motion ownership includes the final partial tick")

func test_moving_area_hits_targets_along_path_not_only_at_endpoint() -> void:
	var definition: AbilityDefinition = AbilityLibrary.examples()[1]
	definition.steps[0].start = 0.0
	definition.steps[0].radius = 0.8
	definition.steps[0].duration = 0.5
	definition.modifiers[1].action.duration = 0.5
	definition.modifiers[1].action.distance = 4.0
	assert_true(arena.play(definition))
	arena.runner.advance(0.5)
	assert_eq(arena.targets[0].current_health, 440.0)
	assert_almost_eq(arena.actor.position.z, -3.0, 0.0001)
	assert_false(arena.runner.running)

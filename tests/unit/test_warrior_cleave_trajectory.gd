extends GutTest

## Regression: a target can enter broad phase before its centre enters the sector.
## It must still be hit later during the moving active window, and only once.
const PLAYER: PackedScene = preload("res://scenes/player.tscn")
const ENEMY: PackedScene = preload("res://scenes/enemy_dummy.tscn")
const TALENT_VFX: Script = preload("res://scripts/effects/warrior/warrior_talent_vfx.gd")

class MovementDriver:
	extends Node
	var actor: PlayerPrototype
	var last_delta: float = 0.0
	func _physics_process(delta: float) -> void:
		last_delta = delta
		actor.movement.update_timers(delta)
		actor.combat.update_timers(delta)
		actor.movement.process_movement(actor, delta, null, 1.0, Vector3.FORWARD)
		actor.presentation.update_animations(actor, false, false, delta, actor.orientation)

var _world: Node3D
var _player: PlayerPrototype
var _ticks_before: int
var _driver: MovementDriver

func after_each() -> void:
	get_tree().paused = false
	Engine.physics_ticks_per_second = _ticks_before

func before_each() -> void:
	_ticks_before = Engine.physics_ticks_per_second
	_world = Node3D.new()
	add_child_autoqfree(_world)
	var floor: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(30.0, 0.4, 30.0)
	shape.shape = box
	floor.add_child(shape)
	floor.position.y = -0.2
	_world.add_child(floor)
	_player = PLAYER.instantiate() as PlayerPrototype
	_world.add_child(_player)
	_player.set_physics_process(false)
	_player.input_enabled = false
	_player.talents.reset_for_viewer(WarriorTalentCatalog.TALENT_IDS)
	_player.talents.build().selected_talents.assign(["whirlwind_cleave", "wide_lunge"])
	_player.talents.build().specializations["cleave_radius"] = 3
	_player.talents.refresh_stats()
	_player.global_position = Vector3(0.0, 0.9, 0.0)
	_player.orientation.setup(Vector3.FORWARD)
	_driver = MovementDriver.new()
	_driver.actor = _player
	_world.add_child(_driver)
	await get_tree().physics_frame

func _use_ten_physics_ticks() -> void:
	Engine.physics_ticks_per_second = 10
	for frame: int in range(12):
		await get_tree().physics_frame
		await get_tree().process_frame
		if is_equal_approx(_driver.last_delta, 0.1):
			return
	assert_almost_eq(_driver.last_delta, 0.1, 0.001, "The physics timestep is stable before measuring displacement")

func _target(position: Vector3) -> EnemyBase:
	var enemy: EnemyBase = ENEMY.instantiate() as EnemyBase
	_world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = position
	enemy.max_health = 1000.0
	enemy.current_health = 1000.0
	return enemy

func test_whirlwind_hits_target_later_on_lunge_trajectory_once_and_restores_spin() -> void:
	var late: EnemyBase = _target(Vector3(0.0, 0.9, -5.8))
	var behind: EnemyBase = _target(Vector3(0.0, 0.9, 2.5))
	_player.perform_special_attack()
	await get_tree().create_timer(0.14).timeout
	assert_eq(late.current_health, 1000.0, "Preparation has no damage")
	assert_eq(behind.current_health, 1000.0)
	await get_tree().create_timer(0.85).timeout
	assert_eq(late.current_health, 940.0, "Recheck a broad-phase overlap after its centre reaches the swept footprint")
	assert_eq(behind.current_health, 940.0, "360° cleave includes the starting rear sector once")
	assert_lt(_player.global_position.z, -2.3)
	assert_gt(_player.global_position.z, -3.5)
	assert_almost_eq(_player.presentation.active_model.rotation.y, PI, 0.001)
	assert_false(_player.slash_area.monitoring)
	var effects: int = 0
	for child: Node in _world.get_children():
		if child.get_script() == TALENT_VFX:
			effects += 1
	assert_eq(effects, 0, "Modified cast/release visuals settle after their real active window")

func test_death_during_preparation_cannot_start_lunge_or_damage() -> void:
	var target: EnemyBase = _target(Vector3(0.0, 0.9, -2.0))
	_player.perform_special_attack()
	await get_tree().create_timer(0.10).timeout
	_player.current_health = 0.0
	await get_tree().create_timer(0.60).timeout
	assert_eq(target.current_health, 1000.0)
	assert_false(_player.movement.is_lunging)
	assert_false(_player.slash_area.monitoring)

func test_wide_lunge_alone_is_harmless_in_transit_and_strikes_at_endpoint() -> void:
	_player.talents.build().selected_talents.assign(["wide_lunge"])
	_player.talents.build().specializations.clear()
	_player.talents.refresh_stats()
	var passed_target: EnemyBase = _target(Vector3(0.0, 0.9, -1.2))
	var endpoint_target: EnemyBase = _target(Vector3(0.0, 0.9, -5.8))
	_player.perform_special_attack()
	await get_tree().create_timer(0.45).timeout
	assert_lt(_player.global_position.z, -0.5, "The native actor has begun the dash")
	assert_eq(passed_target.current_health, 1000.0, "Passing a monster deals no standalone lunge damage")
	assert_eq(endpoint_target.current_health, 1000.0, "The frontal strike waits for the endpoint")
	assert_false(_player.slash_area.monitoring)
	await get_tree().create_timer(0.55).timeout
	assert_almost_eq(_player.global_position.z, -2.7, 0.025)
	assert_eq(passed_target.current_health, 1000.0, "A passed monster is behind the final frontal strike")
	assert_eq(endpoint_target.current_health, 940.0)
	assert_false(_player.slash_area.monitoring)

func test_death_during_standalone_lunge_cancels_its_endpoint_strike() -> void:
	_player.talents.build().selected_talents.assign(["wide_lunge"])
	_player.talents.refresh_stats()
	var target: EnemyBase = _target(Vector3(0.0, 0.9, -5.8))
	_player.perform_special_attack()
	await get_tree().create_timer(0.40).timeout
	assert_true(_player.movement.is_lunging)
	_player.current_health = 0.0
	await get_tree().create_timer(0.60).timeout
	assert_eq(target.current_health, 1000.0)
	assert_false(_player.movement.is_lunging)
	assert_false(_player.slash_area.monitoring)

func test_pause_between_release_and_first_physics_frame_defers_all_contacts() -> void:
	var target: EnemyBase = _target(Vector3(0.0, 0.9, -2.0))
	await get_tree().physics_frame
	await get_tree().physics_frame
	_player.combat.trigger_slash(_player, 60.0, 0.0, 360.0, false, true)
	get_tree().paused = true
	await get_tree().create_timer(0.12, true).timeout
	assert_eq(target.current_health, 1000.0, "Opening the modal before the first contact frame must freeze damage")
	assert_true(_player.slash_area.monitoring, "Pause preserves the remaining contact window")
	get_tree().paused = false
	await get_tree().create_timer(0.6).timeout
	assert_eq(target.current_health, 940.0, "The preserved cast resumes and hits each target once")

func test_real_lunge_preserves_distance_at_ten_physics_ticks_and_shorter_than_one_tick() -> void:
	await _use_ten_physics_ticks()
	_player.movement.start_lunge(Vector3.FORWARD, 2.7, 0.25)
	for frame: int in range(3):
		await get_tree().physics_frame
	await get_tree().process_frame
	assert_almost_eq(_player.global_position.z, -2.7, 0.025, "The final half tick still contributes its exact displacement")
	assert_false(_player.movement.is_lunging)
	_player.global_position = Vector3(0.0, 0.9, 0.0)
	_player.velocity = Vector3.ZERO
	_player.movement.start_lunge(Vector3.FORWARD, 2.7, 0.05)
	await get_tree().physics_frame
	await get_tree().process_frame
	assert_almost_eq(_player.global_position.z, -2.7, 0.025, "A lunge shorter than one physics tick is not discarded")
	assert_false(_player.movement.is_lunging)
	await get_tree().physics_frame
	await get_tree().process_frame
	assert_almost_eq(_player.global_position.z, -2.7, 0.025, "A completed lunge leaves no residual motion in the next tick")
	assert_eq(_player.velocity.z, 0.0)

func test_terminal_state_cancels_short_lunge_before_first_motion_tick() -> void:
	await _use_ten_physics_ticks()
	_player.combat._start_warrior_cleave(_player, false)
	_player.progression.run_build.end_run()
	await get_tree().physics_frame
	await get_tree().process_frame
	assert_almost_eq(_player.global_position.z, 0.0, 0.001)
	assert_false(_player.movement.is_lunging)
	assert_false(_player.slash_area.monitoring)

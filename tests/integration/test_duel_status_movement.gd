extends GutTest

## PR #60 B1: exercise the native player's physics branch, not only the formula.
const PLAYER: PackedScene = preload("res://scenes/player.tscn")
const ENEMY: PackedScene = preload("res://scenes/enemy_dummy.tscn")

class MotionProbe extends Node:
	signal completed()
	var actor: PlayerPrototype
	var frames_remaining: int = 0
	var elapsed: float = 0.0
	var displacement: Vector3 = Vector3.ZERO
	var _origin: Vector3
	var _pending_origin: bool = false
	func sample(frames: int) -> void:
		# A timer can resume before the player processes this physics tick.
		# Anchor after the player first, then count complete physical intervals.
		_pending_origin = true
		frames_remaining = frames
		elapsed = 0.0
		set_physics_process(true)
	func _physics_process(delta: float) -> void:
		if frames_remaining <= 0:
			return
		if _pending_origin:
			_origin = actor.global_position
			_pending_origin = false
			return
		elapsed += delta
		frames_remaining -= 1
		if frames_remaining == 0:
			displacement = actor.global_position - _origin
			set_physics_process(false)
			completed.emit()

class OverrideDriver extends Node:
	var actor: PlayerPrototype
	var target: EnemyBase
	func _physics_process(delta: float) -> void:
		actor.movement.process_movement(actor, delta, target, 0.4, Vector3.FORWARD, true)

var _world: Node3D
var _player: PlayerPrototype
var _target: EnemyBase
var _probe: MotionProbe
var _ticks_before: int

func before_each() -> void:
	_ticks_before = Engine.physics_ticks_per_second
	Engine.physics_ticks_per_second = 60
	_world = Node3D.new()
	add_child_autoqfree(_world)
	var floor: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(80.0, 0.4, 80.0)
	collision.shape = box
	floor.add_child(collision)
	floor.position.y = -0.2
	_world.add_child(floor)
	_player = PLAYER.instantiate() as PlayerPrototype
	_world.add_child(_player)
	_player.set_class(PlayerPrototype.CharacterClass.WARRIOR, false)
	_player.talents.reset_for_viewer(WarriorTalentCatalog.TALENT_IDS)
	_player.global_position = Vector3(0.0, 0.9, 0.0)
	_target = ENEMY.instantiate() as EnemyBase
	_world.add_child(_target)
	_target.set_physics_process(false)
	_target.global_position = Vector3(0.0, 0.9, -30.0)
	_target.max_health = 10000.0
	_target.current_health = 10000.0
	_probe = MotionProbe.new()
	_probe.actor = _player
	_probe.process_physics_priority = 1000
	_world.add_child(_probe)
	_probe.set_physics_process(false)
	await wait_physics_frames(3)
	_player.abilities.perform_warrior_ultimate(_player, _target, true)
	assert_true(_player.is_dueling, "Native Duel ability owns the target before physical sampling")
	Input.action_press("move_down")

func after_each() -> void:
	for action: String in ["move_up", "move_down", "aim_up", "aim_left"]:
		Input.action_release(action)
	get_tree().paused = false
	Engine.physics_ticks_per_second = _ticks_before
	if is_instance_valid(_player):
		_player.end_duel()
	get_node("/root/VFXManager").clear_effects()

func _check_duel_travel(expected_multiplier: float) -> void:
	_probe.sample(12)
	await _probe.completed
	var horizontal: Vector2 = Vector2(_probe.displacement.x, _probe.displacement.z)
	assert_almost_eq(horizontal.length(), _player.speed * 1.15 * expected_multiplier * _probe.elapsed, 0.025, "Actual move_and_slide displacement includes Duel's 1.15 and the active statuses")
	assert_lt(_probe.displacement.z, 0.0, "Duel still approaches its target despite held retreat input")
	assert_almost_eq(_probe.displacement.x, 0.0, 0.005)
	assert_true(_player.is_dueling)

func test_single_slow_changes_actual_native_duel_approach() -> void:
	_player.apply_slow("one", 0.5, 2.0)
	await _check_duel_travel(0.5)

func test_independent_slows_multiply_during_actual_duel_approach() -> void:
	_player.apply_slow("one", 0.5, 2.0)
	_player.apply_slow("two", 0.25, 2.0)
	await _check_duel_travel(0.375)

func test_dismemberment_resistance_applies_to_actual_duel_approach() -> void:
	_player.progression.run_build.selected_talents.assign(["dismemberment"])
	_player.apply_slow("one", 0.5, 2.0)
	await _check_duel_travel(0.9)

func test_morale_and_resisted_slows_apply_together_to_actual_duel_approach() -> void:
	_player.progression.run_build.selected_talents.assign(["dismemberment"])
	_player.talents.on_duel_victory(_player.global_position)
	_player.apply_slow("one", 0.5, 2.0)
	_player.apply_slow("two", 0.25, 2.0)
	await _check_duel_travel(0.9 * 0.95 * (1.0 + WarriorTalentCatalog.MORALE_SPEED))

func test_native_status_timers_restore_full_duel_speed_after_expiry() -> void:
	_player.apply_slow("short", 0.5, 0.3)
	_player.talents.morale_remaining = 0.3
	await _check_duel_travel(0.5 * (1.0 + WarriorTalentCatalog.MORALE_SPEED))
	await wait_seconds(0.2)
	assert_true(_player.talents.statuses.slows.is_empty())
	assert_almost_eq(_player.talents.morale_remaining, 0.0, 0.001)
	await _check_duel_travel(1.0)

func test_ending_duel_returns_to_native_wasd_with_remaining_slow() -> void:
	_player.apply_slow("persistent", 0.5, 2.0)
	await _check_duel_travel(0.5)
	_player.end_duel()
	Input.action_release("move_down")
	Input.action_press("move_up")
	Input.action_press("aim_up")
	Input.action_press("aim_left")
	_player.orientation.setup(PlayerMovementMath.DEFAULT_SCREEN_FORWARD)
	_probe.sample(12)
	await _probe.completed
	assert_false(_player.is_dueling)
	var horizontal: Vector3 = Vector3(_probe.displacement.x, 0.0, _probe.displacement.z)
	assert_almost_eq(horizontal.length(), _player.speed * 0.5 * _probe.elapsed, 0.025, "Ordinary motion keeps the slow and removes Duel's speed bonus")
	assert_gt(horizontal.normalized().dot(PlayerMovementMath.DEFAULT_SCREEN_FORWARD), 0.99, "Native screen-relative WASD control returns after Duel")

func test_movement_override_forwards_multiplier_into_real_physics_motion() -> void:
	_player.set_physics_process(false)
	var driver: OverrideDriver = OverrideDriver.new()
	driver.actor = _player
	driver.target = _target
	_world.add_child(driver)
	await _check_duel_travel(0.4)

extends GutTest

var _world: Node3D
var _player: PlayerPrototype
var _owner: Node

func before_each() -> void:
	_world = Node3D.new()
	add_child_autoqfree(_world)
	var floor_body: StaticBody3D = StaticBody3D.new()
	var floor_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(30.0, 0.2, 30.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.1
	_world.add_child(floor_body)
	_player = preload("res://scenes/player.tscn").instantiate() as PlayerPrototype
	_world.add_child(_player)
	_player.set_physics_process(false)
	_player.position = Vector3(0.0, 0.9, 0.0)
	_owner = Node.new()
	_world.add_child(_owner)
	await get_tree().physics_frame
	await get_tree().physics_frame

func test_owner_releases_without_changing_input_or_combat_state() -> void:
	var second_owner: Node = Node.new()
	_world.add_child(second_owner)
	assert_true(_player.begin_enemy_carry(_owner))
	assert_false(_player.begin_enemy_carry(second_owner))
	_player.end_enemy_carry(second_owner)
	assert_true(_player.enemy_carry.active(_player))
	assert_true(_player.input_enabled)
	assert_true(_player.apply_enemy_carry_motion(_owner, Vector3(0.5, 0.0, 0.0)))
	assert_almost_eq(_player.position.x, 0.5, 0.01)
	_player.end_enemy_carry(_owner)
	_player.end_enemy_carry(_owner)
	assert_false(_player.enemy_carry.active(_player))
	assert_true(_player.input_enabled)

func test_carry_stops_at_real_wall_without_teleporting_through_it() -> void:
	var wall: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(1.0, 4.0, 4.0)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(1.5, 1.0, 0.0)
	_world.add_child(wall)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_true(_player.begin_enemy_carry(_owner))
	assert_false(_player.apply_enemy_carry_motion(_owner, Vector3(4.0, 0.0, 0.0)))
	assert_between(_player.position.x, 0.0, 0.61)
	assert_false(_player.enemy_carry.active(_player))

func test_freed_owner_and_finished_run_release_weak_reference() -> void:
	assert_true(_player.begin_enemy_carry(_owner))
	_owner.queue_free()
	await get_tree().process_frame
	assert_false(_player.enemy_carry.active(_player))
	var replacement: Node = Node.new()
	_world.add_child(replacement)
	assert_true(_player.begin_enemy_carry(replacement))
	_player.progression.run_build.end_run()
	assert_false(_player.enemy_carry.active(_player))
	assert_true(_player.input_enabled)

func test_cleave_lunge_does_not_resume_after_sweep_and_death_cleans_up() -> void:
	assert_true(_player.begin_enemy_carry(_owner))
	_player.movement.start_lunge(Vector3.FORWARD, 2.7, 0.3)
	_player.enemy_carry.advance_vertical(_player, 1.0 / 60.0)
	assert_false(_player.movement.is_lunging)
	assert_eq(_player.movement.lunge_timer, 0.0)
	_player.end_enemy_carry(_owner)
	assert_false(_player.movement.is_lunging)
	assert_true(_player.begin_enemy_carry(_owner))
	_player.current_health = 0.0
	assert_false(_player.enemy_carry.active(_player))

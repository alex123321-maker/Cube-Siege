extends GutTest

const CAMPFIRE_SCENE: PackedScene = preload("res://scenes/prefabs/campfire.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

func _player_at(at: Vector3) -> PlayerPrototype:
	var player: PlayerPrototype = PLAYER_SCENE.instantiate() as PlayerPrototype
	add_child_autoqfree(player)
	player.global_position = at
	player.set_physics_process(false)
	player.current_health = 50.0
	return player

func test_radius_boundary_and_vertical_limit_match_healing_volume() -> void:
	var fire: Campfire = CAMPFIRE_SCENE.instantiate() as Campfire
	add_child_autoqfree(fire)
	assert_true(fire.contains_player(Vector3(5, 0.9, 0)), "The visible 5 m perimeter is inclusive")
	assert_false(fire.contains_player(Vector3(5.01, 0.9, 0)), "No healing beyond perimeter")
	assert_false(fire.contains_player(Vector3(0, 2.51, 0)), "No healing through an elevated cliff")
	assert_true(fire.contains_player(Vector3(3, 0.9, 4)), "Diagonal distance uses a circle")
	assert_false(fire.contains_player(Vector3(4, 0.9, 4)), "A square corner cannot receive regeneration")

func test_enter_heals_and_exit_removes_only_that_hearth() -> void:
	var player: PlayerPrototype = _player_at(Vector3(2, 0.9, 0))
	var fire: Campfire = CAMPFIRE_SCENE.instantiate() as Campfire
	add_child_autoqfree(fire)
	fire._on_body_entered(player)
	fire._physics_process(0.25)
	assert_almost_eq(player.status_effects.regeneration_per_second(), 3.0, 0.001)
	player.status_effects.advance(0.25)
	assert_almost_eq(player.current_health, 50.75, 0.001)
	# Repeated aura refresh replaces this source instead of adding copies.
	fire._physics_process(0.25)
	assert_almost_eq(player.status_effects.regeneration_per_second(), 3.0, 0.001)
	player.status_effects.refresh_regeneration(123456, 2.0, 1.0)
	fire._on_body_exited(player)
	assert_almost_eq(player.status_effects.regeneration_per_second(), 2.0, 0.001)

func test_two_hearths_stack_and_destroy_immediately_cancels_source() -> void:
	var player: PlayerPrototype = _player_at(Vector3(2, 0.9, 0))
	var first: Campfire = CAMPFIRE_SCENE.instantiate() as Campfire
	var second: Campfire = CAMPFIRE_SCENE.instantiate() as Campfire
	add_child_autoqfree(first)
	add_child_autoqfree(second)
	first._on_body_entered(player)
	second._on_body_entered(player)
	first._physics_process(0.25)
	second._physics_process(0.25)
	assert_almost_eq(player.status_effects.regeneration_per_second(), 6.0, 0.001, "Space defines additive regeneration")
	first.destroy_building()
	assert_almost_eq(player.status_effects.regeneration_per_second(), 3.0, 0.001)
	second.queue_free()
	await get_tree().process_frame
	assert_almost_eq(player.status_effects.regeneration_per_second(), 0.0, 0.001)

func test_real_area_enters_and_leaves_without_group_scans() -> void:
	var player: PlayerPrototype = _player_at(Vector3(2, 0.9, 0))
	var fire: Campfire = CAMPFIRE_SCENE.instantiate() as Campfire
	add_child_autoqfree(fire)
	await wait_physics_frames(4)
	assert_almost_eq(player.status_effects.regeneration_per_second(), 3.0, 0.001, "Area3D body_entered wires the gameplay source")
	player.global_position = Vector3(8, 0.9, 0)
	await wait_physics_frames(4)
	assert_almost_eq(player.status_effects.regeneration_per_second(), 0.0, 0.001, "Leaving Area3D removes regeneration immediately")

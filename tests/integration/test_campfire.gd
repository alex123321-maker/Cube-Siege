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

func test_exact_radius_exit_stops_healing_while_real_body_still_overlaps() -> void:
	var player: PlayerPrototype = _player_at(Vector3(4.99, 0.9, 0))
	var fire: Campfire = CAMPFIRE_SCENE.instantiate() as Campfire
	add_child_autoqfree(fire)
	await wait_physics_frames(4)
	assert_true(fire.aura_area.overlaps_body(player), "The real body enters the real aura")
	fire.set_physics_process(false)
	fire._physics_process(0.25)
	player.status_effects.advance(0.1)
	assert_almost_eq(player.current_health, 50.3, 0.001, "The center inside 5 m receives 3 HP/s")
	player.global_position = Vector3(5.01, 0.9, 0)
	await wait_physics_frames(2)
	assert_true(fire.aura_area.overlaps_body(player), "The 0.8 m body still overlaps; body_exited cannot remove this source")
	assert_false(fire.contains_player(player.global_position))
	var before: float = player.current_health
	fire._physics_process(0.1)
	player.status_effects.advance(0.1)
	assert_almost_eq(player.current_health, before, 0.001, "Crossing the exact boundary stops health growth before refresh is due")
	assert_almost_eq(player.status_effects.regeneration_per_second(), 0.0, 0.001)
	# Re-entering the center radius while still overlapping remains eligible.
	player.global_position = Vector3(4.99, 0.9, 0)
	fire._physics_process(0.25)
	player.status_effects.advance(0.1)
	assert_almost_eq(player.current_health, before + 0.3, 0.001)

func test_heal_reducer_checks_exact_radius_before_fire_tick_and_preserves_other_sources() -> void:
	var player: PlayerPrototype = _player_at(Vector3(4.99, 0.9, 0))
	var first: Campfire = CAMPFIRE_SCENE.instantiate() as Campfire
	var second: Campfire = CAMPFIRE_SCENE.instantiate() as Campfire
	second.position = Vector3(8, 0, 0)
	add_child_autoqfree(first)
	add_child_autoqfree(second)
	await wait_physics_frames(4)
	assert_true(first.aura_area.overlaps_body(player))
	assert_true(second.aura_area.overlaps_body(player))
	first.set_physics_process(false)
	second.set_physics_process(false)
	first._physics_process(0.25)
	second._physics_process(0.25)
	player.status_effects.refresh_regeneration(123456, 2.0, 1.0)
	player.status_effects.advance(0.1)
	assert_almost_eq(player.current_health, 50.8, 0.001, "Two hearths plus an independent timed source sum")
	player.global_position = Vector3(5.01, 0.9, 0)
	await wait_physics_frames(2)
	assert_true(first.aura_area.overlaps_body(player), "The departing aura has not emitted body_exited")
	assert_true(second.aura_area.overlaps_body(player), "The other hearth remains eligible")
	var before: float = player.current_health
	# Deliberately advance before either hearth; scheduling cannot permit stale healing.
	player.status_effects.advance(0.1)
	assert_almost_eq(player.current_health, before + 0.5, 0.001, "Only the remaining hearth and timed source heal")
	assert_almost_eq(player.status_effects.regeneration_per_second(), 5.0, 0.001)
	first._physics_process(0.1)
	second._physics_process(0.1)
	assert_almost_eq(player.status_effects.regeneration_per_second(), 5.0, 0.001, "A later aura tick cannot reintroduce the departed source")

func test_freed_eligibility_owner_cancels_only_its_guarded_source() -> void:
	var player: PlayerPrototype = _player_at(Vector3(2, 0.9, 0))
	var provider: Node = Node.new()
	add_child(provider)
	player.status_effects.refresh_regeneration(101, 3.0, 1.0, 5.0, provider.is_inside_tree)
	player.status_effects.refresh_regeneration(102, 2.0, 1.0)
	player.status_effects.advance(0.1)
	assert_almost_eq(player.current_health, 50.5, 0.001)
	provider.free()
	player.status_effects.advance(0.1)
	assert_almost_eq(player.current_health, 50.7, 0.001, "A freed predicate never becomes an unrestricted regeneration source")
	assert_almost_eq(player.status_effects.regeneration_per_second(), 2.0, 0.001, "The independent timed source survives")

func test_terminal_stop_clears_and_never_refreshes_even_if_area_enters_again() -> void:
	var player: PlayerPrototype = _player_at(Vector3(2, 0.9, 0))
	var fire: Campfire = CAMPFIRE_SCENE.instantiate() as Campfire
	add_child_autoqfree(fire)
	fire._on_body_entered(player)
	fire._physics_process(0.25)
	assert_almost_eq(player.status_effects.regeneration_per_second(), 3.0, 0.001)
	fire.stop_regeneration()
	assert_almost_eq(player.status_effects.regeneration_per_second(), 0.0, 0.001)
	fire._on_body_entered(player)
	fire._physics_process(0.25)
	assert_almost_eq(player.status_effects.regeneration_per_second(), 0.0, 0.001, "A terminal run cannot restore a frozen source")
	assert_true(fire.is_inside_tree(), "The terminal run retains its decorative hearth")

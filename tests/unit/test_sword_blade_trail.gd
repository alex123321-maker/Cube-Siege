extends GutTest

const PROFILE: SwordVFXProfile = preload("res://assets/vfx/sword/steel_slash.tres")
const PLAYER: PackedScene = preload("res://scenes/player.tscn")

func _make_rig() -> Node3D:
	var rig := Node3D.new()
	rig.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	var blade_base := Node3D.new()
	blade_base.name = "Base"
	var blade_tip := Node3D.new()
	blade_tip.name = "Tip"
	blade_tip.position = Vector3(0.0, 0.0, -1.0)
	rig.add_child(blade_base)
	rig.add_child(blade_tip)
	add_child_autoqfree(rig)
	var trail := SwordBladeTrail.new()
	trail.name = "Trail"
	rig.add_child(trail)
	trail.setup(PROFILE, blade_base, blade_tip)
	trail.set_process(false)
	trail.set_attack_phase(true, 0.1)
	return rig

func test_trail_retains_world_history_and_ends_at_actual_blade() -> void:
	var rig: Node3D = _make_rig()
	var trail: SwordBladeTrail = rig.get_node("Trail") as SwordBladeTrail
	var tip: Node3D = rig.get_node("Tip") as Node3D
	rig.position = Vector3(7.0, 2.0, 4.0)
	trail._process(1.0 / 60.0)
	var original_tip: Vector3 = tip.global_position
	rig.position += Vector3(0.3, 0.0, 0.2)
	rig.rotation.y = 0.6
	trail._process(1.0 / 60.0)
	var vertices: PackedVector3Array = trail.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_lt(vertices[0].distance_to(original_tip), 0.0001, "Past samples must not turn or move with the character")
	assert_lt(vertices[-2].distance_to(tip.global_position), 0.0001, "The newest tip edge must touch the real sword")
	assert_lt(vertices[-1].distance_to(rig.global_position), 0.0001, "The newest inner edge must touch the real guard")
	assert_eq(trail.global_transform, Transform3D.IDENTITY)
	trail.set_attack_phase(false, 0.0)
	trail._process(PROFILE.blade_trail_lifetime + 0.01)
	assert_eq(trail.mesh.get_surface_count(), 0, "All geometry must drain after emission stops")

func test_teleport_hidden_weapon_and_sample_budget_do_not_leave_streaks() -> void:
	var rig: Node3D = _make_rig()
	var trail: SwordBladeTrail = rig.get_node("Trail") as SwordBladeTrail
	for index in range(100):
		rig.position.x += 0.01
		trail._process(0.0005)
	assert_eq(trail._tips.size(), SwordBladeTrail.MAX_SAMPLES, "Dense render sampling must have a fixed upper bound")
	rig.position.x += 20.0
	trail._process(1.0 / 60.0)
	assert_eq(trail.mesh.get_surface_count(), 0, "A teleport starts fresh instead of joining distant points")
	assert_eq(trail._tips.size(), 1)
	rig.hide()
	trail._process(1.0 / 60.0)
	assert_eq(trail._tips.size(), 0, "A hidden weapon must release its visual history")

func test_real_warrior_binding_attacks_and_class_switch_cleanup() -> void:
	var player: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	player.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child_autoqfree(player)
	player.set_physics_process(false)
	player.set_class(0, false)
	var trail: SwordBladeTrail = player.presentation.blade_trail
	assert_not_null(trail, "The real warrior must resolve both exported weapon anchors")
	if not trail:
		return
	trail.set_process(false)
	player.presentation.play_attack_animation()
	for index in range(9):
		player.presentation.update_animations(player, false, false, 1.0 / 60.0, player.orientation)
		trail._process(1.0 / 60.0)
	assert_gt(trail.mesh.get_surface_count(), 0, "The actual authored attack must create a trail")
	var vertices: PackedVector3Array = trail.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_lt(vertices[-2].distance_to(trail._tip_anchor.global_position), 0.0001)
	player.presentation.play_special_animation()
	assert_eq(trail.mesh.get_surface_count(), 0, "A new action must not join the previous swing")
	player.set_class(1, false)
	await wait_process_frames(2)
	assert_false(is_instance_valid(trail), "Changing class must free the old renderer")
	assert_null(player.presentation.blade_trail, "The archer has no sword trail binding")

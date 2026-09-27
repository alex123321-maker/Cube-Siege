extends GutTest

const PLAYER = preload("res://scenes/player.tscn")

func test_directional_stance_overrides_authored_forward_knee() -> void:
	var player: CharacterBody3D = _player()
	for class_id: int in [0, 1, 2]:
		player.set_class(class_id, false)
		var profile: CharacterAnimationProfile = player.presentation.animation_profile.duplicate()
		profile.foot_plant_enabled = false
		player.presentation.set_active_model(player.presentation.active_model, profile)
		var layer: CharacterPoseLayer = player.presentation.pose_layer
		var knee: Node3D = layer.nodes[CharacterPoseLayer.Joint.RIGHT_LEG].get_node("right_knee")
		knee.rotation.x = .65
		layer.phase = 0.0
		layer.move_weight = 1.0
		layer.blend = Vector4(1, 0, 0, 0)
		layer.update(.000001, Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD, Vector3(0, 0, -3), 0, false, &"", false)
		assert_lt(knee.quaternion.angle_to(Quaternion.IDENTITY), .001,
			"A planted procedural foot must not inherit the unrelated authored swing knee")
		layer.reset()
		assert_lt(knee.quaternion.angle_to(Quaternion.IDENTITY), .001, "Class cleanup restores the knee")

func test_missing_optional_knee_keeps_rigid_leg_animation_working() -> void:
	var player: CharacterBody3D = _player()
	var profile: CharacterAnimationProfile = player.presentation.animation_profile.duplicate()
	profile.right_knee_path = ^""
	profile.left_knee_path = ^"missing_optional_knee"
	player.presentation.set_active_model(player.presentation.active_model, profile)
	player.presentation.update_animations(player, false, false, .016, player.orientation)
	assert_not_null(player.presentation.pose_layer)

func test_world_space_stance_contact_does_not_slide_with_the_body() -> void:
	var player: CharacterBody3D = _player()
	for class_id: int in [0, 1, 2]:
		for direction: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
			player.set_class(class_id, false)
			player.presentation.set_active_model(player.presentation.active_model, player.presentation.animation_profile)
			var layer: CharacterPoseLayer = player.presentation.pose_layer
			layer.move_weight = 1.0
			layer.phase = .01
			var knee: Node3D = layer.knees[0]
			var lower_length: float = layer.profile.leg_length - layer.knee_rest[0].origin.length()
			var planted: Vector3
			for frame: int in 8:
				player.position += direction * .03
				layer.reset()
				layer.update(.01, Vector3.FORWARD, Vector3.FORWARD, direction,
					direction * 3, 0.0, false, &"", false)
				var foot: Vector3 = knee.to_global(Vector3(0, -lower_length, 0))
				if frame == 0:
					planted = foot
				else:
					assert_lt(foot.distance_to(planted), .012, "World-space stance stays fixed during forward/back/strafe")
				assert_true(layer.right_contact)

func _player() -> CharacterBody3D:
	var player: CharacterBody3D = PLAYER.instantiate()
	add_child_autoqfree(player)
	player.set_physics_process(false)
	player.set_class(0, false)
	return player

func test_three_profiles_bind_switch_and_release_old_pose() -> void:
	var player: CharacterBody3D = _player()
	for class_id: int in [0, 1, 2, 0]:
		var old: CharacterPoseLayer = player.presentation.pose_layer
		var old_player: AnimationPlayer = player.presentation.anim_player
		player.set_class(class_id, false)
		var layer: CharacterPoseLayer = player.presentation.pose_layer
		var profiles: Array[CharacterAnimationProfile] = [PlayerPresentation.WARRIOR_PROFILE,
			PlayerPresentation.ARCHER_PROFILE, PlayerPresentation.ENGINEER_PROFILE]
		assert_same(layer.profile, profiles[class_id], "Class selects its own animation tuning")
		assert_not_same(layer, old)
		assert_eq(layer.nodes.size(), 7)
		for node: Node3D in layer.nodes:
			assert_not_null(node, "Profile resolves actual runtime rig")
		assert_eq(layer.aim_yaw, Vector3.ZERO)
		if old_player != player.presentation.anim_player:
			assert_false(old_player.is_playing(), "Hidden model must stop")
		layer.update(0.1, Vector3.FORWARD, Vector3.RIGHT, Vector3.FORWARD, Vector3(0, 0, -3), 3, false, &"", false)
		assert_gt(layer.aim_yaw.length(), 0.0)
	player.presentation.set_active_model(null)
	assert_null(player.presentation.pose_layer)

func test_player_physics_passes_elapsed_time_and_orientation_to_presentation() -> void:
	var player: CharacterBody3D = _player()
	player.presentation.play_special_animation()
	player.orientation.setup(Vector3.LEFT)
	player.orientation.aim_direction = Vector3.FORWARD
	player._physics_process(0.05)
	assert_almost_eq(player.presentation.anim_player.current_animation_position, 0.05, 0.001,
		"Authored action uses the actual physics delta")
	assert_almost_eq(player.presentation.pose_layer.body_aim_angle,
		player.orientation.body_facing_direction.signed_angle_to(player.orientation.aim_direction, Vector3.UP),
		0.001, "Procedural pose receives the gameplay orientation")

func test_player_debug_keys_toggle_animation_diagnostics_and_layer() -> void:
	var player: CharacterBody3D = _player()
	var event: InputEventKey = InputEventKey.new()
	event.pressed = true
	event.keycode = KEY_F3
	player._unhandled_input(event)
	assert_true(player.presentation.debug_enabled)
	event.keycode = KEY_F4
	player._unhandled_input(event)
	assert_false(player.presentation.procedural_enabled)
	event.echo = true
	player._unhandled_input(event)
	assert_false(player.presentation.procedural_enabled, "Key repeat does not toggle the layer")

func test_presentation_does_not_write_gameplay_and_action_clock_stays_unscaled() -> void:
	var player: CharacterBody3D = _player()
	player.orientation.setup(Vector3.LEFT)
	player.orientation.aim_direction = Vector3.RIGHT
	player.orientation.angular_velocity = 5.0
	player.velocity = Vector3(3, 0, 2)
	player.presentation.play_special_animation()
	for i: int in 12:
		player.presentation.update_animations(player, false, true, 1.0 / 60, player.orientation)
	assert_eq(player.orientation.body_facing_direction, Vector3.LEFT)
	assert_eq(player.orientation.aim_direction, Vector3.RIGHT)
	assert_eq(player.orientation.angular_velocity, 5.0)
	assert_eq(player.velocity, Vector3(3, 0, 2))
	assert_almost_eq(player.presentation.anim_player.current_animation_position, 0.2, 0.001)
	assert_eq(player.presentation.anim_player.speed_scale, 1.0)

func test_moving_action_keeps_legs_and_no_offset_accumulates() -> void:
	var player: CharacterBody3D = _player()
	var layer: CharacterPoseLayer = player.presentation.pose_layer
	var right: Node3D = layer.nodes[CharacterPoseLayer.Joint.RIGHT_LEG]
	var first: Basis = right.basis
	for i: int in 120:
		layer.restore_authored()
		layer.update(1.0 / 60, Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3(0, 0, 3), 0, false, &"attack", false)
	assert_gt(first.get_rotation_quaternion().angle_to(right.quaternion), 0.01)
	assert_lt(absf(layer.aim_yaw.x), layer.profile.torso_limit * 0.1)
	assert_almost_eq(right.scale, Vector3.ONE, Vector3.ONE * 0.0001, "Rigid segment never stretches")
	layer.restore_authored()
	assert_eq(right.transform, layer.rest[CharacterPoseLayer.Joint.RIGHT_LEG])

func test_toggle_smoothly_fades_and_stationary_turn_steps() -> void:
	var player: CharacterBody3D = _player()
	var layer: CharacterPoseLayer = player.presentation.pose_layer
	for i: int in 60:
		layer.restore_authored()
		layer.update(1.0 / 60, Vector3.FORWARD, Vector3.BACK, Vector3.ZERO, Vector3.ZERO, 5, false, &"", false)
	assert_gt(absf(layer.turn_amount), 0.5)
	var right: Node3D = layer.nodes[CharacterPoseLayer.Joint.RIGHT_LEG]
	var left: Node3D = layer.nodes[CharacterPoseLayer.Joint.LEFT_LEG]
	assert_true(right.position.y > layer.rest[5].origin.y or left.position.y > layer.rest[6].origin.y)
	var yaw: float = layer.aim_yaw.x
	layer.enabled = false
	layer.restore_authored()
	layer.update(1.0 / 60, Vector3.FORWARD, Vector3.BACK, Vector3.ZERO, Vector3.ZERO, 0, false, &"", false)
	assert_lt(absf(layer.aim_yaw.x - yaw), 0.05, "No toggle snap")
	for i: int in 120:
		layer.restore_authored()
		layer.update(1.0 / 60, Vector3.FORWARD, Vector3.BACK, Vector3.ZERO, Vector3.ZERO, 0, false, &"", false)
	assert_lt(layer.aim_yaw.length(), 0.001)
	assert_lt(layer.layer_weight, 0.001)

func test_missing_optional_rig_nodes_are_safe() -> void:
	var model: Node3D = Node3D.new()
	add_child_autoqfree(model)
	var layer: CharacterPoseLayer = CharacterPoseLayer.new()
	layer.bind(model, PlayerPresentation.WARRIOR_PROFILE)
	layer.update(0.1, Vector3.FORWARD, Vector3.BACK, Vector3.RIGHT, Vector3.RIGHT, 5, true, &"attack", false)
	layer.restore_authored()
	layer.reset()
	assert_eq(layer.nodes.size(), 7)

func test_death_releases_pose_and_debug_helpers() -> void:
	var player: CharacterBody3D = _player()
	player.presentation.debug_enabled = true
	player.presentation.update_animations(player, false, false, 0.1, player.orientation)
	var model: Node3D = player.presentation.active_model
	var child_count: int = model.get_child_count()
	player.health.player_died.emit()
	assert_null(player.presentation.pose_layer)
	assert_null(player.presentation.anim_player)
	assert_eq(model.get_child_count(), child_count - 1, "Debug helper removed on death")
	player.presentation.update_animations(player, false, false, 0.1, player.orientation)

func test_sparse_idle_restores_legs_after_finished_action() -> void:
	var player: CharacterBody3D = _player()
	player.set_class(1, false)
	player.presentation.procedural_enabled = false
	var layer: CharacterPoseLayer = player.presentation.pose_layer
	layer.layer_weight = 0.0
	player.presentation.anim_player.play("walk")
	player.presentation.anim_player.advance(0.2)
	player.presentation.play_attack_animation()
	for i: int in 90:
		player.presentation.update_animations(player, false, false, 1.0 / 60, player.orientation)
	assert_eq(player.presentation.anim_player.current_animation, "idle")
	assert_eq(layer.nodes[5].transform, layer.rest[5], "Sparse idle does not retain last walk leg key")
	assert_eq(layer.nodes[6].transform, layer.rest[6])

func _lean_steps(layer: CharacterPoseLayer, velocity: Vector3, facing: Vector3 = Vector3.FORWARD,
		action_name: StringName = &"", blocking: bool = false, frames: int = 90) -> void:
	for i: int in frames:
		layer.restore_authored()
		layer.update(1.0 / 60, facing, facing, Vector3.FORWARD, velocity, 0, false, action_name, blocking)

func test_torso_leans_toward_world_travel_for_each_rig_and_body_facing() -> void:
	var player: CharacterBody3D = _player()
	for class_id: int in [0, 1, 2]:
		player.set_class(class_id, false)
		var layer: CharacterPoseLayer = player.presentation.pose_layer
		for yaw: float in [0.0, PI / 2, PI]:
			player.rotation.y = yaw
			var facing: Vector3 = -player.global_basis.z
			for direction: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT, Vector3(1, 0, -1).normalized()]:
				layer.restore_authored()
				var authored_up: Vector3 = layer.nodes[CharacterPoseLayer.Joint.TORSO].global_basis.y.normalized()
				_lean_steps(layer, direction * 7, facing)
				var torso_up: Vector3 = layer.nodes[CharacterPoseLayer.Joint.TORSO].global_basis.y.normalized()
				var tilt: Vector3 = Vector3(torso_up.x - authored_up.x, 0, torso_up.z - authored_up.z)
				assert_gt(tilt.normalized().dot(direction), 0.99, "Torso inclines toward travel, including the rotated Blender rig")
				assert_lte(layer.movement_lean.length(), layer.profile.movement_lean_limit + 0.00001, "Diagonals respect the same angular cap")
				assert_true(player.global_basis.is_equal_approx(Basis(Vector3.UP, yaw)), "Presentation does not rotate gameplay body")

func test_lean_uses_actual_speed_and_settles_on_stop_or_disable() -> void:
	var player: CharacterBody3D = _player()
	var layer: CharacterPoseLayer = player.presentation.pose_layer
	_lean_steps(layer, Vector3.FORWARD * 3.5)
	assert_almost_eq(layer.movement_lean.y, layer.profile.movement_lean_limit * 0.5, 0.0001)
	_lean_steps(layer, Vector3.FORWARD * 18)
	assert_almost_eq(layer.movement_lean.y, layer.profile.movement_lean_limit, 0.0001, "Dash speed cannot exceed the tilt cap")
	var previous: Vector2 = layer.movement_lean
	_lean_steps(layer, Vector3.BACK * 7, Vector3.FORWARD, &"", false, 1)
	assert_gt(layer.movement_lean.y, 0.0, "Reversal passes smoothly through upright")
	assert_lt((layer.movement_lean - previous).length(), layer.profile.movement_lean_limit * 0.3)
	_lean_steps(layer, Vector3.ZERO)
	assert_lt(layer.movement_lean.length(), 0.0001, "Held movement input without actual motion does not lean")
	_lean_steps(layer, Vector3.RIGHT * 7)
	layer.enabled = false
	_lean_steps(layer, Vector3.RIGHT * 7, Vector3.FORWARD, &"", false, 180)
	assert_eq(layer.movement_lean, Vector2.ZERO)

func test_actions_and_block_soften_movement_lean() -> void:
	var player: CharacterBody3D = _player()
	var layer: CharacterPoseLayer = player.presentation.pose_layer
	_lean_steps(layer, Vector3.RIGHT * 7)
	var full_lean: float = layer.movement_lean.length()
	_lean_steps(layer, Vector3.RIGHT * 7, Vector3.FORWARD, &"attack")
	assert_almost_eq(layer.movement_lean.length(), full_lean * layer.profile.action_movement_lean_weight, 0.0001)
	_lean_steps(layer, Vector3.RIGHT * 7, Vector3.FORWARD, &"", true)
	assert_almost_eq(layer.movement_lean.length(), full_lean * layer.profile.block_movement_lean_weight, 0.0001)
	_lean_steps(layer, Vector3.RIGHT * 7)
	assert_almost_eq(layer.movement_lean.length(), full_lean, 0.0001)

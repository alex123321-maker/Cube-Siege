extends GutTest

const PLAYER = preload("res://scenes/player.tscn")
const BOOT_NAMES: Array = [
	[["R_Boot", "R_BootToe"], ["L_Boot", "L_BootToe"]],
	[["right_boot", "right_boot_toecap", "right_boot_sole", "right_boot_gold_toe"], ["left_boot", "left_boot_toecap", "left_boot_sole", "left_boot_gold_toe"]],
	[["right_boot", "right_sole"], ["left_boot", "left_sole"]],
]

func _player(class_id: int) -> CharacterBody3D:
	var player: CharacterBody3D = PLAYER.instantiate()
	add_child_autoqfree(player)
	player.set_physics_process(false)
	player.set_class(class_id, false)
	return player

func _boot_vertices(model: Node3D, class_id: int, side: int) -> Array:
	var result: Array = []
	for name: String in BOOT_NAMES[class_id][side]:
		var part: MeshInstance3D = model.find_child(name, true, false)
		assert_not_null(part, "Actual exported boot part " + name)
		if part:
			for surface: int in part.mesh.get_surface_count():
				result.append([part, part.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]])
	return result

func _minimum_height(parts: Array) -> float:
	var height: float = INF
	for entry: Array in parts:
		for vertex: Vector3 in entry[1]:
			height = minf(height, entry[0].to_global(vertex).y)
	return height

func test_real_boot_geometry_clears_flat_floor_through_full_directional_cycles() -> void:
	for class_id: int in 3:
		for speed: float in [3.0, 7.0]:
			for direction: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
				var player: CharacterBody3D = _player(class_id)
				var layer: CharacterPoseLayer = player.presentation.pose_layer
				var model: Node3D = player.presentation.active_model
				var boots: Array = [_boot_vertices(model, class_id, 0), _boot_vertices(model, class_id, 1)]
				layer.move_weight = 1.0
				var minimum: float = INF
				var maximum_stance_gap: float = 0.0
				var wraps: int = 0
				for frame: int in 240:
					var previous_phase: float = layer.phase
					player.position += direction * speed / 120.0
					layer.reset()
					layer.update(1.0 / 120, Vector3.FORWARD, Vector3.FORWARD, direction, direction * speed, 0, false, &"", false)
					if layer.phase < previous_phase:
						wraps += 1
					for side: int in 2:
						var height: float = _minimum_height(boots[side]) - model.global_position.y
						minimum = minf(minimum, height)
						if layer.right_contact if side == 0 else layer.left_contact:
							maximum_stance_gap = maxf(maximum_stance_gap, height)
				var context: String = "class=%d speed=%.1f direction=%s" % [class_id, speed, direction]
				assert_gte(wraps, 2, "At least two full cycles: " + context)
				assert_gte(minimum, -.005, "Visible sole/toe must clear the actual floor: " + context)
				assert_lt(maximum_stance_gap, .025, "Visible planted sole remains near floor: " + context)
				gut.p("SOLE %s min_y=%.6f max_stance_gap=%.6f cycles=%d" % [context, minimum, maximum_stance_gap, wraps])
				player.free()

func test_real_presentation_dash_boundaries_do_not_pop_root_or_knees() -> void:
	for class_id: int in 3:
		for phase: float in [.05, .3, .55, .8]:
			var player: CharacterBody3D = _player(class_id)
			var presentation: PlayerPresentation = player.presentation
			var layer: CharacterPoseLayer = presentation.pose_layer
			# Populate CharacterBody3D's real velocity, which presentation actually reads.
			player.velocity = Vector3.FORWARD * 3
			player.move_and_slide()
			for warmup: int in 90:
				player.move_and_slide()
				presentation.update_animations(player, false, false, 1.0 / 60, player.orientation)
			layer.phase = phase
			presentation.update_animations(player, false, false, 1.0 / 60, player.orientation)
			var previous_root: float = layer.nodes[0].position.y - layer.authored[0].origin.y
			var previous_knee: Quaternion = layer.knees[0].quaternion
			var max_height_jump: float = 0.0
			var max_knee_jump: float = 0.0
			var max_knee_frame: int = -1
			var dash_frames: int = ceili(player.movement.dash_duration * 60.0)
			for frame: int in 80:
				var dashing: bool = frame < dash_frames
				var requested_velocity: Vector3 = Vector3.FORWARD * (player.movement.dash_speed if dashing else 3.0)
				player.velocity = requested_velocity
				player.move_and_slide()
				presentation.update_animations(player, false, dashing, 1.0 / 60, player.orientation)
				assert_eq(player.velocity, requested_velocity, "Presentation never changes gameplay velocity")
				var visual_root: float = layer.nodes[0].position.y - layer.authored[0].origin.y
				max_height_jump = maxf(max_height_jump, absf(visual_root - previous_root))
				var knee_delta: float = layer.knees[0].quaternion.angle_to(previous_knee)
				if knee_delta > max_knee_jump:
					max_knee_jump = knee_delta
					max_knee_frame = frame
				previous_root = visual_root
				previous_knee = layer.knees[0].quaternion
			assert_lt(max_height_jump, .025, "Dash boundary must not add a 14 cm root pop")
			assert_lt(max_knee_jump, .4, "Knee correction must blend across dash boundaries")
			gut.p("DASH class=%d start_phase=%.2f max_root_delta=%.6f max_knee_delta=%.6f at_frame=%d" % [class_id, phase, max_height_jump, max_knee_jump, max_knee_frame])
			assert_eq(player.velocity, Vector3.FORWARD * 3, "Presentation never changes gameplay velocity")
			player.free()

func test_boot_corrections_restore_when_switching_class_or_disabling_layer() -> void:
	var player: CharacterBody3D = _player(0)
	for class_id: int in [0, 1, 2, 0]:
		player.set_class(class_id, false)
		var model: Node3D = player.presentation.active_model
		var parts: Array = _boot_vertices(model, class_id, 0)
		var original: Array[Transform3D] = []
		for entry: Array in parts:
			original.append(entry[0].transform)
		var child_count: int = model.find_children("*", "", true, false).size()
		var layer: CharacterPoseLayer = player.presentation.pose_layer
		for frame: int in 30:
			layer.restore_authored()
			layer.update(1.0 / 60, Vector3.FORWARD, Vector3.FORWARD, Vector3.RIGHT, Vector3.RIGHT * 3, 0, false, &"", false)
		layer.enabled = false
		for frame: int in 180:
			layer.restore_authored()
			layer.update(1.0 / 60, Vector3.FORWARD, Vector3.FORWARD, Vector3.ZERO, Vector3.ZERO, 0, false, &"", false)
		layer.reset()
		for index: int in parts.size():
			assert_eq(parts[index][0].transform, original[index], "Boot geometry returns to its authored transform")
		assert_eq(model.find_children("*", "", true, false).size(), child_count, "No ankle helper nodes accumulate")

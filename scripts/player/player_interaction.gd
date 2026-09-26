extends RefCounted
class_name PlayerInteraction

## Manages nearby interactable candidates, selection highlight, and hold-to-interact execution.
## Uses physics snapshot from InteractionSensor as single source of truth (Issue #42).

var focused_interactable: Node = null
var interact_hold_timer: float = 0.0
var candidate_nodes: Array[Node] = []

func update_candidates(new_candidates: Array[Node]) -> void:
	candidate_nodes = new_candidates

func add_candidate(node: Node) -> void:
	if node and not candidate_nodes.has(node):
		candidate_nodes.append(node)

func remove_candidate(node: Node) -> void:
	candidate_nodes.erase(node)
	if focused_interactable == node:
		if node and is_instance_valid(node) and not node.is_queued_for_deletion() and node.has_method("set_focused"):
			node.set_focused(false)
		focused_interactable = null
		interact_hold_timer = 0.0

func process_interaction(player: CharacterBody3D, delta: float, sensor: Area3D = null) -> void:
	if not player or not is_instance_valid(player):
		return

	if not sensor:
		sensor = player.get_node_or_null("InteractionSensor") as Area3D

	# 1. Physics snapshot from InteractionSensor
	if sensor and is_instance_valid(sensor):
		var overlapping: Array[Area3D] = sensor.get_overlapping_areas()
		var discovered_targets: Array[Node] = []
		for area in overlapping:
			if not is_instance_valid(area) or area.is_queued_for_deletion():
				continue
			var target: Node = null
			if area is InteractionZone:
				target = area.get_interaction_target()
			elif area.has_method("get_interaction_target"):
				target = area.get_interaction_target()
			elif "target_node" in area:
				target = area.target_node

			# 2. Check target validity and scene tree state
			if target and is_instance_valid(target) and target.is_inside_tree() and not target.is_queued_for_deletion():
				# 3. Deduplicate zones of the same target
				if not discovered_targets.has(target):
					discovered_targets.append(target)
		candidate_nodes = discovered_targets

	# Guard current focus against deleted/unloaded objects
	if focused_interactable:
		if not is_instance_valid(focused_interactable) or not focused_interactable.is_inside_tree() or focused_interactable.is_queued_for_deletion():
			focused_interactable = null
			interact_hold_timer = 0.0

	var vp: Viewport = player.get_viewport()
	var cam: Camera3D = vp.get_camera_3d() if vp else null
	var mouse_world: Vector3 = player.global_position

	if cam and vp:
		var m_pos: Vector2 = vp.get_mouse_position()
		var r_orig: Vector3 = cam.project_ray_origin(m_pos)
		var r_norm: Vector3 = cam.project_ray_normal(m_pos)
		var plane: Plane = Plane(Vector3.UP, player.global_position.y)
		var hit: Variant = plane.intersects_ray(r_orig, r_norm)
		if hit is Vector3:
			mouse_world = hit as Vector3

	# 4. Filter candidates within 4.5m and select closest to cursor
	var best_target: Node = null
	var best_dist: float = 999999.0

	for i in range(candidate_nodes.size() - 1, -1, -1):
		var obj = candidate_nodes[i]
		if not is_instance_valid(obj) or not (obj is Node3D) or not obj.is_inside_tree() or obj.is_queued_for_deletion():
			candidate_nodes.remove_at(i)
			continue

		var dist_to_player: float = player.global_position.distance_to((obj as Node3D).global_position)
		if dist_to_player > 4.5:
			continue

		if not InteractableTarget.can_interact(obj, player):
			continue

		var dist_to_cursor: float = mouse_world.distance_to((obj as Node3D).global_position)
		if dist_to_cursor < best_dist:
			best_dist = dist_to_cursor
			best_target = obj

	# 5. Manage focus & highlight without resetting hold progress if target remains the same
	if best_target != focused_interactable:
		if focused_interactable and is_instance_valid(focused_interactable) and not focused_interactable.is_queued_for_deletion() and focused_interactable.has_method("set_focused"):
			focused_interactable.set_focused(false)
		focused_interactable = best_target
		interact_hold_timer = 0.0
		if focused_interactable and is_instance_valid(focused_interactable) and not focused_interactable.is_queued_for_deletion() and focused_interactable.has_method("set_focused"):
			focused_interactable.set_focused(true)

	# Hold execution
	if Input.is_action_pressed("interact") and focused_interactable and is_instance_valid(focused_interactable) and not focused_interactable.is_queued_for_deletion():
		interact_hold_timer += delta
		var hold_required: float = 1.0
		var act_type = InteractableTarget.get_action_type(focused_interactable, player)
		if act_type == InteractableTarget.ActionType.PORTAL_EVACUATE:
			hold_required = 2.0
		elif act_type == InteractableTarget.ActionType.PICKUP:
			hold_required = 0.2

		var progress: float = clampf(interact_hold_timer / hold_required, 0.0, 1.0)
		if focused_interactable.has_method("set_interaction_progress"):
			focused_interactable.set_interaction_progress(progress)

		if interact_hold_timer >= hold_required:
			interact_hold_timer = 0.0
			var is_shift: bool = Input.is_key_pressed(KEY_SHIFT)
			var target_to_execute = focused_interactable
			_execute_interaction(target_to_execute, player, is_shift)

			# If target was successfully consumed or is no longer interactable, clear focus
			if not is_instance_valid(target_to_execute) or target_to_execute.is_queued_for_deletion() or not InteractableTarget.can_interact(target_to_execute, player):
				if focused_interactable == target_to_execute:
					if is_instance_valid(focused_interactable) and not focused_interactable.is_queued_for_deletion() and focused_interactable.has_method("set_focused"):
						focused_interactable.set_focused(false)
					focused_interactable = null
	else:
		if interact_hold_timer > 0.0:
			interact_hold_timer = 0.0
			if focused_interactable and is_instance_valid(focused_interactable) and not focused_interactable.is_queued_for_deletion() and focused_interactable.has_method("set_focused"):
				focused_interactable.set_focused(true)

func _execute_interaction(target: Node, player: CharacterBody3D, is_shift: bool) -> void:
	InteractableTarget.execute_interaction(target, player, is_shift)

extends RefCounted
class_name PlayerInteraction

## Manages nearby interactable candidates, selection highlight, and hold-to-interact execution.

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
		if node and is_instance_valid(node) and node.has_method("set_focused"):
			node.set_focused(false)
		focused_interactable = null
		interact_hold_timer = 0.0

func process_interaction(player: CharacterBody3D, delta: float) -> void:
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

	# Filter valid candidates within 4.5m
	var best_target: Node = null
	var best_dist: float = 999.0

	# Clean up invalid candidate references
	for i in range(candidate_nodes.size() - 1, -1, -1):
		var obj = candidate_nodes[i]
		if not is_instance_valid(obj) or not (obj is Node3D):
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

	# Manage focus & highlight
	if best_target != focused_interactable:
		if focused_interactable and is_instance_valid(focused_interactable) and focused_interactable.has_method("set_focused"):
			focused_interactable.set_focused(false)
		focused_interactable = best_target
		interact_hold_timer = 0.0
		if focused_interactable and focused_interactable.has_method("set_focused"):
			focused_interactable.set_focused(true)

	# Hold [E] for 1.0s or 2.0s for portal extraction
	if Input.is_action_pressed("interact") and focused_interactable:
		interact_hold_timer += delta
		var hold_required: float = 1.0
		if InteractableTarget.get_action_type(focused_interactable, player) == InteractableTarget.ActionType.PORTAL_EVACUATE:
			hold_required = 2.0

		var progress: float = clampf(interact_hold_timer / hold_required, 0.0, 1.0)
		if focused_interactable.has_method("set_interaction_progress"):
			focused_interactable.set_interaction_progress(progress)

		if interact_hold_timer >= hold_required:
			interact_hold_timer = 0.0
			var is_shift: bool = Input.is_key_pressed(KEY_SHIFT)
			_execute_interaction(focused_interactable, player, is_shift)
			focused_interactable = null
	else:
		if interact_hold_timer > 0.0:
			interact_hold_timer = 0.0
			if focused_interactable and is_instance_valid(focused_interactable) and focused_interactable.has_method("set_focused"):
				focused_interactable.set_focused(true)

func _execute_interaction(target: Node, player: CharacterBody3D, is_shift: bool) -> void:
	InteractableTarget.execute_interaction(target, player, is_shift)

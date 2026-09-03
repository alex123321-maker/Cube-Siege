extends Camera3D

@export var target_path: NodePath
@export var follow_speed: float = 8.0
@export var look_ahead_factor: float = 3.0
@export var offset: Vector3 = Vector3(18.0, 24.0, 18.0)

var target: Node3D = null
var occluding_buildings: Array[Node] = []

func _ready() -> void:
	current = true
	if has_node(target_path):
		target = get_node(target_path)
		global_position = target.global_position + offset
		look_at(target.global_position, Vector3.UP)
		print("DEBUG_CAMERA: target=", target, " pos=", global_position, " rot=", rotation_degrees)

func _process(delta: float) -> void:
	if not target:
		return

	# Base isometric target position
	var desired_pos: Vector3 = target.global_position + offset

	# Optional Look-ahead towards mouse (safe clamped)
	var vp: Viewport = get_viewport()
	if vp:
		var v_size: Vector2 = vp.get_visible_rect().size
		if v_size.x > 10.0 and v_size.y > 10.0:
			var mouse_pos: Vector2 = vp.get_mouse_position()
			if Rect2(Vector2.ZERO, v_size).has_point(mouse_pos):
				var screen_center: Vector2 = v_size / 2.0
				var mouse_offset_normalized: Vector2 = ((mouse_pos - screen_center) / screen_center).clamp(Vector2(-1, -1), Vector2(1, 1))
				var lead_vector: Vector3 = Vector3(mouse_offset_normalized.x, 0.0, mouse_offset_normalized.y) * look_ahead_factor
				desired_pos += lead_vector

	global_position = global_position.lerp(desired_pos, clampf(1.0 - exp(-follow_speed * delta), 0.0, 1.0))
	look_at(target.global_position, Vector3.UP)
	check_occlusion()

func check_occlusion() -> void:
	if not target or not is_inside_tree():
		return
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position, target.global_position + Vector3(0, 0.9, 0), 1)

	var hit: Dictionary = space_state.intersect_ray(query)
	var new_occluders: Array[Node] = []
	if not hit.is_empty():
		var col: Object = hit.get("collider")
		if col and col is Node and (col as Node).is_in_group("buildings"):
			new_occluders.append(col as Node)

	# Restore buildings that are no longer occluding
	for b in occluding_buildings:
		if is_instance_valid(b) and not new_occluders.has(b) and b.has_method("set_transparency"):
			b.set_transparency(0.0)

	# Set new occluders to semi-transparent
	for b in new_occluders:
		if is_instance_valid(b) and b.has_method("set_transparency"):
			b.set_transparency(0.6)

	occluding_buildings = new_occluders

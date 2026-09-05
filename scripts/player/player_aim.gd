extends RefCounted
class_name PlayerAim

## Handles player aiming: arrow keys, mouse cursor raycast, and deadzone preservation.
## Pure calculation of desired aim direction vector without mutating body transform directly.

var last_mouse_pos: Vector2 = Vector2(-9999, -9999)
var last_aim_dir: Vector3 = Vector3(0.0, 0.0, -1.0)

func handle_aim(body: CharacterBody3D, forced_target: Node3D = null, deadzone: float = 0.6) -> Vector3:
	# 0. Forced target (e.g. warrior duel)
	if forced_target and is_instance_valid(forced_target):
		var to_target: Vector3 = forced_target.global_position - body.global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.01:
			last_aim_dir = to_target.normalized()
			return last_aim_dir

	# 1. Keyboard Arrow Keys Aim
	var k_aim_x: float = Input.get_axis("aim_left", "aim_right")
	var k_aim_y: float = Input.get_axis("aim_up", "aim_down")
	if Vector2(k_aim_x, k_aim_y).length_squared() > 0.1:
		var k_dir: Vector3 = Vector3(k_aim_x, 0.0, k_aim_y).normalized()
		last_aim_dir = k_dir
		last_mouse_pos = Vector2(-9999, -9999)
		return last_aim_dir

	var vp: Viewport = body.get_viewport()
	if not vp:
		return _safe_aim_fallback(body)

	# 2. Mouse raycast aiming with deadzone
	var cam: Camera3D = vp.get_camera_3d()
	if not cam:
		return _safe_aim_fallback(body)

	var current_mouse_pos: Vector2 = vp.get_mouse_position()
	last_mouse_pos = current_mouse_pos

	var ray_origin: Vector3 = cam.project_ray_origin(current_mouse_pos)
	var ray_normal: Vector3 = cam.project_ray_normal(current_mouse_pos)
	var ground_plane: Plane = Plane(Vector3(0, 1, 0), body.global_position.y)
	var intersect: Variant = ground_plane.intersects_ray(ray_origin, ray_normal)

	if intersect is Vector3:
		var hit_pos: Vector3 = intersect as Vector3
		var diff: Vector3 = hit_pos - body.global_position
		diff.y = 0.0
		var dist: float = diff.length()
		# If cursor is outside deadzone, update last_aim_dir
		if dist >= deadzone and dist > 0.001:
			last_aim_dir = diff.normalized()
			return last_aim_dir
		else:
			# Cursor is inside deadzone: preserve last valid aim direction!
			return last_aim_dir

	return _safe_aim_fallback(body)

func _safe_aim_fallback(body: CharacterBody3D) -> Vector3:
	if last_aim_dir.length_squared() > 0.01 and last_aim_dir.is_finite():
		return last_aim_dir

	if body and is_instance_valid(body):
		var forward: Vector3 = -body.global_transform.basis.z
		forward.y = 0.0
		if forward.length_squared() > 0.01:
			last_aim_dir = forward.normalized()
			return last_aim_dir

	last_aim_dir = Vector3(0.0, 0.0, -1.0)
	return last_aim_dir

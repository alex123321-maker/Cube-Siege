extends RefCounted
class_name PlayerAim

## Handles player aiming: arrow keys, mouse cursor raycast, and fallback to movement direction.

var last_mouse_pos: Vector2 = Vector2(-9999, -9999)
var last_mouse_move_time: float = 0.0

func handle_aim(body: CharacterBody3D, forced_target: Node3D = null) -> Vector3:
	# 0. Forced target (e.g. warrior duel)
	if forced_target and is_instance_valid(forced_target):
		var to_target: Vector3 = forced_target.global_position - body.global_position
		to_target.y = 0.0
		if to_target.length_squared() > 0.01:
			body.look_at(body.global_position + to_target.normalized(), Vector3.UP)
			return to_target.normalized()

	# 1. Keyboard Arrow Keys Aim
	var k_aim_x: float = Input.get_axis("aim_left", "aim_right")
	var k_aim_y: float = Input.get_axis("aim_up", "aim_down")
	if Vector2(k_aim_x, k_aim_y).length_squared() > 0.1:
		var k_dir: Vector3 = Vector3(k_aim_x, 0.0, k_aim_y).normalized()
		body.look_at(body.global_position + k_dir, Vector3.UP)
		last_mouse_pos = Vector2(-9999, -9999)
		return k_dir

	var vp: Viewport = body.get_viewport()
	if not vp:
		return -body.global_transform.basis.z

	var current_mouse_pos: Vector2 = vp.get_mouse_position()
	var mouse_moved: bool = (current_mouse_pos - last_mouse_pos).length_squared() > 4.0

	if mouse_moved:
		last_mouse_pos = current_mouse_pos
		last_mouse_move_time = Time.get_ticks_msec() / 1000.0

	var time_since_mouse_move: float = (Time.get_ticks_msec() / 1000.0) - last_mouse_move_time

	# 2. If mouse is idle, auto-aim in walk direction
	if time_since_mouse_move > 0.35:
		var move_dir_h: Vector3 = Vector3(body.velocity.x, 0.0, body.velocity.z)
		if move_dir_h.length_squared() > 0.1:
			body.look_at(body.global_position + move_dir_h.normalized(), Vector3.UP)
			return move_dir_h.normalized()

	# 3. Mouse raycast aiming
	var cam: Camera3D = vp.get_camera_3d()
	if not cam:
		return -body.global_transform.basis.z

	var ray_origin: Vector3 = cam.project_ray_origin(current_mouse_pos)
	var ray_normal: Vector3 = cam.project_ray_normal(current_mouse_pos)
	var ground_plane: Plane = Plane(Vector3(0, 1, 0), body.global_position.y)
	var intersect: Variant = ground_plane.intersects_ray(ray_origin, ray_normal)

	if intersect is Vector3:
		var aim_dir: Vector3 = (intersect as Vector3) - body.global_position
		aim_dir.y = 0.0
		if aim_dir.length_squared() > 0.01:
			body.look_at(body.global_position + aim_dir.normalized(), Vector3.UP)
			return aim_dir.normalized()

	return -body.global_transform.basis.z

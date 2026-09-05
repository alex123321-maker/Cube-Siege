class_name CameraFollow
extends Camera3D

## Fixed isometric gameplay camera with smooth character tracking,
## deadzone-based peripheral screen edge panning, and distance preset support.
## Preserves constant isometric orientation and FOV under all gameplay conditions.

const CameraMath = preload("res://scripts/camera/camera_math.gd")

@export var target_path: NodePath
@export var follow_speed: float = 8.0
@export var pan_speed: float = 6.0
@export var preset_transition_speed: float = 5.0
@export var max_peripheral_offset: float = CameraMath.DEFAULT_MAX_PERIPHERAL_OFFSET
@export var deadzone_ratio: float = CameraMath.DEFAULT_DEADZONE_RATIO
@export var offset: Vector3 = Vector3(15.0, 20.0, 15.0)

var target: Node3D = null
var occluding_buildings: Array[Node] = []

var fixed_basis: Basis
var fixed_rotation_degrees: Vector3
var target_base_offset: Vector3 = Vector3(15.0, 20.0, 15.0)
var current_base_offset: Vector3 = Vector3(15.0, 20.0, 15.0)
var current_peripheral_offset: Vector3 = Vector3.ZERO
var target_peripheral_offset: Vector3 = Vector3.ZERO
var is_initialized: bool = false
var pan_enabled: bool = true

func _ready() -> void:
	current = true
	fov = CameraMath.FIXED_FOV

	# Wire to persistent settings if available
	var game_settings = get_node_or_null("/root/GameSettings")
	if game_settings:
		if not game_settings.camera_distance_changed.is_connected(_on_camera_distance_changed):
			game_settings.camera_distance_changed.connect(_on_camera_distance_changed)
		target_base_offset = game_settings.get_camera_offset()
	else:
		target_base_offset = offset

	var eb = get_node_or_null("/root/EventBus")
	if eb and eb.has_signal("camera_distance_changed"):
		if not eb.is_connected("camera_distance_changed", Callable(self, "_on_camera_distance_changed")):
			eb.connect("camera_distance_changed", Callable(self, "_on_camera_distance_changed"))

	current_base_offset = target_base_offset

	if has_node(target_path):
		target = get_node(target_path) as Node3D
		_init_camera_transform()

func set_target(new_target: Node3D) -> void:
	target = new_target
	if is_inside_tree() and target:
		_init_camera_transform()

var mouse_override: Vector2 = Vector2(-9999, -9999)

func _init_camera_transform() -> void:
	if not target or not is_instance_valid(target):
		return

	fixed_basis = Basis.looking_at(-current_base_offset.normalized(), Vector3.UP)
	transform.basis = fixed_basis
	fixed_rotation_degrees = rotation_degrees
	global_position = target.global_position + current_base_offset
	is_initialized = true

func _on_camera_distance_changed(_preset: int, new_offset: Vector3) -> void:
	target_base_offset = new_offset

func set_distance_preset(preset: int, immediate: bool = false) -> void:
	target_base_offset = CameraMath.get_preset_offset(preset)
	if immediate:
		current_base_offset = target_base_offset

func _process(delta: float) -> void:
	if not target or not is_instance_valid(target):
		return

	if not is_initialized:
		_init_camera_transform()
		if not is_initialized:
			return

	# Strictly enforce fixed orientation and constant FOV every frame
	transform.basis = fixed_basis
	fov = CameraMath.FIXED_FOV

	# Smoothly interpolate base offset when preset is changed
	current_base_offset = current_base_offset.lerp(
		target_base_offset,
		clampf(1.0 - exp(-preset_transition_speed * delta), 0.0, 1.0)
	)

	# Compute peripheral pan offset based on cursor position relative to viewport
	target_peripheral_offset = Vector3.ZERO
	if pan_enabled:
		var vp: Viewport = get_viewport()
		var window_focused: bool = true
		if DisplayServer.has_method("window_is_focused"):
			window_focused = DisplayServer.window_is_focused()

		if vp and window_focused:
			var vp_size: Vector2 = vp.get_visible_rect().size
			if vp_size.x > 10.0 and vp_size.y > 10.0:
				var mouse_pos: Vector2 = mouse_override if mouse_override.x >= 0.0 else vp.get_mouse_position()
				target_peripheral_offset = CameraMath.calculate_target_peripheral_offset(
					mouse_pos,
					vp_size,
					fixed_basis,
					max_peripheral_offset,
					deadzone_ratio,
					current_base_offset
				)

	# Smoothly interpolate peripheral offset (prevents snapping, ensures smooth return)
	current_peripheral_offset = current_peripheral_offset.lerp(
		target_peripheral_offset,
		clampf(1.0 - exp(-pan_speed * delta), 0.0, 1.0)
	)

	# Strictly enforce safe-frustum clamp on current offset every frame,
	# ensuring resize or preset changes never leave player outside safe screen bounds.
	var vp_current: Viewport = get_viewport()
	if vp_current:
		var current_vp_size: Vector2 = vp_current.get_visible_rect().size
		if current_vp_size.x > 10.0 and current_vp_size.y > 10.0:
			current_peripheral_offset = CameraMath.clamp_offset_to_safe_frustum(
				current_peripheral_offset,
				current_base_offset,
				fixed_basis,
				current_vp_size,
				CameraMath.FIXED_FOV,
				CameraMath.DEFAULT_SAFE_FRUSTUM_MARGIN
			)

	# Desired position: character anchor + selected distance preset + peripheral pan
	var desired_pos: Vector3 = target.global_position + current_base_offset + current_peripheral_offset

	# Smooth follow for character movement and pan
	global_position = global_position.lerp(
		desired_pos,
		clampf(1.0 - exp(-follow_speed * delta), 0.0, 1.0)
	)

	# Also clamp actual global_position's peripheral displacement against safe frustum.
	# When a sudden resize or preset change occurs, global_position immediately conforms
	# to the safe frustum margin so the character NEVER leaves the screen even on frame 1 of resize.
	if vp_current:
		var current_vp_size: Vector2 = vp_current.get_visible_rect().size
		if current_vp_size.x > 10.0 and current_vp_size.y > 10.0:
			var actual_disp: Vector3 = global_position - (target.global_position + current_base_offset)
			actual_disp.y = 0.0
			var safe_disp: Vector3 = CameraMath.clamp_offset_to_safe_frustum(
				actual_disp,
				current_base_offset,
				fixed_basis,
				current_vp_size,
				CameraMath.FIXED_FOV,
				CameraMath.DEFAULT_SAFE_FRUSTUM_MARGIN
			)
			if safe_disp.length_squared() < actual_disp.length_squared() - 0.0001:
				global_position = target.global_position + current_base_offset + safe_disp

	# Ensure orientation remains strictly fixed after translation
	transform.basis = fixed_basis

	check_occlusion()

func check_occlusion() -> void:
	if not target or not is_inside_tree():
		return
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_position,
		target.global_position + Vector3(0.0, 0.9, 0.0),
		1
	)

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

func _exit_tree() -> void:
	for b in occluding_buildings:
		if is_instance_valid(b) and b.has_method("set_transparency"):
			b.set_transparency(0.0)
	occluding_buildings.clear()

func get_peripheral_offset() -> Vector3:
	return current_peripheral_offset

func get_base_offset() -> Vector3:
	return current_base_offset

func get_fixed_rotation_degrees() -> Vector3:
	return fixed_rotation_degrees

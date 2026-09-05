class_name CameraMath
extends RefCounted

## Pure mathematical helpers for isometric camera follow, deadzone calculation,
## peripheral edge panning, and distance preset mapping.

enum Preset {
	CLOSE = 0,
	MEDIUM = 1,
	FAR = 2,
}

const PRESET_OFFSETS: Dictionary = {
	Preset.CLOSE: Vector3(12.0, 16.0, 12.0),
	Preset.MEDIUM: Vector3(15.0, 20.0, 15.0),
	Preset.FAR: Vector3(18.0, 24.0, 18.0),
}

const PRESET_NAMES: Dictionary = {
	Preset.CLOSE: "Близко",
	Preset.MEDIUM: "Средне",
	Preset.FAR: "Далеко",
}

const DEFAULT_PRESET: int = Preset.MEDIUM
const DEFAULT_DEADZONE_RATIO: float = 0.70
const DEFAULT_MAX_PERIPHERAL_OFFSET: float = 4.0
const FIXED_FOV: float = 45.0

## Smooth hermite curve (3t^2 - 2t^3) for zero-velocity boundary transition
static func smooth_curve(t: float) -> float:
	var ct: float = clampf(t, 0.0, 1.0)
	return ct * ct * (3.0 - 2.0 * ct)

## Calculates deadzone factors for screen position in viewport.
## Returns Vector2(signed_factor_x, signed_factor_y) where each component is in [-1.0, 1.0].
## Returns Vector2.ZERO if inside the central 70% deadzone.
## X: -1 = full left, +1 = full right
## Y: +1 = full top (screen up/forward), -1 = full bottom (screen down/back)
static func calculate_deadzone_factors(screen_pos: Vector2, vp_size: Vector2, deadzone_ratio: float = DEFAULT_DEADZONE_RATIO) -> Vector2:
	if vp_size.x <= 0.0 or vp_size.y <= 0.0:
		return Vector2.ZERO

	var peripheral_ratio_x: float = (1.0 - deadzone_ratio) * 0.5
	var peripheral_ratio_y: float = (1.0 - deadzone_ratio) * 0.5

	var clamped_pos: Vector2 = screen_pos.clamp(Vector2.ZERO, vp_size)
	var nx: float = clamped_pos.x / vp_size.x
	var ny: float = clamped_pos.y / vp_size.y

	var fx: float = 0.0
	if nx < peripheral_ratio_x:
		var t: float = (peripheral_ratio_x - nx) / peripheral_ratio_x
		fx = -smooth_curve(t)
	elif nx > (1.0 - peripheral_ratio_x):
		var t: float = (nx - (1.0 - peripheral_ratio_x)) / peripheral_ratio_x
		fx = smooth_curve(t)

	var fy: float = 0.0
	if ny < peripheral_ratio_y:
		# Top of screen: in camera view, top points into the world forward
		var t: float = (peripheral_ratio_y - ny) / peripheral_ratio_y
		fy = smooth_curve(t)
	elif ny > (1.0 - peripheral_ratio_y):
		# Bottom of screen: in camera view, bottom points towards camera back
		var t: float = (ny - (1.0 - peripheral_ratio_y)) / peripheral_ratio_y
		fy = -smooth_curve(t)

	return Vector2(fx, fy)

## Calculates normalized 2D peripheral offset direction with strict vector length clamping (<= 1.0).
## Prevents diagonal directions from increasing offset beyond 100%.
static func calculate_peripheral_offset_2d(screen_pos: Vector2, vp_size: Vector2, deadzone_ratio: float = DEFAULT_DEADZONE_RATIO) -> Vector2:
	var raw_factors: Vector2 = calculate_deadzone_factors(screen_pos, vp_size, deadzone_ratio)
	if raw_factors.length_squared() > 1.0:
		return raw_factors.normalized()
	return raw_factors

## Extracts camera right and forward unit vectors projected onto horizontal ground plane (XZ, Y = 0).
static func get_ground_plane_directions(cam_basis: Basis) -> Dictionary:
	var right: Vector3 = Vector3(cam_basis.x.x, 0.0, cam_basis.x.z)
	if right.length_squared() > 0.0001:
		right = right.normalized()
	else:
		right = Vector3(1.0, 0.0, -1.0).normalized()

	var forward: Vector3 = Vector3(-cam_basis.z.x, 0.0, -cam_basis.z.z)
	if forward.length_squared() > 0.0001:
		forward = forward.normalized()
	else:
		forward = Vector3(-1.0, 0.0, -1.0).normalized()

	return {
		"right": right,
		"forward": forward
	}

## Calculates target 3D peripheral offset on horizontal ground plane (Y = 0).
## Guaranteed to be clamped to max_offset in all directions, including diagonals.
static func calculate_target_peripheral_offset(
	screen_pos: Vector2,
	vp_size: Vector2,
	cam_basis: Basis,
	max_offset: float = DEFAULT_MAX_PERIPHERAL_OFFSET,
	deadzone_ratio: float = DEFAULT_DEADZONE_RATIO
) -> Vector3:
	var dir_2d: Vector2 = calculate_peripheral_offset_2d(screen_pos, vp_size, deadzone_ratio)
	if dir_2d.is_zero_approx():
		return Vector3.ZERO

	var ground_dirs: Dictionary = get_ground_plane_directions(cam_basis)
	var right_dir: Vector3 = ground_dirs["right"]
	var forward_dir: Vector3 = ground_dirs["forward"]

	var offset_3d: Vector3 = (right_dir * dir_2d.x + forward_dir * dir_2d.y) * max_offset
	if offset_3d.length() > max_offset:
		offset_3d = offset_3d.normalized() * max_offset

	return offset_3d

static func get_preset_offset(preset: int) -> Vector3:
	return PRESET_OFFSETS.get(preset, PRESET_OFFSETS[DEFAULT_PRESET])

static func get_preset_name(preset: int) -> String:
	return PRESET_NAMES.get(preset, PRESET_NAMES[DEFAULT_PRESET])

static func parse_preset_name(name_str: String) -> int:
	var lower: String = name_str.strip_edges().to_lower()
	if lower == "близко" or lower == "close":
		return Preset.CLOSE
	elif lower == "далеко" or lower == "far":
		return Preset.FAR
	return Preset.MEDIUM

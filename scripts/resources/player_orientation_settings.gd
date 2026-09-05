extends Resource
class_name PlayerOrientationSettings

## Data-driven configuration for player spatial orientation, rotation kinematics, and directional locomotion.

@export var max_turn_rate: float = 14.0 ## Max angular velocity in radians/sec (~800 deg/s, full 180 deg in ~0.22s)
@export var angular_acceleration: float = 70.0 ## Angular acceleration in rad/s^2
@export var angular_deceleration: float = 90.0 ## Angular deceleration in rad/s^2 for braking near target
@export var base_facing_tolerance: float = deg_to_rad(15.0) ## Base angle threshold (radians) where action is permitted
@export var aim_deadzone: float = 0.6 ## Distance from player below which aim direction is frozen

@export var directional_speed_curve: Curve = null

func _init() -> void:
	if directional_speed_curve == null:
		directional_speed_curve = create_default_speed_curve()

static func create_default_speed_curve() -> Curve:
	var curve: Curve = Curve.new()
	# X-axis is normalized angle (0.0 = 0 deg forward, 0.5 = 90 deg strafe, 1.0 = 180 deg backward)
	# Y-axis is speed multiplier (1.00 at forward, ~0.75 at strafe, ~0.50 at backward)
	curve.add_point(Vector2(0.0, 1.0), 0.0, -0.4, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(0.25, 0.90), -0.5, -0.6, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(0.5, 0.75), -0.6, -0.5, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(0.75, 0.62), -0.5, -0.48, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	curve.add_point(Vector2(1.0, 0.50), -0.48, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return curve

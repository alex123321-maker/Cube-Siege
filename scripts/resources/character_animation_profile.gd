extends Resource
class_name CharacterAnimationProfile

## Presentation only: never used to calculate movement, facing or action timings.
@export var animation_player_path: NodePath = ^"AnimationPlayer"
@export var root_path: NodePath = ^"root"
@export var torso_path: NodePath = ^"root/torso"
@export var head_path: NodePath = ^"root/torso/head"
@export var right_arm_path: NodePath = ^"root/torso/right_arm"
@export var left_arm_path: NodePath = ^"root/torso/left_arm"
@export var right_leg_path: NodePath = ^"root/right_leg"
@export var left_leg_path: NodePath = ^"root/left_leg"
@export var right_knee_path: NodePath = ^"root/right_leg/right_knee"
@export var left_knee_path: NodePath = ^"root/left_leg/left_knee"
@export var knee_swing_angle: float = 0.55
@export var knee_lift_reference: float = 0.1
@export var foot_plant_enabled: bool = true
@export var plant_stride_fraction: float = 0.42
@export var plant_crouch: float = 0.14
@export var plant_swing_height: float = 0.13
@export var forward: CharacterGait
@export var backward: CharacterGait
@export var strafe_right: CharacterGait
@export var strafe_left: CharacterGait
@export var torso_limit: float = 0.40
@export var head_limit: float = 0.61
@export var arm_limit: float = 0.10
@export var torso_share: float = 0.45
@export var head_share: float = 0.75
@export var arm_share: float = 0.08
@export var left_arm_weight: float = 0.15
@export var right_arm_weight: float = 0.5
@export var aim_response: float = 9.0
@export var head_response: float = 16.0
@export var blend_response: float = 12.0
@export var action_aim_weight: float = 0.05
@export var block_aim_weight: float = 0.08
@export var action_blend_seconds: float = 0.08
@export var cycle_seconds: float = 0.8
@export var gait_reference_speed: float = 2.8
@export var movement_threshold: float = 0.1
@export var full_stride_speed: float = 0.35
@export var min_playback_rate: float = 0.15
@export var max_playback_rate: float = 3.0
@export var stride_weight: float = 1.0
@export var dash_stride_weight: float = 0.22
@export var leg_length: float = 0.60
@export var max_inward_leg_angle: float = 0.025
@export var turn_rate_reference: float = 6.0
@export var turn_deadzone: float = 0.15
@export var turn_step_rate: float = 2.8
@export var turn_lift: float = 0.06
@export var turn_leg_yaw: float = 0.20
@export var turn_hip_yaw: float = 0.06
@export var turn_lean: float = 0.035
@export_range(0, 15, 0.5, "radians_as_degrees") var movement_lean_limit: float = 0.104719755
@export_range(0.1, 30, 0.1) var movement_lean_reference_speed: float = 7.0
@export_range(0.1, 30, 0.1) var movement_lean_response: float = 8.0
@export_range(0, 1, 0.05) var action_movement_lean_weight: float = 0.25
@export_range(0, 1, 0.05) var block_movement_lean_weight: float = 0.15
@export var foot_placement_enabled: bool = false
@export var foot_placement_weight: float = 0.5
@export var foot_placement_max_height: float = 0.18
@export var foot_ray_height: float = 0.5
@export var foot_collision_mask: int = 1

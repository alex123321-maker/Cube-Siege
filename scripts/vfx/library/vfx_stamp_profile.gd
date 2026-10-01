class_name VFXStampProfile
extends Resource

## A subordinate one-shot sprite accent, never a damage shape or a full ability.
@export var texture: Texture2D
@export var tint: Color = Color(1.0, 0.76, 0.32, 0.85)
@export var start_size: Vector2 = Vector2(0.8, 0.8)
@export var end_size: Vector2 = Vector2(1.2, 1.2)
@export_range(0.02, 2.0) var lifetime: float = 0.24
@export_range(0.0, 0.4) var rise_seconds: float = 0.025
@export_range(0.0, 3.0) var emission: float = 0.7
@export var drift: Vector3 = Vector3.ZERO

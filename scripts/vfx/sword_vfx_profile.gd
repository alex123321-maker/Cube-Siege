class_name SwordVFXProfile
extends Resource

## Art controls only. Combat owns damage, reach, hit timing, and cooldowns.
@export var ribbon_texture: Texture2D
@export var contact_texture: Texture2D
@export var body_color: Color = Color(0.19, 0.48, 0.76)
@export var edge_color: Color = Color(0.82, 0.96, 1.0)
@export var contact_color: Color = Color(1.0, 0.70, 0.29)
@export_range(0.1, 0.6) var lifetime: float = 0.32
@export_range(0.02, 0.15) var sweep_time: float = 0.065
@export_range(0.2, 1.4) var ribbon_width: float = 0.94
@export_range(0.0, 4.0) var emission: float = 1.6
@export_range(0, 24) var shard_count: int = 11
@export_range(0.4, 2.0) var contact_size: float = 1.35
@export_range(0.06, 0.3) var contact_lifetime: float = 0.16
@export_range(0.0, 1.0) var arc_opacity: float = 0.65
@export_range(0.03, 0.2) var blade_trail_lifetime: float = 0.11
@export_range(0.0, 0.35) var blade_trail_start: float = 0.055
@export_range(0.0, 0.35) var blade_trail_end: float = 0.22
@export_range(0.0, 1.0) var blade_trail_opacity: float = 0.9

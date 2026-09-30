class_name ArrowImpactProfile
extends Resource

## Presentation only. Small-model variants edit these fields, never damage or flight.
@export var contact_texture: Texture2D
@export var dust_texture: Texture2D
@export var contact_color: Color = Color(0.90, 0.67, 0.31)
@export var dust_color: Color = Color(0.48, 0.43, 0.32)
@export_range(0.6, 1.8, 0.05) var contact_size: float = 1.5
@export_range(0.08, 0.20, 0.01) var contact_lifetime: float = 0.16
@export_range(0.0, 1.8, 0.05) var emission: float = 0.75
@export_range(4, 16, 1) var shard_count: int = 9
@export_range(1.5, 6.0, 0.1) var shard_speed: float = 3.7
@export_range(0.18, 0.45, 0.01) var shard_lifetime: float = 0.32
@export_range(0.5, 1.3, 0.05) var dust_size: float = 0.8
@export_range(0.18, 0.45, 0.01) var dust_lifetime: float = 0.34
@export_range(0.0, 0.4, 0.01) var dust_opacity: float = 0.22

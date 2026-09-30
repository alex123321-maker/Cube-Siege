class_name MineVFXProfile
extends Resource

## Presentation only. The remote mine owns damage, blast radius and detonation time.
@export var fire_texture: Texture2D
@export var smoke_texture: Texture2D
@export var flash_texture: Texture2D
@export var ring_texture: Texture2D
@export var flame_color: Color = Color(1.0, 0.25, 0.035)
@export var hot_color: Color = Color(1.0, 0.88, 0.49)
@export var smoke_color: Color = Color(0.32, 0.29, 0.25)
@export var dust_color: Color = Color(0.47, 0.37, 0.24)
@export_range(0.22, 0.65) var fire_lifetime: float = 0.42
@export_range(0.7, 1.8) var smoke_lifetime: float = 1.3
@export_range(0.5, 1.1) var smoke_opacity: float = 0.72
@export_range(0.6, 1.3) var fire_scale: float = 1.0
@export_range(0.6, 1.3) var smoke_scale: float = 1.0
@export_range(0.0, 3.0) var emission: float = 1.35
@export_range(0.1, 1.0) var ring_opacity: float = 0.76
## The full footprint flashes immediately, then cools in place at the periphery.
@export_range(0.20, 0.34) var wave_edge_lifetime: float = 0.28
@export_range(0.04, 0.12) var wave_hold_time: float = 0.09
@export_range(0.32, 0.6) var wave_lifetime: float = 0.42
@export_range(0.8, 2.5) var ground_lifetime: float = 1.45
@export_range(0.0, 0.7) var ground_opacity: float = 0.58
@export_range(8, 40) var ember_count: int = 28
@export_range(0.4, 1.2) var ember_lifetime: float = 0.8
@export_range(0.0, 3.0) var light_energy: float = 1.8

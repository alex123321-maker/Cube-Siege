class_name CleaveVFXProfile
extends Resource

## Presentation only; the combat component owns the hit window and damage.
@export var steel_color: Color = Color(0.08, 0.32, 0.51)
@export var edge_color: Color = Color(0.76, 0.94, 1.0)
@export var gold_color: Color = Color(1.0, 0.59, 0.16)
@export var ribbon_texture: Texture2D
@export var traveling_head: bool = false
@export var ability: WarriorCleaveSpec = preload("res://assets/abilities/warrior_cleave.tres")
var radius: float:
	get:
		return ability.radius
@export_range(0.2, 2.0) var blade_width: float = 1.65
@export_range(0.2, 1.0) var lifetime: float = 0.72
@export_range(0.03, 0.2) var sweep_time: float = 0.10
@export_range(0.0, 4.0) var emission: float = 1.65
@export_range(0, 64) var fragment_count: int = 22
@export_range(0, 48) var spark_count: int = 18
@export var release_sound: AudioStream
@export_range(-40.0, 0.0) var volume_db: float = -13.0

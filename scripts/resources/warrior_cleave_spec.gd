class_name WarriorCleaveSpec
extends Resource

## Shared gameplay footprint and phase timing; presentation consumes this resource.
@export_range(2.5, 6.0) var radius: float = 3.8
@export_range(90.0, 180.0) var arc_degrees: float = 180.0
@export_range(0.1, 0.5) var windup: float = 0.28
@export_range(0.3, 1.2) var recovery: float = 0.82

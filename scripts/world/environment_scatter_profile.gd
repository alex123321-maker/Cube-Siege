extends Resource
class_name EnvironmentScatterProfile

## Inspector-editable authored prop weights for one world biome.

@export_range(0.0, 1.0, 0.005) var grass_rate: float = 0.0
@export_range(0.0, 1.0, 0.005) var flower_rate: float = 0.0
@export_range(0.0, 1.0, 0.005) var debris_rate: float = 0.0
@export var grass_props: PackedStringArray = []
@export var flower_props: PackedStringArray = []
@export var debris_props: PackedStringArray = []

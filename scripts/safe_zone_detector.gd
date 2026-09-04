extends Node
class_name SafeZoneDetector

const SafeZoneCalculator = preload("res://scripts/algorithms/safe_zone_calculator.gd")

signal safe_zone_changed(enclosed_cells: Array[Vector2i])

@export var building_system_path: NodePath
@export var wave_director_path: NodePath

var building_system: Node = null
var wave_director: Node = null
var current_safe_cells: Array[Vector2i] = []

func _ready() -> void:
	if has_node(building_system_path):
		building_system = get_node(building_system_path)
		if building_system.has_signal("building_placed"):
			building_system.connect("building_placed", Callable(self, "_on_building_changed"))

	if has_node(wave_director_path):
		wave_director = get_node(wave_director_path)

func _on_building_changed(_cell: Vector2i, building: Node) -> void:
	# Recalculate safe zone on building change
	if building and building.has_signal("building_destroyed"):
		if not building.is_connected("building_destroyed", Callable(self, "_on_building_destroyed_safezone")):
			building.connect("building_destroyed", Callable(self, "_on_building_destroyed_safezone"))
	call_deferred("recalculate_safe_zone")

func _on_building_destroyed_safezone(_building: Node) -> void:
	call_deferred("recalculate_safe_zone")

func recalculate_safe_zone() -> void:
	if not building_system:
		return

	var placed: Dictionary = building_system.get("placed_buildings")
	if not placed or placed.is_empty():
		update_safe_zone([])
		return

	# Collect all wall positions
	var wall_cells: Array[Vector2i] = []
	for cell in placed.keys():
		var b: Node = placed[cell]
		if b and is_instance_valid(b) and b.is_in_group("walls"):
			wall_cells.append(cell)

	var enclosed: Array[Vector2i] = SafeZoneCalculator.calculate_safe_cells(wall_cells)
	update_safe_zone(enclosed)

func update_safe_zone(enclosed: Array[Vector2i]) -> void:
	current_safe_cells = enclosed
	emit_signal("safe_zone_changed", current_safe_cells)

	if wave_director and wave_director.has_method("set_safe_zone_cells"):
		wave_director.set_safe_zone_cells(current_safe_cells)

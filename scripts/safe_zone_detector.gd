extends Node
class_name SafeZoneDetector

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

	if wall_cells.size() < 4:
		# At least 4 walls needed to enclose even 1 cell
		update_safe_zone([])
		return

	# Find bounding box
	var min_x: int = 999
	var max_x: int = -999
	var min_z: int = 999
	var max_z: int = -999

	for c in wall_cells:
		min_x = min(min_x, c.x)
		max_x = max(max_x, c.x)
		min_z = min(min_z, c.y)
		max_z = max(max_z, c.y)

	# Expand by 1 cell padding
	var box_min_x: int = min_x - 1
	var box_max_x: int = max_x + 1
	var box_min_z: int = min_z - 1
	var box_max_z: int = max_z + 1

	var visited: Dictionary = {} # Vector2i -> bool
	var queue: Array[Vector2i] = []

	# Enqueue all border cells of the expanded bounding box
	for x in range(box_min_x, box_max_x + 1):
		queue.append(Vector2i(x, box_min_z))
		queue.append(Vector2i(x, box_max_z))
		visited[Vector2i(x, box_min_z)] = true
		visited[Vector2i(x, box_max_z)] = true

	for z in range(box_min_z, box_max_z + 1):
		queue.append(Vector2i(box_min_x, z))
		queue.append(Vector2i(box_max_x, z))
		visited[Vector2i(box_min_x, z)] = true
		visited[Vector2i(box_max_x, z)] = true

	# Flood-fill outside
	var wall_dict: Dictionary = {}
	for w in wall_cells:
		wall_dict[w] = true

	var dirs: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

	while not queue.is_empty():
		var curr: Vector2i = queue.pop_front()
		for d in dirs:
			var n: Vector2i = curr + d
			if n.x >= box_min_x and n.x <= box_max_x and n.y >= box_min_z and n.y <= box_max_z:
				if not visited.has(n):
					visited[n] = true
					if not wall_dict.has(n):
						queue.append(n)

	# Any cell inside the bounding box NOT visited by exterior flood fill is enclosed!
	var enclosed: Array[Vector2i] = []
	for x in range(box_min_x + 1, box_max_x):
		for z in range(box_min_z + 1, box_max_z):
			var cell: Vector2i = Vector2i(x, z)
			if not visited.has(cell) and not wall_dict.has(cell):
				enclosed.append(cell)

	update_safe_zone(enclosed)

func update_safe_zone(enclosed: Array[Vector2i]) -> void:
	var prev_size: int = current_safe_cells.size()
	current_safe_cells = enclosed
	emit_signal("safe_zone_changed", current_safe_cells)

	if wave_director and wave_director.has_method("set_safe_zone_cells"):
		wave_director.set_safe_zone_cells(current_safe_cells)

	if enclosed.size() > 0 and prev_size == 0:
		var main_node: Node = get_tree().root.find_child("Main", true, false)
		if main_node and main_node.has_node("Player"):
			var p: Node = main_node.get_node("Player")
			if p.has_method("spawn_popup_text"):
				p.spawn_popup_text("SAFE ZONE SECURED! (%d tiles)" % enclosed.size(), Color(0.2, 0.9, 1.0))

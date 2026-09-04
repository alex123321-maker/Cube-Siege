extends RefCounted
class_name SafeZoneCalculator

## Pure static domain algorithm for calculating SafeZone enclosed cells via 4-way orthogonal flood-fill.
## Does not depend on SceneTree, nodes, or runtime singletons.

static func calculate_safe_cells(wall_cells: Array[Vector2i]) -> Array[Vector2i]:
	if wall_cells.size() < 4:
		# At least 4 walls are required to enclose at least 1 tile in a discrete 2D grid
		return []

	var min_x: int = 2147483647
	var max_x: int = -2147483648
	var min_z: int = 2147483647
	var max_z: int = -2147483648

	var wall_dict: Dictionary = {}
	for c in wall_cells:
		wall_dict[c] = true
		min_x = mini(min_x, c.x)
		max_x = maxi(max_x, c.x)
		min_z = mini(min_z, c.y)
		max_z = maxi(max_z, c.y)

	# Bounding box expanded by 1 tile padding around all walls
	var box_min_x: int = min_x - 1
	var box_max_x: int = max_x + 1
	var box_min_z: int = min_z - 1
	var box_max_z: int = max_z + 1

	var visited: Dictionary = {}
	var queue: Array[Vector2i] = []

	# Seed perimeter border tiles of expanded bounding box
	for x in range(box_min_x, box_max_x + 1):
		var top_cell = Vector2i(x, box_min_z)
		var bot_cell = Vector2i(x, box_max_z)
		queue.append(top_cell)
		queue.append(bot_cell)
		visited[top_cell] = true
		visited[bot_cell] = true

	for z in range(box_min_z + 1, box_max_z):
		var left_cell = Vector2i(box_min_x, z)
		var right_cell = Vector2i(box_max_x, z)
		queue.append(left_cell)
		queue.append(right_cell)
		visited[left_cell] = true
		visited[right_cell] = true

	# 8 directions: 4 orthogonal + 4 diagonal so diagonal wall gaps are permeable to exterior flood-fill
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(1, 1),
		Vector2i(-1, -1),
		Vector2i(1, -1),
		Vector2i(-1, 1)
	]

	# O(1) amortized queue traversal via head index
	var head: int = 0
	while head < queue.size():
		var curr: Vector2i = queue[head]
		head += 1

		for d in dirs:
			var n: Vector2i = curr + d
			if n.x >= box_min_x and n.x <= box_max_x and n.y >= box_min_z and n.y <= box_max_z:
				if not visited.has(n):
					visited[n] = true
					# Exterior traversal cannot pass through walls
					if not wall_dict.has(n):
						queue.append(n)

	# Interior tiles not visited by exterior flood fill and not walls are enclosed safe cells
	var enclosed: Array[Vector2i] = []
	for x in range(box_min_x + 1, box_max_x):
		for z in range(box_min_z + 1, box_max_z):
			var cell: Vector2i = Vector2i(x, z)
			if not visited.has(cell) and not wall_dict.has(cell):
				enclosed.append(cell)

	return enclosed

extends RefCounted

## Clips a threat triangle into voxel cells before sampling their top surfaces.
## The XZ footprint is preserved; neighbouring stairs never share sloped faces.
static func append_triangle(vertices: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, origin: Vector3, lookup: Callable, heights: Dictionary) -> void:
	if not lookup.is_valid():
		vertices.append(Vector3(a.x, 0.06, a.z))
		vertices.append(Vector3(b.x, 0.06, b.z))
		vertices.append(Vector3(c.x, 0.06, c.z))
		return
	var polygon: Array[Vector2] = [Vector2(a.x + origin.x, a.z + origin.z), Vector2(b.x + origin.x, b.z + origin.z), Vector2(c.x + origin.x, c.z + origin.z)]
	var first_x: int = floori(minf(polygon[0].x, minf(polygon[1].x, polygon[2].x)))
	var last_x: int = ceili(maxf(polygon[0].x, maxf(polygon[1].x, polygon[2].x))) - 1
	var first_z: int = floori(minf(polygon[0].y, minf(polygon[1].y, polygon[2].y)))
	var last_z: int = ceili(maxf(polygon[0].y, maxf(polygon[1].y, polygon[2].y))) - 1
	for x: int in range(first_x, last_x + 1):
		for z: int in range(first_z, last_z + 1):
			var clipped: Array[Vector2] = _clip(polygon, 0, float(x), false)
			clipped = _clip(clipped, 0, float(x + 1), true)
			clipped = _clip(clipped, 1, float(z), false)
			clipped = _clip(clipped, 1, float(z + 1), true)
			if clipped.size() < 3:
				continue
			var cell: Vector2i = Vector2i(x, z)
			if not heights.has(cell):
				heights[cell] = float(lookup.call(x, z))
			var height: float = float(heights[cell]) - origin.y + 0.06
			for index: int in range(1, clipped.size() - 1):
				if absf((clipped[index] - clipped[0]).cross(clipped[index + 1] - clipped[0])) < 0.000001:
					continue
				for corner: int in [0, index, index + 1]:
					var point: Vector2 = clipped[corner]
					vertices.append(Vector3(point.x - origin.x, height, point.y - origin.z))

static func _clip(polygon: Array[Vector2], axis: int, boundary: float, keep_less: bool) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if polygon.is_empty():
		return result
	var previous: Vector2 = polygon[-1]
	var previous_inside: bool = previous[axis] <= boundary if keep_less else previous[axis] >= boundary
	for current: Vector2 in polygon:
		var current_inside: bool = current[axis] <= boundary if keep_less else current[axis] >= boundary
		if current_inside != previous_inside:
			var fraction: float = (boundary - previous[axis]) / (current[axis] - previous[axis])
			result.append(previous.lerp(current, fraction))
		if current_inside:
			result.append(current)
		previous = current
		previous_inside = current_inside
	return result

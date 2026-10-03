extends RefCounted

## Projects the authoritative charge rectangle onto voxel tops. Each clipped
## quad stays at its own terrain height, so a warning cannot disappear in stairs.
static func create_mesh(origin: Vector3, direction: Vector3, distance: float, half_width: float, terrain: MapGenerator) -> ArrayMesh:
	var side: Vector3 = Vector3(-direction.z, 0.0, direction.x)
	var end: Vector3 = origin + direction * distance
	var reach: float = half_width * 2.0
	var min_x: int = floori(minf(origin.x, end.x) - reach)
	var max_x: int = ceili(maxf(origin.x, end.x) + reach)
	var min_z: int = floori(minf(origin.z, end.z) - reach)
	var max_z: int = ceili(maxf(origin.z, end.z) + reach)
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	for x in range(min_x, max_x + 1):
		for z in range(min_z, max_z + 1):
			var polygon: Array[Vector2] = []
			for corner: Vector2 in [Vector2(x, z), Vector2(x + 1, z), Vector2(x + 1, z + 1), Vector2(x, z + 1)]:
				var relative: Vector3 = Vector3(corner.x, origin.y, corner.y) - origin
				polygon.append(Vector2(relative.dot(side), relative.dot(direction)))
			polygon = _clip(polygon, 0, -half_width, false)
			polygon = _clip(polygon, 0, half_width, true)
			polygon = _clip(polygon, 1, -half_width, false)
			polygon = _clip(polygon, 1, distance + half_width, true)
			if polygon.size() < 3:
				continue
			var height: float = float(terrain.get_voxel_height(x, z)) - origin.y
			for triangle in range(1, polygon.size() - 1):
				for index in [0, triangle, triangle + 1]:
					var point: Vector2 = polygon[index]
					vertices.append(Vector3(point.x, height, distance * 0.5 - point.y))
					normals.append(Vector3.UP)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh: ArrayMesh = ArrayMesh.new()
	if not vertices.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

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

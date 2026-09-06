extends RefCounted
class_name ChunkBuilder

## ChunkBuilder: Procedurally constructs unified mesh and collision geometry
## for a 16x16 voxel terrain chunk with zero border seams and optimized draw calls.

const CHUNK_SIZE: int = 16

static func build_chunk_terrain(
	cx: int,
	cz: int,
	seed_val: int,
	mat_forest: Material,
	mat_plains: Material,
	mat_mountains: Material,
	mat_cliff: Material
) -> Dictionary:
	var st_forest: SurfaceTool = SurfaceTool.new()
	var st_plains: SurfaceTool = SurfaceTool.new()
	var st_mountains: SurfaceTool = SurfaceTool.new()
	var st_cliff: SurfaceTool = SurfaceTool.new()

	st_forest.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_forest.set_material(mat_forest)

	st_plains.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_plains.set_material(mat_plains)

	st_mountains.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_mountains.set_material(mat_mountains)

	st_cliff.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_cliff.set_material(mat_cliff)

	var count_forest: int = 0
	var count_plains: int = 0
	var count_mountains: int = 0
	var count_cliff: int = 0

	var origin_x: int = cx * CHUNK_SIZE
	var origin_z: int = cz * CHUNK_SIZE

	for lz in range(CHUNK_SIZE):
		for lx in range(CHUNK_SIZE):
			var wx: int = origin_x + lx
			var wz: int = origin_z + lz

			var y: int = BiomeSystem.get_voxel_height(wx, wz, seed_val)
			var y_top: float = float(y)

			# Stochastic dithering across biome blend weights for smooth organic material transitions
			var biome_info: Dictionary = BiomeSystem.sample_biome_weights(float(wx) + 0.5, float(wz) + 0.5, seed_val)
			var weights: Dictionary = biome_info["weights"]
			var wf: float = weights.get(BiomeSystem.BiomeType.FOREST, 0.0)
			var wp: float = weights.get(BiomeSystem.BiomeType.PLAINS, 0.0)

			var dither_hash: int = int((wx * 374761393) ^ (wz * 668265263) ^ (seed_val * 1274126177)) & 0x7fffffff
			var dither_val: float = float(dither_hash % 10000) / 10000.0

			var st_top: SurfaceTool = st_mountains
			if dither_val < wf:
				st_top = st_forest
				count_forest += 1
			elif dither_val < wf + wp:
				st_top = st_plains
				count_plains += 1
			else:
				count_mountains += 1

			# 1. Top face quad
			var fx: float = float(wx)
			var fz: float = float(wz)

			var p0: Vector3 = Vector3(fx, y_top, fz)
			var p1: Vector3 = Vector3(fx + 1.0, y_top, fz)
			var p2: Vector3 = Vector3(fx + 1.0, y_top, fz + 1.0)
			var p3: Vector3 = Vector3(fx, y_top, fz + 1.0)

			_add_quad(st_top, p0, p1, p2, p3, Vector3.UP)

			# 2. Side faces for step drops (North: z-1, South: z+1, West: x-1, East: x+1)
			# North (-Z)
			var yn: int = BiomeSystem.get_voxel_height(wx, wz - 1, seed_val)
			if yn < y:
				var y_bot: float = float(yn)
				var s0: Vector3 = Vector3(fx, y_bot, fz)
				var s1: Vector3 = Vector3(fx, y_top, fz)
				var s2: Vector3 = Vector3(fx + 1.0, y_top, fz)
				var s3: Vector3 = Vector3(fx + 1.0, y_bot, fz)
				_add_quad(st_cliff, s0, s1, s2, s3, Vector3(0, 0, -1))
				count_cliff += 1

			# South (+Z)
			var ys: int = BiomeSystem.get_voxel_height(wx, wz + 1, seed_val)
			if ys < y:
				var y_bot: float = float(ys)
				var s0: Vector3 = Vector3(fx + 1.0, y_bot, fz + 1.0)
				var s1: Vector3 = Vector3(fx + 1.0, y_top, fz + 1.0)
				var s2: Vector3 = Vector3(fx, y_top, fz + 1.0)
				var s3: Vector3 = Vector3(fx, y_bot, fz + 1.0)
				_add_quad(st_cliff, s0, s1, s2, s3, Vector3(0, 0, 1))
				count_cliff += 1

			# West (-X)
			var yw: int = BiomeSystem.get_voxel_height(wx - 1, wz, seed_val)
			if yw < y:
				var y_bot: float = float(yw)
				var s0: Vector3 = Vector3(fx, y_bot, fz + 1.0)
				var s1: Vector3 = Vector3(fx, y_top, fz + 1.0)
				var s2: Vector3 = Vector3(fx, y_top, fz)
				var s3: Vector3 = Vector3(fx, y_bot, fz)
				_add_quad(st_cliff, s0, s1, s2, s3, Vector3(-1, 0, 0))
				count_cliff += 1

			# East (+X)
			var ye: int = BiomeSystem.get_voxel_height(wx + 1, wz, seed_val)
			if ye < y:
				var y_bot: float = float(ye)
				var s0: Vector3 = Vector3(fx + 1.0, y_bot, fz)
				var s1: Vector3 = Vector3(fx + 1.0, y_top, fz)
				var s2: Vector3 = Vector3(fx + 1.0, y_top, fz + 1.0)
				var s3: Vector3 = Vector3(fx + 1.0, y_bot, fz + 1.0)
				_add_quad(st_cliff, s0, s1, s2, s3, Vector3(1, 0, 0))
				count_cliff += 1


	var mesh: ArrayMesh = ArrayMesh.new()
	if count_forest > 0:
		st_forest.commit(mesh)
	if count_plains > 0:
		st_plains.commit(mesh)
	if count_mountains > 0:
		st_mountains.commit(mesh)
	if count_cliff > 0:
		st_cliff.commit(mesh)

	var shape: Shape3D = null
	if mesh.get_surface_count() > 0:
		shape = mesh.create_trimesh_shape()

	return {
		"mesh": mesh,
		"shape": shape
	}

static func _add_quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, norm: Vector3) -> void:
	st.set_normal(norm)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(p0)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(p1)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(p2)

	st.set_normal(norm)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(p0)
	st.set_uv(Vector2(1, 1))
	st.add_vertex(p2)
	st.set_uv(Vector2(0, 1))
	st.add_vertex(p3)

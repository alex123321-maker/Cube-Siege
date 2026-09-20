extends RefCounted
class_name ChunkBuilder

## ChunkBuilder: Procedurally constructs unified mesh and collision geometry
## for a 16x16 voxel terrain chunk with zero border seams, natural cliff grouping,
## terraced mountain massing, and optimized draw calls.

const CHUNK_SIZE: int = 16
const SKIRT_DEPTH: float = 16.0
const LEDGE_OVERHANG: float = 0.12
const LEDGE_THICKNESS: float = 0.15
const BUTTRESS_EXTRUSION: float = 0.14

static func build_chunk_terrain(
	cx: int,
	cz: int,
	seed_val: int,
	mat_forest: Material,
	mat_plains: Material,
	mat_mountains: Material,
	mat_cliff: Material,
	mat_turf: Material = null
) -> Dictionary:
	var st_forest: SurfaceTool = SurfaceTool.new()
	var st_plains: SurfaceTool = SurfaceTool.new()
	var st_mountains: SurfaceTool = SurfaceTool.new()
	var st_cliff: SurfaceTool = SurfaceTool.new()
	var st_turf: SurfaceTool = SurfaceTool.new()
	var st_col: SurfaceTool = SurfaceTool.new()

	st_forest.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_forest.set_material(mat_forest)

	st_plains.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_plains.set_material(mat_plains)

	st_mountains.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_mountains.set_material(mat_mountains)

	st_cliff.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_cliff.set_material(mat_cliff)

	st_turf.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_turf.set_material(mat_turf if mat_turf != null else mat_forest)

	st_col.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Surface counts array: [0: Forest, 1: Plains, 2: Mountains, 3: Cliff, 4: Turf]
	var counts: Array[int] = [0, 0, 0, 0, 0]

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
			var cell_biome: int = 2 # 0: Forest, 1: Plains, 2: Mountains
			if dither_val < wf:
				st_top = st_forest
				cell_biome = 0
				counts[0] += 1
			elif dither_val < wf + wp:
				st_top = st_plains
				cell_biome = 1
				counts[1] += 1
			else:
				counts[2] += 1

			# 1. Top face quad
			var fx: float = float(wx)
			var fz: float = float(wz)

			var p0: Vector3 = Vector3(fx, y_top, fz)
			var p1: Vector3 = Vector3(fx + 1.0, y_top, fz)
			var p2: Vector3 = Vector3(fx + 1.0, y_top, fz + 1.0)
			var p3: Vector3 = Vector3(fx, y_top, fz + 1.0)

			# Continuous world-aligned UVs prevent artificial 1m cell tile seams
			_add_quad_world_uv(st_top, p0, p1, p2, p3, Vector3.UP, Vector2(fx, fz), Vector2(fx + 1.0, fz + 1.0))
			_add_quad_col(st_col, p0, p1, p2, p3)

			# 2. Side faces for step drops (North: z-1, South: z+1, West: x-1, East: x+1)
			# North (-Z)
			var yn: int = BiomeSystem.get_voxel_height(wx, wz - 1, seed_val)
			if yn < y:
				var y_bot: float = float(yn)
				var s0: Vector3 = Vector3(fx, y_bot, fz)
				var s1: Vector3 = Vector3(fx, y_top, fz)
				var s2: Vector3 = Vector3(fx + 1.0, y_top, fz)
				var s3: Vector3 = Vector3(fx + 1.0, y_bot, fz)

				# Collision quad (authoritative, strictly unchanged)
				_add_quad_col(st_col, s0, s1, s2, s3)

				# Visual presentation & material classification
				var visual_res: Dictionary = _resolve_side_presentation(
					wx, wz, wx, wz - 1, y, yn, cell_biome, seed_val,
					st_forest, st_plains, st_mountains, st_cliff, st_turf,
					Vector3(0, 0, -1)
				)
				var st_side: SurfaceTool = visual_res["surface_tool"]
				var norm_side: Vector3 = visual_res["normal"]
				_add_side_quad_uv(st_side, s0, s1, s2, s3, norm_side, fx, fx + 1.0, y_bot, y_top)
				counts[visual_res["type"]] += 1

				# Ledge dressing & rock buttresses on prominent cliffs
				if visual_res["has_dressing"]:
					_add_ledge_dressing_north(st_cliff, fx, y_top, fz)
					counts[3] += 3
				if visual_res["has_buttress"]:
					_add_buttress_north(st_cliff, fx, y_bot, y_top, fz)
					counts[3] += 3

			# Perimeter skirt on North chunk boundary (lz == 0) prevents void sightlines
			if lz == 0:
				var skirt_top: float = float(min(y, yn))
				var skirt_bot: float = skirt_top - SKIRT_DEPTH
				var k0: Vector3 = Vector3(fx, skirt_bot, fz)
				var k1: Vector3 = Vector3(fx, skirt_top, fz)
				var k2: Vector3 = Vector3(fx + 1.0, skirt_top, fz)
				var k3: Vector3 = Vector3(fx + 1.0, skirt_bot, fz)
				_add_side_quad_uv(st_cliff, k0, k1, k2, k3, Vector3(0, 0, -1), fx, fx + 1.0, skirt_bot, skirt_top)
				counts[3] += 1

			# South (+Z)
			var ys: int = BiomeSystem.get_voxel_height(wx, wz + 1, seed_val)
			if ys < y:
				var y_bot: float = float(ys)
				var s0: Vector3 = Vector3(fx + 1.0, y_bot, fz + 1.0)
				var s1: Vector3 = Vector3(fx + 1.0, y_top, fz + 1.0)
				var s2: Vector3 = Vector3(fx, y_top, fz + 1.0)
				var s3: Vector3 = Vector3(fx, y_bot, fz + 1.0)

				_add_quad_col(st_col, s0, s1, s2, s3)

				var visual_res: Dictionary = _resolve_side_presentation(
					wx, wz, wx, wz + 1, y, ys, cell_biome, seed_val,
					st_forest, st_plains, st_mountains, st_cliff, st_turf,
					Vector3(0, 0, 1)
				)
				var st_side: SurfaceTool = visual_res["surface_tool"]
				var norm_side: Vector3 = visual_res["normal"]
				_add_side_quad_uv(st_side, s0, s1, s2, s3, norm_side, fx + 1.0, fx, y_bot, y_top)
				counts[visual_res["type"]] += 1

				if visual_res["has_dressing"]:
					_add_ledge_dressing_south(st_cliff, fx, y_top, fz + 1.0)
					counts[3] += 3
				if visual_res["has_buttress"]:
					_add_buttress_south(st_cliff, fx, y_bot, y_top, fz + 1.0)
					counts[3] += 3

			# Perimeter skirt on South chunk boundary (lz == CHUNK_SIZE - 1)
			if lz == CHUNK_SIZE - 1:
				var skirt_top: float = float(min(y, ys))
				var skirt_bot: float = skirt_top - SKIRT_DEPTH
				var k0: Vector3 = Vector3(fx + 1.0, skirt_bot, fz + 1.0)
				var k1: Vector3 = Vector3(fx + 1.0, skirt_top, fz + 1.0)
				var k2: Vector3 = Vector3(fx, skirt_top, fz + 1.0)
				var k3: Vector3 = Vector3(fx, skirt_bot, fz + 1.0)
				_add_side_quad_uv(st_cliff, k0, k1, k2, k3, Vector3(0, 0, 1), fx + 1.0, fx, skirt_bot, skirt_top)
				counts[3] += 1

			# West (-X)
			var yw: int = BiomeSystem.get_voxel_height(wx - 1, wz, seed_val)
			if yw < y:
				var y_bot: float = float(yw)
				var s0: Vector3 = Vector3(fx, y_bot, fz + 1.0)
				var s1: Vector3 = Vector3(fx, y_top, fz + 1.0)
				var s2: Vector3 = Vector3(fx, y_top, fz)
				var s3: Vector3 = Vector3(fx, y_bot, fz)

				_add_quad_col(st_col, s0, s1, s2, s3)

				var visual_res: Dictionary = _resolve_side_presentation(
					wx, wz, wx - 1, wz, y, yw, cell_biome, seed_val,
					st_forest, st_plains, st_mountains, st_cliff, st_turf,
					Vector3(-1, 0, 0)
				)
				var st_side: SurfaceTool = visual_res["surface_tool"]
				var norm_side: Vector3 = visual_res["normal"]
				_add_side_quad_uv(st_side, s0, s1, s2, s3, norm_side, fz + 1.0, fz, y_bot, y_top)
				counts[visual_res["type"]] += 1

				if visual_res["has_dressing"]:
					_add_ledge_dressing_west(st_cliff, fx, y_top, fz)
					counts[3] += 3
				if visual_res["has_buttress"]:
					_add_buttress_west(st_cliff, fx, y_bot, y_top, fz)
					counts[3] += 3

			# Perimeter skirt on West chunk boundary (lx == 0)
			if lx == 0:
				var skirt_top: float = float(min(y, yw))
				var skirt_bot: float = skirt_top - SKIRT_DEPTH
				var k0: Vector3 = Vector3(fx, skirt_bot, fz + 1.0)
				var k1: Vector3 = Vector3(fx, skirt_top, fz + 1.0)
				var k2: Vector3 = Vector3(fx, skirt_top, fz)
				var k3: Vector3 = Vector3(fx, skirt_bot, fz)
				_add_side_quad_uv(st_cliff, k0, k1, k2, k3, Vector3(-1, 0, 0), fz + 1.0, fz, skirt_bot, skirt_top)
				counts[3] += 1

			# East (+X)
			var ye: int = BiomeSystem.get_voxel_height(wx + 1, wz, seed_val)
			if ye < y:
				var y_bot: float = float(ye)
				var s0: Vector3 = Vector3(fx + 1.0, y_bot, fz)
				var s1: Vector3 = Vector3(fx + 1.0, y_top, fz)
				var s2: Vector3 = Vector3(fx + 1.0, y_top, fz + 1.0)
				var s3: Vector3 = Vector3(fx + 1.0, y_bot, fz + 1.0)

				_add_quad_col(st_col, s0, s1, s2, s3)

				var visual_res: Dictionary = _resolve_side_presentation(
					wx, wz, wx + 1, wz, y, ye, cell_biome, seed_val,
					st_forest, st_plains, st_mountains, st_cliff, st_turf,
					Vector3(1, 0, 0)
				)
				var st_side: SurfaceTool = visual_res["surface_tool"]
				var norm_side: Vector3 = visual_res["normal"]
				_add_side_quad_uv(st_side, s0, s1, s2, s3, norm_side, fz, fz + 1.0, y_bot, y_top)
				counts[visual_res["type"]] += 1

				if visual_res["has_dressing"]:
					_add_ledge_dressing_east(st_cliff, fx + 1.0, y_top, fz)
					counts[3] += 3
				if visual_res["has_buttress"]:
					_add_buttress_east(st_cliff, fx + 1.0, y_bot, y_top, fz)
					counts[3] += 3

			# Perimeter skirt on East chunk boundary (lx == CHUNK_SIZE - 1)
			if lx == CHUNK_SIZE - 1:
				var skirt_top: float = float(min(y, ye))
				var skirt_bot: float = skirt_top - SKIRT_DEPTH
				var k0: Vector3 = Vector3(fx + 1.0, skirt_bot, fz)
				var k1: Vector3 = Vector3(fx + 1.0, skirt_top, fz)
				var k2: Vector3 = Vector3(fx + 1.0, skirt_top, fz + 1.0)
				var k3: Vector3 = Vector3(fx + 1.0, skirt_bot, fz + 1.0)
				_add_side_quad_uv(st_cliff, k0, k1, k2, k3, Vector3(1, 0, 0), fz, fz + 1.0, skirt_bot, skirt_top)
				counts[3] += 1

	# Commit visual mesh surfaces
	var mesh: ArrayMesh = ArrayMesh.new()
	if counts[0] > 0:
		st_forest.commit(mesh)
	if counts[1] > 0:
		st_plains.commit(mesh)
	if counts[2] > 0:
		st_mountains.commit(mesh)
	if counts[3] > 0:
		st_cliff.commit(mesh)
	if counts[4] > 0:
		st_turf.commit(mesh)

	# Commit authoritative collision shape
	var col_mesh: ArrayMesh = ArrayMesh.new()
	st_col.commit(col_mesh)

	var shape: Shape3D = null
	if col_mesh.get_surface_count() > 0:
		shape = col_mesh.create_trimesh_shape()

	return {
		"mesh": mesh,
		"shape": shape
	}

static func _resolve_side_presentation(
	wx: int,
	wz: int,
	nx: int,
	nz: int,
	y: int,
	yn: int,
	cell_biome: int,
	seed_val: int,
	st_forest: SurfaceTool,
	st_plains: SurfaceTool,
	st_mountains: SurfaceTool,
	st_cliff: SurfaceTool,
	st_turf: SurfaceTool,
	base_normal: Vector3
) -> Dictionary:
	var h_drop: int = y - yn
	var is_trail_step: bool = BiomeSystem.is_mountain_trail(wx, wz, seed_val) or BiomeSystem.is_mountain_trail(nx, nz, seed_val)

	# Softened normal for 1-meter terrace steps catches sunlight from above,
	# completely eliminating the harsh black terminator shadow stripe
	var softened_normal: Vector3 = Vector3(base_normal.x * 0.4, 0.9, base_normal.z * 0.4).normalized()

	# 1. Mountain trail: preserve clean stone path appearance without zebra stripes
	if is_trail_step and h_drop <= 1:
		return {
			"surface_tool": st_mountains,
			"normal": softened_normal,
			"type": 2,
			"has_dressing": false,
			"has_buttress": false
		}

	# 2. Forest / Plains gentle slope step: use matching grass material for seamless grassy hillside
	if h_drop <= 2 and cell_biome != 2:
		var grass_tool: SurfaceTool = st_forest if cell_biome == 0 else st_plains
		var grass_type: int = cell_biome
		return {
			"surface_tool": grass_tool,
			"normal": softened_normal,
			"type": grass_type,
			"has_dressing": false,
			"has_buttress": false
		}

	# 3. Mountains: group slopes into broad stone terrace masses and distinct cliff clusters
	if cell_biome == 2:
		# Coherent spatial clustering for natural rock bluffs vs broad terrace masses
		var cx_f: float = float(wx) * 0.18
		var cz_f: float = float(wz) * 0.18
		var seed_phase: float = float(seed_val % 79) * 0.12
		var cluster_field: float = sin(cx_f + seed_phase) * cos(cz_f * 0.85 + seed_phase * 0.7) + sin((cx_f + cz_f) * 0.5) * 0.35

		# A cliff cluster forms bold escarpments in high-relief zones
		var is_cliff_cluster: bool = false
		if h_drop >= 3:
			is_cliff_cluster = true
		elif h_drop >= 2:
			is_cliff_cluster = (cluster_field > -0.10)
		elif h_drop == 1 and (y % 4 == 0):
			is_cliff_cluster = (cluster_field > 0.40)

		if not is_cliff_cluster:
			# Cohesive mountain slate terrace step
			return {
				"surface_tool": st_mountains,
				"normal": softened_normal,
				"type": 2,
				"has_dressing": false,
				"has_buttress": false
			}
		else:
			# Bold cliff face with stratified rock texture and optional ledge dressing
			var has_dressing: bool = (h_drop >= 2)
			var has_buttress: bool = (h_drop >= 3) and (((wx * 11 + wz * 17 + seed_val) % 3) == 0)
			return {
				"surface_tool": st_cliff,
				"normal": base_normal,
				"type": 3,
				"has_dressing": has_dressing,
				"has_buttress": has_buttress
			}

	# 4. Sheer drops in other biomes (h_drop >= 3): Exposed bedrock cliff
	return {
		"surface_tool": st_cliff,
		"normal": base_normal,
		"type": 3,
		"has_dressing": true,
		"has_buttress": (h_drop >= 3) and (((wx * 13 + wz * 23 + seed_val) % 3) == 0)
	}

static func _add_quad_world_uv(
	st: SurfaceTool,
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	p3: Vector3,
	norm: Vector3,
	uv_min: Vector2,
	uv_max: Vector2
) -> void:
	st.set_normal(norm)
	st.set_uv(Vector2(uv_min.x, uv_min.y))
	st.add_vertex(p0)
	st.set_uv(Vector2(uv_max.x, uv_min.y))
	st.add_vertex(p1)
	st.set_uv(Vector2(uv_max.x, uv_max.y))
	st.add_vertex(p2)

	st.set_normal(norm)
	st.set_uv(Vector2(uv_min.x, uv_min.y))
	st.add_vertex(p0)
	st.set_uv(Vector2(uv_max.x, uv_max.y))
	st.add_vertex(p2)
	st.set_uv(Vector2(uv_min.x, uv_max.y))
	st.add_vertex(p3)

static func _add_side_quad_uv(
	st: SurfaceTool,
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	p3: Vector3,
	norm: Vector3,
	u_start: float,
	u_end: float,
	v_bot: float,
	v_top: float
) -> void:
	st.set_normal(norm)
	st.set_uv(Vector2(u_start, v_bot))
	st.add_vertex(p0)
	st.set_uv(Vector2(u_start, v_top))
	st.add_vertex(p1)
	st.set_uv(Vector2(u_end, v_top))
	st.add_vertex(p2)

	st.set_normal(norm)
	st.set_uv(Vector2(u_start, v_bot))
	st.add_vertex(p0)
	st.set_uv(Vector2(u_end, v_top))
	st.add_vertex(p2)
	st.set_uv(Vector2(u_end, v_bot))
	st.add_vertex(p3)

static func _add_quad_col(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	st.add_vertex(p0)
	st.add_vertex(p1)
	st.add_vertex(p2)

	st.add_vertex(p0)
	st.add_vertex(p2)
	st.add_vertex(p3)

# -----------------------------------------------------------------------------
# Visual Ledge Dressing (Overhanging stone lip along cliff tops)
# -----------------------------------------------------------------------------
static func _add_ledge_dressing_north(st: SurfaceTool, fx: float, y_top: float, fz: float) -> void:
	var z_over: float = fz - LEDGE_OVERHANG
	var y_lip: float = y_top - LEDGE_THICKNESS

	# Top face of overhanging ledge
	var t0: Vector3 = Vector3(fx, y_top, fz)
	var t1: Vector3 = Vector3(fx + 1.0, y_top, fz)
	var t2: Vector3 = Vector3(fx + 1.0, y_top, z_over)
	var t3: Vector3 = Vector3(fx, y_top, z_over)
	_add_quad_world_uv(st, t0, t1, t2, t3, Vector3.UP, Vector2(fx, fz), Vector2(fx + 1.0, z_over))

	# Front face of ledge
	var f0: Vector3 = Vector3(fx, y_lip, z_over)
	var f1: Vector3 = Vector3(fx, y_top, z_over)
	var f2: Vector3 = Vector3(fx + 1.0, y_top, z_over)
	var f3: Vector3 = Vector3(fx + 1.0, y_lip, z_over)
	_add_side_quad_uv(st, f0, f1, f2, f3, Vector3(0, 0, -1), fx, fx + 1.0, y_lip, y_top)

	# Underside return
	var b0: Vector3 = Vector3(fx, y_lip, z_over)
	var b1: Vector3 = Vector3(fx + 1.0, y_lip, z_over)
	var b2: Vector3 = Vector3(fx + 1.0, y_lip, fz)
	var b3: Vector3 = Vector3(fx, y_lip, fz)
	_add_quad_world_uv(st, b0, b1, b2, b3, Vector3.DOWN, Vector2(fx, z_over), Vector2(fx + 1.0, fz))

static func _add_ledge_dressing_south(st: SurfaceTool, fx: float, y_top: float, fz: float) -> void:
	var z_over: float = fz + LEDGE_OVERHANG
	var y_lip: float = y_top - LEDGE_THICKNESS

	var t0: Vector3 = Vector3(fx + 1.0, y_top, fz)
	var t1: Vector3 = Vector3(fx, y_top, fz)
	var t2: Vector3 = Vector3(fx, y_top, z_over)
	var t3: Vector3 = Vector3(fx + 1.0, y_top, z_over)
	_add_quad_world_uv(st, t0, t1, t2, t3, Vector3.UP, Vector2(fx + 1.0, fz), Vector2(fx, z_over))

	var f0: Vector3 = Vector3(fx + 1.0, y_lip, z_over)
	var f1: Vector3 = Vector3(fx + 1.0, y_top, z_over)
	var f2: Vector3 = Vector3(fx, y_top, z_over)
	var f3: Vector3 = Vector3(fx, y_lip, z_over)
	_add_side_quad_uv(st, f0, f1, f2, f3, Vector3(0, 0, 1), fx + 1.0, fx, y_lip, y_top)

	var b0: Vector3 = Vector3(fx + 1.0, y_lip, z_over)
	var b1: Vector3 = Vector3(fx, y_lip, z_over)
	var b2: Vector3 = Vector3(fx, y_lip, fz)
	var b3: Vector3 = Vector3(fx + 1.0, y_lip, fz)
	_add_quad_world_uv(st, b0, b1, b2, b3, Vector3.DOWN, Vector2(fx + 1.0, z_over), Vector2(fx, fz))

static func _add_ledge_dressing_west(st: SurfaceTool, fx: float, y_top: float, fz: float) -> void:
	var x_over: float = fx - LEDGE_OVERHANG
	var y_lip: float = y_top - LEDGE_THICKNESS

	var t0: Vector3 = Vector3(fx, y_top, fz + 1.0)
	var t1: Vector3 = Vector3(fx, y_top, fz)
	var t2: Vector3 = Vector3(x_over, y_top, fz)
	var t3: Vector3 = Vector3(x_over, y_top, fz + 1.0)
	_add_quad_world_uv(st, t0, t1, t2, t3, Vector3.UP, Vector2(fx, fz + 1.0), Vector2(x_over, fz))

	var f0: Vector3 = Vector3(x_over, y_lip, fz + 1.0)
	var f1: Vector3 = Vector3(x_over, y_top, fz + 1.0)
	var f2: Vector3 = Vector3(x_over, y_top, fz)
	var f3: Vector3 = Vector3(x_over, y_lip, fz)
	_add_side_quad_uv(st, f0, f1, f2, f3, Vector3(-1, 0, 0), fz + 1.0, fz, y_lip, y_top)

	var b0: Vector3 = Vector3(x_over, y_lip, fz + 1.0)
	var b1: Vector3 = Vector3(x_over, y_lip, fz)
	var b2: Vector3 = Vector3(fx, y_lip, fz)
	var b3: Vector3 = Vector3(fx, y_lip, fz + 1.0)
	_add_quad_world_uv(st, b0, b1, b2, b3, Vector3.DOWN, Vector2(x_over, fz + 1.0), Vector2(fx, fz))

static func _add_ledge_dressing_east(st: SurfaceTool, fx: float, y_top: float, fz: float) -> void:
	var x_over: float = fx + LEDGE_OVERHANG
	var y_lip: float = y_top - LEDGE_THICKNESS

	var t0: Vector3 = Vector3(fx, y_top, fz)
	var t1: Vector3 = Vector3(fx, y_top, fz + 1.0)
	var t2: Vector3 = Vector3(x_over, y_top, fz + 1.0)
	var t3: Vector3 = Vector3(x_over, y_top, fz)
	_add_quad_world_uv(st, t0, t1, t2, t3, Vector3.UP, Vector2(fx, fz), Vector2(x_over, fz + 1.0))

	var f0: Vector3 = Vector3(x_over, y_lip, fz)
	var f1: Vector3 = Vector3(x_over, y_top, fz)
	var f2: Vector3 = Vector3(x_over, y_top, fz + 1.0)
	var f3: Vector3 = Vector3(x_over, y_lip, fz + 1.0)
	_add_side_quad_uv(st, f0, f1, f2, f3, Vector3(1, 0, 0), fz, fz + 1.0, y_lip, y_top)

	var b0: Vector3 = Vector3(x_over, y_lip, fz)
	var b1: Vector3 = Vector3(x_over, y_lip, fz + 1.0)
	var b2: Vector3 = Vector3(fx, y_lip, fz + 1.0)
	var b3: Vector3 = Vector3(fx, y_lip, fz)
	_add_quad_world_uv(st, b0, b1, b2, b3, Vector3.DOWN, Vector2(x_over, fz), Vector2(fx, fz + 1.0))

# -----------------------------------------------------------------------------
# Visual Rock Buttresses (3D faceted rock-face clusters on tall cliffs)
# -----------------------------------------------------------------------------
static func _add_buttress_north(st: SurfaceTool, fx: float, y_bot: float, y_top: float, fz: float) -> void:
	var z_b: float = fz - BUTTRESS_EXTRUSION
	var y_high: float = y_top - LEDGE_THICKNESS
	if y_high <= y_bot: return

	var b0: Vector3 = Vector3(fx + 0.15, y_bot, z_b)
	var b1: Vector3 = Vector3(fx + 0.15, y_high, z_b)
	var b2: Vector3 = Vector3(fx + 0.85, y_high, z_b)
	var b3: Vector3 = Vector3(fx + 0.85, y_bot, z_b)
	_add_side_quad_uv(st, b0, b1, b2, b3, Vector3(0, 0, -1), fx + 0.15, fx + 0.85, y_bot, y_high)

	var s_w0: Vector3 = Vector3(fx + 0.15, y_bot, fz)
	var s_w1: Vector3 = Vector3(fx + 0.15, y_high, fz)
	var s_w2: Vector3 = Vector3(fx + 0.15, y_high, z_b)
	var s_w3: Vector3 = Vector3(fx + 0.15, y_bot, z_b)
	_add_side_quad_uv(st, s_w0, s_w1, s_w2, s_w3, Vector3(-1, 0, 0), fz, z_b, y_bot, y_high)

	var s_e0: Vector3 = Vector3(fx + 0.85, y_bot, z_b)
	var s_e1: Vector3 = Vector3(fx + 0.85, y_high, z_b)
	var s_e2: Vector3 = Vector3(fx + 0.85, y_high, fz)
	var s_e3: Vector3 = Vector3(fx + 0.85, y_bot, fz)
	_add_side_quad_uv(st, s_e0, s_e1, s_e2, s_e3, Vector3(1, 0, 0), z_b, fz, y_bot, y_high)

static func _add_buttress_south(st: SurfaceTool, fx: float, y_bot: float, y_top: float, fz: float) -> void:
	var z_b: float = fz + BUTTRESS_EXTRUSION
	var y_high: float = y_top - LEDGE_THICKNESS
	if y_high <= y_bot: return

	var b0: Vector3 = Vector3(fx + 0.85, y_bot, z_b)
	var b1: Vector3 = Vector3(fx + 0.85, y_high, z_b)
	var b2: Vector3 = Vector3(fx + 0.15, y_high, z_b)
	var b3: Vector3 = Vector3(fx + 0.15, y_bot, z_b)
	_add_side_quad_uv(st, b0, b1, b2, b3, Vector3(0, 0, 1), fx + 0.85, fx + 0.15, y_bot, y_high)

	var s_e0: Vector3 = Vector3(fx + 0.85, y_bot, fz)
	var s_e1: Vector3 = Vector3(fx + 0.85, y_high, fz)
	var s_e2: Vector3 = Vector3(fx + 0.85, y_high, z_b)
	var s_e3: Vector3 = Vector3(fx + 0.85, y_bot, z_b)
	_add_side_quad_uv(st, s_e0, s_e1, s_e2, s_e3, Vector3(1, 0, 0), fz, z_b, y_bot, y_high)

	var s_w0: Vector3 = Vector3(fx + 0.15, y_bot, z_b)
	var s_w1: Vector3 = Vector3(fx + 0.15, y_high, z_b)
	var s_w2: Vector3 = Vector3(fx + 0.15, y_high, fz)
	var s_w3: Vector3 = Vector3(fx + 0.15, y_bot, fz)
	_add_side_quad_uv(st, s_w0, s_w1, s_w2, s_w3, Vector3(-1, 0, 0), z_b, fz, y_bot, y_high)

static func _add_buttress_west(st: SurfaceTool, fx: float, y_bot: float, y_top: float, fz: float) -> void:
	var x_b: float = fx - BUTTRESS_EXTRUSION
	var y_high: float = y_top - LEDGE_THICKNESS
	if y_high <= y_bot: return

	var b0: Vector3 = Vector3(x_b, y_bot, fz + 0.85)
	var b1: Vector3 = Vector3(x_b, y_high, fz + 0.85)
	var b2: Vector3 = Vector3(x_b, y_high, fz + 0.15)
	var b3: Vector3 = Vector3(x_b, y_bot, fz + 0.15)
	_add_side_quad_uv(st, b0, b1, b2, b3, Vector3(-1, 0, 0), fz + 0.85, fz + 0.15, y_bot, y_high)

	var s_s0: Vector3 = Vector3(fx, y_bot, fz + 0.85)
	var s_s1: Vector3 = Vector3(fx, y_high, fz + 0.85)
	var s_s2: Vector3 = Vector3(x_b, y_high, fz + 0.85)
	var s_s3: Vector3 = Vector3(x_b, y_bot, fz + 0.85)
	_add_side_quad_uv(st, s_s0, s_s1, s_s2, s_s3, Vector3(0, 0, 1), fx, x_b, y_bot, y_high)

	var s_n0: Vector3 = Vector3(x_b, y_bot, fz + 0.15)
	var s_n1: Vector3 = Vector3(x_b, y_high, fz + 0.15)
	var s_n2: Vector3 = Vector3(fx, y_high, fz + 0.15)
	var s_n3: Vector3 = Vector3(fx, y_bot, fz + 0.15)
	_add_side_quad_uv(st, s_n0, s_n1, s_n2, s_n3, Vector3(0, 0, -1), x_b, fx, y_bot, y_high)

static func _add_buttress_east(st: SurfaceTool, fx: float, y_bot: float, y_top: float, fz: float) -> void:
	var x_b: float = fx + BUTTRESS_EXTRUSION
	var y_high: float = y_top - LEDGE_THICKNESS
	if y_high <= y_bot: return

	var b0: Vector3 = Vector3(x_b, y_bot, fz + 0.15)
	var b1: Vector3 = Vector3(x_b, y_high, fz + 0.15)
	var b2: Vector3 = Vector3(x_b, y_high, fz + 0.85)
	var b3: Vector3 = Vector3(x_b, y_bot, fz + 0.85)
	_add_side_quad_uv(st, b0, b1, b2, b3, Vector3(1, 0, 0), fz + 0.15, fz + 0.85, y_bot, y_high)

	var s_n0: Vector3 = Vector3(fx, y_bot, fz + 0.15)
	var s_n1: Vector3 = Vector3(fx, y_high, fz + 0.15)
	var s_n2: Vector3 = Vector3(x_b, y_high, fz + 0.15)
	var s_n3: Vector3 = Vector3(x_b, y_bot, fz + 0.15)
	_add_side_quad_uv(st, s_n0, s_n1, s_n2, s_n3, Vector3(0, 0, -1), fx, x_b, y_bot, y_high)

	var s_s0: Vector3 = Vector3(x_b, y_bot, fz + 0.85)
	var s_s1: Vector3 = Vector3(x_b, y_high, fz + 0.85)
	var s_s2: Vector3 = Vector3(fx, y_high, fz + 0.85)
	var s_s3: Vector3 = Vector3(fx, y_bot, fz + 0.85)
	_add_side_quad_uv(st, s_s0, s_s1, s_s2, s_s3, Vector3(0, 0, 1), x_b, fx, y_bot, y_high)

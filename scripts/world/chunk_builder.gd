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

## Verification harness flag: when true, ChunkBuilder executes the exact 1:1 legacy
## baseline generation algorithm from base SHA f09d1c4 for reproducible benchmarking.
static var use_legacy_presentation: bool = false

static func build_chunk_terrain(
	cx: int,
	cz: int,
	seed_val: int,
	mat_forest: Material,
	mat_plains: Material,
	mat_mountains: Material,
	mat_cliff: Material
) -> Dictionary:
	if use_legacy_presentation:
		return _build_chunk_terrain_legacy(cx, cz, seed_val, mat_forest, mat_plains, mat_mountains, mat_cliff)
	return _build_chunk_terrain_modern(cx, cz, seed_val, mat_forest, mat_plains, mat_mountains, mat_cliff)

# =============================================================================
# Modern Visual Presentation Pass (Issue #25)
# =============================================================================
static func _build_chunk_terrain_modern(
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
	var st_col: SurfaceTool = SurfaceTool.new()

	st_forest.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_forest.set_material(mat_forest)

	st_plains.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_plains.set_material(mat_plains)

	st_mountains.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_mountains.set_material(mat_mountains)

	st_cliff.begin(Mesh.PRIMITIVE_TRIANGLES)
	st_cliff.set_material(mat_cliff)

	st_col.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Surface counts array: [0: Forest, 1: Plains, 2: Mountains, 3: Cliff]
	var counts: Array[int] = [0, 0, 0, 0]

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
					st_forest, st_plains, st_mountains, st_cliff,
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
					st_forest, st_plains, st_mountains, st_cliff,
					Vector3(0, 0, 1)
				)
				var st_side: SurfaceTool = visual_res["surface_tool"]
				var norm_side: Vector3 = visual_res["normal"]
				_add_side_quad_uv(st_side, s0, s1, s2, s3, norm_side, fx + 1.0, fx, y_bot, y_top)
				counts[visual_res["type"]] += 1

				if visual_res["has_dressing"]:
					_add_ledge_dressing_south(st_cliff, fx, y_top, fz)
					counts[3] += 3
				if visual_res["has_buttress"]:
					_add_buttress_south(st_cliff, fx, y_bot, y_top, fz)
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
					st_forest, st_plains, st_mountains, st_cliff,
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
					st_forest, st_plains, st_mountains, st_cliff,
					Vector3(1, 0, 0)
				)
				var st_side: SurfaceTool = visual_res["surface_tool"]
				var norm_side: Vector3 = visual_res["normal"]
				_add_side_quad_uv(st_side, s0, s1, s2, s3, norm_side, fz, fz + 1.0, y_bot, y_top)
				counts[visual_res["type"]] += 1

				if visual_res["has_dressing"]:
					_add_ledge_dressing_east(st_cliff, fx, y_top, fz)
					counts[3] += 3
				if visual_res["has_buttress"]:
					_add_buttress_east(st_cliff, fx, y_bot, y_top, fz)
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

	var mesh: ArrayMesh = ArrayMesh.new()
	if counts[0] > 0:
		st_forest.commit(mesh)
	if counts[1] > 0:
		st_plains.commit(mesh)
	if counts[2] > 0:
		st_mountains.commit(mesh)
	if counts[3] > 0:
		st_cliff.commit(mesh)

	# Collision Shape3D: generated strictly from authoritative voxel quads
	var shape: Shape3D = null
	var col_mesh: ArrayMesh = ArrayMesh.new()
	st_col.commit(col_mesh)
	if col_mesh.get_surface_count() > 0:
		shape = col_mesh.create_trimesh_shape()

	return {
		"mesh": mesh,
		"shape": shape
	}

# -----------------------------------------------------------------------------
# Organic Side Presentation Resolver
# -----------------------------------------------------------------------------
static func _resolve_side_presentation(
	wx: int,
	wz: int,
	_wnx: int,
	_wnz: int,
	y_from: int,
	y_to: int,
	from_biome: int,
	seed_val: int,
	st_forest: SurfaceTool,
	st_plains: SurfaceTool,
	st_mountains: SurfaceTool,
	st_cliff: SurfaceTool,
	dir: Vector3
) -> Dictionary:
	var h_drop: int = y_from - y_to

	# BLOCKER 1 FIX:
	# Gameplay traversal contract is strictly |Δheight| <= 1.
	# Only walkable drops (h_drop <= 1) receive gentle visual treatment (softened upward normal).
	# Any drop >= 2 is an impassable vertical barrier and MUST be visually presented
	# as an impassable rock cliff with perpendicular normal and cliff material.
	if h_drop <= 1:
		var softened_normal: Vector3 = Vector3(dir.x * 0.4, 0.9, dir.z * 0.4).normalized()

		# Mountain trail steps and mountain biome terraces
		if from_biome == BiomeSystem.BiomeType.MOUNTAINS or BiomeSystem.is_mountain_trail(wx, wz, seed_val):
			return {
				"surface_tool": st_mountains,
				"normal": softened_normal,
				"type": 2,
				"has_dressing": false,
				"has_buttress": false
			}
		elif from_biome == BiomeSystem.BiomeType.PLAINS:
			return {
				"surface_tool": st_plains,
				"normal": softened_normal,
				"type": 1,
				"has_dressing": false,
				"has_buttress": false
			}
		else: # FOREST
			return {
				"surface_tool": st_forest,
				"normal": softened_normal,
				"type": 0,
				"has_dressing": false,
				"has_buttress": false
			}

	# High cliffs / impassable drops (h_drop >= 2)
	# Crisp perpendicular normal for bold stylized shadow contrast and unmistakable impassable reading
	var norm_cliff: Vector3 = dir
	var has_dressing: bool = true
	var has_buttress: bool = (h_drop >= 3) and ((_hash2d(wx, wz) % 3) == 0)

	return {
		"surface_tool": st_cliff,
		"normal": norm_cliff,
		"type": 3,
		"has_dressing": has_dressing,
		"has_buttress": has_buttress
	}

# -----------------------------------------------------------------------------
# Spatial Hashing
# -----------------------------------------------------------------------------
static func _hash2d(ix: int, iz: int) -> int:
	return int((ix * 374761393) ^ (iz * 668265263)) & 0x7fffffff

# -----------------------------------------------------------------------------
# Geometry Helpers (World-Aligned UVs)
# -----------------------------------------------------------------------------
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

	# Front face of overhanging ledge
	var f0: Vector3 = Vector3(fx, y_lip, z_over)
	var f1: Vector3 = Vector3(fx, y_top, z_over)
	var f2: Vector3 = Vector3(fx + 1.0, y_top, z_over)
	var f3: Vector3 = Vector3(fx + 1.0, y_lip, z_over)
	_add_side_quad_uv(st, f0, f1, f2, f3, Vector3(0, 0, -1), fx, fx + 1.0, y_lip, y_top)

	# Bottom undercut of overhanging ledge
	var b0: Vector3 = Vector3(fx, y_lip, z_over)
	var b1: Vector3 = Vector3(fx + 1.0, y_lip, z_over)
	var b2: Vector3 = Vector3(fx + 1.0, y_lip, fz)
	var b3: Vector3 = Vector3(fx, y_lip, fz)
	_add_quad_world_uv(st, b0, b1, b2, b3, Vector3.DOWN, Vector2(fx, z_over), Vector2(fx + 1.0, fz))

static func _add_ledge_dressing_south(st: SurfaceTool, fx: float, y_top: float, fz: float) -> void:
	var z_boundary: float = fz + 1.0
	var z_over: float = z_boundary + LEDGE_OVERHANG
	var y_lip: float = y_top - LEDGE_THICKNESS

	var t0: Vector3 = Vector3(fx + 1.0, y_top, z_boundary)
	var t1: Vector3 = Vector3(fx, y_top, z_boundary)
	var t2: Vector3 = Vector3(fx, y_top, z_over)
	var t3: Vector3 = Vector3(fx + 1.0, y_top, z_over)
	_add_quad_world_uv(st, t0, t1, t2, t3, Vector3.UP, Vector2(fx + 1.0, z_boundary), Vector2(fx, z_over))

	var f0: Vector3 = Vector3(fx + 1.0, y_lip, z_over)
	var f1: Vector3 = Vector3(fx + 1.0, y_top, z_over)
	var f2: Vector3 = Vector3(fx, y_top, z_over)
	var f3: Vector3 = Vector3(fx, y_lip, z_over)
	_add_side_quad_uv(st, f0, f1, f2, f3, Vector3(0, 0, 1), fx + 1.0, fx, y_lip, y_top)

	var b0: Vector3 = Vector3(fx + 1.0, y_lip, z_over)
	var b1: Vector3 = Vector3(fx, y_lip, z_over)
	var b2: Vector3 = Vector3(fx, y_lip, z_boundary)
	var b3: Vector3 = Vector3(fx + 1.0, y_lip, z_boundary)
	_add_quad_world_uv(st, b0, b1, b2, b3, Vector3.DOWN, Vector2(fx + 1.0, z_over), Vector2(fx, z_boundary))

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
	var x_boundary: float = fx + 1.0
	var x_over: float = x_boundary + LEDGE_OVERHANG
	var y_lip: float = y_top - LEDGE_THICKNESS

	var t0: Vector3 = Vector3(x_boundary, y_top, fz)
	var t1: Vector3 = Vector3(x_boundary, y_top, fz + 1.0)
	var t2: Vector3 = Vector3(x_over, y_top, fz + 1.0)
	var t3: Vector3 = Vector3(x_over, y_top, fz)
	_add_quad_world_uv(st, t0, t1, t2, t3, Vector3.UP, Vector2(x_boundary, fz), Vector2(x_over, fz + 1.0))

	var f0: Vector3 = Vector3(x_over, y_lip, fz)
	var f1: Vector3 = Vector3(x_over, y_top, fz)
	var f2: Vector3 = Vector3(x_over, y_top, fz + 1.0)
	var f3: Vector3 = Vector3(x_over, y_lip, fz + 1.0)
	_add_side_quad_uv(st, f0, f1, f2, f3, Vector3(1, 0, 0), fz, fz + 1.0, y_lip, y_top)

	var b0: Vector3 = Vector3(x_over, y_lip, fz)
	var b1: Vector3 = Vector3(x_over, y_lip, fz + 1.0)
	var b2: Vector3 = Vector3(x_boundary, y_lip, fz + 1.0)
	var b3: Vector3 = Vector3(x_boundary, y_lip, fz)
	_add_quad_world_uv(st, b0, b1, b2, b3, Vector3.DOWN, Vector2(x_over, fz), Vector2(x_boundary, fz + 1.0))

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
	var z_boundary: float = fz + 1.0
	var z_b: float = z_boundary + BUTTRESS_EXTRUSION
	var y_high: float = y_top - LEDGE_THICKNESS
	if y_high <= y_bot: return

	var b0: Vector3 = Vector3(fx + 0.85, y_bot, z_b)
	var b1: Vector3 = Vector3(fx + 0.85, y_high, z_b)
	var b2: Vector3 = Vector3(fx + 0.15, y_high, z_b)
	var b3: Vector3 = Vector3(fx + 0.15, y_bot, z_b)
	_add_side_quad_uv(st, b0, b1, b2, b3, Vector3(0, 0, 1), fx + 0.85, fx + 0.15, y_bot, y_high)

	var s_e0: Vector3 = Vector3(fx + 0.85, y_bot, z_boundary)
	var s_e1: Vector3 = Vector3(fx + 0.85, y_high, z_boundary)
	var s_e2: Vector3 = Vector3(fx + 0.85, y_high, z_b)
	var s_e3: Vector3 = Vector3(fx + 0.85, y_bot, z_b)
	_add_side_quad_uv(st, s_e0, s_e1, s_e2, s_e3, Vector3(1, 0, 0), z_boundary, z_b, y_bot, y_high)

	var s_w0: Vector3 = Vector3(fx + 0.15, y_bot, z_b)
	var s_w1: Vector3 = Vector3(fx + 0.15, y_high, z_b)
	var s_w2: Vector3 = Vector3(fx + 0.15, y_high, z_boundary)
	var s_w3: Vector3 = Vector3(fx + 0.15, y_bot, z_boundary)
	_add_side_quad_uv(st, s_w0, s_w1, s_w2, s_w3, Vector3(-1, 0, 0), z_b, z_boundary, y_bot, y_high)

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
	var x_boundary: float = fx + 1.0
	var x_b: float = x_boundary + BUTTRESS_EXTRUSION
	var y_high: float = y_top - LEDGE_THICKNESS
	if y_high <= y_bot: return

	var b0: Vector3 = Vector3(x_b, y_bot, fz + 0.15)
	var b1: Vector3 = Vector3(x_b, y_high, fz + 0.15)
	var b2: Vector3 = Vector3(x_b, y_high, fz + 0.85)
	var b3: Vector3 = Vector3(x_b, y_bot, fz + 0.85)
	_add_side_quad_uv(st, b0, b1, b2, b3, Vector3(1, 0, 0), fz + 0.15, fz + 0.85, y_bot, y_high)

	var s_n0: Vector3 = Vector3(x_boundary, y_bot, fz + 0.15)
	var s_n1: Vector3 = Vector3(x_boundary, y_high, fz + 0.15)
	var s_n2: Vector3 = Vector3(x_b, y_high, fz + 0.15)
	var s_n3: Vector3 = Vector3(x_b, y_bot, fz + 0.15)
	_add_side_quad_uv(st, s_n0, s_n1, s_n2, s_n3, Vector3(0, 0, -1), x_boundary, x_b, y_bot, y_high)

	var s_s0: Vector3 = Vector3(x_b, y_bot, fz + 0.85)
	var s_s1: Vector3 = Vector3(x_b, y_high, fz + 0.85)
	var s_s2: Vector3 = Vector3(x_boundary, y_high, fz + 0.85)
	var s_s3: Vector3 = Vector3(x_boundary, y_bot, fz + 0.85)
	_add_side_quad_uv(st, s_s0, s_s1, s_s2, s_s3, Vector3(0, 0, 1), x_b, x_boundary, y_bot, y_high)

# =============================================================================
# Legacy Baseline Generation (1:1 emulation of base SHA f09d1c4)
# =============================================================================
static func _build_chunk_terrain_legacy(
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

			var fx: float = float(wx)
			var fz: float = float(wz)

			var p0: Vector3 = Vector3(fx, y_top, fz)
			var p1: Vector3 = Vector3(fx + 1.0, y_top, fz)
			var p2: Vector3 = Vector3(fx + 1.0, y_top, fz + 1.0)
			var p3: Vector3 = Vector3(fx, y_top, fz + 1.0)

			_add_quad_legacy(st_top, p0, p1, p2, p3, Vector3.UP)

			# North (-Z)
			var yn: int = BiomeSystem.get_voxel_height(wx, wz - 1, seed_val)
			if yn < y:
				var y_bot: float = float(yn)
				var s0: Vector3 = Vector3(fx, y_bot, fz)
				var s1: Vector3 = Vector3(fx, y_top, fz)
				var s2: Vector3 = Vector3(fx + 1.0, y_top, fz)
				var s3: Vector3 = Vector3(fx + 1.0, y_bot, fz)
				_add_quad_uv_legacy(st_cliff, s0, s1, s2, s3, Vector3(0, 0, -1), y_top - y_bot)
				count_cliff += 1

			if lz == 0:
				var skirt_top: float = float(min(y, yn))
				var skirt_bot: float = skirt_top - SKIRT_DEPTH
				var k0: Vector3 = Vector3(fx, skirt_bot, fz)
				var k1: Vector3 = Vector3(fx, skirt_top, fz)
				var k2: Vector3 = Vector3(fx + 1.0, skirt_top, fz)
				var k3: Vector3 = Vector3(fx + 1.0, skirt_bot, fz)
				_add_quad_uv_legacy(st_cliff, k0, k1, k2, k3, Vector3(0, 0, -1), SKIRT_DEPTH)
				count_cliff += 1

			# South (+Z)
			var ys: int = BiomeSystem.get_voxel_height(wx, wz + 1, seed_val)
			if ys < y:
				var y_bot: float = float(ys)
				var s0: Vector3 = Vector3(fx + 1.0, y_bot, fz + 1.0)
				var s1: Vector3 = Vector3(fx + 1.0, y_top, fz + 1.0)
				var s2: Vector3 = Vector3(fx, y_top, fz + 1.0)
				var s3: Vector3 = Vector3(fx, y_bot, fz + 1.0)
				_add_quad_uv_legacy(st_cliff, s0, s1, s2, s3, Vector3(0, 0, 1), y_top - y_bot)
				count_cliff += 1

			if lz == CHUNK_SIZE - 1:
				var skirt_top: float = float(min(y, ys))
				var skirt_bot: float = skirt_top - SKIRT_DEPTH
				var k0: Vector3 = Vector3(fx + 1.0, skirt_bot, fz + 1.0)
				var k1: Vector3 = Vector3(fx + 1.0, skirt_top, fz + 1.0)
				var k2: Vector3 = Vector3(fx, skirt_top, fz + 1.0)
				var k3: Vector3 = Vector3(fx, skirt_bot, fz + 1.0)
				_add_quad_uv_legacy(st_cliff, k0, k1, k2, k3, Vector3(0, 0, 1), SKIRT_DEPTH)
				count_cliff += 1

			# West (-X)
			var yw: int = BiomeSystem.get_voxel_height(wx - 1, wz, seed_val)
			if yw < y:
				var y_bot: float = float(yw)
				var s0: Vector3 = Vector3(fx, y_bot, fz + 1.0)
				var s1: Vector3 = Vector3(fx, y_top, fz + 1.0)
				var s2: Vector3 = Vector3(fx, y_top, fz)
				var s3: Vector3 = Vector3(fx, y_bot, fz)
				_add_quad_uv_legacy(st_cliff, s0, s1, s2, s3, Vector3(-1, 0, 0), y_top - y_bot)
				count_cliff += 1

			if lx == 0:
				var skirt_top: float = float(min(y, yw))
				var skirt_bot: float = skirt_top - SKIRT_DEPTH
				var k0: Vector3 = Vector3(fx, skirt_bot, fz + 1.0)
				var k1: Vector3 = Vector3(fx, skirt_top, fz + 1.0)
				var k2: Vector3 = Vector3(fx, skirt_top, fz)
				var k3: Vector3 = Vector3(fx, skirt_bot, fz)
				_add_quad_uv_legacy(st_cliff, k0, k1, k2, k3, Vector3(-1, 0, 0), SKIRT_DEPTH)
				count_cliff += 1

			# East (+X)
			var ye: int = BiomeSystem.get_voxel_height(wx + 1, wz, seed_val)
			if ye < y:
				var y_bot: float = float(ye)
				var s0: Vector3 = Vector3(fx + 1.0, y_bot, fz)
				var s1: Vector3 = Vector3(fx + 1.0, y_top, fz)
				var s2: Vector3 = Vector3(fx + 1.0, y_top, fz + 1.0)
				var s3: Vector3 = Vector3(fx + 1.0, y_bot, fz + 1.0)
				_add_quad_uv_legacy(st_cliff, s0, s1, s2, s3, Vector3(1, 0, 0), y_top - y_bot)
				count_cliff += 1

			if lx == CHUNK_SIZE - 1:
				var skirt_top: float = float(min(y, ye))
				var skirt_bot: float = skirt_top - SKIRT_DEPTH
				var k0: Vector3 = Vector3(fx + 1.0, skirt_bot, fz)
				var k1: Vector3 = Vector3(fx + 1.0, skirt_top, fz)
				var k2: Vector3 = Vector3(fx + 1.0, skirt_top, fz + 1.0)
				var k3: Vector3 = Vector3(fx + 1.0, skirt_bot, fz + 1.0)
				_add_quad_uv_legacy(st_cliff, k0, k1, k2, k3, Vector3(1, 0, 0), SKIRT_DEPTH)
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

static func _add_quad_legacy(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, norm: Vector3) -> void:
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

static func _add_quad_uv_legacy(
	st: SurfaceTool,
	p0: Vector3,
	p1: Vector3,
	p2: Vector3,
	p3: Vector3,
	norm: Vector3,
	uv_height: float
) -> void:
	st.set_normal(norm)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(p0)
	st.set_uv(Vector2(0, uv_height))
	st.add_vertex(p1)
	st.set_uv(Vector2(1, uv_height))
	st.add_vertex(p2)

	st.set_normal(norm)
	st.set_uv(Vector2(0, 0))
	st.add_vertex(p0)
	st.set_uv(Vector2(1, uv_height))
	st.add_vertex(p2)
	st.set_uv(Vector2(1, 0))
	st.add_vertex(p3)

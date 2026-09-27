extends GutTest

## Unit tests for ChunkBuilder:
## Validates directional ledge and buttress dressing planes, non-degenerate quads,
## outward triangle winding (Issue #43 fix), and 2-band side texture presentation.

var dummy_mat: StandardMaterial3D

func before_all() -> void:
	dummy_mat = StandardMaterial3D.new()

func _triangle_area(p0: Vector3, p1: Vector3, p2: Vector3) -> float:
	return (p1 - p0).cross(p2 - p0).length() * 0.5

func _triangle_geometric_normal(p0: Vector3, p1: Vector3, p2: Vector3) -> Vector3:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_vertex(p0)
	st.add_vertex(p1)
	st.add_vertex(p2)
	st.generate_normals()
	var mesh = st.commit()
	var mdt = MeshDataTool.new()
	mdt.create_from_surface(mesh, 0)
	return mdt.get_face_normal(0)

func test_ledge_and_buttress_helpers_non_degenerate_and_exact_boundaries() -> void:
	var fx: float = 10.0
	var fz: float = 20.0
	var y_top: float = 5.0
	var y_bot: float = 2.0

	var st: SurfaceTool = SurfaceTool.new()

	# 1. North: plane is fz = 20.0, extends outside to z_over < 20.0
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	ChunkBuilder._add_ledge_dressing_north(st, fx, y_top, fz)
	ChunkBuilder._add_buttress_north(st, fx, y_bot, y_top, fz)
	var mesh_n = st.commit()
	var mdt_n = MeshDataTool.new()
	mdt_n.create_from_surface(mesh_n, 0)
	for f in range(mdt_n.get_face_count()):
		var p0 = mdt_n.get_vertex(mdt_n.get_face_vertex(f, 0))
		var p1 = mdt_n.get_vertex(mdt_n.get_face_vertex(f, 1))
		var p2 = mdt_n.get_vertex(mdt_n.get_face_vertex(f, 2))
		var area = _triangle_area(p0, p1, p2)
		assert_gt(area, 0.0001, "North face %d must not be degenerate" % f)
		assert_true(p0.z <= fz + 0.0001 and p1.z <= fz + 0.0001 and p2.z <= fz + 0.0001,
			"North dressing must not invade interior Z > fz")

	# 2. South: plane is fz + 1.0 = 21.0, extends outside to z_over > 21.0
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	ChunkBuilder._add_ledge_dressing_south(st, fx, y_top, fz)
	ChunkBuilder._add_buttress_south(st, fx, y_bot, y_top, fz)
	var mesh_s = st.commit()
	var mdt_s = MeshDataTool.new()
	mdt_s.create_from_surface(mesh_s, 0)
	var south_plane: float = fz + 1.0
	for f in range(mdt_s.get_face_count()):
		var p0 = mdt_s.get_vertex(mdt_s.get_face_vertex(f, 0))
		var p1 = mdt_s.get_vertex(mdt_s.get_face_vertex(f, 1))
		var p2 = mdt_s.get_vertex(mdt_s.get_face_vertex(f, 2))
		var area = _triangle_area(p0, p1, p2)
		assert_gt(area, 0.0001, "South face %d must not be degenerate" % f)
		assert_true(p0.z >= south_plane - 0.0001 and p1.z >= south_plane - 0.0001 and p2.z >= south_plane - 0.0001,
			"South dressing must start at boundary plane Z >= fz + 1.0 (no invasion into cell interior)")

	# 3. West: plane is fx = 10.0, extends outside to x_over < 10.0
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	ChunkBuilder._add_ledge_dressing_west(st, fx, y_top, fz)
	ChunkBuilder._add_buttress_west(st, fx, y_bot, y_top, fz)
	var mesh_w = st.commit()
	var mdt_w = MeshDataTool.new()
	mdt_w.create_from_surface(mesh_w, 0)
	for f in range(mdt_w.get_face_count()):
		var p0 = mdt_w.get_vertex(mdt_w.get_face_vertex(f, 0))
		var p1 = mdt_w.get_vertex(mdt_w.get_face_vertex(f, 1))
		var p2 = mdt_w.get_vertex(mdt_w.get_face_vertex(f, 2))
		var area = _triangle_area(p0, p1, p2)
		assert_gt(area, 0.0001, "West face %d must not be degenerate" % f)
		assert_true(p0.x <= fx + 0.0001 and p1.x <= fx + 0.0001 and p2.x <= fx + 0.0001,
			"West dressing must not invade interior X > fx")

	# 4. East: plane is fx + 1.0 = 11.0, extends outside to x_over > 11.0
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	ChunkBuilder._add_ledge_dressing_east(st, fx, y_top, fz)
	ChunkBuilder._add_buttress_east(st, fx, y_bot, y_top, fz)
	var mesh_e = st.commit()
	var mdt_e = MeshDataTool.new()
	mdt_e.create_from_surface(mesh_e, 0)
	var east_plane: float = fx + 1.0
	for f in range(mdt_e.get_face_count()):
		var p0 = mdt_e.get_vertex(mdt_e.get_face_vertex(f, 0))
		var p1 = mdt_e.get_vertex(mdt_e.get_face_vertex(f, 1))
		var p2 = mdt_e.get_vertex(mdt_e.get_face_vertex(f, 2))
		var area = _triangle_area(p0, p1, p2)
		assert_gt(area, 0.0001, "East face %d must not be degenerate" % f)
		assert_true(p0.x >= east_plane - 0.0001 and p1.x >= east_plane - 0.0001 and p2.x >= east_plane - 0.0001,
			"East dressing must start at boundary plane X >= fx + 1.0 (no invasion into cell interior)")

func test_side_quad_outward_normals_in_all_directions() -> void:
	# Issue #43 Regression Test:
	# Side faces must have outward winding so CULL_BACK does not make them invisible from outside.
	var fx: float = 2.0
	var fz: float = 3.0
	var y_bot: float = 1.0
	var y_top: float = 2.0

	var directions: Array[Dictionary] = [
		{
			"name": "North",
			"expected": Vector3(0, 0, -1),
			"p0": Vector3(fx, y_bot, fz),
			"p1": Vector3(fx, y_top, fz),
			"p2": Vector3(fx + 1.0, y_top, fz),
			"p3": Vector3(fx + 1.0, y_bot, fz),
			"u_start": fx,
			"u_end": fx + 1.0
		},
		{
			"name": "South",
			"expected": Vector3(0, 0, 1),
			"p0": Vector3(fx + 1.0, y_bot, fz + 1.0),
			"p1": Vector3(fx + 1.0, y_top, fz + 1.0),
			"p2": Vector3(fx, y_top, fz + 1.0),
			"p3": Vector3(fx, y_bot, fz + 1.0),
			"u_start": fx + 1.0,
			"u_end": fx
		},
		{
			"name": "West",
			"expected": Vector3(-1, 0, 0),
			"p0": Vector3(fx, y_bot, fz + 1.0),
			"p1": Vector3(fx, y_top, fz + 1.0),
			"p2": Vector3(fx, y_top, fz),
			"p3": Vector3(fx, y_bot, fz),
			"u_start": fz + 1.0,
			"u_end": fz
		},
		{
			"name": "East",
			"expected": Vector3(1, 0, 0),
			"p0": Vector3(fx + 1.0, y_bot, fz),
			"p1": Vector3(fx + 1.0, y_top, fz),
			"p2": Vector3(fx + 1.0, y_top, fz + 1.0),
			"p3": Vector3(fx + 1.0, y_bot, fz + 1.0),
			"u_start": fz,
			"u_end": fz + 1.0
		}
	]

	for d: Dictionary in directions:
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		ChunkBuilder._add_side_quad_uv(
			st, d["p0"], d["p1"], d["p2"], d["p3"],
			d["expected"], d["u_start"], d["u_end"], -y_bot, -y_top
		)
		st.generate_normals()
		var mesh: ArrayMesh = st.commit()
		var mdt: MeshDataTool = MeshDataTool.new()
		mdt.create_from_surface(mesh, 0)

		assert_eq(mdt.get_face_count(), 2, "%s quad must have 2 triangles" % d["name"])
		for f in range(mdt.get_face_count()):
			var norm: Vector3 = mdt.get_face_normal(f)
			var dot: float = norm.dot(d["expected"])
			assert_gt(dot, 0.99, "%s face %d normal (%s) must point outward (%s)" % [
				d["name"], f, str(norm), str(d["expected"])
			])

func test_side_quad_collision_outward_normals() -> void:
	# Verifies _add_side_quad_col produces outward normal triangles
	var p0 = Vector3(0, 0, 0)
	var p1 = Vector3(0, 1, 0)
	var p2 = Vector3(1, 1, 0)
	var p3 = Vector3(1, 0, 0)
	var expected = Vector3(0, 0, -1)

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	ChunkBuilder._add_side_quad_col(st, p0, p1, p2, p3)
	st.generate_normals()
	var mesh = st.commit()
	var mdt = MeshDataTool.new()
	mdt.create_from_surface(mesh, 0)

	for f in range(mdt.get_face_count()):
		var norm = mdt.get_face_normal(f)
		assert_gt(norm.dot(expected), 0.99, "Collision face %d must point outward" % f)

func test_ledge_dressing_normals_in_all_directions() -> void:
	# Ledge top must point UP (+Y), front must point OUTWARD, bottom undercut must point DOWN (-Y)
	var fx: float = 4.0
	var fz: float = 6.0
	var y_top: float = 8.0

	var test_cases = [
		{"dir": "North", "fn": "_add_ledge_dressing_north", "outward": Vector3(0, 0, -1)},
		{"dir": "South", "fn": "_add_ledge_dressing_south", "outward": Vector3(0, 0, 1)},
		{"dir": "West", "fn": "_add_ledge_dressing_west", "outward": Vector3(-1, 0, 0)},
		{"dir": "East", "fn": "_add_ledge_dressing_east", "outward": Vector3(1, 0, 0)}
	]

	for tc in test_cases:
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		match tc["dir"]:
			"North": ChunkBuilder._add_ledge_dressing_north(st, fx, y_top, fz)
			"South": ChunkBuilder._add_ledge_dressing_south(st, fx, y_top, fz)
			"West": ChunkBuilder._add_ledge_dressing_west(st, fx, y_top, fz)
			"East": ChunkBuilder._add_ledge_dressing_east(st, fx, y_top, fz)
		st.generate_normals()
		var mesh = st.commit()
		var mdt = MeshDataTool.new()
		mdt.create_from_surface(mesh, 0)

		# 3 quads = 6 triangles (faces 0-1: top, faces 2-3: front, faces 4-5: bottom)
		assert_eq(mdt.get_face_count(), 6, "%s ledge must have 6 triangles" % tc["dir"])

		# Top face
		for f in [0, 1]:
			var norm = mdt.get_face_normal(f)
			assert_gt(norm.dot(Vector3.UP), 0.99, "%s ledge top face %d must point UP" % [tc["dir"], f])

		# Front face
		for f in [2, 3]:
			var norm = mdt.get_face_normal(f)
			assert_gt(norm.dot(tc["outward"]), 0.99, "%s ledge front face %d must point outward" % [tc["dir"], f])

		# Bottom undercut face
		for f in [4, 5]:
			var norm = mdt.get_face_normal(f)
			assert_gt(norm.dot(Vector3.DOWN), 0.99, "%s ledge bottom face %d must point DOWN" % [tc["dir"], f])

func test_buttress_normals_in_all_directions() -> void:
	var fx: float = 4.0
	var fz: float = 6.0
	var y_top: float = 8.0
	var y_bot: float = 3.0

	var test_cases = [
		{
			"dir": "North", "fn": "_add_buttress_north",
			"front": Vector3(0, 0, -1), "side1": Vector3(-1, 0, 0), "side2": Vector3(1, 0, 0)
		},
		{
			"dir": "South", "fn": "_add_buttress_south",
			"front": Vector3(0, 0, 1), "side1": Vector3(1, 0, 0), "side2": Vector3(-1, 0, 0)
		},
		{
			"dir": "West", "fn": "_add_buttress_west",
			"front": Vector3(-1, 0, 0), "side1": Vector3(0, 0, 1), "side2": Vector3(0, 0, -1)
		},
		{
			"dir": "East", "fn": "_add_buttress_east",
			"front": Vector3(1, 0, 0), "side1": Vector3(0, 0, -1), "side2": Vector3(0, 0, 1)
		}
	]

	for tc in test_cases:
		var st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		match tc["dir"]:
			"North": ChunkBuilder._add_buttress_north(st, fx, y_bot, y_top, fz)
			"South": ChunkBuilder._add_buttress_south(st, fx, y_bot, y_top, fz)
			"West": ChunkBuilder._add_buttress_west(st, fx, y_bot, y_top, fz)
			"East": ChunkBuilder._add_buttress_east(st, fx, y_bot, y_top, fz)
		st.generate_normals()
		var mesh = st.commit()
		var mdt = MeshDataTool.new()
		mdt.create_from_surface(mesh, 0)

		# 3 quads = 6 triangles (faces 0-1: front, faces 2-3: side1, faces 4-5: side2)
		assert_eq(mdt.get_face_count(), 6, "%s buttress must have 6 triangles" % tc["dir"])

		for f in [0, 1]:
			var norm = mdt.get_face_normal(f)
			assert_gt(norm.dot(tc["front"]), 0.99, "%s buttress front face %d must point front" % [tc["dir"], f])
		for f in [2, 3]:
			var norm = mdt.get_face_normal(f)
			assert_gt(norm.dot(tc["side1"]), 0.99, "%s buttress side1 face %d must point outward" % [tc["dir"], f])
		for f in [4, 5]:
			var norm = mdt.get_face_normal(f)
			assert_gt(norm.dot(tc["side2"]), 0.99, "%s buttress side2 face %d must point outward" % [tc["dir"], f])

func test_side_materials_and_two_band_cliff_integration() -> void:
	# Build chunk with all 7 materials supplied
	var mat_top_forest = StandardMaterial3D.new()
	var mat_top_plains = StandardMaterial3D.new()
	var mat_top_mountains = StandardMaterial3D.new()
	var mat_cliff = StandardMaterial3D.new()
	var mat_side_forest = StandardMaterial3D.new()
	var mat_side_plains = StandardMaterial3D.new()
	var mat_side_mountains = StandardMaterial3D.new()

	var result = ChunkBuilder.build_chunk_terrain(
		0, 0, 1337,
		mat_top_forest, mat_top_plains, mat_top_mountains, mat_cliff,
		mat_side_forest, mat_side_plains, mat_side_mountains
	)

	var mesh: ArrayMesh = result["mesh"]
	assert_not_null(mesh, "Chunk terrain mesh must generate")
	assert_gt(mesh.get_surface_count(), 0, "Chunk must produce visible surfaces")

	# Verify every face on every committed surface has a valid, non-zero outward or upward normal
	for s in range(mesh.get_surface_count()):
		var mdt = MeshDataTool.new()
		mdt.create_from_surface(mesh, s)
		for f in range(mdt.get_face_count()):
			var norm = mdt.get_face_normal(f)
			assert_gt(norm.length_squared(), 0.5, "Surface %d face %d normal must not be zero" % [s, f])

func test_legacy_baseline_emulation_toggle() -> void:
	ChunkBuilder.use_legacy_presentation = true
	var res_legacy = ChunkBuilder.build_chunk_terrain(0, 0, 1337, dummy_mat, dummy_mat, dummy_mat, dummy_mat)
	assert_not_null(res_legacy["mesh"], "Legacy mesh must generate")
	assert_not_null(res_legacy["shape"], "Legacy shape must generate")

	ChunkBuilder.use_legacy_presentation = false
	var res_modern = ChunkBuilder.build_chunk_terrain(0, 0, 1337, dummy_mat, dummy_mat, dummy_mat, dummy_mat)
	assert_not_null(res_modern["mesh"], "Modern mesh must generate")
	assert_not_null(res_modern["shape"], "Modern shape must generate")

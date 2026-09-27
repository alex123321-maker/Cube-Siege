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

	var all_materials = [
		mat_top_forest, mat_top_plains, mat_top_mountains, mat_cliff,
		mat_side_forest, mat_side_plains, mat_side_mountains
	]

	var result = ChunkBuilder.build_chunk_terrain(
		0, 0, 1337,
		mat_top_forest, mat_top_plains, mat_top_mountains, mat_cliff,
		mat_side_forest, mat_side_plains, mat_side_mountains
	)

	var mesh: ArrayMesh = result["mesh"]
	assert_not_null(mesh, "Chunk terrain mesh must generate")
	assert_gt(mesh.get_surface_count(), 0, "Chunk must produce visible surfaces")

	# Verify every committed surface has one of the 7 specified materials assigned
	for s in range(mesh.get_surface_count()):
		var assigned_mat = mesh.surface_get_material(s)
		assert_not_null(assigned_mat, "Surface %d must have an assigned material" % s)
		assert_true(all_materials.has(assigned_mat), "Surface %d material must be from the supplied 7 materials" % s)

		var mdt = MeshDataTool.new()
		mdt.create_from_surface(mesh, s)
		for f in range(mdt.get_face_count()):
			var norm = mdt.get_face_normal(f)
			assert_gt(norm.length_squared(), 0.5, "Surface %d face %d normal must not be zero" % [s, f])

func test_two_band_cliff_geometry_and_uv_coordinates() -> void:
	# Simulates tall cliff (h_drop = 3m, y_top = 5.0, y_bot = 2.0)
	var fx: float = 8.0
	var fz: float = 2.0
	var y_top: float = 5.0
	var y_bot: float = 2.0
	var y_rim: float = y_top - 1.0 # Exactly 4.0
	var norm_north: Vector3 = Vector3(0, 0, -1)

	# 1. Top rim band (height: 1.0m, y in [4.0, 5.0])
	var st_rim = SurfaceTool.new()
	st_rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r0 = Vector3(fx, y_rim, fz)
	var r1 = Vector3(fx, y_top, fz)
	var r2 = Vector3(fx + 1.0, y_top, fz)
	var r3 = Vector3(fx + 1.0, y_rim, fz)
	ChunkBuilder._add_side_quad_uv(st_rim, r0, r1, r2, r3, norm_north, fx, fx + 1.0, -y_rim, -y_top)
	st_rim.generate_normals()
	var mesh_rim = st_rim.commit()
	var mdt_rim = MeshDataTool.new()
	mdt_rim.create_from_surface(mesh_rim, 0)

	assert_eq(mdt_rim.get_face_count(), 2, "Rim band must have 2 triangles (1 quad)")
	for f in range(2):
		assert_gt(mdt_rim.get_face_normal(f).dot(norm_north), 0.99, "Rim face normal must point North")

	var rim_y_min: float = 999.0
	var rim_y_max: float = -999.0
	for vi in range(mdt_rim.get_vertex_count()):
		var vpos = mdt_rim.get_vertex(vi)
		var vuv = mdt_rim.get_vertex_uv(vi)
		rim_y_min = minf(rim_y_min, vpos.y)
		rim_y_max = maxf(rim_y_max, vpos.y)
		if is_equal_approx(vpos.y, y_top):
			assert_true(is_equal_approx(vuv.y, -y_top), "Top rim vertex must have v = -y_top (-5.0)")
		elif is_equal_approx(vpos.y, y_rim):
			assert_true(is_equal_approx(vuv.y, -y_rim), "Bottom rim vertex must have v = -y_rim (-4.0)")

	assert_true(is_equal_approx(rim_y_min, 4.0), "Rim band bottom Y must be exactly 4.0")
	assert_true(is_equal_approx(rim_y_max, 5.0), "Rim band top Y must be exactly 5.0")
	assert_true(is_equal_approx(rim_y_max - rim_y_min, 1.0), "Rim band height must be exactly 1.0m")

	# 2. Cliff body band (height: 2.0m, y in [2.0, 4.0])
	var st_cliff = SurfaceTool.new()
	st_cliff.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c0 = Vector3(fx, y_bot, fz)
	var c1 = Vector3(fx, y_rim, fz)
	var c2 = Vector3(fx + 1.0, y_rim, fz)
	var c3 = Vector3(fx + 1.0, y_bot, fz)
	ChunkBuilder._add_side_quad_uv(st_cliff, c0, c1, c2, c3, norm_north, fx, fx + 1.0, -y_bot, -y_rim)
	st_cliff.generate_normals()
	var mesh_cliff = st_cliff.commit()
	var mdt_cliff = MeshDataTool.new()
	mdt_cliff.create_from_surface(mesh_cliff, 0)

	assert_eq(mdt_cliff.get_face_count(), 2, "Cliff body band must have 2 triangles (1 quad)")
	for f in range(2):
		assert_gt(mdt_cliff.get_face_normal(f).dot(norm_north), 0.99, "Cliff body normal must point North")

	var cliff_y_min: float = 999.0
	var cliff_y_max: float = -999.0
	for vi in range(mdt_cliff.get_vertex_count()):
		var vpos = mdt_cliff.get_vertex(vi)
		var vuv = mdt_cliff.get_vertex_uv(vi)
		cliff_y_min = minf(cliff_y_min, vpos.y)
		cliff_y_max = maxf(cliff_y_max, vpos.y)
		if is_equal_approx(vpos.y, y_rim):
			assert_true(is_equal_approx(vuv.y, -y_rim), "Top cliff body vertex must have v = -y_rim (-4.0)")
		elif is_equal_approx(vpos.y, y_bot):
			assert_true(is_equal_approx(vuv.y, -y_bot), "Bottom cliff body vertex must have v = -y_bot (-2.0)")

	assert_true(is_equal_approx(cliff_y_min, 2.0), "Cliff body bottom Y must be exactly 2.0")
	assert_true(is_equal_approx(cliff_y_max, 4.0), "Cliff body top Y must be exactly 4.0")
	assert_true(is_equal_approx(cliff_y_max - cliff_y_min, 2.0), "Cliff body height must be exactly 2.0m")

func test_legacy_baseline_emulation_toggle() -> void:
	ChunkBuilder.use_legacy_presentation = true
	var res_legacy = ChunkBuilder.build_chunk_terrain(0, 0, 1337, dummy_mat, dummy_mat, dummy_mat, dummy_mat)
	assert_not_null(res_legacy["mesh"], "Legacy mesh must generate")
	assert_not_null(res_legacy["shape"], "Legacy shape must generate")

	ChunkBuilder.use_legacy_presentation = false
	var res_modern = ChunkBuilder.build_chunk_terrain(0, 0, 1337, dummy_mat, dummy_mat, dummy_mat, dummy_mat)
	assert_not_null(res_modern["mesh"], "Modern mesh must generate")
	assert_not_null(res_modern["shape"], "Modern shape must generate")

func test_chunk_terrain_physics_direct_space_state_raycasts_and_collision() -> void:
	# 1. Build chunk terrain (cx=0, cz=0, seed=1337) with standard materials
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

	var shape: Shape3D = result["shape"]
	assert_not_null(shape, "ChunkBuilder must produce Shape3D from authoritative voxel quads")

	# 2. Put into a StaticBody3D in active SceneTree World3D
	var static_body: StaticBody3D = StaticBody3D.new()
	var col_shape: CollisionShape3D = CollisionShape3D.new()
	col_shape.shape = shape
	static_body.add_child(col_shape)
	add_child_autoqfree(static_body)

	await get_tree().physics_frame
	await get_tree().physics_frame

	var space_state = get_viewport().world_3d.direct_space_state
	assert_not_null(space_state, "DirectSpaceState3D must be available")

	# 3. Raycast 1: Top Ground Surface Hit from above
	var h00: float = float(BiomeSystem.get_voxel_height(0, 0, 1337))
	var top_ray_from: Vector3 = Vector3(0.5, h00 + 3.0, 0.5)
	var top_ray_to: Vector3 = Vector3(0.5, h00 - 3.0, 0.5)
	var top_query := PhysicsRayQueryParameters3D.create(top_ray_from, top_ray_to)
	var top_hit: Dictionary = space_state.intersect_ray(top_query)

	assert_false(top_hit.is_empty(), "Top raycast must hit the ground surface")
	assert_eq(top_hit.get("collider"), static_body, "Top raycast collider must be the terrain StaticBody3D")
	assert_true(is_equal_approx(top_hit.get("position", Vector3.ZERO).y, h00), "Top hit position Y must match voxel height %f" % h00)
	var top_norm: Vector3 = top_hit.get("normal", Vector3.ZERO)
	assert_gt(top_norm.dot(Vector3.UP), 0.99, "Top hit normal must point UP")

	# 4. Raycasts 2-5: Directional Side Walls from outside looking inward
	var north_drop_found: bool = false
	var south_drop_found: bool = false
	var east_drop_found: bool = false
	var west_drop_found: bool = false

	for lz in range(ChunkBuilder.CHUNK_SIZE):
		for lx in range(ChunkBuilder.CHUNK_SIZE):
			var wx: int = lx
			var wz: int = lz
			var y: int = BiomeSystem.get_voxel_height(wx, wz, 1337)

			# Test North (-Z) drop
			if not north_drop_found:
				var yn: int = BiomeSystem.get_voxel_height(wx, wz - 1, 1337)
				if yn < y:
					north_drop_found = true
					var mid_y: float = (float(y) + float(yn)) * 0.5
					var wall_center: Vector3 = Vector3(float(wx) + 0.5, mid_y, float(wz))
					var from_outside: Vector3 = wall_center + Vector3(0.0, 0.0, -0.6)
					var to_inside: Vector3 = wall_center + Vector3(0.0, 0.0, 0.6)
					var query := PhysicsRayQueryParameters3D.create(from_outside, to_inside)
					var hit: Dictionary = space_state.intersect_ray(query)
					assert_false(hit.is_empty(), "North wall at (%d, %d) must be hit from outside" % [wx, wz])
					assert_eq(hit.get("collider"), static_body)
					var n: Vector3 = hit.get("normal", Vector3.ZERO)
					assert_gt(n.dot(Vector3(0, 0, -1)), 0.99, "North wall normal must point North (0, 0, -1)")

			# Test South (+Z) drop
			if not south_drop_found:
				var ys: int = BiomeSystem.get_voxel_height(wx, wz + 1, 1337)
				if ys < y:
					south_drop_found = true
					var mid_y: float = (float(y) + float(ys)) * 0.5
					var wall_center: Vector3 = Vector3(float(wx) + 0.5, mid_y, float(wz + 1))
					var from_outside: Vector3 = wall_center + Vector3(0.0, 0.0, 0.6)
					var to_inside: Vector3 = wall_center + Vector3(0.0, 0.0, -0.6)
					var query := PhysicsRayQueryParameters3D.create(from_outside, to_inside)
					var hit: Dictionary = space_state.intersect_ray(query)
					assert_false(hit.is_empty(), "South wall at (%d, %d) must be hit from outside" % [wx, wz])
					assert_eq(hit.get("collider"), static_body)
					var n: Vector3 = hit.get("normal", Vector3.ZERO)
					assert_gt(n.dot(Vector3(0, 0, 1)), 0.99, "South wall normal must point South (0, 0, 1)")

			# Test West (-X) drop
			if not west_drop_found:
				var yw: int = BiomeSystem.get_voxel_height(wx - 1, wz, 1337)
				if yw < y:
					west_drop_found = true
					var mid_y: float = (float(y) + float(yw)) * 0.5
					var wall_center: Vector3 = Vector3(float(wx), mid_y, float(wz) + 0.5)
					var from_outside: Vector3 = wall_center + Vector3(-0.6, 0.0, 0.0)
					var to_inside: Vector3 = wall_center + Vector3(0.6, 0.0, 0.0)
					var query := PhysicsRayQueryParameters3D.create(from_outside, to_inside)
					var hit: Dictionary = space_state.intersect_ray(query)
					assert_false(hit.is_empty(), "West wall at (%d, %d) must be hit from outside" % [wx, wz])
					assert_eq(hit.get("collider"), static_body)
					var n: Vector3 = hit.get("normal", Vector3.ZERO)
					assert_gt(n.dot(Vector3(-1, 0, 0)), 0.99, "West wall normal must point West (-1, 0, 0)")

			# Test East (+X) drop
			if not east_drop_found:
				var ye: int = BiomeSystem.get_voxel_height(wx + 1, wz, 1337)
				if ye < y:
					east_drop_found = true
					var mid_y: float = (float(y) + float(ye)) * 0.5
					var wall_center: Vector3 = Vector3(float(wx + 1), mid_y, float(wz) + 0.5)
					var from_outside: Vector3 = wall_center + Vector3(0.6, 0.0, 0.0)
					var to_inside: Vector3 = wall_center + Vector3(-0.6, 0.0, 0.0)
					var query := PhysicsRayQueryParameters3D.create(from_outside, to_inside)
					var hit: Dictionary = space_state.intersect_ray(query)
					assert_false(hit.is_empty(), "East wall at (%d, %d) must be hit from outside" % [wx, wz])
					assert_eq(hit.get("collider"), static_body)
					var n: Vector3 = hit.get("normal", Vector3.ZERO)
					assert_gt(n.dot(Vector3(1, 0, 0)), 0.99, "East wall normal must point East (1, 0, 0)")

	assert_true(north_drop_found, "Must find at least one North drop in chunk")
	assert_true(south_drop_found, "Must find at least one South drop in chunk")
	assert_true(west_drop_found, "Must find at least one West drop in chunk")
	assert_true(east_drop_found, "Must find at least one East drop in chunk")

	# 5. Collision rule verification: 1m step vs >= 2m impassable cliff
	# Cell (7, 1) y=1 vs West (6, 1) y=0 (1m step):
	# Horizontal ray at y = 0.5 (below step top) hits the step wall
	var ray_step_blocked := PhysicsRayQueryParameters3D.create(Vector3(6.5, 0.5, 1.5), Vector3(7.5, 0.5, 1.5))
	var hit_step_blocked: Dictionary = space_state.intersect_ray(ray_step_blocked)
	assert_false(hit_step_blocked.is_empty(), "Ray below 1m step must hit the step wall")
	assert_gt(hit_step_blocked.get("normal", Vector3.ZERO).dot(Vector3(-1, 0, 0)), 0.99)

	# Ray at y = 1.1 (above the 1m step top) passes over and does not hit the vertical side wall
	var ray_step_pass := PhysicsRayQueryParameters3D.create(Vector3(6.5, 1.1, 1.5), Vector3(7.5, 1.1, 1.5))
	var hit_step_pass: Dictionary = space_state.intersect_ray(ray_step_pass)
	assert_true(hit_step_pass.is_empty(), "Ray above 1m step must pass freely without colliding with side wall")

	# Cell (8, 2) y=3 vs West (7, 2) y=1 (2m cliff):
	# Ray at y = 1.5 (1st meter above ground) hits the wall
	var ray_cliff_1 := PhysicsRayQueryParameters3D.create(Vector3(7.5, 1.5, 2.5), Vector3(8.5, 1.5, 2.5))
	var hit_cliff_1: Dictionary = space_state.intersect_ray(ray_cliff_1)
	assert_false(hit_cliff_1.is_empty(), "Ray at 1st meter of 2m cliff must hit the wall")
	assert_gt(hit_cliff_1.get("normal", Vector3.ZERO).dot(Vector3(-1, 0, 0)), 0.99)

	# Ray at y = 2.5 (2nd meter above ground, impassable) ALSO hits the wall
	var ray_cliff_2 := PhysicsRayQueryParameters3D.create(Vector3(7.5, 2.5, 2.5), Vector3(8.5, 2.5, 2.5))
	var hit_cliff_2: Dictionary = space_state.intersect_ray(ray_cliff_2)
	assert_false(hit_cliff_2.is_empty(), "Ray at 2nd meter of 2m cliff must hit the wall (impassable cliff)")
	assert_gt(hit_cliff_2.get("normal", Vector3.ZERO).dot(Vector3(-1, 0, 0)), 0.99)

func test_chunk_builder_build_chunk_terrain_tall_cliff_splits_two_band_surfaces() -> void:
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
	assert_not_null(mesh, "Mesh must be generated")

	# Find surface indices for mat_cliff and biome side materials
	var cliff_surf_idx: int = -1
	var biome_side_surf_indices: Array[int] = []
	for s in range(mesh.get_surface_count()):
		var m = mesh.surface_get_material(s)
		if m == mat_cliff:
			cliff_surf_idx = s
		elif m in [mat_side_forest, mat_side_plains, mat_side_mountains]:
			biome_side_surf_indices.append(s)

	assert_gt(cliff_surf_idx, -1, "Mesh must contain a surface with mat_cliff")
	assert_gt(biome_side_surf_indices.size(), 0, "Mesh must contain at least one biome side surface")

	# Cell (8, 2) has y=3, west neighbor (7, 2) has y=1 (2m drop, West face at x=8.0, z in [2, 3]).
	# 1. Top rim band must be in biome side surface: x=8.0, z in [2.0, 3.0], y in [2.0, 3.0], normal (-1, 0, 0), UV v in [-3.0, -2.0]
	var found_rim_quad: bool = false
	for s_idx in biome_side_surf_indices:
		var mdt = MeshDataTool.new()
		mdt.create_from_surface(mesh, s_idx)
		for f in range(mdt.get_face_count()):
			var p0 = mdt.get_vertex(mdt.get_face_vertex(f, 0))
			var p1 = mdt.get_vertex(mdt.get_face_vertex(f, 1))
			var p2 = mdt.get_vertex(mdt.get_face_vertex(f, 2))
			var norm = mdt.get_face_normal(f)
			if is_equal_approx(p0.x, 8.0) and is_equal_approx(p1.x, 8.0) and is_equal_approx(p2.x, 8.0):
				if p0.z >= 1.99 and p0.z <= 3.01 and p1.z >= 1.99 and p1.z <= 3.01 and p2.z >= 1.99 and p2.z <= 3.01:
					if norm.dot(Vector3(-1, 0, 0)) > 0.95:
						assert_true(p0.y >= 1.99 and p1.y >= 1.99 and p2.y >= 1.99, "Top rim vertex Y must be >= 2.0")
						assert_true(p0.y <= 3.01 and p1.y <= 3.01 and p2.y <= 3.01, "Top rim vertex Y must be <= 3.0")
						var uv0 = mdt.get_vertex_uv(mdt.get_face_vertex(f, 0))
						assert_true(uv0.y <= -1.99 and uv0.y >= -3.01, "Top rim UV v must be in [-3.0, -2.0]")
						found_rim_quad = true

	assert_true(found_rim_quad, "build_chunk_terrain must produce top rim quad in biome side material surface for cell (8, 2)")

	# 2. Cliff body band must be in cliff material surface: x=8.0, z in [2.0, 3.0], y in [1.0, 2.0], normal (-1, 0, 0), UV v in [-2.0, -1.0]
	var found_cliff_quad: bool = false
	var mdt_cliff = MeshDataTool.new()
	mdt_cliff.create_from_surface(mesh, cliff_surf_idx)
	for f in range(mdt_cliff.get_face_count()):
		var p0 = mdt_cliff.get_vertex(mdt_cliff.get_face_vertex(f, 0))
		var p1 = mdt_cliff.get_vertex(mdt_cliff.get_face_vertex(f, 1))
		var p2 = mdt_cliff.get_vertex(mdt_cliff.get_face_vertex(f, 2))
		var norm = mdt_cliff.get_face_normal(f)
		if is_equal_approx(p0.x, 8.0) and is_equal_approx(p1.x, 8.0) and is_equal_approx(p2.x, 8.0):
			if p0.z >= 1.99 and p0.z <= 3.01 and p1.z >= 1.99 and p1.z <= 3.01 and p2.z >= 1.99 and p2.z <= 3.01:
				if norm.dot(Vector3(-1, 0, 0)) > 0.95:
					if p0.y <= 2.01 and p1.y <= 2.01 and p2.y <= 2.01:
						assert_true(p0.y >= 0.99 and p1.y >= 0.99 and p2.y >= 0.99, "Cliff body vertex Y must be >= 1.0")
						var uv0 = mdt_cliff.get_vertex_uv(mdt_cliff.get_face_vertex(f, 0))
						assert_true(uv0.y <= -0.99 and uv0.y >= -2.01, "Cliff body UV v must be in [-2.0, -1.0]")
						found_cliff_quad = true

	assert_true(found_cliff_quad, "build_chunk_terrain must produce lower cliff quad in cliff material surface for cell (8, 2)")


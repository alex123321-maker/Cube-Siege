extends GutTest

## Unit tests for ChunkBuilder:
## Validates directional ledge and buttress dressing planes, non-degenerate quads,
## and legacy emulation contract.

var dummy_mat: StandardMaterial3D

func before_all() -> void:
	dummy_mat = StandardMaterial3D.new()

func _triangle_area(p0: Vector3, p1: Vector3, p2: Vector3) -> float:
	return (p1 - p0).cross(p2 - p0).length() * 0.5

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

func test_legacy_baseline_emulation_toggle() -> void:
	ChunkBuilder.use_legacy_presentation = true
	var res_legacy = ChunkBuilder.build_chunk_terrain(0, 0, 1337, dummy_mat, dummy_mat, dummy_mat, dummy_mat)
	assert_not_null(res_legacy["mesh"], "Legacy mesh must generate")
	assert_not_null(res_legacy["shape"], "Legacy shape must generate")

	ChunkBuilder.use_legacy_presentation = false
	var res_modern = ChunkBuilder.build_chunk_terrain(0, 0, 1337, dummy_mat, dummy_mat, dummy_mat, dummy_mat)
	assert_not_null(res_modern["mesh"], "Modern mesh must generate")
	assert_not_null(res_modern["shape"], "Modern shape must generate")

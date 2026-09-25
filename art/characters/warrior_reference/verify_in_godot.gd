extends SceneTree
## Standalone GLB import, bounds / joint / material validation and runtime captures.
## Run inside a disposable project with -- --asset <absolute.glb> --output <directory>.

var world: Node3D
var model: Node3D
var camera: Camera3D
var output: String
var mesh_count: int = 0
var triangle_count: int = 0
var bounds: AABB
var have_bounds: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _arg(name: String) -> String:
	var args := OS.get_cmdline_user_args()
	var index: int = args.find(name)
	return args[index + 1] if index >= 0 and index + 1 < args.size() else ""

func _inspect(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		mesh_count += 1
		var box: AABB = mesh_node.global_transform * mesh_node.get_aabb()
		bounds = bounds.merge(box) if have_bounds else box
		have_bounds = true
		for surface: int in range(mesh_node.mesh.get_surface_count()):
			var arrays: Array = mesh_node.mesh.surface_get_arrays(surface)
			triangle_count += (arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else arrays[Mesh.ARRAY_VERTEX].size()) / 3
			var material := mesh_node.mesh.surface_get_material(surface) as BaseMaterial3D
			assert(material != null, "Missing material")
			assert(material.albedo_texture != null, "Missing atlas")
			assert(material.texture_filter in [BaseMaterial3D.TEXTURE_FILTER_NEAREST, BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS], "Atlas must use nearest sampling")
	for child: Node in node.get_children():
		_inspect(child)

func _run() -> void:
	output = _arg("--output")
	DirAccess.make_dir_recursive_absolute(output)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var error: Error = document.append_from_file(_arg("--asset"), state)
	assert(error == OK, "GLB import failed")
	model = document.generate_scene(state)
	assert(model != null)
	world = Node3D.new()
	root.add_child(world)
	world.add_child(model)
	_inspect(model)
	for joint: String in ["root", "body", "head", "arm_left", "arm_right", "leg_left", "leg_right", "sword", "shield", "cape"]:
		assert(model.find_child(joint, true, false) != null or model.name == joint, "Missing joint " + joint)
	assert(absf(bounds.position.y) < 0.002, "Feet must touch Y=0")
	assert(absf(bounds.size.y - 2.0) < 0.03, "Unexpected character height")
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.57, 0.55, 0.52)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.88, 0.91, 1.0)
	environment.ambient_light_energy = 0.35
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment_node.environment = environment
	world.add_child(environment_node)
	for setup: Array in [[Vector3(-42,-30,0),0.8],[Vector3(-28,135,0),0.3]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = setup[0]
		light.light_energy = setup[1]
		light.shadow_enabled = light.light_energy > 0.5
		light.directional_shadow_max_distance = 12.0
		world.add_child(light)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200,200)
	ground.mesh = plane
	ground.position.y = -0.007
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.57,0.55,0.52)
	ground_material.roughness = 0.9
	ground.material_override = ground_material
	world.add_child(ground)
	camera = Camera3D.new()
	root.msaa_3d = Viewport.MSAA_4X
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.65
	world.add_child(camera)
	camera.make_current()
	for view: Array in [["godot_front",Vector3(0,1.2,8)],["godot_three_quarter",Vector3(-5.8,3.1,8)],["godot_back",Vector3(0,1.2,-8)]]:
		camera.position = view[1]
		camera.look_at(Vector3(-0.06,1.02,0))
		for frame: int in range(5):
			await process_frame
		await RenderingServer.frame_post_draw
		var image: Image = root.get_texture().get_image()
		assert(image != null and not image.is_empty(), "No runtime image")
		assert(image.save_png(output.path_join(view[0] + ".png")) == OK)
	var report := {"engine": Engine.get_version_info().string, "meshes": mesh_count,
		"triangles": triangle_count, "height_m": bounds.size.y, "ground_y": bounds.position.y,
		"materials_and_nearest_filter": "PASS", "joints": "PASS", "glb_import": "PASS",
		"runtime_captures": 3, "animations": "Not authored; combat-idle static pose candidate"}
	var file := FileAccess.open(output.path_join("godot_report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("REFERENCE_GODOT_REPORT=" + JSON.stringify(report))
	quit(0)

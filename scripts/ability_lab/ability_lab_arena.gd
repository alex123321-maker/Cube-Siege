extends Node3D
class_name AbilityLabArena

var actor: CharacterBody3D
var runner: AbilityRunner
var targets: Array[AbilityLabTarget] = []
var paused: bool = false
var scenario: int = 0
var _areas: Dictionary[String, MeshInstance3D] = {}
var _obstacle: StaticBody3D
var _platform: StaticBody3D

func _ready() -> void:
	runner = AbilityRunner.new()
	runner.automatic = false
	add_child(runner)
	runner.area_changed.connect(_display_area)
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("111c2b")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b9d4f2")
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 1.5
	light.shadow_enabled = true
	add_child(light)
	var camera: Camera3D = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(8, 12, 11)
	camera.look_at(Vector3(0, 0, -1))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 10.0
	camera.current = true
	_box(Vector3(20, 0.2, 20), Vector3(0, -0.1, 0), Color("1d2d40"))
	_grid()
	_obstacle = _box(Vector3(1.4, 2.0, 0.4), Vector3(0, 1, -1.2), Color("607087"))
	_platform = _box(Vector3(2, 2, 2), Vector3(0, 1, -2), Color("607087"))
	actor = CharacterBody3D.new()
	actor.name = "Автор"
	actor.collision_layer = 2
	actor.collision_mask = 1
	add_child(actor)
	actor.add_to_group("player")
	_body_visual(actor, Color("52d7e2"))
	var label: Label3D = Label3D.new()
	label.text = "ИСТОЧНИК"
	label.position.y = 1.3
	label.font_size = 30
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	actor.add_child(label)
	for i: int in range(4):
		var target: AbilityLabTarget = _make_target(i)
		targets.append(target)
	reset()

func _physics_process(delta: float) -> void:
	if not paused:
		advance(delta)

func advance(delta: float) -> void:
	runner.advance(delta)
	for target: AbilityLabTarget in targets:
		target.advance_fixture(delta)

func reset() -> void:
	runner.cancel("Арена сброшена")
	runner.cooldown_remaining = 0.0
	runner.traces.clear()
	actor.position = Vector3(0, 0.9, 1)
	var positions: Array[Vector3] = [Vector3(0, 0.9, -1), Vector3(-1.6, 0.9, -0.2), Vector3(1.6, 0.9, -0.2), Vector3(0, 0.9, 2.6)]
	_obstacle.visible = scenario == 1
	_obstacle.collision_layer = 1 if scenario == 1 else 0
	_platform.visible = scenario == 2
	_platform.collision_layer = 1 if scenario == 2 else 0
	if scenario == 1:
		positions[0] = Vector3(0, 0.9, -2)
	if scenario == 2:
		positions[0] = Vector3(0, 2.9, -2)
	for i: int in range(targets.size()):
		targets[i].position = positions[i]
		targets[i].reset_fixture()
	for mesh: MeshInstance3D in _areas.values():
		if is_instance_valid(mesh):
			mesh.queue_free()
	_areas.clear()

func play(definition: AbilityDefinition) -> bool:
	return runner.start_cast(definition, actor, Vector3.FORWARD, Callable(), true)

func step_frame() -> void:
	paused = true
	advance(1.0 / 60.0)

func _make_target(index: int) -> AbilityLabTarget:
	var target: AbilityLabTarget = AbilityLabTarget.new()
	target.name = "Манекен_%d" % (index + 1)
	target.max_health = 500.0
	target.collision_layer = 4
	target.collision_mask = 1
	_body_visual(target, Color("f6a86e"))
	var hurtbox: HurtboxArea = HurtboxArea.new()
	hurtbox.name = "Hurtbox"
	hurtbox.collision_layer = 8
	hurtbox.collision_mask = 0
	hurtbox.target_node_path = NodePath("..")
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	shape.shape = box
	hurtbox.add_child(shape)
	target.add_child(hurtbox)
	var visuals: Node3D = Node3D.new()
	visuals.name = "Visuals"
	var label: Label3D = Label3D.new()
	label.name = "HPLabel"
	label.position.y = 1.3
	label.font_size = 32
	label.pixel_size = 0.012
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	visuals.add_child(label)
	target.add_child(visuals)
	add_child(target)
	return target

func _body_visual(body: CharacterBody3D, color: Color) -> void:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(0.7, 1.8, 0.7)
	mesh.mesh = box
	mesh.material_override = _material(color)
	body.add_child(mesh)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var collision: BoxShape3D = BoxShape3D.new()
	collision.size = box.size
	shape.shape = collision
	body.add_child(shape)

func _box(size: Vector3, position_value: Vector3, color: Color) -> StaticBody3D:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _material(color)
	body.add_child(mesh)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var collision: BoxShape3D = BoxShape3D.new()
	collision.size = size
	shape.shape = collision
	body.add_child(shape)
	add_child(body)
	body.position = position_value
	return body

func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	return material

func _grid() -> void:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var geometry: ImmediateMesh = ImmediateMesh.new()
	geometry.surface_begin(Mesh.PRIMITIVE_LINES)
	for i: int in range(-10, 11):
		geometry.surface_add_vertex(Vector3(i, 0.015, -10))
		geometry.surface_add_vertex(Vector3(i, 0.015, 10))
		geometry.surface_add_vertex(Vector3(-10, 0.015, i))
		geometry.surface_add_vertex(Vector3(10, 0.015, i))
	geometry.surface_end()
	mesh.mesh = geometry
	mesh.material_override = _material(Color("36516b"))
	add_child(mesh)

func _display_area(slot: String, center: Vector3, direction: Vector3, step: AbilityStep, active: bool) -> void:
	if step.kind != AbilityStep.Kind.AREA:
		return
	if not active:
		if _areas.has(slot) and is_instance_valid(_areas[slot]):
			_areas[slot].visible = false
		return
	if not _areas.has(slot):
		var mesh: MeshInstance3D = MeshInstance3D.new()
		var material: StandardMaterial3D = _material(Color(0.1, 0.85, 0.8, 0.4))
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.material_override = material
		add_child(mesh)
		_areas[slot] = mesh
	var display: MeshInstance3D = _areas[slot]
	display.visible = active
	if display.get_meta("radius", -1.0) != step.radius or display.get_meta("arc", -1.0) != step.arc_degrees:
		var geometry: ImmediateMesh = ImmediateMesh.new()
		geometry.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i: int in range(48):
			var angle_a: float = deg_to_rad(-step.arc_degrees * 0.5 + step.arc_degrees * i / 48.0)
			var angle_b: float = deg_to_rad(-step.arc_degrees * 0.5 + step.arc_degrees * (i + 1) / 48.0)
			geometry.surface_add_vertex(Vector3.ZERO)
			geometry.surface_add_vertex(Vector3(sin(angle_a), 0, -cos(angle_a)) * step.radius)
			geometry.surface_add_vertex(Vector3(sin(angle_b), 0, -cos(angle_b)) * step.radius)
		geometry.surface_end()
		display.mesh = geometry
		display.set_meta("radius", step.radius)
		display.set_meta("arc", step.arc_degrees)
	display.global_position = center + Vector3(0, -0.8, 0)
	display.rotation.y = atan2(-direction.x, -direction.z)

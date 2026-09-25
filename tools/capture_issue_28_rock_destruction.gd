extends SceneTree

const ROCK_SCENE: PackedScene = preload("res://scenes/resource_stone.tscn")
const IRON_SCENE: PackedScene = preload("res://scenes/resource_iron.tscn")

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var world := Node3D.new()
	world.name = "Issue28RockDestructionCapture"
	root.add_child(world)
	current_scene = world
	_create_stage(world)

	var camera := Camera3D.new()
	camera.position = Vector3(4.0, 5.0, 9.0)
	camera.fov = 38.0
	world.add_child(camera)
	camera.look_at(Vector3(0.0, 1.0, 0.0))
	camera.current = true

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	light.light_energy = 1.8
	world.add_child(light)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.16, 0.19)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.63, 0.68, 0.72)
	env.ambient_light_energy = 0.75
	environment.environment = env
	world.add_child(environment)

	var rocks: Array[ResourceRock] = []
	for index in range(3):
		var rock_scene: PackedScene = IRON_SCENE if index == 2 else ROCK_SCENE
		var rock := rock_scene.instantiate() as ResourceRock
		rock.configure_rock(ResourceRock.RockType.IRON if index == 2 else ResourceRock.RockType.STONE, 6, 1, index, 139 + index * 37)
		rock.position = Vector3((index - 1) * 3.5, 0.0, 0.0)
		world.add_child(rock)
		rocks.append(rock)

	await process_frame
	await create_timer(1.4).timeout
	for hit_index in range(5):
		for rock in rocks:
			if not rock.is_destroyed:
				rock._on_damaged(rock.max_health / 5.0, Vector3.ZERO, "capture", null)
		await create_timer(0.72).timeout
	await create_timer(1.6).timeout
	quit()

func _create_stage(world: Node3D) -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "ShowcaseGround"
	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(20.0, 0.2, 12.0)
	floor_mesh.mesh = plane
	floor_mesh.position.y = -0.12
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.18, 0.24, 0.20)
	floor_material.roughness = 1.0
	floor_mesh.material_override = floor_material
	floor_body.add_child(floor_mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = plane.size
	collision.shape = shape
	collision.position.y = -0.12
	floor_body.add_child(collision)
	world.add_child(floor_body)

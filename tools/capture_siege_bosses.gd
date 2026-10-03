extends SceneTree

## Actual Forward+ render of every live encounter and its authoritative hazards.
## -- --stage=2 --night restricts a short charge movie to Gorgon at night.
const SCENES: PackedStringArray = [
	"res://scenes/bosses/boss_01_cairn.tscn", "res://scenes/bosses/boss_02_gorgon.tscn",
	"res://scenes/bosses/boss_03_ash_oracle.tscn", "res://scenes/bosses/boss_04_mortar.tscn",
	"res://scenes/bosses/boss_05_rift_warden.tscn", "res://scenes/bosses/boss_06_rift_harbinger.tscn"]
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")

class StairTerrain extends MapGenerator:
	func _ready() -> void:
		set_process(false)
	func get_voxel_height(x: int, _z: int) -> int:
		return 2 if x >= 5 else (1 if x >= 0 else 0)

var output_dir: String = "screenshots_debug/demo_polish/canonical_bosses"
var world: Node3D
var player: PlayerPrototype
var camera: Camera3D
var terrain: StairTerrain
var night: bool = false
var only_stage: int = 0

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--stage="):
			only_stage = int(argument.get_slice("=", 1))
		elif argument == "--night":
			night = true
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	call_deferred("_capture")

func _floor(position: Vector3, size: Vector3, color: Color) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.94
	mesh.material = material
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = mesh
	body.add_child(visual)
	world.add_child(body)
	body.global_position = position

func _setup_world() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	terrain = StairTerrain.new()
	terrain.add_to_group("map_generator")
	world.add_child(terrain)
	_floor(Vector3(0, -0.5, 0), Vector3(50, 1, 50), Color(0.23, 0.32, 0.18))
	_floor(Vector3(2.5, 0.5, 0), Vector3(5, 1, 50), Color(0.28, 0.37, 0.21))
	_floor(Vector3(15, 1, 0), Vector3(20, 2, 50), Color(0.34, 0.4, 0.26))
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.035, 0.06, 0.12) if night else Color(0.15, 0.22, 0.28)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(0.32, 0.43, 0.7) if night else Color(0.78, 0.82, 0.88)
	environment.environment.ambient_light_energy = 0.45 if night else 0.7
	world.add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_color = Color(0.55, 0.68, 0.95) if night else Color(1.0, 0.91, 0.76)
	sun.light_energy = 0.5 if night else 1.25
	sun.shadow_enabled = true
	world.add_child(sun)
	player = PLAYER_SCENE.instantiate() as PlayerPrototype
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process(false)
	player.input_enabled = false
	player.current_health = 100000.0
	player.global_position = Vector3(3.0, 1.9, -5.0)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(15, 20, 14)
	camera.rotation_degrees = Vector3(-43.3, 45, 0)
	camera.fov = 45.0
	camera.make_current()
	var registry: Node = root.get_node_or_null("EntityRegistry")
	if registry:
		registry.monster_flowfield.set_height_lookup(terrain.get_voxel_height)

func _frames(count: int) -> void:
	for _frame: int in range(count):
		await physics_frame
		await process_frame

func _save(stage: int, attack: int, phase: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = "%s/%s_%02d_attack_%d_%s.png" % [output_dir, "night" if night else "day", stage, attack, phase]
	if root.get_texture().get_image().save_png(path) != OK:
		push_error("Could not save " + path)
		quit(1)

func _capture() -> void:
	create_timer(90.0).timeout.connect(func() -> void:
		push_error("SIEGE_BOSS_CAPTURE TIMEOUT after 90 seconds")
		quit(1)
	)
	DirAccess.make_dir_recursive_absolute(output_dir)
	_setup_world()
	await _frames(4)
	var captures: int = 0
	for stage: int in range(1, 7):
		if only_stage > 0 and stage != only_stage:
			continue
		var profile: BossEncounterProfile = BossEncounterCatalog.build(stage)
		for attack: int in range(profile.attacks.size()):
			if only_stage == 2 and attack > 0:
				continue
			player.global_position = Vector3(3.0, 1.9, -5.0)
			var boss: SiegeBoss = (load(SCENES[stage - 1]) as PackedScene).instantiate() as SiegeBoss
			boss.configure(stage, player)
			world.add_child(boss)
			boss.global_position = Vector3(-3.0, 1.5, 2.0)
			boss._attack_index = attack - 1
			boss.begin_next_attack()
			var half_warning: int = maxi(1, int(boss._attack.windup * 60.0 * 0.5))
			await _frames(half_warning)
			await _save(stage, attack, "warning")
			# Hero reacts after the locked warning. Hazard placement must stay put.
			if boss._attack.kind == BossAttackSpec.Kind.SWEEP:
				player.global_position += Vector3(3.0, 0.0, 3.0)
			await _frames(half_warning + maxi(2, int(boss._attack.active * 60.0 * 0.2)))
			await _save(stage, attack, "active")
			captures += 2
			if only_stage == 2:
				await _frames(int(boss._attack.recovery * 60.0))
			boss.queue_free()
			await _frames(2)
	print("SIEGE_BOSS_CAPTURE PASS: %d actual warning/active PNGs, %s" % [captures, "night" if night else "day"])
	quit(0)

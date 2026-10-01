extends Node3D
class_name AbilityLabArena

signal event_recorded(message: String)
signal damage_recorded(amount: float)

const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
const ZOMBIE_SCENE: PackedScene = preload("res://scenes/enemy_dummy.tscn")
const ActorScript: Script = preload("res://scripts/ability_lab/ability_viewer_actor.gd")
const TargetScript: Script = preload("res://scripts/ability_lab/ability_lab_target.gd")
var actor: AbilityViewerActor
var targets: Array[AbilityLabTarget] = []
var camera: Camera3D
var elapsed: float = 0.0
var playing: bool = false
var _stage: Node3D
var _generation: int = 0

class RetiredScene extends RefCounted:
	var stage: Node3D
	var remaining: float = PlayerAbilities.NUKE_WINDUP + 0.2

var _retired: Array[RetiredScene] = []

func _ready() -> void:
	var world: WorldEnvironment = WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("111c2b")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("b9d4f2")
	world.environment.ambient_light_energy = 0.8
	add_child(world)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 1.5
	light.shadow_enabled = true
	add_child(light)
	camera = Camera3D.new()
	add_child(camera)
	camera.position = Vector3(8, 11, 12)
	camera.look_at(Vector3(0, 0, -1.5))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 12.0
	camera.current = true
	var floor_body: StaticBody3D = StaticBody3D.new()
	var shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(60, 0.2, 60)
	shape.shape = box
	floor_body.add_child(shape)
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var geometry: BoxMesh = BoxMesh.new()
	geometry.size = box.size
	mesh.mesh = geometry
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("273747")
	material.roughness = 0.9
	mesh.material_override = material
	floor_body.add_child(mesh)
	add_child(floor_body)
	floor_body.position.y = -0.1
	_grid()

func clear_preview() -> void:
	_generation += 1
	playing = false
	if is_instance_valid(_stage):
		remove_child(_stage)
		# Native async methods must observe an actor outside the tree before their
		# RefCounted combat owner is released. No retired scene can hit new targets.
		var retired: RetiredScene = RetiredScene.new()
		retired.stage = _stage
		_retired.append(retired)
	_stage = null
	actor = null
	var vfx: Node = get_node_or_null("/root/VFXManager")
	if vfx:
		vfx.clear_effects()
	targets.clear()

func prepare(entry: AbilityViewerCatalog.Entry, variant: AbilityViewerCatalog.VariantKind) -> void:
	clear_preview()
	elapsed = 0.0
	camera.size = 12.0
	_stage = Node3D.new()
	add_child(_stage)
	var instance: CharacterBody3D = PLAYER_SCENE.instantiate() as CharacterBody3D
	instance.set_script(ActorScript)
	actor = instance as AbilityViewerActor
	_stage.add_child(actor)
	actor.position = Vector3(0, 0.9, 1)
	actor.set_class(entry.class_id as AbilityViewerActor.CharacterClass, false)
	actor.show_warrior_model()
	actor.orientation.setup(Vector3.FORWARD)
	var positions: Array[Vector3] = [Vector3(0, 0.9, -0.7), Vector3(0, 0.9, -2.7), Vector3(0, 0.9, -4.7), Vector3(1.2, 0.9, -0.7)]
	for i: int in range(positions.size()):
		var zombie: CharacterBody3D = ZOMBIE_SCENE.instantiate() as CharacterBody3D
		zombie.set_script(TargetScript)
		var target: AbilityLabTarget = zombie as AbilityLabTarget
		target.name = "Зомби_%d" % (i + 1)
		_stage.add_child(target)
		target.position = positions[i]
		target.rotation.y = PI
		target.damage_observed.connect(func(amount: float, type: String) -> void:
			damage_recorded.emit(amount)
			event_recorded.emit("%.2f с · %s · %s урона (%s)" % [elapsed, target.name, str(snappedf(amount, 0.001)), type])
		)
		targets.append(target)
	match variant:
		AbilityViewerCatalog.VariantKind.SHARP_EDGE: actor.abilities.apply_card_upgrade("SHARP_EDGE", actor)
		AbilityViewerCatalog.VariantKind.VAMPIRISM:
			actor.current_health = actor.max_health * 0.5
			actor.abilities.apply_card_upgrade("VAMPIRIC_STRIKE", actor)
		AbilityViewerCatalog.VariantKind.WINDSTRIDER: actor.abilities.apply_card_upgrade("WINDSTRIDER", actor)
		AbilityViewerCatalog.VariantKind.DUEL:
			actor.abilities.perform_warrior_ultimate(actor, targets[0], true)

func demonstrate(entry: AbilityViewerCatalog.Entry, variant: AbilityViewerCatalog.VariantKind) -> void:
	playing = true
	event_recorded.emit("Применение: " + entry.title)
	var generation: int = _generation
	match entry.slot:
		AbilityViewerCatalog.Slot.ATTACK: actor.perform_attack()
		AbilityViewerCatalog.Slot.SPECIAL: actor.perform_special_attack()
		AbilityViewerCatalog.Slot.UTILITY:
			actor.perform_utility()
			if variant == AbilityViewerCatalog.VariantKind.PARRY_SUCCESS:
				await get_tree().create_timer(0.2).timeout
				if generation == _generation and is_instance_valid(actor):
					targets[0].target_player = actor
					targets[0].demonstrate_attack()
					event_recorded.emit("Входящий удар зомби · парирование")
			elif variant == AbilityViewerCatalog.VariantKind.DETONATE:
				await get_tree().create_timer(1.0).timeout
				if generation == _generation and is_instance_valid(actor):
					actor.perform_utility()
		AbilityViewerCatalog.Slot.ULTIMATE:
			if entry.class_id == 2:
				actor.abilities.perform_engineer_ultimate(actor, Vector3(0, 0, -1.5))
			else:
				actor.abilities.perform_ultimate(actor, entry.class_id, targets[0], true)
		AbilityViewerCatalog.Slot.DASH:
			actor.movement.perform_dash(Vector3.FORWARD, Vector3.RIGHT)

func _physics_process(delta: float) -> void:
	if playing:
		elapsed += delta
	for i: int in range(_retired.size() - 1, -1, -1):
		_retired[i].remaining -= delta
		if _retired[i].remaining <= 0.0:
			_retired[i].stage.free()
			_retired.remove_at(i)

func _exit_tree() -> void:
	for retired: RetiredScene in _retired:
		if is_instance_valid(retired.stage):
			retired.stage.free()
	_retired.clear()

func _grid() -> void:
	var lines: ImmediateMesh = ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for i: int in range(-20, 21):
		lines.surface_add_vertex(Vector3(i, 0.015, -20))
		lines.surface_add_vertex(Vector3(i, 0.015, 20))
		lines.surface_add_vertex(Vector3(-20, 0.015, i))
		lines.surface_add_vertex(Vector3(20, 0.015, i))
	lines.surface_end()
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.mesh = lines
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color("385165")
	mesh.material_override = material
	add_child(mesh)

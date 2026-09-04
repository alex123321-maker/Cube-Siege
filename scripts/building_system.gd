extends Node3D
class_name BuildingSystem

signal building_placed(cell: Vector2i, building: Node)
signal resources_updated(wood: int, stone: int, iron: int)

enum PrefabType { NONE, WOOD_WALL, FLOOR_SPIKES, ARCHER_TOWER, IRON_WALL, BALLISTA }

@export var player_path: NodePath
@export var hud_path: NodePath

var current_prefab_type: PrefabType = PrefabType.NONE
var placed_buildings: Dictionary = {} # Vector2i -> BuildingBase

const ResourceWallet = preload("res://scripts/economy/resource_wallet.gd")
const BuildingDefinition = preload("res://scripts/resources/building_definition.gd")

var wallet: ResourceWallet = ResourceWallet.new(16, 8, 4)

var wood_count: int:
	get:
		return wallet.get_wood()
	set(val):
		var diff = val - wallet.get_wood()
		if diff > 0:
			wallet.add_resource(diff, 0, 0)
		elif diff < 0:
			wallet.spend_resources(-diff, 0, 0)

var stone_count: int:
	get:
		return wallet.get_stone()
	set(val):
		var diff = val - wallet.get_stone()
		if diff > 0:
			wallet.add_resource(0, diff, 0)
		elif diff < 0:
			wallet.spend_resources(0, -diff, 0)

var iron_count: int:
	get:
		return wallet.get_iron()
	set(val):
		var diff = val - wallet.get_iron()
		if diff > 0:
			wallet.add_resource(0, 0, diff)
		elif diff < 0:
			wallet.spend_resources(0, 0, -diff)

# Preview Hologram
var preview_node: Node3D = null
var preview_mesh: MeshInstance3D = null
var green_mat: StandardMaterial3D = null
var red_mat: StandardMaterial3D = null

func _ready() -> void:
	wallet.resources_changed.connect(_on_wallet_resources_changed)
	setup_materials()
	setup_preview()
	_on_wallet_resources_changed(wallet.get_wood(), wallet.get_stone(), wallet.get_iron())

func _on_wallet_resources_changed(wood: int, stone: int, iron: int) -> void:
	emit_signal("resources_updated", wood, stone, iron)
	if get_node_or_null("/root/EventBus"):
		EventBus.resources_changed.emit(wood, stone, iron)

func setup_materials() -> void:
	green_mat = StandardMaterial3D.new()
	green_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	green_mat.albedo_color = Color(0.2, 1.0, 0.3, 0.5)
	green_mat.emission_enabled = true
	green_mat.emission = Color(0.2, 0.9, 0.3, 1.0)
	green_mat.emission_energy_multiplier = 0.5

	red_mat = StandardMaterial3D.new()
	red_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	red_mat.albedo_color = Color(1.0, 0.2, 0.2, 0.5)
	red_mat.emission_enabled = true
	red_mat.emission = Color(0.9, 0.2, 0.2, 1.0)
	red_mat.emission_energy_multiplier = 0.5

func setup_preview() -> void:
	preview_node = Node3D.new()
	add_child(preview_node)
	preview_node.visible = false

	preview_mesh = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = Vector3(1.0, 2.0, 1.0)
	preview_mesh.mesh = box
	preview_mesh.position.y = 1.0
	preview_node.add_child(preview_mesh)

func _process(_delta: float) -> void:
	if current_prefab_type == PrefabType.NONE:
		preview_node.visible = false
		return

	var snapped_pos: Vector3 = get_aimed_grid_position()
	var cell: Vector2i = Vector2i(int(snapped_pos.x), int(snapped_pos.z))
	preview_node.global_position = snapped_pos
	preview_node.visible = true

	var can_build: bool = is_cell_free(cell) and has_enough_resources(current_prefab_type)
	preview_mesh.material_override = green_mat if can_build else red_mat

	# Placement on LMB
	if Input.is_action_just_pressed("attack_lmb"):
		if can_build:
			place_building(snapped_pos, cell, current_prefab_type)
		get_viewport().set_input_as_handled()

	# Cancel on RMB
	if Input.is_action_just_pressed("special_rmb"):
		cancel_build_mode()
		get_viewport().set_input_as_handled()

func select_prefab(type: PrefabType) -> void:
	current_prefab_type = type
	set_all_buildings_transparency(0.6)
	if type == PrefabType.FLOOR_SPIKES:
		(preview_mesh.mesh as BoxMesh).size = Vector3(1.0, 0.2, 1.0)
		preview_mesh.position.y = 0.1
	elif type == PrefabType.ARCHER_TOWER:
		(preview_mesh.mesh as BoxMesh).size = Vector3(1.0, 3.5, 1.0)
		preview_mesh.position.y = 1.75
	elif type == PrefabType.BALLISTA:
		(preview_mesh.mesh as BoxMesh).size = Vector3(1.2, 2.8, 1.2)
		preview_mesh.position.y = 1.4
	else:
		(preview_mesh.mesh as BoxMesh).size = Vector3(1.0, 2.0, 1.0)
		preview_mesh.position.y = 1.0

func cancel_build_mode() -> void:
	current_prefab_type = PrefabType.NONE
	set_all_buildings_transparency(0.0)
	if preview_node:
		preview_node.visible = false

func set_all_buildings_transparency(alpha: float) -> void:
	for b in placed_buildings.values():
		if b and is_instance_valid(b) and b.has_method("set_transparency"):
			b.set_transparency(alpha)

func is_cell_free(cell: Vector2i) -> bool:
	# Cannot place a building on another building!
	if placed_buildings.has(cell):
		return false
	# Protect central portal at (0, 0)
	if abs(cell.x) <= 1 and abs(cell.y) <= 1:
		return false
	# Cannot place a building inside existing resource nodes
	var resources: Array[Node] = get_tree().get_nodes_in_group("resource_nodes")
	for res in resources:
		if res and is_instance_valid(res) and res is Node3D:
			var r_pos: Vector3 = (res as Node3D).global_position
			if Vector2i(round(r_pos.x), round(r_pos.z)) == cell:
				return false
	return true

func has_enough_resources(type: PrefabType) -> bool:
	var def: BuildingDefinition = BuildingDefinition.get_definition(type)
	if not def:
		return false
	return wallet.has_resources(def.wood_cost, def.stone_cost, def.iron_cost)

func place_building(snapped_pos: Vector3, cell: Vector2i, type: PrefabType) -> void:
	var def: BuildingDefinition = BuildingDefinition.get_definition(type)
	if not def:
		return

	# Deduct costs via authoritative wallet
	if not wallet.spend_resources(def.wood_cost, def.stone_cost, def.iron_cost):
		return

	# Spawn building
	var b_scene: PackedScene = load(def.scene_path)
	if not b_scene:
		return
	var building: Node3D = b_scene.instantiate()
	get_parent().add_child(building)
	building.global_position = snapped_pos
	building.grid_coord = cell
	placed_buildings[cell] = building

	# Keep transparent while still in building mode
	if building.has_method("set_transparency"):
		building.set_transparency(0.6)

	if building.has_signal("building_destroyed"):
		building.connect("building_destroyed", Callable(self, "_on_building_destroyed"))

	emit_signal("building_placed", cell, building)
	if get_node_or_null("/root/EventBus"):
		EventBus.building_placed.emit(str(type), cell, building)

func _on_building_destroyed(b: Node) -> void:
	if b.has_method("get") and b.get("grid_coord") != null:
		var c: Vector2i = b.grid_coord
		if placed_buildings.has(c):
			placed_buildings.erase(c)
			if get_node_or_null("/root/EventBus"):
				EventBus.building_destroyed.emit(c, b)

func get_aimed_grid_position() -> Vector3:
	var vp: Viewport = get_viewport()
	if not vp: return Vector3.ZERO
	var cam: Camera3D = vp.get_camera_3d()
	if not cam: return Vector3.ZERO

	var mouse_pos: Vector2 = vp.get_mouse_position()
	var ray_origin: Vector3 = cam.project_ray_origin(mouse_pos)
	var ray_normal: Vector3 = cam.project_ray_normal(mouse_pos)

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_origin, ray_origin + ray_normal * 100.0, 1)

	# Exclude existing buildings so ray passes THROUGH them to the ground behind!
	var exclude_rids: Array[RID] = []
	for b in placed_buildings.values():
		if b and is_instance_valid(b) and b is CollisionObject3D:
			exclude_rids.append((b as CollisionObject3D).get_rid())
	query.exclude = exclude_rids

	var hit: Dictionary = space_state.intersect_ray(query)

	if not hit.is_empty():
		var hit_pos: Vector3 = hit.position
		var hit_norm: Vector3 = hit.normal
		var target: Vector3 = hit_pos + hit_norm * 0.1
		return Vector3(round(target.x), round(target.y), round(target.z))

	var ground_plane: Plane = Plane(Vector3.UP, 0.0)
	var inter: Variant = ground_plane.intersects_ray(ray_origin, ray_normal)
	if inter is Vector3:
		return Vector3(round(inter.x), 0.0, round(inter.z))
	return Vector3.ZERO

func add_resource(wood: int = 0, stone: int = 0, iron: int = 0) -> void:
	wallet.add_resource(wood, stone, iron)

func spend_resources(wood: int = 0, stone: int = 0, iron: int = 0) -> bool:
	return wallet.spend_resources(wood, stone, iron)

func has_resources(wood: int = 0, stone: int = 0, iron: int = 0) -> bool:
	return wallet.has_resources(wood, stone, iron)

func update_hud_counters() -> void:
	# Deprecated direct mutation: UI components now react to EventBus.resources_changed
	pass

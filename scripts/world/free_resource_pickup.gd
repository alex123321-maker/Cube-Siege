extends Area3D
class_name FreeResourcePickup

## FreeResourcePickup: Non-blocking loose resource pickup (1-3 units).
## Picked up via interaction [E] without requiring combat/attacks.
## Does not block player, enemy, or projectile movement.

@export var resource_type: ResourceDistribution.ResourceType = ResourceDistribution.ResourceType.WOOD
@export var yield_amount: int = 1
@export var variation_index: int = 0

var is_harvested: bool = false
var prompt_label: Label3D = null
var visuals_node: Node3D = null

const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("free_resources")

	# Collision layer 4 (bit 3: value 8) matches InteractionSensor mask (mask 9 = 1 | 8)
	collision_layer = 8
	collision_mask = 0
	monitoring = false
	monitorable = true

	_build_visuals()
	_setup_prompt()

func _setup_prompt() -> void:
	prompt_label = Label3D.new()
	add_child(prompt_label)
	prompt_label.position = Vector3(0, 0.6, 0)
	prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	prompt_label.no_depth_test = true
	prompt_label.font_size = 24
	prompt_label.outline_size = 5
	prompt_label.outline_modulate = Color(0, 0, 0, 1)
	prompt_label.visible = false

func _build_visuals() -> void:
	visuals_node = Node3D.new()
	visuals_node.name = "Visuals"
	add_child(visuals_node)

	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = 1.0
	col_shape.shape = sphere
	add_child(col_shape)

	match resource_type:
		ResourceDistribution.ResourceType.WOOD:
			_create_wood_twigs()
		ResourceDistribution.ResourceType.STONE:
			_create_pebbles()
		ResourceDistribution.ResourceType.IRON:
			_create_iron_nuggets()
		ResourceDistribution.ResourceType.MAGIC_STONE:
			_create_magic_crystals()

func _create_wood_twigs() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.30, 0.16, 1.0)
	mat.roughness = 0.9

	for i in range(yield_amount):
		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		box.size = Vector3(0.08, 0.08, 0.45 + (i * 0.05))
		box.material = mat
		mesh_inst.mesh = box
		mesh_inst.position = Vector3(
			(i - (yield_amount - 1) * 0.5) * 0.22,
			0.05,
			(sin(float(i + variation_index) * 2.1) * 0.12)
		)
		mesh_inst.rotation_degrees = Vector3(0, float(i * 45 + variation_index * 30), 0)
		visuals_node.add_child(mesh_inst)

func _create_pebbles() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.52, 0.54, 0.56, 1.0)
	mat.roughness = 0.85

	for i in range(yield_amount):
		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		var sz: float = 0.16 + (i * 0.04)
		box.size = Vector3(sz, sz * 0.7, sz * 1.1)
		box.material = mat
		mesh_inst.mesh = box
		mesh_inst.position = Vector3(
			(i - (yield_amount - 1) * 0.5) * 0.25,
			sz * 0.35,
			(cos(float(i + variation_index) * 1.7) * 0.1)
		)
		mesh_inst.rotation_degrees = Vector3(float(i * 15), float(i * 55), 0)
		visuals_node.add_child(mesh_inst)

func _create_iron_nuggets() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.28, 0.25, 1.0)
	mat.metallic = 0.85
	mat.roughness = 0.4
	mat.emission_enabled = true
	mat.emission = Color(0.85, 0.5, 0.15, 1.0)
	mat.emission_energy_multiplier = 0.4

	for i in range(yield_amount):
		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		var sz: float = 0.18 + (i * 0.03)
		box.size = Vector3(sz, sz * 0.8, sz * 0.9)
		box.material = mat
		mesh_inst.mesh = box
		mesh_inst.position = Vector3(
			(i - (yield_amount - 1) * 0.5) * 0.24,
			sz * 0.4,
			(sin(float(i + variation_index) * 1.9) * 0.1)
		)
		mesh_inst.rotation_degrees = Vector3(12, float(i * 60 + 20), 8)
		visuals_node.add_child(mesh_inst)

func _create_magic_crystals() -> void:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.85, 1.0, 0.9)
	mat.roughness = 0.2
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.9, 1.0, 1.0)
	mat.emission_energy_multiplier = 1.8

	for i in range(yield_amount):
		var mesh_inst: MeshInstance3D = MeshInstance3D.new()
		var box: BoxMesh = BoxMesh.new()
		var h: float = 0.35 + (i * 0.08)
		box.size = Vector3(0.14, h, 0.14)
		box.material = mat
		mesh_inst.mesh = box
		mesh_inst.position = Vector3(
			(i - (yield_amount - 1) * 0.5) * 0.22,
			h * 0.5,
			(cos(float(i + variation_index) * 2.3) * 0.1)
		)
		mesh_inst.rotation_degrees = Vector3(float(i * 12 - 6), float(i * 45 + 15), float(sin(float(i)) * 14.0))
		visuals_node.add_child(mesh_inst)

func is_interactable() -> bool:
	return not is_harvested

func is_ready_for_pickup() -> bool:
	return not is_harvested

func set_focused(focused: bool) -> void:
	if not prompt_label or is_harvested:
		return
	prompt_label.visible = focused
	if focused:
		var name_str: String = _get_resource_name()
		prompt_label.text = "[E] TAKE (+%d %s)" % [yield_amount, name_str]
		prompt_label.modulate = Color(1.0, 0.95, 0.3)
		if visuals_node:
			visuals_node.scale = Vector3(1.15, 1.15, 1.15)
	else:
		if visuals_node:
			visuals_node.scale = Vector3(1.0, 1.0, 1.0)

func set_interaction_progress(progress: float) -> void:
	if not prompt_label or is_harvested:
		return
	var bars: int = int(progress * 10.0)
	var bar_str: String = ""
	for i in range(10):
		bar_str += "█" if i < bars else "░"
	prompt_label.text = "[E] [%s] %d%%\n(+%d %s)" % [bar_str, int(progress * 100), yield_amount, _get_resource_name()]
	prompt_label.modulate = Color(0.3, 1.0, 0.5)

func interact(player: Node, _is_shift: bool = false) -> void:
	harvest(player)

func harvest(player: Node) -> void:
	if is_harvested:
		return
	is_harvested = true
	if prompt_label:
		prompt_label.visible = false

	var total_yield: int = yield_amount
	if player and player.get("resource_multiplier") != null:
		var mult: int = maxi(1, int(player.resource_multiplier))
		total_yield *= mult

	var b_sys = player.get("building_system") if player else null
	if not b_sys and player:
		b_sys = player.get_node_or_null("../BuildingSystem")

	if b_sys and b_sys.has_method("add_resource"):
		match resource_type:
			ResourceDistribution.ResourceType.WOOD:
				b_sys.add_resource(total_yield, 0, 0, 0)
			ResourceDistribution.ResourceType.STONE:
				b_sys.add_resource(0, total_yield, 0, 0)
			ResourceDistribution.ResourceType.IRON:
				b_sys.add_resource(0, 0, total_yield, 0)
			ResourceDistribution.ResourceType.MAGIC_STONE:
				b_sys.add_resource(0, 0, 0, total_yield)

	var eb = get_node_or_null("/root/EventBus")
	if eb and eb.has_signal("resource_gathered"):
		eb.resource_gathered.emit(_get_resource_name(), total_yield, player)

	_spawn_popup(total_yield)

	# Notify MapGenerator of harvest so it won't respawn if chunk unloads
	var map_gen = get_tree().get_first_node_in_group("map_generator") if is_inside_tree() else null
	if map_gen and map_gen.has_method("record_harvest"):
		map_gen.record_harvest(global_position)

	queue_free()

func _spawn_popup(amount: int) -> void:
	if not is_inside_tree():
		return
	var ft = FLOATING_TEXT_SCENE.instantiate()
	var parent_node = get_parent()
	if not parent_node:
		return
	parent_node.add_child(ft)
	ft.global_position = global_position + Vector3(0, 0.6, 0)
	var col: Color = Color(0.3, 1.0, 0.4)
	if resource_type == ResourceDistribution.ResourceType.MAGIC_STONE:
		col = Color(0.4, 0.9, 1.0)
	elif resource_type == ResourceDistribution.ResourceType.IRON:
		col = Color(1.0, 0.7, 0.2)
	elif resource_type == ResourceDistribution.ResourceType.STONE:
		col = Color(0.7, 0.75, 0.8)
	var text_val: String = "+%d %s" % [amount, _get_resource_name()]
	if ft.has_method("setup_text"):
		ft.setup_text(text_val, col)
	else:
		ft.setup(float(amount), false, col)
		var lbl = ft.get_node_or_null("Label3D")
		if lbl:
			lbl.text = text_val
			lbl.modulate = col


func _get_resource_name() -> String:
	match resource_type:
		ResourceDistribution.ResourceType.WOOD:
			return "WOOD"
		ResourceDistribution.ResourceType.STONE:
			return "STONE"
		ResourceDistribution.ResourceType.IRON:
			return "IRON"
		ResourceDistribution.ResourceType.MAGIC_STONE:
			return "MAGIC STONE"
		_:
			return "RESOURCE"

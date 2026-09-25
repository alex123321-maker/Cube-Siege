class_name ResourceTree
extends StaticBody3D

@export var max_health: float = 60.0
@export var wood_yield: int = 4
@export var tree_variation: int = 0

var current_health: float = 60.0
var is_harvested: bool = false
var is_destroyed: bool = false
var foliage_materials: Array[StandardMaterial3D] = []
var canopy_occlusion_area: Area3D = null
var canopy_occlusion_shape: CollisionShape3D = null
var trunk: MeshInstance3D = null
var foliage_meshes: Array[MeshInstance3D] = []
var _tree_bounds: AABB

@onready var hurtbox: Area3D = $Hurtbox
@onready var tree_model: Node3D = $Visuals/TreeModel
@onready var foliage: Node3D = $Visuals/Canopy
@onready var body_collision_shape: CollisionShape3D = $CollisionShape3D
@onready var tree_hurtbox_shape: CollisionShape3D = $Hurtbox/CollisionShape3D
@onready var pickup_prompt: Label3D = $PickupPrompt

const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")
const TREE_VARIANTS: Array[PackedScene] = [
	preload("res://assets/environment/resources/tree_oak/tree_0_standard_oak.glb"),
	preload("res://assets/environment/resources/tree_oak/tree_1_tall_oak.glb"),
	preload("res://assets/environment/resources/tree_oak/tree_2_broad_oak.glb"),
	preload("res://assets/environment/resources/tree_oak/tree_3_young_oak.glb"),
	preload("res://assets/environment/resources/tree_oak/tree_4_shrub_oak.glb")
]

func _ready() -> void:
	_make_collision_shapes_local()
	current_health = max_health
	if pickup_prompt:
		pickup_prompt.visible = false
	if hurtbox:
		hurtbox.damaged.connect(_on_damaged)
	_apply_variation()
	_setup_canopy_occlusion()

func _make_collision_shapes_local() -> void:
	if body_collision_shape and body_collision_shape.shape:
		body_collision_shape.shape = body_collision_shape.shape.duplicate(true)
	if tree_hurtbox_shape and tree_hurtbox_shape.shape:
		tree_hurtbox_shape.shape = tree_hurtbox_shape.shape.duplicate(true)

func _setup_canopy_occlusion() -> void:
	canopy_occlusion_area = Area3D.new()
	canopy_occlusion_area.name = "CanopyOcclusion"
	canopy_occlusion_area.collision_layer = 16
	canopy_occlusion_area.collision_mask = 0
	canopy_occlusion_area.monitoring = false
	canopy_occlusion_area.monitorable = true
	canopy_occlusion_area.add_to_group("resource_nodes")
	canopy_occlusion_shape = CollisionShape3D.new()
	canopy_occlusion_shape.name = "CollisionShape3D"
	canopy_occlusion_shape.shape = BoxShape3D.new()
	canopy_occlusion_area.add_child(canopy_occlusion_shape)
	add_child(canopy_occlusion_area)
	_update_canopy_occlusion()

func _update_canopy_occlusion() -> void:
	if not canopy_occlusion_area or not canopy_occlusion_shape or foliage_meshes.is_empty():
		return
	var bounds: AABB = _get_mesh_bounds(foliage_meshes, foliage)
	canopy_occlusion_area.position = foliage.position
	canopy_occlusion_shape.position = bounds.position + bounds.size * 0.5
	var box: BoxShape3D = canopy_occlusion_shape.shape as BoxShape3D
	box.size = bounds.size

func configure_tree(p_variation: int, p_yield: int = 4) -> void:
	tree_variation = p_variation
	wood_yield = p_yield
	if is_inside_tree():
		_apply_variation()
		_update_canopy_occlusion()

func _apply_variation() -> void:
	for child in tree_model.get_children():
		child.free()
	for child in foliage.get_children():
		child.free()
	foliage_meshes.clear()
	foliage_materials.clear()
	trunk = null

	var variant_index: int = clampi(tree_variation, 0, TREE_VARIANTS.size() - 1)
	var asset_root: Node3D = TREE_VARIANTS[variant_index].instantiate() as Node3D
	asset_root.name = "TreeAsset"
	tree_model.add_child(asset_root)
	var meshes: Array[Node] = asset_root.find_children("*", "MeshInstance3D", true, false)
	var all_meshes: Array[MeshInstance3D] = []
	for node in meshes:
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if not mesh_instance:
			continue
		all_meshes.append(mesh_instance)
		if mesh_instance.name.ends_with("_W"):
			trunk = mesh_instance
		elif mesh_instance.name.ends_with("_D") or mesh_instance.name.ends_with("_L"):
			mesh_instance.reparent(foliage, true)
			foliage_meshes.append(mesh_instance)
			_setup_foliage_material(mesh_instance)

	_tree_bounds = _get_mesh_bounds(all_meshes, tree_model)
	_fit_tree_hurtbox(_tree_bounds)
	_fit_tree_solid_collision()
	_update_canopy_occlusion()
	_update_hurtbox_flash_target()

func _setup_foliage_material(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance.mesh == null:
		return
	for surface_index in range(mesh_instance.mesh.get_surface_count()):
		var source_material: Material = mesh_instance.get_active_material(surface_index)
		if source_material is StandardMaterial3D:
			var material: StandardMaterial3D = source_material.duplicate() as StandardMaterial3D
			mesh_instance.set_surface_override_material(surface_index, material)
			foliage_materials.append(material)

func _fit_tree_hurtbox(bounds: AABB) -> void:
	var box: BoxShape3D = tree_hurtbox_shape.shape as BoxShape3D
	box.size = bounds.size
	tree_hurtbox_shape.position = bounds.position + bounds.size * 0.5

func _fit_tree_solid_collision() -> void:
	if not trunk or not body_collision_shape or not body_collision_shape.shape is BoxShape3D:
		return
	var trunk_bounds: AABB = _get_mesh_bounds([trunk], self)
	var box: BoxShape3D = body_collision_shape.shape as BoxShape3D
	box.size = trunk_bounds.size
	body_collision_shape.position = trunk_bounds.position + trunk_bounds.size * 0.5

func _update_hurtbox_flash_target() -> void:
	var hurtbox_controller: HurtboxArea = hurtbox as HurtboxArea
	if hurtbox_controller:
		if not foliage_meshes.is_empty():
			hurtbox_controller.mesh_to_flash = foliage_meshes[0]
		elif trunk:
			hurtbox_controller.mesh_to_flash = trunk

func _get_mesh_bounds(meshes: Array[MeshInstance3D], relative_to: Node3D) -> AABB:
	var has_bounds: bool = false
	var result: AABB = AABB()
	for mesh_instance in meshes:
		if not is_instance_valid(mesh_instance) or not mesh_instance.mesh:
			continue
		var local_bounds: AABB = mesh_instance.mesh.get_aabb()
		var mesh_transform: Transform3D = relative_to.global_transform.affine_inverse() * mesh_instance.global_transform
		for corner_index in range(8):
			var point: Vector3 = mesh_transform * local_bounds.get_endpoint(corner_index)
			if not has_bounds:
				result = AABB(point, Vector3.ZERO)
				has_bounds = true
			else:
				result = result.expand(point)
	return result

func set_transparency(alpha: float) -> void:
	if alpha > 0.05:
		for material in foliage_materials:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.albedo_color.a = 1.0 - alpha
	else:
		for material in foliage_materials:
			material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			material.albedo_color.a = 1.0

func _on_damaged(amount: float, _knockback: Vector3, _type: String, _attacker: Node) -> void:
	if is_destroyed:
		return

	current_health -= amount
	spawn_damage_text(amount)

	# Shake animation
	var tween: Tween = create_tween()
	tween.tween_property($Visuals, "rotation:z", 0.08, 0.05)
	tween.tween_property($Visuals, "rotation:z", -0.08, 0.05)
	tween.tween_property($Visuals, "rotation:z", 0.0, 0.05)

	if current_health <= 0.0:
		fell_tree()

func fell_tree() -> void:
	is_destroyed = true
	# Shift to collision_layer 8 (interactable items). The player (mask 1) no longer collides
	# with the stump, while InteractionSensor (mask 9 = 1 | 8) continues to detect it.
	collision_layer = 8
	collision_mask = 0
	if has_node("CollisionShape3D"):
		$CollisionShape3D.set_deferred("disabled", false)
	if hurtbox:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)
	if canopy_occlusion_area:
		canopy_occlusion_area.set_deferred("monitoring", false)
		canopy_occlusion_area.set_deferred("monitorable", false)

	# Hide the canopy while leaving the bark mesh and harvest prompt available.
	var tween: Tween = create_tween()
	tween.tween_property(foliage, "scale", Vector3.ZERO, 0.2)
	tween.chain().tween_callback(func(): foliage.visible = false)

	if pickup_prompt:
		pickup_prompt.visible = false
		pickup_prompt.text = ""

func is_ready_for_pickup() -> bool:
	return is_destroyed and not is_harvested

func is_interactable() -> bool:
	return is_ready_for_pickup()

func interact(player: Node, _is_shift: bool = false) -> void:
	harvest(player)

func set_focused(focused: bool) -> void:
	if not is_ready_for_pickup() or not pickup_prompt:
		return
	pickup_prompt.visible = focused
	if focused:
		pickup_prompt.text = "[E] HOLD (1.0s)\n(+%d WOOD)" % wood_yield
		pickup_prompt.modulate = Color(1.0, 0.9, 0.2)
		if trunk:
			trunk.scale = Vector3(1.1, 1.0, 1.1)
	else:
		if trunk:
			trunk.scale = Vector3.ONE

func set_interaction_progress(progress: float) -> void:
	if not is_ready_for_pickup() or not pickup_prompt:
		return
	var bars: int = int(progress * 10.0)
	var bar_str: String = ""
	for i in range(10):
		bar_str += "█" if i < bars else "░"
	pickup_prompt.text = "[E] [%s] %d%%\n(+%d WOOD)" % [bar_str, int(progress * 100), wood_yield]
	pickup_prompt.modulate = Color(0.2, 1.0, 0.4)

func harvest(player: Node) -> void:
	if is_harvested or not is_destroyed:
		return

	is_harvested = true
	if player and "interaction" in player and player.interaction:
		player.interaction.remove_candidate(self)
	if pickup_prompt:
		pickup_prompt.visible = false

	var mult: int = 1
	if player and player.get("resource_multiplier") != null:
		mult = player.resource_multiplier
	var total_yield: int = wood_yield * mult

	# Add resources to inventory
	var building_system: BuildingSystem = null
	if player and "building_system" in player and player.building_system:
		building_system = player.building_system as BuildingSystem
	if building_system:
		building_system.add_resource(total_yield, 0, 0)
	elif player:
		push_warning("ResourceTree: cannot add wood because Player.building_system is not wired.")

	spawn_damage_text(0, "+%d WOOD" % total_yield, Color.GREEN)

	var map_gen = get_tree().get_first_node_in_group("map_generator") if is_inside_tree() else null
	if map_gen and map_gen.has_method("record_harvest"):
		map_gen.record_harvest(global_position)

	var tween: Tween = create_tween()
	tween.tween_property(trunk, "scale", Vector3.ZERO, 0.2)
	tween.chain().tween_callback(queue_free)

func spawn_damage_text(amount: float, custom_text: String = "", custom_color: Color = Color.WHITE) -> void:
	var popup: Node3D = FLOATING_TEXT_SCENE.instantiate()
	get_parent().add_child(popup)
	popup.global_position = global_position + Vector3(0, 2.2, 0)
	if custom_text != "":
		popup.get_node("Label3D").text = custom_text
		popup.get_node("Label3D").modulate = custom_color
	else:
		popup.setup(amount, false, Color(0.9, 0.8, 0.4))

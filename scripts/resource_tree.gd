class_name ResourceTree
extends StaticBody3D

@export var max_health: float = 60.0
@export var wood_yield: int = 4
@export var tree_variation: int = 0

var current_health: float = 60.0
var is_harvested: bool = false
var is_destroyed: bool = false
var foliage_material: StandardMaterial3D = null
var canopy_occlusion_area: Area3D = null

@onready var hurtbox: Area3D = $Hurtbox
@onready var foliage: MeshInstance3D = $Visuals/Foliage
@onready var trunk: MeshInstance3D = $Visuals/Trunk
@onready var pickup_prompt: Label3D = $PickupPrompt

const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

func _ready() -> void:
	current_health = max_health
	if pickup_prompt:
		pickup_prompt.visible = false
	if hurtbox:
		hurtbox.damaged.connect(_on_damaged)
	_setup_foliage_material()
	_setup_canopy_occlusion()
	_apply_variation()

func _setup_canopy_occlusion() -> void:
	canopy_occlusion_area = Area3D.new()
	canopy_occlusion_area.name = "CanopyOcclusion"
	canopy_occlusion_area.collision_layer = 16
	canopy_occlusion_area.collision_mask = 0
	canopy_occlusion_area.monitoring = false
	canopy_occlusion_area.monitorable = true
	canopy_occlusion_area.add_to_group("resource_nodes")

	var col_shape: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(2.4, 2.4, 2.4)
	col_shape.shape = box
	canopy_occlusion_area.add_child(col_shape)
	add_child(canopy_occlusion_area)
	_update_canopy_occlusion()

func _update_canopy_occlusion() -> void:
	if not canopy_occlusion_area or not foliage:
		return
	canopy_occlusion_area.position = foliage.position
	canopy_occlusion_area.scale = foliage.scale


func configure_tree(p_variation: int, p_yield: int = 4) -> void:
	tree_variation = p_variation
	wood_yield = p_yield
	if is_inside_tree():
		_apply_variation()

func _setup_foliage_material() -> void:
	if foliage and foliage.mesh and foliage.mesh.material:
		foliage_material = foliage.mesh.material.duplicate() as StandardMaterial3D
		foliage.material_override = foliage_material
	elif foliage:
		foliage_material = StandardMaterial3D.new()
		foliage_material.albedo_color = Color(0.18, 0.55, 0.22, 1.0)
		foliage_material.roughness = 0.8
		foliage.material_override = foliage_material

func _apply_variation() -> void:
	if not foliage or not trunk:
		return

	match tree_variation:
		0: # Standard Oak
			trunk.scale = Vector3(1.0, 1.0, 1.0)
			foliage.scale = Vector3(1.0, 1.0, 1.0)
			foliage.position = Vector3(0, 2.6, 0)
		1: # Tall Oak
			trunk.scale = Vector3(0.85, 1.35, 0.85)
			foliage.scale = Vector3(0.85, 1.2, 0.85)
			foliage.position = Vector3(0, 3.2, 0)
		2: # Broad Oak
			trunk.scale = Vector3(1.3, 0.9, 1.3)
			foliage.scale = Vector3(1.35, 0.85, 1.35)
			foliage.position = Vector3(0, 2.3, 0)
		3: # Young Small Oak
			trunk.scale = Vector3(0.65, 0.65, 0.65)
			foliage.scale = Vector3(0.65, 0.65, 0.65)
			foliage.position = Vector3(0, 1.7, 0)
		4: # Shrub / Bush Oak
			trunk.scale = Vector3(0.5, 0.4, 0.5)
			foliage.scale = Vector3(0.8, 0.6, 0.8)
			foliage.position = Vector3(0, 1.1, 0)

	_update_canopy_occlusion()

func set_transparency(alpha: float) -> void:
	if not foliage_material:
		_setup_foliage_material()
	if foliage_material:
		if alpha > 0.05:
			foliage_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			foliage_material.albedo_color.a = 1.0 - alpha
		else:
			foliage_material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
			foliage_material.albedo_color.a = 1.0


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
	$CollisionShape3D.set_deferred("disabled", true)
	if hurtbox:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)
	if canopy_occlusion_area:
		canopy_occlusion_area.set_deferred("monitoring", false)
		canopy_occlusion_area.set_deferred("monitorable", false)

	# Hide top foliage, keep small stump + pickup prompt
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
			trunk.scale = Vector3(1.0, 1.0, 1.0)

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

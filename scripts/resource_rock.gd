class_name ResourceRock
extends StaticBody3D

enum RockType { STONE, IRON }

@export var rock_type: RockType = RockType.STONE
@export var max_health: float = 80.0
@export var resource_yield: int = 4
@export var deposit_tier: int = 1 # 0: small, 1: medium, 2: large
@export var variation_index: int = 0

var current_health: float = 80.0
var is_destroyed: bool = false
var is_harvested: bool = false
var degradation_stage: int = 2 # 2: full, 1: cracked, 0: heavily chipped
var base_scale: Vector3 = Vector3.ONE
var broken_scale: Vector3 = Vector3.ONE

@onready var hurtbox: Area3D = get_node_or_null("Hurtbox")
@onready var rock_mesh: Node3D = get_node_or_null("Visuals/RockMesh")
@onready var prompt_label: Label3D = get_node_or_null("PromptLabel")
@onready var body_collision_shape: CollisionShape3D = get_node_or_null("CollisionShape3D")
@onready var hurtbox_shape: CollisionShape3D = get_node_or_null("Hurtbox/CollisionShape3D")

var rock_asset: Node3D = null
var rock_mesh_instances: Array[MeshInstance3D] = []
var rock_bounds: AABB

const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")
const ROCK_VARIANTS: Array[PackedScene] = [
	preload("res://assets/environment/resources/rock_stage1/rock_stage1_var_0.glb"),
	preload("res://assets/environment/resources/rock_stage1/rock_stage1_var_1.glb"),
	preload("res://assets/environment/resources/rock_stage1/rock_stage1_var_2.glb"),
	preload("res://assets/environment/resources/rock_stage1/rock_stage1_var_3.glb"),
	preload("res://assets/environment/resources/rock_stage1/rock_stage1_var_4.glb"),
	preload("res://assets/environment/resources/rock_stage1/rock_stage1_var_5.glb")
]

static func visual_variant_for_cell(cell_seed: int) -> int:
	return posmod(cell_seed, ROCK_VARIANTS.size())

func _ready() -> void:
	_make_collision_shapes_local()
	add_to_group("interactables")
	add_to_group("resource_nodes")

	if rock_type == RockType.IRON:
		max_health = 120.0
		if resource_yield == 4:
			resource_yield = 2
	current_health = max_health

	if prompt_label:
		prompt_label.visible = false
	if hurtbox and hurtbox.has_signal("damaged"):
		hurtbox.damaged.connect(_on_damaged)

	_apply_tier_and_variation()

func _make_collision_shapes_local() -> void:
	if body_collision_shape and body_collision_shape.shape:
		body_collision_shape.shape = body_collision_shape.shape.duplicate(true)
	if hurtbox_shape and hurtbox_shape.shape:
		hurtbox_shape.shape = hurtbox_shape.shape.duplicate(true)

func configure_rock(p_type: RockType, p_yield: int, p_tier: int, p_var_idx: int) -> void:
	rock_type = p_type
	resource_yield = p_yield
	deposit_tier = p_tier
	variation_index = p_var_idx
	if rock_type == RockType.IRON:
		max_health = 80.0 + float(p_tier * 35.0)
	else:
		max_health = 60.0 + float(p_tier * 25.0)
	current_health = max_health
	if is_inside_tree():
		_apply_tier_and_variation()

func _apply_tier_and_variation() -> void:
	if not rock_mesh:
		return
	for child in rock_mesh.get_children():
		child.free()
	rock_mesh_instances.clear()

	# Amount-driven visual scale based on tier/yield
	match deposit_tier:
		0: # Small deposit
			base_scale = Vector3(0.85, 0.75, 0.85)
		1: # Medium deposit
			base_scale = Vector3(1.15, 1.05, 1.15)
		2: # Large deposit
			base_scale = Vector3(1.5, 1.35, 1.5)
		_:
			base_scale = Vector3(1.0, 1.0, 1.0)

	# Select a production Stage 1 mesh by variation index; keep each authored silhouette intact.
	var variant_index: int = posmod(variation_index, ROCK_VARIANTS.size())
	rock_asset = ROCK_VARIANTS[variant_index].instantiate() as Node3D
	rock_asset.name = "Stage1RockVariant%d" % variant_index
	rock_mesh.add_child(rock_asset)
	for node in rock_asset.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance:
			rock_mesh_instances.append(mesh_instance)
	if rock_type == RockType.IRON:
		_apply_iron_material_tint()
	rock_bounds = _get_mesh_bounds(rock_mesh_instances, rock_asset)
	rock_mesh.scale = base_scale
	_fit_collision_shapes(rock_bounds)
	_update_prompt_position(rock_bounds)
	_update_hurtbox_flash_target()

func _apply_iron_material_tint() -> void:
	for mesh_instance in rock_mesh_instances:
		if not mesh_instance.mesh:
			continue
		for surface_index in range(mesh_instance.mesh.get_surface_count()):
			var source_material: Material = mesh_instance.get_active_material(surface_index)
			if source_material is StandardMaterial3D:
				var material: StandardMaterial3D = source_material.duplicate() as StandardMaterial3D
				material.albedo_color = Color(
					material.albedo_color.r * 1.12,
					material.albedo_color.g * 0.82,
					material.albedo_color.b * 0.64,
					material.albedo_color.a
				)
				material.metallic = maxf(material.metallic, 0.35)
				mesh_instance.set_surface_override_material(surface_index, material)

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

func _fit_collision_shapes(bounds: AABB) -> void:
	var scaled_bounds: AABB = _scale_aabb(bounds, base_scale)
	if body_collision_shape and body_collision_shape.shape is BoxShape3D:
		(body_collision_shape.shape as BoxShape3D).size = scaled_bounds.size
		body_collision_shape.position = scaled_bounds.position + scaled_bounds.size * 0.5
	if hurtbox_shape and hurtbox_shape.shape is BoxShape3D:
		(hurtbox_shape.shape as BoxShape3D).size = scaled_bounds.size
		hurtbox_shape.position = scaled_bounds.position + scaled_bounds.size * 0.5

func _scale_aabb(bounds: AABB, scale: Vector3) -> AABB:
	var scaled_min: Vector3 = bounds.position * scale
	var scaled_max: Vector3 = bounds.end * scale
	return AABB(scaled_min, scaled_max - scaled_min)

func _update_prompt_position(bounds: AABB) -> void:
	if prompt_label:
		prompt_label.position.y = _scale_aabb(bounds, base_scale).end.y + 0.3

func _update_hurtbox_flash_target() -> void:
	var hurtbox_controller: HurtboxArea = hurtbox as HurtboxArea
	if hurtbox_controller and not rock_mesh_instances.is_empty():
		hurtbox_controller.mesh_to_flash = rock_mesh_instances[0]

func _on_damaged(amount: float, _knockback: Vector3, _type: String, _attacker: Node) -> void:
	if is_destroyed:
		return

	current_health -= amount
	spawn_damage_text(amount)

	# Shake visual
	var tween: Tween = create_tween()
	tween.tween_property($Visuals, "rotation:z", 0.07, 0.04)
	tween.tween_property($Visuals, "rotation:z", -0.07, 0.04)
	tween.tween_property($Visuals, "rotation:z", 0.0, 0.04)

	# Visual stages of breakdown
	var hp_ratio: float = current_health / max_health
	if hp_ratio <= 0.33 and degradation_stage > 0:
		degradation_stage = 0
		_trigger_breakdown_step(0.60)
	elif hp_ratio <= 0.66 and degradation_stage > 1:
		degradation_stage = 1
		_trigger_breakdown_step(0.82)

	if current_health <= 0.0:
		break_rock()

func _trigger_breakdown_step(scale_factor: float) -> void:
	if rock_mesh:
		var target_s: Vector3 = base_scale * scale_factor
		var t: Tween = create_tween()
		t.tween_property(rock_mesh, "scale", target_s, 0.12).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

	var vfx = get_node_or_null("/root/VFXManager")
	if vfx:
		var spark_col: Color = Color(0.8, 0.5, 0.2) if rock_type == RockType.IRON else Color(0.7, 0.7, 0.75)
		vfx.spawn_sparks(global_position + Vector3(0, 0.5, 0), Vector3.UP, spark_col, 8, 3.5)

func break_rock() -> void:
	is_destroyed = true
	# Shift to collision_layer 8 (interactable items). The player (mask 1) no longer collides
	# with the broken rock, while InteractionSensor (mask 9 = 1 | 8) continues to detect it.
	collision_layer = 8
	collision_mask = 0
	if has_node("CollisionShape3D"):
		$CollisionShape3D.set_deferred("disabled", false)
	if hurtbox:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)

	if is_inside_tree() and rock_mesh:
		broken_scale = Vector3(base_scale.x * 1.2, 0.22, base_scale.z * 1.2)
		var tween: Tween = create_tween()
		tween.tween_property(rock_mesh, "scale", broken_scale, 0.15)
	else:
		broken_scale = Vector3(base_scale.x * 1.2, 0.22, base_scale.z * 1.2)

	if prompt_label:
		prompt_label.visible = false
		prompt_label.text = ""

func is_ready_for_pickup() -> bool:
	return is_destroyed and not is_harvested

func is_interactable() -> bool:
	return is_ready_for_pickup()

func interact(player: Node, _is_shift: bool = false) -> void:
	harvest(player)

func set_focused(focused: bool) -> void:
	if not is_ready_for_pickup() or not prompt_label:
		return
	prompt_label.visible = focused
	var res_name: String = "STONE" if rock_type == RockType.STONE else "IRON"
	if focused:
		prompt_label.text = "[E] HOLD (1.0s)\n(+%d %s)" % [resource_yield, res_name]
		prompt_label.modulate = Color(1.0, 0.9, 0.2)
		if rock_mesh:
			rock_mesh.scale = _pickup_base_scale() * 1.08
	else:
		if rock_mesh:
			rock_mesh.scale = _pickup_base_scale()

func _pickup_base_scale() -> Vector3:
	return broken_scale if is_destroyed else base_scale

func set_interaction_progress(progress: float) -> void:
	if not is_ready_for_pickup() or not prompt_label:
		return
	var res_name: String = "STONE" if rock_type == RockType.STONE else "IRON"
	var bars: int = int(progress * 10.0)
	var bar_str: String = ""
	for i in range(10):
		bar_str += "█" if i < bars else "░"
	prompt_label.text = "[E] [%s] %d%%\n(+%d %s)" % [bar_str, int(progress * 100), resource_yield, res_name]
	prompt_label.modulate = Color(0.2, 1.0, 0.4)

func harvest(player: Node) -> void:
	if is_harvested or not is_destroyed:
		return

	is_harvested = true
	if player and "interaction" in player and player.interaction:
		player.interaction.remove_candidate(self)
	if prompt_label:
		prompt_label.visible = false

	var mult: int = 1
	if player and player.get("resource_multiplier") != null:
		mult = player.resource_multiplier
	var total_yield: int = resource_yield * mult

	var building_system: BuildingSystem = null
	if player and "building_system" in player and player.building_system:
		building_system = player.building_system as BuildingSystem
	if building_system:
		if rock_type == RockType.STONE:
			building_system.add_resource(0, total_yield, 0)
			spawn_damage_text(0, "+%d STONE" % total_yield, Color(0.7, 0.75, 0.8))
		else:
			building_system.add_resource(0, 0, total_yield)
			spawn_damage_text(0, "+%d IRON" % total_yield, Color(1.0, 0.7, 0.3))
	elif player:
		push_warning("ResourceRock: cannot add resources because Player.building_system is not wired.")

	var map_gen = get_tree().get_first_node_in_group("map_generator") if is_inside_tree() else null
	if map_gen and map_gen.has_method("record_harvest"):
		map_gen.record_harvest(global_position)

	if is_inside_tree() and rock_mesh:
		var tween: Tween = create_tween()
		tween.tween_property(rock_mesh, "scale", Vector3.ZERO, 0.2)
		tween.chain().tween_callback(queue_free)
	else:
		queue_free()

func spawn_damage_text(amount: float, custom_text: String = "", custom_color: Color = Color.WHITE) -> void:
	var popup: Node3D = FLOATING_TEXT_SCENE.instantiate()
	get_parent().add_child(popup)
	popup.global_position = global_position + Vector3(0, 1.6, 0)
	if custom_text != "":
		popup.get_node("Label3D").text = custom_text
		popup.get_node("Label3D").modulate = custom_color
	else:
		popup.setup(amount, false, Color(0.8, 0.8, 0.85))

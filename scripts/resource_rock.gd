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

@onready var hurtbox: Area3D = $Hurtbox
@onready var rock_mesh: MeshInstance3D = $Visuals/RockMesh
@onready var prompt_label: Label3D = $PromptLabel

const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

func _ready() -> void:
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
		hurtbox.connect("damaged", Callable(self, "_on_damaged"))

	_apply_tier_and_variation()

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

	# Silhouette variations per tier
	match variation_index % 4:
		0:
			rock_mesh.rotation_degrees = Vector3(0, 0, 0)
		1:
			base_scale = Vector3(base_scale.x * 1.2, base_scale.y * 0.9, base_scale.z * 0.85)
			rock_mesh.rotation_degrees = Vector3(5, 35, -4)
		2:
			base_scale = Vector3(base_scale.x * 0.9, base_scale.y * 1.15, base_scale.z * 1.1)
			rock_mesh.rotation_degrees = Vector3(-6, 75, 8)
		3:
			base_scale = Vector3(base_scale.x * 1.1, base_scale.y * 1.0, base_scale.z * 1.15)
			rock_mesh.rotation_degrees = Vector3(4, 130, -5)

	rock_mesh.scale = base_scale

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
	$CollisionShape3D.set_deferred("disabled", true)
	if hurtbox:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)

	var tween: Tween = create_tween()
	tween.tween_property(rock_mesh, "scale", Vector3(base_scale.x * 1.2, 0.22, base_scale.z * 1.2), 0.15)

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
			rock_mesh.scale = Vector3(1.3, 0.35, 1.3)
	else:
		if rock_mesh:
			rock_mesh.scale = Vector3(1.2, 0.25, 1.2)

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

	var tween: Tween = create_tween()
	tween.tween_property(rock_mesh, "scale", Vector3.ZERO, 0.2)
	tween.chain().tween_callback(queue_free)

func spawn_damage_text(amount: float, custom_text: String = "", custom_color: Color = Color.WHITE) -> void:
	var popup: Node3D = FLOATING_TEXT_SCENE.instantiate()
	get_parent().add_child(popup)
	popup.global_position = global_position + Vector3(0, 1.6, 0)
	if custom_text != "":
		popup.get_node("Label3D").text = custom_text
		popup.get_node("Label3D").modulate = custom_color
	else:
		popup.setup(amount, false, Color(0.8, 0.8, 0.85))

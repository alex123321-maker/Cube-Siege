class_name ResourceRock
extends StaticBody3D

enum RockType { STONE, IRON }

@export var rock_type: RockType = RockType.STONE
@export var max_health: float = 80.0
@export var resource_yield: int = 4

var current_health: float = 80.0
var is_destroyed: bool = false
var is_harvested: bool = false

@onready var hurtbox: Area3D = $Hurtbox
@onready var rock_mesh: MeshInstance3D = $Visuals/RockMesh
@onready var prompt_label: Label3D = $PromptLabel

const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("resource_nodes")
	current_health = max_health

	if rock_type == RockType.IRON:
		max_health = 120.0
		current_health = 120.0
		resource_yield = 2

	if prompt_label:
		prompt_label.visible = false
	if hurtbox and hurtbox.has_signal("damaged"):
		hurtbox.connect("damaged", Callable(self, "_on_damaged"))

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

	if current_health <= 0.0:
		break_rock()

func break_rock() -> void:
	is_destroyed = true
	$CollisionShape3D.set_deferred("disabled", true)
	if hurtbox:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)

	var tween: Tween = create_tween()
	tween.tween_property(rock_mesh, "scale", Vector3(1.2, 0.25, 1.2), 0.15)

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

	var building_system: Node = null
	if player and "building_system" in player and player.building_system:
		building_system = player.building_system
	elif get_tree() and get_tree().root:
		building_system = get_tree().root.find_child("BuildingSystem", true, false)
	if building_system:
		if rock_type == RockType.STONE:
			building_system.add_resource(0, total_yield, 0)
			spawn_damage_text(0, "+%d STONE" % total_yield, Color(0.7, 0.75, 0.8))
		else:
			building_system.add_resource(0, 0, total_yield)
			spawn_damage_text(0, "+%d IRON" % total_yield, Color(1.0, 0.7, 0.3))

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

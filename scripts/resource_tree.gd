class_name ResourceTree
extends StaticBody3D

@export var max_health: float = 60.0
@export var wood_yield: int = 4

var current_health: float = 60.0
var is_harvested: bool = false
var is_destroyed: bool = false

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
	var building_system: Node = null
	if player and "building_system" in player and player.building_system:
		building_system = player.building_system
	elif get_tree() and get_tree().root:
		building_system = get_tree().root.find_child("BuildingSystem", true, false)
	if building_system:
		building_system.add_resource(total_yield, 0, 0)

	spawn_damage_text(0, "+%d WOOD" % total_yield, Color.GREEN)

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

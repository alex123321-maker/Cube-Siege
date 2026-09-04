extends StaticBody3D
class_name BuildingBase

signal building_destroyed(building: Node)
signal health_changed(current: float, max_hp: float)

@export var building_name: String = "Building"
@export var max_health: float = 250.0
@export var wood_cost: int = 4
@export var stone_cost: int = 0
@export var iron_cost: int = 0

var current_health: float = 250.0
var grid_coord: Vector2i = Vector2i.ZERO

@onready var hurtbox: Area3D = get_node_or_null("Hurtbox") as Area3D
@onready var mesh_instance: MeshInstance3D = get_node_or_null("MeshInstance3D") as MeshInstance3D
@onready var hp_label: Label3D = get_node_or_null("HPLabel") as Label3D

const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

func _enter_tree() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg:
		reg.register_building(self)

func _exit_tree() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg:
		reg.unregister_building(self)

func _ready() -> void:
	if not mesh_instance:
		mesh_instance = find_child("*Mesh*", true, false) as MeshInstance3D
	add_to_group("buildings")
	add_to_group("interactables")
	current_health = max_health
	update_hp_label()
	if hurtbox and hurtbox.has_signal("damaged"):
		hurtbox.connect("damaged", Callable(self, "_on_damaged"))

func is_ready_for_pickup() -> bool:
	return true

func is_interactable() -> bool:
	return true

func interact(player: Node, is_shift: bool = false) -> void:
	if is_shift:
		demolish(player)
	else:
		interact_repair(player)

func interact_repair(player: Node) -> bool:
	if current_health >= max_health:
		return false
	var bs: BuildingSystem = null
	if player and "building_system" in player and player.building_system:
		bs = player.building_system as BuildingSystem
	if bs:
		if bs.spend_resources(1, 0, 0):
			return repair(100.0)
		elif player and player.has_method("spawn_popup_text"):
			player.spawn_popup_text("NEED 1 WOOD!", Color.ORANGE)
	else:
		push_warning("BuildingBase: cannot repair because Player.building_system is not wired.")
	return false

func set_focused(focused: bool) -> void:
	if not hp_label:
		return
	if focused:
		hp_label.visible = true
		if current_health < max_health:
			hp_label.text = "%d/%d HP\n[E] REPAIR (1 Wood)\n[Shift+E] DEMOLISH" % [int(current_health), int(max_health)]
		else:
			hp_label.text = "%d/%d HP\n[Shift+E] DEMOLISH" % [int(current_health), int(max_health)]
		hp_label.modulate = Color(1.0, 0.9, 0.2)
	else:
		update_hp_label()
		hp_label.modulate = Color.WHITE

func set_interaction_progress(progress: float) -> void:
	if not hp_label:
		return
	var bars: int = int(progress * 10.0)
	var bar_str: String = ""
	for i in range(10):
		bar_str += "█" if i < bars else "░"
	var is_shift: bool = Input.is_key_pressed(KEY_SHIFT)
	var action: String = "DEMOLISHING" if is_shift else "REPAIRING"
	hp_label.text = "[%s] %d%%\n%s..." % [bar_str, int(progress * 100), action]
	hp_label.modulate = Color(0.2, 1.0, 0.4)

func demolish(player: Node = null) -> void:
	var bs: BuildingSystem = null
	if player and "building_system" in player and player.building_system:
		bs = player.building_system as BuildingSystem
	if bs:
		var ref_w: int = int(wood_cost * 0.5)
		var ref_s: int = int(stone_cost * 0.5)
		var ref_i: int = int(iron_cost * 0.5)
		bs.add_resource(ref_w, ref_s, ref_i)
		spawn_damage_text(0, "+REFUND (%dW %dS %dI)" % [ref_w, ref_s, ref_i], Color.GOLD)
	elif player:
		push_warning("BuildingBase: cannot refund resources because Player.building_system is not wired.")

	destroy_building()

func _on_damaged(amount: float, _knockback: Vector3, _type: String, attacker: Node) -> void:
	# Buildings can only be damaged by enemies, NEVER by the player!
	if attacker and (attacker.is_in_group("player") or attacker.name == "Player"):
		return

	current_health -= amount
	update_hp_label()
	spawn_damage_text(amount)

	# Shake visual
	var shake_node: Node3D = mesh_instance if mesh_instance else self
	var tween: Tween = create_tween()
	tween.tween_property(shake_node, "rotation:z", 0.06, 0.04)
	tween.tween_property(shake_node, "rotation:z", -0.06, 0.04)
	tween.tween_property(shake_node, "rotation:z", 0.0, 0.04)

	if current_health <= 0.0:
		destroy_building()

func repair(amount: float) -> bool:
	if current_health >= max_health:
		return false
	current_health = min(max_health, current_health + amount)
	update_hp_label()
	spawn_damage_text(0, "+%d HP" % int(amount), Color.GREEN)
	return true

func update_hp_label() -> void:
	if hp_label:
		if current_health < max_health:
			hp_label.visible = true
			hp_label.text = "%d/%d" % [max(0, int(current_health)), int(max_health)]
		else:
			hp_label.visible = false

func spawn_damage_text(amount: float, custom_text: String = "", custom_color: Color = Color.WHITE) -> void:
	var popup: Node3D = FLOATING_TEXT_SCENE.instantiate()
	get_parent().add_child(popup)
	popup.global_position = global_position + Vector3(0, 1.8, 0)
	if custom_text != "":
		popup.get_node("Label3D").text = custom_text
		popup.get_node("Label3D").modulate = custom_color
	else:
		popup.setup(amount, false, Color(0.95, 0.7, 0.2))

func destroy_building() -> void:
	emit_signal("building_destroyed", self)
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.15)
	tween.chain().tween_callback(queue_free)

func set_transparency(alpha_trans: float) -> void:
	for child in find_children("*", "MeshInstance3D", true, false):
		if child is MeshInstance3D:
			(child as MeshInstance3D).transparency = alpha_trans
	if has_node("MeshInstance3D"):
		var m: MeshInstance3D = get_node("MeshInstance3D") as MeshInstance3D
		if m:
			m.transparency = alpha_trans

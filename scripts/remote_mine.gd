extends Node3D

@export var blast_damage: float = 250.0
@export var blast_radius: float = 4.5

const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

@onready var light_mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	add_to_group("remote_mines")
	# Gentle blink tween
	var tween: Tween = create_tween().set_loops()
	tween.tween_property(light_mesh, "scale", Vector3(1.15, 1.15, 1.15), 0.3)
	tween.tween_property(light_mesh, "scale", Vector3(1.0, 1.0, 1.0), 0.3)

func detonate(attacker: Node = null) -> void:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e and is_instance_valid(e) and e is Node3D:
			var dist: float = global_position.distance_to((e as Node3D).global_position)
			if dist <= blast_radius:
				var hurt = (e as Node).find_child("Hurtbox", true, false)
				var dir: Vector3 = ((e as Node3D).global_position - global_position).normalized()
				if hurt and hurt.has_method("take_damage"):
					hurt.take_damage(blast_damage, dir * 8.0, "explosion", attacker)
				elif e.has_method("take_damage"):
					e.take_damage(blast_damage)

	var popup: Node3D = FLOATING_TEXT_SCENE.instantiate()
	get_parent().add_child(popup)
	popup.global_position = global_position + Vector3(0, 1.5, 0)
	if popup.has_node("Label3D"):
		popup.get_node("Label3D").text = "BOOM! (250 DMG)"
		popup.get_node("Label3D").modulate = Color.ORANGE_RED

	queue_free()

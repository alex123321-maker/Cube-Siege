extends Node3D

@export var blast_damage: float = 250.0
@export var blast_radius: float = 4.5

const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

@onready var beacon: Node3D = find_child("beacon_light", true, false)

func _ready() -> void:
	add_to_group("remote_mines")
	# Plant dust & sound click
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx:
		vfx.spawn_sparks(global_position + Vector3(0, 0.1, 0), Vector3.UP, Color(0.9, 0.4, 0.2), 6, 2.5)

	# Gentle beacon blink
	if beacon:
		var tween: Tween = create_tween().set_loops()
		tween.tween_property(beacon, "scale", Vector3(1.25, 1.25, 1.25), 0.35)
		tween.tween_property(beacon, "scale", Vector3(1.0, 1.0, 1.0), 0.35)

func detonate(attacker: Node = null) -> void:
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx:
		vfx.spawn_mine_explosion(global_position, blast_radius)

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

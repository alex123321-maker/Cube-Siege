extends CharacterBody3D

@export var max_health: float = 250.0
var current_health: float = 250.0
var lifetime: float = 3.5
var aggro_pulse_timer: float = 0.0

@onready var hurtbox: Area3D = $Hurtbox
@onready var hp_label: Label3D = $HPLabel

func _ready() -> void:
	add_to_group("decoy")
	current_health = max_health
	if hurtbox and hurtbox.has_signal("damaged"):
		hurtbox.connect("damaged", Callable(self, "_on_damaged"))

	# Landing spawn puff
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx:
		vfx.spawn_puff(global_position + Vector3(0, 0.5, 0), Color(0.85, 0.78, 0.45), 18, 4.0)
		vfx.spawn_shockwave(global_position, 7.0, Color(0.3, 0.9, 0.4), 0.5)

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		expire()
		return

	# Pulsing aggro ring indicator every 1.0s
	aggro_pulse_timer -= delta
	if aggro_pulse_timer <= 0.0:
		aggro_pulse_timer = 1.0
		var vfx = get_node_or_null("/root/VFXManager")
		if vfx:
			vfx.spawn_shockwave(global_position, 7.0, Color(0.2, 0.85, 0.35), 0.45)

	# Force all nearby enemies within 7m to target this decoy
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if e and is_instance_valid(e) and e is Node3D:
			if global_position.distance_to((e as Node3D).global_position) <= 7.0:
				if "target_player" in e:
					e.target_player = self

	if not is_on_floor():
		velocity.y -= 20.0 * delta
	move_and_slide()

func _on_damaged(amount: float, _kb: Vector3, _type: String, _attacker: Node) -> void:
	current_health -= amount
	if hp_label:
		hp_label.text = "DECOY: %d" % max(0, int(current_health))

	var vfx = get_node_or_null("/root/VFXManager")
	if vfx:
		vfx.spawn_sparks(global_position + Vector3(0, 1.0, 0), Vector3.UP, Color(0.85, 0.75, 0.35), 8, 3.5)

	if current_health <= 0.0:
		expire()

func expire() -> void:
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx:
		vfx.spawn_puff(global_position + Vector3(0, 1.0, 0), Color(0.86, 0.78, 0.46), 24, 5.0)

	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.15)
	tween.chain().tween_callback(queue_free)

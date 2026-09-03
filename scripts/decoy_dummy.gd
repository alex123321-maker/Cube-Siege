extends CharacterBody3D

@export var max_health: float = 250.0
var current_health: float = 250.0
var lifetime: float = 3.5

@onready var hurtbox: Area3D = $Hurtbox
@onready var hp_label: Label3D = $HPLabel

func _ready() -> void:
	add_to_group("decoy")
	current_health = max_health
	if hurtbox and hurtbox.has_signal("damaged"):
		hurtbox.connect("damaged", Callable(self, "_on_damaged"))

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0:
		expire()
		return

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
	if current_health <= 0.0:
		expire()

func expire() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.2)
	tween.chain().tween_callback(queue_free)

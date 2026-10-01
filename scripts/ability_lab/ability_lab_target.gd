extends EnemyBase
class_name AbilityLabTarget

## Uses the actual EnemyBase health pipeline with inert training presentation.
## No XP, drops, persistence, AI, or asynchronous death cleanup in a fixture.
func _ready() -> void:
	add_to_group("enemies")
	current_health = max_health
	if hurtbox:
		(hurtbox as HurtboxArea).damaged.connect(_on_damaged)
	update_hp_label()

func _physics_process(_delta: float) -> void:
	# The arena advances fixture physics together with the shared ability clock.
	pass

func advance_fixture(delta: float) -> void:
	super._physics_process(delta)

func _custom_physics(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0

func _on_damaged(amount: float, knockback: Vector3, type: String, attacker: Node) -> void:
	super._on_damaged(amount, knockback, type, attacker)

func _spawn_damage_text_on_damaged(_amount: float) -> void:
	pass

func die() -> void:
	is_dying = true
	update_hp_label()

func reset_fixture() -> void:
	is_dying = false
	current_health = max_health
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	update_hp_label()

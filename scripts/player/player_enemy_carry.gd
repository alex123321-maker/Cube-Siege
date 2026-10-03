extends RefCounted
class_name PlayerEnemyCarry

## An enemy-owned sweep temporarily drives horizontal motion through collisions.
## No input flag is changed; normal combat, aim and timer updates still run.
var _owner: WeakRef = null

func begin(actor: PlayerPrototype, owner: Node) -> bool:
	if not is_instance_valid(owner) or not owner.is_inside_tree() or actor.current_health <= 0.0 or not actor.input_enabled:
		return false
	if active(actor) and _owner.get_ref() != owner:
		return false
	_owner = weakref(owner)
	actor.movement.is_dashing = false
	actor.movement.dash_timer = 0.0
	actor.movement.is_lunging = false
	actor.movement.lunge_timer = 0.0
	actor.velocity.x = 0.0
	actor.velocity.z = 0.0
	return true

func active(actor: PlayerPrototype) -> bool:
	var owner: Node = _owner.get_ref() as Node if _owner else null
	if not is_instance_valid(owner) or not owner.is_inside_tree() or actor.current_health <= 0.0 or not actor.input_enabled or not actor.progression.run_build.active:
		clear()
		return false
	return true

func apply_motion(actor: PlayerPrototype, owner: Node, displacement: Vector3) -> bool:
	if not active(actor) or _owner.get_ref() != owner or not displacement.is_finite():
		return false
	var horizontal: Vector3 = Vector3(displacement.x, 0.0, displacement.z)
	actor.velocity.x = 0.0
	actor.velocity.z = 0.0
	if horizontal.length_squared() <= 0.000001:
		return true
	var collision: KinematicCollision3D = actor.move_and_collide(horizontal)
	if collision:
		end(owner)
		return false
	return true

func advance_vertical(actor: PlayerPrototype, delta: float) -> void:
	# A cleave released while swept can still hit, but cannot queue a deferred
	# lunge that unexpectedly moves the character after the enemy lets go.
	actor.movement.is_lunging = false
	actor.movement.lunge_timer = 0.0
	actor.velocity.x = 0.0
	actor.velocity.z = 0.0
	if actor.is_on_floor():
		if actor.velocity.y < 0.0:
			actor.velocity.y = 0.0
	else:
		actor.velocity.y -= 25.0 * delta
	actor.move_and_slide()

func end(owner: Node) -> void:
	if _owner and _owner.get_ref() == owner:
		clear()

func clear() -> void:
	_owner = null

extends RefCounted
class_name PlayerHealth

## Handles Player HP, damage reception, parry mechanics, and death.

signal health_changed(current_health: float, max_health: float)
signal parry_triggered(successful: bool)
signal player_died()

const PARRY_WINDOW: float = 0.5
const PARRY_COOLDOWN: float = 6.0
const PARRY_SUCCESS_COOLDOWN: float = 3.0
const COUNTER_RADIUS: float = 3.5
const COUNTER_DAMAGE: float = 0.0
const COUNTER_STUN: float = 1.0

var max_health: float = 100.0
var current_health: float = 100.0
var shield_health: float = 0.0
var _death_sent: bool = false

var is_parrying: bool = false
var parry_timer: float = 0.0
var parry_cooldown_timer: float = 0.0

var current_day: int = 1

func update_timers(delta: float) -> void:
	if parry_cooldown_timer > 0.0:
		parry_cooldown_timer -= delta
	if is_parrying:
		parry_timer -= delta
		if parry_timer <= 0.0:
			is_parrying = false

func trigger_parry(duration: float = PARRY_WINDOW, cooldown: float = PARRY_COOLDOWN) -> bool:
	if parry_cooldown_timer > 0.0 or is_parrying:
		return false
	is_parrying = true
	parry_timer = duration
	parry_cooldown_timer = cooldown
	parry_triggered.emit(false)
	return true

func take_damage(damage: float, attacker: Node = null, is_invulnerable: bool = false, is_dueling: bool = false, duel_target: Node = null, player_node: Node = null) -> void:
	if is_invulnerable or current_health <= 0.0 or damage <= 0.0 or not _owner_available(player_node):
		return
	var runtime: WarriorTalentRuntime = player_node.talents if player_node is PlayerPrototype else null
	if runtime and runtime.dodge():
		player_node.spawn_popup_text("УКЛОНЕНИЕ", Color.CYAN)
		return

	if is_parrying:
		var counter: bool = runtime != null and runtime.has("counterattack")
		is_parrying = counter
		parry_cooldown_timer = PARRY_SUCCESS_COOLDOWN * (runtime.multiplier("parry_cooldown") if runtime else 1.0)
		parry_triggered.emit(true)
		if not _owner_available(player_node):
			return

		if player_node and is_instance_valid(player_node):
			var vfx = player_node.get_node_or_null("/root/VFXManager")
			if vfx:
				if not counter:
					vfx.dismiss_parry_stance_aura(player_node)
				vfx.spawn_parry_clash(player_node.global_position)

		# Stun nearby enemies on successful parry (counter attack damage/knockback removed per Issue 48)
		if player_node and is_instance_valid(player_node):
			var enemies: Array[Node] = player_node.get_tree().get_nodes_in_group("enemies")
			for e in enemies:
				if not _owner_available(player_node):
					return
				if not is_instance_valid(e) or e == player_node:
					continue
				if e is Node3D and player_node.global_position.distance_to(e.global_position) <= COUNTER_RADIUS:
					if e.has_method("apply_stun"):
						e.apply_stun(COUNTER_STUN)
					if not _owner_available(player_node):
						return
					if COUNTER_DAMAGE > 0.0 and is_instance_valid(e) and e.has_method("_on_damaged"):
						e._on_damaged(COUNTER_DAMAGE, (e.global_position - player_node.global_position).normalized() * 8.0, "counter", player_node)
		if _owner_available(player_node) and counter and is_instance_valid(attacker) and not attacker.is_queued_for_deletion() and attacker.has_method("_on_damaged"):
			attacker._on_damaged(runtime.attack_based_ability_damage(attacker), Vector3.ZERO, "counter", player_node)
		return

	var health_multiplier: float = 1.0
	var reflection_fraction: float = 0.0
	# Projectiles keep their damage provenance after their shooter disappears.
	# Duel defense still applies; only reflection needs a living recipient.
	if is_dueling and (not is_instance_valid(attacker) or attacker != duel_target):
		health_multiplier = 1.0 / (1.0 + (2.0 / 3.0) * (runtime.multiplier("duel_resistance") if runtime else 1.0))
		reflection_fraction = minf(1.0, 0.2 * (runtime.multiplier("duel_reflection") if runtime else 1.0))
	var receipt: DamageReceipt = DamageReceipt.resolve(damage, current_health, shield_health, health_multiplier)
	current_health = receipt.remaining_health
	shield_health = receipt.remaining_shield
	if reflection_fraction > 0.0 and is_instance_valid(attacker) and attacker.has_method("_on_damaged"):
		attacker._on_damaged(receipt.reflection_base() * reflection_fraction, Vector3.ZERO, "reflected", player_node)
	if not _owner_available(player_node):
		return
	health_changed.emit(current_health, max_health)
	if not _owner_available(player_node):
		return

	var bus = player_node.get_node_or_null("/root/EventBus") if player_node else null
	if bus:
		bus.player_health_changed.emit(current_health, max_health)
	if not _owner_available(player_node):
		return

	if current_health <= 0.0 and not _death_sent:
		_death_sent = true
		current_health = 0.0
		player_died.emit()
		# Ordinary death ends the run synchronously through the coordinator.
		# Keep its one global notification, but never touch a deleted owner.
		if _owner_available(player_node, false) and is_instance_valid(bus):
			bus.player_died.emit()

func _owner_available(owner: Variant, require_active_run: bool = true) -> bool:
	if typeof(owner) == TYPE_NIL:
		return true # Standalone health component has no actor lifecycle to cancel.
	if not is_instance_valid(owner) or not owner is Node or not owner.is_inside_tree() or owner.is_queued_for_deletion():
		return false
	return not require_active_run or not owner is PlayerPrototype or (owner as PlayerPrototype).progression.run_build.active

func heal(amount: float) -> void:
	if current_health <= 0.0:
		return
	current_health = minf(max_health, current_health + amount)
	health_changed.emit(current_health, max_health)

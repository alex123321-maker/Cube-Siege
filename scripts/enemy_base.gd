extends CharacterBody3D
class_name EnemyBase

@export var max_health: float = 60.0
@export var move_speed: float = 3.0

var current_health: float = 60.0
var shield_health: float = 0.0
var last_health_damage: float = 0.0
var last_damage_type: String = ""
var status_effects: StatusEffectState = StatusEffectState.new()
var knockback_velocity: Vector3 = Vector3.ZERO
var target_player: Node3D = null

const EnemyPresentationClass = preload("res://scripts/enemy_presentation.gd")

var is_in_duel: bool = false
var duel_opponent: Node = null
var is_dying: bool = false
var presentation: EnemyPresentationClass = EnemyPresentationClass.new()

@onready var hurtbox: Area3D = $Hurtbox if has_node("Hurtbox") else null
@onready var hp_label: Label3D = $Visuals/HPLabel if has_node("Visuals/HPLabel") else null

const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

func _enter_tree() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg:
		reg.register_enemy(self)

func _exit_tree() -> void:
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg:
		reg.unregister_enemy(self)

func _ready() -> void:
	add_to_group("enemies")
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg:
		reg.register_enemy(self)
	current_health = max_health
	update_hp_label()
	if hurtbox and hurtbox.has_signal("damaged"):
		if not hurtbox.is_connected("damaged", Callable(self, "_on_damaged")):
			hurtbox.connect("damaged", Callable(self, "_on_damaged"))
	
	presentation.setup(self)
	_find_player()

@export var radius: float = 0.4
@export var half_height: float = 0.9
var step_smooth_offset_y: float = 0.0
var desired_velocity_h: Vector3 = Vector3.ZERO

func _physics_process(delta: float) -> void:
	if is_dying:
		return

	status_effects.advance(delta)
	if not status_effects.is_stunned():
		_custom_physics(delta)
	desired_velocity_h *= status_effects.movement_multiplier()

	# Locomotion with authoritative voxel step-up/down, cliff avoidance, and 3D knockback preservation
	var loc_result: Dictionary = MonsterLocomotion.process_locomotion(
		self,
		delta,
		desired_velocity_h,
		knockback_velocity,
		half_height,
		radius,
		step_smooth_offset_y
	)
	step_smooth_offset_y = float(loc_result.get("smooth_offset_y", 0.0))
	knockback_velocity = loc_result.get("knockback", Vector3.ZERO)

	presentation.update(delta, velocity, move_speed)

	var visuals: Node3D = get_node_or_null("Visuals") as Node3D
	if visuals:
		visuals.position.y = step_smooth_offset_y

	desired_velocity_h = Vector3.ZERO

func _custom_physics(_delta: float) -> void:
	pass

func _find_player() -> void:
	if not is_inside_tree():
		return
	var reg = get_node_or_null("/root/EntityRegistry")
	if reg and reg.has_method("get_player"):
		var p_cand = reg.get_player()
		if is_instance_valid(p_cand) and p_cand is Node3D and p_cand.is_inside_tree():
			target_player = p_cand as Node3D
			return
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	for candidate in players:
		if is_instance_valid(candidate) and candidate is Node3D and candidate.is_inside_tree():
			target_player = candidate as Node3D
			return

func _on_damaged(amount: float, knockback: Vector3, _type: String, _attacker: Node) -> void:
	if is_dying:
		return
	var receipt: DamageReceipt = DamageReceipt.resolve(amount, current_health, shield_health)
	current_health = receipt.remaining_health
	shield_health = receipt.remaining_shield
	last_health_damage = receipt.health_loss
	last_damage_type = _type
	if _attacker is PlayerPrototype:
		(_attacker as PlayerPrototype).talents.on_damage_dealt(receipt.health_loss, self, _type)
	_apply_knockback(knockback)
	update_hp_label()
	_spawn_damage_text_on_damaged(receipt.health_loss + receipt.shield_loss)

	if current_health <= 0.0:
		if _attacker is PlayerPrototype:
			(_attacker as PlayerPrototype).talents.on_enemy_killed(self, _type)
		die()
	else:
		if presentation:
			presentation.play_hit()

func apply_slow(source_id: String, strength: float, duration: float) -> void:
	status_effects.apply_slow(source_id, strength, duration)

func apply_stun(duration: float) -> void:
	if is_in_group("boss"):
		return
	status_effects.apply_stun("parry", duration)
	desired_velocity_h = Vector3.ZERO

func _apply_knockback(knockback: Vector3) -> void:
	knockback_velocity = knockback

func _spawn_damage_text_on_damaged(amount: float) -> void:
	spawn_damage_text(amount)

func update_hp_label() -> void:
	if hp_label:
		hp_label.text = "%d/%d" % [max(0, int(current_health)), int(max_health)]
		if shield_health > 0.0:
			hp_label.text += "\nЩИТ: %d" % int(ceilf(shield_health))
			hp_label.modulate = Color(0.4, 0.8, 1.0)
		else:
			hp_label.modulate = Color.WHITE

func spawn_damage_text(amount: float, custom_text: String = "", custom_color: Color = Color.WHITE) -> void:
	var popup: Node3D = FLOATING_TEXT_SCENE.instantiate()
	get_parent().add_child(popup)
	popup.global_position = global_position + Vector3(0, 1.8, 0)
	if custom_text != "":
		popup.get_node("Label3D").text = custom_text
		popup.get_node("Label3D").modulate = custom_color
	else:
		popup.setup(amount, amount >= 40.0)

func start_duel(warrior: Node) -> void:
	is_in_duel = true
	duel_opponent = warrior
	target_player = warrior as Node3D
	_on_duel_started()

func _on_duel_started() -> void:
	spawn_damage_text(0, "DUEL!", Color.RED)

func end_duel() -> void:
	is_in_duel = false
	duel_opponent = null

func die() -> void:
	if is_dying:
		return
	is_dying = true

	remove_from_group("enemies")

	if is_in_duel and duel_opponent and is_instance_valid(duel_opponent) and duel_opponent.has_method("end_duel"):
		duel_opponent.end_duel()

	_on_death_effects()

	var reg = get_node_or_null("/root/EntityRegistry")
	var award_player: Node3D = null
	if reg and reg.has_method("get_player"):
		var p_cand = reg.get_player()
		if is_instance_valid(p_cand) and p_cand is Node3D:
			award_player = p_cand as Node3D
	if not award_player:
		var players: Array[Node] = get_tree().get_nodes_in_group("player")
		for candidate in players:
			if is_instance_valid(candidate) and candidate is Node3D:
				award_player = candidate as Node3D
				break
	if award_player and is_instance_valid(award_player) and award_player.has_method("add_xp"):
		award_player.add_xp(_get_xp_reward())

	if reg:
		reg.unregister_enemy(self)

	var eb = get_node_or_null("/root/EventBus")
	if eb:
		eb.enemy_killed.emit(self, global_position)

	if hurtbox:
		hurtbox.set_deferred("monitoring", false)
		hurtbox.set_deferred("monitorable", false)
		for child in hurtbox.get_children():
			if child is CollisionShape3D:
				child.set_deferred("disabled", true)
	var col = get_node_or_null("CollisionShape3D")
	if col:
		col.set_deferred("disabled", true)
	if hp_label:
		hp_label.visible = false

	if presentation:
		presentation.play_death()

	var tween: Tween = create_tween()
	var death_anim_len: float = presentation.get_animation_length(&"death") if presentation else 0.2
	if death_anim_len > 0.3:
		tween.tween_interval(death_anim_len * 0.75)
		tween.tween_property(self, "scale", Vector3.ONE * 0.001, 0.2)
	else:
		tween.tween_property(self, "scale", Vector3.ONE * 0.001, 0.2)
	tween.chain().tween_callback(queue_free)

func _get_xp_reward() -> float:
	return 0.0

func _on_death_effects() -> void:
	pass

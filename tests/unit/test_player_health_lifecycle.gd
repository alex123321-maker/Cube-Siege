extends GutTest

const PLAYER: PackedScene = preload("res://scenes/player.tscn")

class RecordingEnemy extends EnemyBase:
	var actor: PlayerPrototype
	var received: float = 0.0
	var stuns: int = 0
	var free_on_damage: bool = false
	var free_on_stun: bool = false
	func _on_damaged(amount: float, _knockback: Vector3, _type: String, _attacker: Node) -> void:
		received += amount
		if free_on_damage:
			actor.free()
	func apply_stun(_duration: float) -> void:
		stuns += 1
		if free_on_stun:
			actor.queue_free()

var _world: Node3D
var _player: PlayerPrototype

func before_each() -> void:
	_world = Node3D.new()
	add_child_autoqfree(_world)
	_player = PLAYER.instantiate() as PlayerPrototype
	_world.add_child(_player)
	_player.set_physics_process(false)
	_player.input_enabled = false
	_player.talents.reset_for_viewer(WarriorTalentCatalog.TALENT_IDS)
	_player.talents.build().selected_talents.assign(["counterattack", "hot_blood"])
	_player.talents.refresh_stats()
	_player.global_position = Vector3(500, 1, 500)
	_player.health.is_parrying = true

func _enemy() -> RecordingEnemy:
	var enemy: RecordingEnemy = RecordingEnemy.new()
	enemy.actor = _player
	_world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = Vector3(501, 1, 500)
	return enemy

func _end_on_parry(success: bool) -> void:
	if success:
		_player.progression.run_build.end_run()

func _free_on_parry(success: bool) -> void:
	if success:
		_player.queue_free()

func _free_on_health(_current: float, _maximum: float) -> void:
	_player.queue_free()

func _end_on_death() -> void:
	_player.progression.run_build.end_run()

func test_actual_parry_signal_terminal_callback_prevents_counter_stun_and_regeneration() -> void:
	var enemy: RecordingEnemy = _enemy()
	_player.parry_triggered.connect(_end_on_parry)
	_player.take_damage(20.0, enemy)
	assert_false(_player.progression.run_build.active)
	assert_eq(enemy.received, 0.0)
	assert_eq(enemy.stuns, 0)
	assert_eq(_player.talents.regeneration_remaining, 0.0)
	assert_eq(_player.current_health, 100.0)

func test_actual_forwarded_parry_signal_queues_owner_deletion_and_cancels_component_listeners() -> void:
	var enemy: RecordingEnemy = _enemy()
	var runtime: WarriorTalentRuntime = _player.talents
	var health: PlayerHealth = _player.health
	_player.parry_triggered.connect(_free_on_parry)
	_player.take_damage(20.0, enemy)
	assert_true(_player.is_queued_for_deletion())
	assert_eq(enemy.received, 0.0)
	assert_eq(enemy.stuns, 0)
	assert_eq(runtime.regeneration_remaining, 0.0)
	assert_eq(health.current_health, 100.0)
	await get_tree().process_frame
	assert_false(is_instance_valid(_player))

func test_actual_stun_callback_queues_owner_deletion_before_counter_and_remaining_stuns() -> void:
	var enemy: RecordingEnemy = _enemy()
	enemy.free_on_stun = true
	_player.take_damage(20.0, enemy)
	assert_true(_player.is_queued_for_deletion())
	assert_eq(enemy.stuns, 1)
	assert_eq(enemy.received, 0.0)
	await get_tree().process_frame
	assert_false(is_instance_valid(_player))

func test_actual_reflection_callback_can_free_owner_before_health_or_bus_notification() -> void:
	var enemy: RecordingEnemy = _enemy()
	enemy.free_on_damage = true
	var selected: RecordingEnemy = _enemy()
	_player.abilities.is_dueling = true
	_player.abilities.duel_target = selected
	_player.health.is_parrying = false
	var health: PlayerHealth = _player.health
	watch_signals(health)
	# The actor's public wrapper is locked while calling; the component itself
	# supports immediate owner deletion during a synchronous reflected callback.
	health.take_damage(10.0, enemy, false, true, selected, _player)
	assert_false(is_instance_valid(_player))
	assert_almost_eq(health.current_health, 94.0, 0.0001)
	assert_almost_eq(enemy.received, 1.2, 0.0001)
	assert_signal_emit_count(health, "health_changed", 0)

func test_actual_health_signal_queued_owner_deletion_cancels_remaining_death_notifications() -> void:
	_player.health.is_parrying = false
	var health: PlayerHealth = _player.health
	watch_signals(health)
	_player.health_changed.connect(_free_on_health)
	_player.take_damage(200.0)
	assert_true(_player.is_queued_for_deletion())
	assert_eq(health.current_health, 0.0)
	assert_signal_emit_count(health, "player_died", 0)
	await get_tree().process_frame
	assert_false(is_instance_valid(_player))

func test_ordinary_actor_death_still_emits_once_when_coordinator_ends_run_inside_signal() -> void:
	_player.health.is_parrying = false
	_player.player_died.connect(_end_on_death)
	var bus: Node = get_node("/root/EventBus")
	watch_signals(bus)
	watch_signals(_player.health)
	_player.take_damage(200.0)
	_player.take_damage(200.0)
	assert_false(_player.progression.run_build.active)
	assert_eq(_player.current_health, 0.0)
	assert_signal_emit_count(_player.health, "player_died", 1)
	assert_signal_emit_count(bus, "player_died", 1)

func test_standalone_health_without_actor_preserves_damage_and_single_death() -> void:
	var health: PlayerHealth = PlayerHealth.new()
	watch_signals(health)
	health.take_damage(25.0)
	assert_eq(health.current_health, 75.0)
	health.take_damage(100.0)
	health.take_damage(100.0)
	assert_eq(health.current_health, 0.0)
	assert_signal_emit_count(health, "player_died", 1)

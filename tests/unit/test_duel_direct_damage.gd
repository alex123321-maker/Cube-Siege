extends GutTest

const PLAYER: PackedScene = preload("res://scenes/player.tscn")
const ENEMY: PackedScene = preload("res://scenes/enemy_dummy.tscn")
var _world: Node3D
var _player: PlayerPrototype
var _save: Node
var _snapshot: Dictionary

func before_each() -> void:
	_save = get_node("/root/SaveManager")
	_snapshot = _save.snapshot_state()
	_save.reset_to_defaults()
	get_node("/root/RosterManager").selected_slot_index = 0
	_save.roster_slots[0].unlocked_talents = WarriorTalentCatalog.TALENT_IDS.duplicate()
	_world = Node3D.new()
	add_child_autoqfree(_world)
	var floor_body: StaticBody3D = StaticBody3D.new()
	var collision: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(50.0, 0.2, 50.0)
	collision.shape = box
	floor_body.add_child(collision)
	floor_body.position = Vector3(1000.0, -0.1, 1000.0)
	_world.add_child(floor_body)
	_player = PLAYER.instantiate() as PlayerPrototype
	_world.add_child(_player)
	_player.set_physics_process(false)
	_player.position = Vector3(1000.0, 0.9, 1000.0)
	var build: WarriorRunBuild = _player.progression.run_build
	build.selected_talents.assign(["counterattack", "tempered_blade", "perfect_dash", "loud_triumph"])
	build._reveal_synergies()
	build.build_changed.emit()
	_player.talents.refresh_meta()
	await wait_physics_frames(2)

func after_each() -> void:
	_save.restore_state(_snapshot)
	await wait_seconds(0.3)

func _enemy(offset: Vector3) -> EnemyBase:
	var enemy: EnemyBase = ENEMY.instantiate() as EnemyBase
	_world.add_child(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = Vector3(1000.0, 0.9, 1000.0) + offset
	enemy.max_health = 1000.0
	enemy.current_health = 1000.0
	return enemy

func _set_rank(rank: int) -> void:
	_player.progression.run_build.specializations["duel_bonus"] = rank
	_player.progression.run_build.build_changed.emit()

func test_successful_counter_uses_selected_duel_bonus_once_and_actual_hp_lifesteal() -> void:
	var selected: EnemyBase = _enemy(Vector3(1.0, 0.0, -0.8))
	var other: EnemyBase = _enemy(Vector3(1.0, 0.0, 0.8))
	for rank: int in [0, 3]:
		_set_rank(rank)
		_player.abilities.ultimate_cooldown_timer = 0.0
		_player.abilities.perform_warrior_ultimate(_player, selected, true)
		_player.current_health = 50.0
		selected.current_health = 1000.0
		other.current_health = 1000.0
		_player.health.is_parrying = false
		_player.health.parry_cooldown_timer = 0.0
		_player.perform_parry()
		_player.take_damage(20.0, selected)
		_player.take_damage(20.0, other)
		var expected: float = 25.0 * (1.0 + 0.2 * _player.talents.multiplier("duel_bonus"))
		assert_almost_eq(selected.current_health, 1000.0 - expected, 0.001)
		assert_almost_eq(other.current_health, 975.0, 0.001)
		assert_almost_eq(_player.current_health, 50.0 + (expected + 25.0) * 0.08, 0.001)
		assert_almost_eq(_player.attack_damage, 27.25, 0.001, "All Bloodlust openings affect only the basic property")
		_player.end_duel()
		selected.current_health = 1000.0
		_player.take_damage(20.0, selected)
		assert_almost_eq(selected.current_health, 975.0, 0.001, "An ended Duel cannot amplify a counter")

func test_native_dash_contacts_selected_and_other_targets_then_loses_bonus_after_duel() -> void:
	var selected: EnemyBase = _enemy(Vector3(0.8, 0.0, -0.8))
	var other: EnemyBase = _enemy(Vector3(1.5, 0.0, 0.8))
	for rank: int in [0, 3]:
		_set_rank(rank)
		_player.abilities.ultimate_cooldown_timer = 0.0
		_player.abilities.perform_warrior_ultimate(_player, selected, true)
		await _dash_right(selected, other)
		var expected: float = 25.0 * (1.0 + 0.2 * _player.talents.multiplier("duel_bonus"))
		assert_almost_eq(selected.current_health, 1000.0 - expected, 0.001)
		assert_almost_eq(other.current_health, 975.0, 0.001)
		_player.end_duel()
		await _dash_right(selected, other)
		assert_almost_eq(selected.current_health, 975.0, 0.001)
		assert_almost_eq(other.current_health, 975.0, 0.001)

func _dash_right(selected: EnemyBase, other: EnemyBase) -> void:
	_player.global_position = Vector3(1000.0, 0.9, 1000.0)
	_player.velocity = Vector3.ZERO
	_player.movement.is_dashing = false
	_player.movement.dash_cooldown_timer = 0.0
	selected.current_health = 1000.0
	other.current_health = 1000.0
	assert_true(_player.movement.perform_dash(Vector3.RIGHT, Vector3.RIGHT))
	_player.set_physics_process(true)
	await wait_physics_frames(9)
	_player.set_physics_process(false)
	assert_gt(_player.global_position.x, 1001.5, "Real CharacterBody motion crosses both targets")

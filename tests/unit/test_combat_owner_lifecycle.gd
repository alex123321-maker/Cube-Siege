extends GutTest

## Keep the component reference alive after deleting its owner, just as pending
## external continuations once did. Execution must already be cancelled.
const PLAYER: PackedScene = preload("res://scenes/player.tscn")
const ENEMY: PackedScene = preload("res://scenes/enemy_dummy.tscn")

class TerminalTarget extends EnemyBase:
	var actor: PlayerPrototype
	var received: float = 0.0
	func _on_damaged(amount: float, _knockback: Vector3, _type: String, _attacker: Node) -> void:
		received += amount
		actor.progression.run_build.end_run()

class FreeingTarget extends EnemyBase:
	var actor: PlayerPrototype
	var received: float = 0.0
	func _on_damaged(amount: float, _knockback: Vector3, _type: String, _attacker: Node) -> void:
		received += amount
		actor.free()

var _world: Node3D
var _player: PlayerPrototype
var _combat: PlayerCombat

func before_each() -> void:
	_world = Node3D.new()
	add_child_autoqfree(_world)
	_player = PLAYER.instantiate() as PlayerPrototype
	_world.add_child(_player)
	_player.set_physics_process(false)
	_player.input_enabled = false
	_player.talents.reset_for_viewer(WarriorTalentCatalog.TALENT_IDS)
	_player.global_position = Vector3(0, 1, 0)
	_combat = _player.combat
	await get_tree().physics_frame

func _target() -> EnemyBase:
	var enemy: EnemyBase = ENEMY.instantiate() as EnemyBase
	add_child_autoqfree(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = Vector3(0, 1, -1.5)
	enemy.max_health = 1000.0
	enemy.current_health = 1000.0
	return enemy

func _assert_cancelled() -> void:
	assert_eq(_combat._pending_casts.size(), 0, "No prepared attack survives owner cancellation")
	assert_null(_combat._active_slash, "No contact receiver survives owner cancellation")
	assert_eq(_combat._slash_remaining, 0.0)

func test_delete_owner_during_preparation_cancels_without_waiting_for_cast() -> void:
	var target: EnemyBase = _target()
	_combat.perform_special_attack(_player, 0, false, false, _player.abilities)
	assert_eq(_combat._pending_casts.size(), 1)
	_world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_cancelled()
	await get_tree().create_timer(0.4).timeout
	assert_eq(target.current_health, 1000.0, "A deleted hero cannot release its prepared attack")
	assert_false(is_instance_valid(_combat._driver))

func test_delete_owner_during_active_contact_cancels_before_next_physics_frame() -> void:
	var target: EnemyBase = _target()
	_combat.trigger_slash(_player, 60.0, 0.0, 360.0, false, true)
	assert_true(_player.slash_area.monitoring)
	_world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_assert_cancelled()
	await get_tree().create_timer(0.4).timeout
	assert_eq(target.current_health, 1000.0)
	assert_false(is_instance_valid(_combat._driver))

func test_terminal_run_end_cancels_contact_and_restores_model_pose() -> void:
	var target: EnemyBase = _target()
	_player.presentation.start_whirlwind_spin(0.3)
	_player.presentation.active_model.rotation.y += 0.7
	_combat.trigger_slash(_player, 60.0, 0.0, 360.0, false, true)
	_player.progression.run_build.end_run()
	_assert_cancelled()
	assert_almost_eq(_player.presentation.active_model.rotation.y, PI, 0.001)
	await get_tree().physics_frame
	await get_tree().physics_frame
	assert_false(_player.slash_area.monitoring)
	assert_eq(target.current_health, 1000.0)

func test_death_signal_cancels_preparing_cast_immediately() -> void:
	var target: EnemyBase = _target()
	_combat.perform_special_attack(_player, 0, false, false, _player.abilities)
	_player.take_damage(1000.0)
	_assert_cancelled()
	await get_tree().create_timer(0.4).timeout
	assert_eq(target.current_health, 1000.0)

func test_delete_owner_during_decoy_preparation_releases_its_timer() -> void:
	_player.set_class(PlayerPrototype.CharacterClass.ARCHER, false)
	var abilities: PlayerAbilities = _player.abilities
	abilities.deploy_decoy(_player)
	var windup: Timer = _player.get_node_or_null("DecoyWindup") as Timer
	assert_not_null(windup, "A utility windup is an actor child")
	_world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(windup), "No global timer survives deleted actor")
	await get_tree().create_timer(0.3).timeout
	assert_eq(get_tree().get_nodes_in_group("decoy").size(), 0, "Deleted actor cannot release a decoy")

func test_nuke_windup_and_burn_cancel_with_owner_and_terminal_state() -> void:
	_player.set_class(PlayerPrototype.CharacterClass.ENGINEER, false)
	_player.abilities.perform_engineer_ultimate(_player, Vector3.ZERO)
	var windup: Timer = _player.get_node_or_null("NukeWindup") as Timer
	assert_not_null(windup)
	_player.progression.run_build.end_run()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(windup), "Terminal state cancels windup immediately")
	_player.progression.initialize_run(WarriorTalentCatalog.STARTER_IDS)
	_player.abilities._release_tactical_nuke(_player, Vector3.ZERO)
	var burn: Timer = _player.get_node_or_null("NukeBurn") as Timer
	assert_not_null(burn)
	_world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(is_instance_valid(burn), "Deleting actor removes all remaining burn ticks")

func test_nuke_terminal_damage_callback_stops_other_hits_and_burn_release() -> void:
	_player.set_class(PlayerPrototype.CharacterClass.ENGINEER, false)
	var terminal: TerminalTarget = TerminalTarget.new()
	terminal.actor = _player
	_world.add_child(terminal)
	terminal.set_physics_process(false)
	terminal.global_position = Vector3.ZERO
	var bystander: EnemyBase = _target()
	_player.abilities._release_tactical_nuke(_player, Vector3.ZERO)
	assert_eq(terminal.received, PlayerAbilities.NUKE_DAMAGE)
	assert_eq(bystander.current_health, 1000.0, "A synchronous terminal callback stops the remaining impact targets")
	assert_null(_player.get_node_or_null("NukeBurn"), "No burn timer is created after terminal impact callback")

func _prepare_dangerous_dash() -> WarriorTalentRuntime:
	var build: WarriorRunBuild = _player.progression.run_build
	build.selected_talents.assign(["perfect_dash", "loud_triumph"])
	build._reveal_synergies()
	build.build_changed.emit()
	_player.movement.perform_dash(Vector3.RIGHT, Vector3.RIGHT)
	return _player.talents

func test_dash_terminal_callback_stops_the_current_remaining_contacts() -> void:
	var terminal: TerminalTarget = TerminalTarget.new()
	terminal.actor = _player
	_world.add_child(terminal)
	terminal.set_physics_process(false)
	terminal.global_position = Vector3(0.5, 1.0, 0.2)
	var bystander: EnemyBase = _target()
	bystander.global_position = Vector3(1.0, 1.0, 0.3)
	await wait_physics_frames(2)
	var runtime: WarriorTalentRuntime = _prepare_dangerous_dash()
	_player.global_position += Vector3(2.0, 0.0, 0.0)
	runtime.after_movement()
	assert_almost_eq(terminal.received, 25.0, 0.001)
	assert_false(_player.progression.run_build.active)
	assert_eq(bystander.current_health, 1000.0, "Ending a run inside the first hit cancels the remaining dash contacts")

func test_dash_owner_deleted_inside_damage_callback_stops_without_stale_access() -> void:
	var terminal: FreeingTarget = FreeingTarget.new()
	terminal.actor = _player
	_world.add_child(terminal)
	terminal.set_physics_process(false)
	terminal.global_position = Vector3(0.5, 1.0, 0.2)
	var bystander: EnemyBase = _target()
	bystander.global_position = Vector3(1.0, 1.0, 0.3)
	await wait_physics_frames(2)
	var runtime: WarriorTalentRuntime = _prepare_dangerous_dash()
	_player.global_position += Vector3(2.0, 0.0, 0.0)
	runtime.after_movement()
	assert_almost_eq(terminal.received, 25.0, 0.001)
	assert_false(is_instance_valid(_player))
	assert_eq(bystander.current_health, 1000.0, "Deleting the owner inside the first hit cancels later contacts")
	runtime.after_movement()
	assert_eq(bystander.current_health, 1000.0)

func test_dash_real_final_boss_defeat_saves_victory_before_other_contacts() -> void:
	var save: Node = get_node("/root/SaveManager")
	var snapshot: Dictionary = save.snapshot_state()
	var storage: String = save.storage_dir
	save.set_storage_dir("user://test_dash_final_boss/")
	save.reset_to_defaults()
	get_node("/root/RosterManager").begin_run()
	var cycle: DayNightCycle = DayNightCycle.new()
	_world.add_child(cycle)
	cycle.set_process(false)
	cycle.current_day = 30
	cycle.is_night = true
	cycle.boss_pending = true
	var waves: WaveDirector = WaveDirector.new()
	_world.add_child(waves)
	waves.set_process(false)
	var coordinator: WarriorRunCoordinator = WarriorRunCoordinator.new()
	_world.add_child(coordinator)
	coordinator.player = _player
	coordinator.cycle = cycle
	coordinator.waves = waves
	cycle.wave_completed.connect(coordinator._on_wave_completed)
	var boss: SiegeBoss = preload("res://scenes/bosses/boss_06_rift_harbinger.tscn").instantiate() as SiegeBoss
	boss.configure(6, _player)
	_world.add_child(boss)
	boss.set_physics_process(false)
	boss.global_position = Vector3(0.5, 1.0, 0.2)
	boss.current_health = 1.0
	coordinator._boss = boss
	boss.defeated.connect(coordinator._on_boss_defeated)
	var bystander: EnemyBase = _target()
	bystander.global_position = Vector3(1.0, 1.0, 0.3)
	await wait_physics_frames(2)
	var runtime: WarriorTalentRuntime = _prepare_dangerous_dash()
	_player.global_position += Vector3(2.0, 0.0, 0.0)
	runtime.after_movement()
	assert_true(boss.is_dying, "The actual stage-six boss receives the lethal dash contact")
	assert_true(coordinator.finished and coordinator.victory)
	assert_false(_player.progression.run_build.active)
	assert_eq(save.run_history.size(), 1)
	assert_eq(save.run_history[0].outcome, "victory")
	assert_eq(bystander.current_health, 1000.0, "No contact follows the real final-boss terminal save")
	save.restore_state(snapshot)
	save.set_storage_dir(storage)

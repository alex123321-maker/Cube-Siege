extends Node
class_name WarriorRunCoordinator

## Sole owner of run transitions/rewards. Presentation listens to run_finished.
signal run_finished(victory: bool, extracted: bool, earned_xp: int)
signal persistence_failed(message: String)

const BOSS_SCENES: Array[PackedScene] = [
	preload("res://scenes/bosses/boss_01_cairn.tscn"),
	preload("res://scenes/bosses/boss_02_gorgon.tscn"),
	preload("res://scenes/bosses/boss_03_ash_oracle.tscn"),
	preload("res://scenes/bosses/boss_04_mortar.tscn"),
	preload("res://scenes/bosses/boss_05_rift_warden.tscn"),
	preload("res://scenes/bosses/boss_06_rift_harbinger.tscn")
]

var player: PlayerPrototype
var cycle: DayNightCycle
var waves: WaveDirector
var portal: PortalController
var finished: bool = false
var victory: bool = false
var _boss: SiegeBoss
var _boss_spawn_retry: float = 0.0
var _bus: Node
var _resolved_boss_waves: Array[int] = []
var _finish_in_progress: bool = false
var _pending_finish: bool = false
var _pending_victory: bool = false
var _pending_extracted: bool = false
var _pending_xp: int = 0

func setup(p_player: PlayerPrototype, p_cycle: DayNightCycle, p_waves: WaveDirector, p_portal: PortalController) -> void:
	player = p_player
	cycle = p_cycle
	waves = p_waves
	portal = p_portal
	cycle.wave_completed.connect(_on_wave_completed)
	cycle.phase_changed.connect(_on_phase_changed)
	player.player_died.connect(_on_player_died)
	_bus = get_node_or_null("/root/EventBus")
	if _bus:
		_bus.resource_gathered.connect(_on_resource_gathered)
		_bus.portal_evacuated.connect(_on_portal_evacuated)
	var roster: Node = get_node_or_null("/root/RosterManager")
	if roster:
		roster.begin_run()
	call_deferred("_offer_initial_talent")

func _exit_tree() -> void:
	if _bus:
		if _bus.resource_gathered.is_connected(_on_resource_gathered):
			_bus.resource_gathered.disconnect(_on_resource_gathered)
		if _bus.portal_evacuated.is_connected(_on_portal_evacuated):
			_bus.portal_evacuated.disconnect(_on_portal_evacuated)
	if is_instance_valid(player):
		player.progression.run_build.end_run()
	var roster: Node = get_node_or_null("/root/RosterManager")
	if roster:
		roster.run_active = false

func _process(delta: float) -> void:
	if finished or not cycle or not cycle.running or not cycle.is_night or not cycle.boss_pending:
		return
	if is_instance_valid(_boss):
		return
	_boss_spawn_retry -= delta
	if _boss_spawn_retry <= 0.0:
		_boss_spawn_retry = 1.0
		_spawn_current_boss()

func _offer_initial_talent() -> void:
	if not finished and is_instance_valid(player):
		player.progression.run_build.offer_checkpoint(1, true)

func _on_phase_changed(night: bool, wave: int) -> void:
	if finished:
		return
	if night and wave % 5 == 0:
		_spawn_current_boss()

func _spawn_current_boss() -> void:
	if finished or is_instance_valid(_boss) or cycle.current_day % 5 != 0:
		return
	var stage: int = clampi(cycle.current_day / 5, 1, 6)
	_boss = waves.spawn_boss(BOSS_SCENES[stage - 1], stage)
	if _boss:
		_boss.defeated.connect(_on_boss_defeated)

func _on_boss_defeated(boss: SiegeBoss) -> void:
	if finished or boss != _boss or _resolved_boss_waves.has(cycle.current_day):
		return
	var wave: int = cycle.current_day
	_resolved_boss_waves.append(wave)
	player.progression.grant_level(player)
	_boss = null
	cycle.finish_boss_night(wave)

func _on_wave_completed(wave: int) -> void:
	if finished:
		return
	if wave == 30:
		_finish(true, true)
	else:
		player.progression.run_build.offer_checkpoint(wave)

func _on_resource_gathered(_resource_type: String, amount: int, gatherer: Node) -> void:
	if not finished and gatherer == player:
		player.progression.record_resource_gathered(amount)

func _on_portal_evacuated(_day: int, _earned_xp: int) -> void:
	if not finished:
		_finish(false, true)

func _on_player_died() -> void:
	_finish(false, false)

func _finish(won: bool, extracted: bool) -> void:
	if finished or _finish_in_progress:
		return
	_finish_in_progress = true
	if not _pending_finish:
		_pending_finish = true
		_pending_victory = won
		_pending_extracted = extracted
		_pending_xp = player.progression.get_extraction_xp() if extracted else 0
	# Freeze terminal gameplay even if disk persistence needs a retry. In
	# particular death cannot emit another signal, and wave 30 must stay a win.
	_halt_gameplay()
	var earned_xp: int = _pending_xp
	var roster: Node = get_node_or_null("/root/RosterManager")
	var saved: bool = roster.record_run_end(_pending_extracted, cycle.current_day, earned_xp, _pending_victory) if roster else false
	if not saved:
		_finish_in_progress = false
		persistence_failed.emit("Не удалось записать результат забега. Повторите сохранение.")
		return
	finished = true
	victory = _pending_victory
	_pending_finish = false
	player.progression.run_build.end_run()
	run_finished.emit(victory, _pending_extracted, earned_xp)

func retry_save() -> bool:
	if not _pending_finish or finished:
		return false
	_finish(_pending_victory, _pending_extracted)
	return finished

func _halt_gameplay() -> void:
	cycle.stop()
	waves.stop()
	player.progression.run_build.end_run()
	player.set_physics_process(false)
	# Stop remaining actors and projectiles before showing a terminal screen.
	for actor: Node in get_tree().get_nodes_in_group("enemies"):
		# Elite effects are siblings of the actor. Disabling its subtree alone
		# leaves their clocks, colliders and temporary navigation obstacles live.
		if actor is EnemyBase:
			var enemy: EnemyBase = actor as EnemyBase
			if is_instance_valid(enemy.elite_skill_controller):
				enemy.elite_skill_controller.cancel_attack()
		actor.process_mode = Node.PROCESS_MODE_DISABLED
	for projectile: Node in get_tree().get_nodes_in_group("projectiles"):
		projectile.queue_free()

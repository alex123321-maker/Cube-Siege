extends "res://tools/capture_bosses.gd"

## Same review camera/lighting, real combat entry point, real physics movement.
const ENEMY: PackedScene = preload("res://scenes/enemy_dummy.tscn")
var _targets: Array[EnemyBase] = []

class Driver:
	extends Node
	var actor: PlayerPrototype
	func _physics_process(delta: float) -> void:
		actor.movement.update_timers(delta)
		actor.health.update_timers(delta)
		actor.combat.update_timers(delta)
		actor.talents.advance(delta)
		actor.orientation.process_orientation(actor, delta, Vector3.FORWARD, actor.movement.lunge_direction if actor.movement.is_lunging else Vector3.ZERO)
		actor.movement.process_movement(actor, delta, null, 1.0, Vector3.FORWARD)
		actor.presentation.update_animations(actor, false, false, delta, actor.orientation)

func _capture() -> void:
	seed(330519)
	DirAccess.make_dir_recursive_absolute(_output)
	_build_arena()
	_player.talents.reset_for_viewer(WarriorTalentCatalog.TALENT_IDS)
	var driver: Driver = Driver.new()
	driver.actor = _player
	_world.add_child(driver)
	_camera.global_position = Vector3(15.0, 20.0, 13.0)
	_camera.look_at(Vector3(0.0, 0.0, -2.0))
	for index: int in range(5):
		var enemy: EnemyBase = ENEMY.instantiate() as EnemyBase
		_world.add_child(enemy)
		enemy.set_physics_process(false)
		enemy.max_health = 10000.0
		enemy.current_health = 10000.0
		enemy.hp_label.hide()
		_targets.append(enemy)
	for variant: int in range(6):
		await _talent_case(variant)
	_caption.text = "DISMEMBERMENT / ACTUAL DUEL VICTORY LOCATION"
	_detail.text = "Original voxel breakup + morale pulse; enemies receive snapshot slow"
	_player.talents.build().selected_talents.assign(["dismemberment"])
	var victim: EnemyBase = _targets[0]
	var bystander: EnemyBase = _targets[1]
	bystander.global_position = victim.global_position + Vector3(2.0, 0.0, 0.0)
	_player.abilities.perform_warrior_ultimate(_player, victim, true)
	victim.current_health = 1.0
	victim._on_damaged(_player.attack_damage, Vector3.ZERO, "physical", _player)
	var real_victory: bool = victim.current_health <= 0.0 and victim.is_dying and not _player.is_dueling
	for frame: int in range(45):
		if frame in [3, 10, 20]:
			await _save("06_dismember_%02d" % frame)
		await process_frame
	var debris_pass: bool = real_victory and _player.talents.morale_remaining > 0.0 and bystander.status_effects.movement_multiplier() < 1.0
	_failed = _failed or not debris_pass
	_checks.append({"case": "duel_victory_morale", "real_duel_kill": real_victory, "bystander_slow": bystander.status_effects.movement_multiplier(), "passed": debris_pass})
	await create_timer(1.0).timeout
	var effects_left: int = 0
	var vfx_script: Script = load("res://scripts/effects/warrior/warrior_talent_vfx.gd") as Script
	for child: Node in _world.get_children():
		if child.get_script() == vfx_script:
			effects_left += 1
	_failed = _failed or effects_left != 0
	var report: FileAccess = FileAccess.open(_output + "gameplay_checks.json", FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed": not _failed, "checks": _checks, "effects_left": effects_left, "arena": "flat with production actors, physics, camera and lighting"}, "\t"))
	print("TALENT_CAPTURE pass=", not _failed, " cases=", _checks.size(), " effects_left=", effects_left)
	quit(2 if _failed else 0)

func _talent_case(variant: int) -> void:
	_player.global_position = Vector3(0.0, 0.9, 0.0)
	_player.velocity = Vector3.ZERO
	_player.rotation = Vector3.ZERO
	_player.orientation.setup(Vector3.FORWARD)
	_player.combat.special_cooldown_timer = 0.0
	_player.combat.attack_cooldown_timer = 0.0
	_player.movement.is_lunging = false
	_player.movement.lunge_timer = 0.0
	var build: WarriorRunBuild = _player.talents.build()
	build.selected_talents.clear()
	build.specializations.clear()
	if variant == 2:
		build.selected_talents.assign(["whirlwind_cleave"])
	elif variant in [3, 4]:
		build.selected_talents.assign(["whirlwind_cleave", "wide_lunge"])
		build.specializations["cleave_radius"] = 3
	elif variant == 5:
		build.selected_talents.assign(["wide_lunge"])
	_player.talents.refresh_stats()
	var offsets: Array[Vector3] = [Vector3(0.0, 0.0, -1.8), Vector3(2.4, 0.0, -1.6), Vector3(0.0, 0.0, 2.5), Vector3(0.0, 0.0, -5.8), Vector3(0.0, 0.0, 8.0)]
	if variant == 5:
		offsets[0] = Vector3(0.0, 0.0, -1.2)
	for index: int in range(_targets.size()):
		_targets[index].current_health = 10000.0
		_targets[index].global_position = _player.global_position + offsets[index] * (4.0 if variant == 4 else 1.0)
		_targets[index].status_effects.clear()
	if variant <= 2:
		_lighting.apply_day_instant(_light, _environment)
	else:
		_lighting.apply_night_instant(_light, _environment)
	var titles: PackedStringArray = ["BASIC SWORD", "DEFAULT FRONTAL CLEAVE", "360° WHIRLWIND", "WHIRLWIND + LUNGE + RADIUS RANK 3", "WHIRLWIND + LUNGE / MISS", "WIDE LUNGE ALONE / ENDPOINT STRIKE"]
	_caption.text = titles[variant]
	_detail.text = "Real input entry point / same camera / stationary sentinels"
	for frame: int in range(62):
		if frame == 6:
			if variant == 0:
				_player.perform_attack()
			else:
				_player.perform_special_attack()
		if frame in [12, 17, 20, 23, 30, 45]:
			await _save("%02d_talent_%02d" % [variant, frame])
		await process_frame
	var losses: Array[float] = []
	for target: EnemyBase in _targets:
		losses.append(10000.0 - target.current_health)
	var expected: Array[float] = []
	match variant:
		0: expected.assign([25.0, 0.0, 0.0, 0.0, 0.0])
		1: expected.assign([60.0, 60.0, 0.0, 0.0, 0.0])
		2: expected.assign([60.0, 60.0, 60.0, 0.0, 0.0])
		3: expected.assign([60.0, 60.0, 60.0, 60.0, 0.0])
		4: expected.assign([0.0, 0.0, 0.0, 0.0, 0.0])
		5: expected.assign([0.0, 0.0, 0.0, 60.0, 0.0])
	var passed: bool = losses == expected
	var restored: bool = is_equal_approx(_player.presentation.active_model.rotation.y, PI)
	passed = passed and restored
	_failed = _failed or not passed
	_checks.append({"case": titles[variant], "actual_losses": losses, "expected_losses": expected, "spin_restored": restored, "travel": _player.global_position.z, "passed": passed})
	print("TALENT_SAMPLE ", titles[variant], " loss=", losses, " expected=", expected, " spin_restored=", restored, " travel=", _player.global_position.z, " pass=", passed)

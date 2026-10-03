extends GutTest

const BOSS_SCENE: PackedScene = preload("res://scenes/enemies/boss_gorgon.tscn")
const IRON_SCENE: PackedScene = preload("res://scenes/resource_iron.tscn")
const ChargeWarning = preload("res://scripts/combat/boss_charge_warning.gd")
const MainScript = preload("res://scripts/main.gd")

class EncounterCycle extends DayNightCycle:
	var dawn_count: int = 0

	func start_day() -> void:
		dawn_count += 1
		is_night = false
		current_day += 1
		time_left = day_duration

class StairTerrain extends MapGenerator:
	func _ready() -> void:
		set_process(false)

	func get_voxel_height(x: int, _z: int) -> int:
		return 1 if x >= 0 else 0

func after_each() -> void:
	for child: Node in get_children():
		if child.scene_file_path in ["res://scenes/floating_text.tscn", "res://scenes/prefabs/relic_pedestal.tscn"]:
			autoqfree(child)

class WalkingBody extends CharacterBody3D:
	var direction: Vector3 = Vector3.ZERO
	var smooth_offset: float = 0.0

	func _physics_process(delta: float) -> void:
		var result: Dictionary = MonsterLocomotion.process_locomotion(self, delta, direction * 3.2, Vector3.ZERO, 0.9, 0.4, smooth_offset)
		smooth_offset = float(result["smooth_offset_y"])

class DamageTarget extends CharacterBody3D:
	var damage_received: float = 0.0

	func take_damage(amount: float, _attacker: Node = null) -> void:
		damage_received += amount

func before_each() -> void:
	var registry: Node = get_node_or_null("/root/EntityRegistry")
	if registry:
		registry.clear()

func _box_ground(pos: Vector3, size: Vector3) -> void:
	var ground: StaticBody3D = StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	ground.add_child(shape_node)
	add_child_autoqfree(ground)
	ground.global_position = pos

func _walker(pos: Vector3, direction: Vector3) -> WalkingBody:
	var body: WalkingBody = WalkingBody.new()
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var box: BoxShape3D = BoxShape3D.new()
	box.size = Vector3(0.8, 1.8, 0.8)
	shape_node.shape = box
	body.add_child(shape_node)
	add_child_autoqfree(body)
	body.global_position = pos
	body.direction = direction
	return body

func test_monster_climbs_one_block_at_diagonal_voxel_corner() -> void:
	_box_ground(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0))
	_box_ground(Vector3(2.0, 0.5, 2.0), Vector3(4.0, 1.0, 4.0))
	var walker: WalkingBody = _walker(Vector3(-0.6, 0.9, -0.6), Vector3(1, 0, 1).normalized())
	await wait_physics_frames(70)
	assert_gt(walker.global_position.x, 0.6, "Monster must pass the voxel corner without wedging")
	assert_gt(walker.global_position.y, 1.8, "Monster must climb the same +1 block from a diagonal approach")

func test_upward_step_is_not_reported_as_a_cliff() -> void:
	_box_ground(Vector3(0.0, -0.5, 0.0), Vector3(20.0, 1.0, 20.0))
	_box_ground(Vector3(2.0, 0.5, 0.0), Vector3(4.0, 1.0, 4.0))
	var walker: WalkingBody = _walker(Vector3(-0.41, 0.9, 0.0), Vector3.ZERO)
	await wait_physics_frames(3)
	assert_false(MonsterLocomotion.is_cliff_ahead(walker, Vector3.RIGHT, 0.55), "Probe must see the +1m upper surface")

func test_gorgon_charge_does_not_damage_outside_warning_lane() -> void:
	var boss: CharacterBody3D = BOSS_SCENE.instantiate()
	add_child_autoqfree(boss)
	boss.set_physics_process(false)
	var target: DamageTarget = DamageTarget.new()
	add_child_autoqfree(target)
	target.global_position = Vector3(2.7, 0.9, -0.1)
	boss.target_player = target
	boss.start_telegraph(Vector3.FORWARD)
	boss.current_state = boss.BossState.CHARGING
	boss.process_charging(1.0 / 60.0)
	assert_eq(target.damage_received, 0.0, "Charge must not hit a player beside its telegraphed corridor")

func test_gorgon_warning_is_aligned_with_locked_charge_direction() -> void:
	var boss: CharacterBody3D = BOSS_SCENE.instantiate()
	add_child_autoqfree(boss)
	boss.set_physics_process(false)
	boss.global_position = Vector3(4.0, 2.0, 3.0)
	boss.start_telegraph(Vector3.RIGHT)
	var warning: MeshInstance3D = boss.telegraph_mesh
	var warning_direction: Vector3 = -warning.global_basis.z.normalized()
	assert_gt(warning_direction.dot(Vector3.RIGHT), 0.99, "Warning orientation must use the same locked direction as damage")
	var initial_position: Vector3 = warning.global_position
	boss.process_telegraph(0.1)
	assert_almost_eq(warning.global_position, initial_position, Vector3.ONE * 0.001, "Ground warning must stay fixed while the boss shakes")

func test_small_iron_deposit_keeps_configured_yield() -> void:
	var iron: ResourceRock = IRON_SCENE.instantiate()
	iron.configure_rock(ResourceRock.RockType.IRON, 4, 0, 0)
	add_child_autoqfree(iron)
	assert_eq(iron.resource_yield, 4, "Small solid iron must keep its four-unit yield after ready")

func test_gorgon_swept_charge_hits_the_warning_lane_once() -> void:
	var boss: CharacterBody3D = BOSS_SCENE.instantiate()
	add_child_autoqfree(boss)
	boss.set_physics_process(false)
	var target: DamageTarget = DamageTarget.new()
	add_child_autoqfree(target)
	target.global_position = Vector3(0.0, 0.9, -4.0)
	boss.target_player = target
	boss.start_telegraph(Vector3.FORWARD)
	boss.current_state = boss.BossState.CHARGING
	boss.charge_time_remaining = 0.5
	boss.charge_previous_position = Vector3.ZERO
	boss.global_position = Vector3(0.0, 0.0, -6.0)
	boss.post_charge_collision_check()
	assert_eq(target.damage_received, boss.charge_damage, "Swept damage must include targets crossed between physics frames")
	boss.post_charge_collision_check()
	assert_eq(target.damage_received, boss.charge_damage, "Each charge hits the same player only once")

func test_gorgon_charge_damage_matches_warning_bounds() -> void:
	var boss: CharacterBody3D = BOSS_SCENE.instantiate()
	add_child_autoqfree(boss)
	boss.set_physics_process(false)
	boss.start_telegraph(Vector3.RIGHT)
	var warning_mesh: BoxMesh = boss.telegraph_mesh.mesh as BoxMesh
	assert_almost_eq(warning_mesh.size.x, boss.charge_half_width * 2.0, 0.001)
	assert_almost_eq(warning_mesh.size.z, boss.charge_distance + boss.charge_half_width * 2.0, 0.001)
	assert_true(boss._is_in_charge_sweep(Vector3(5.0, 0.9, 1.5), Vector3(4, 0, 0), Vector3(6, 0, 0)))
	assert_false(boss._is_in_charge_sweep(Vector3(5.0, 0.9, 1.8), Vector3(4, 0, 0), Vector3(6, 0, 0)))
	assert_false(boss._is_in_charge_sweep(Vector3(19.0, 0.9, 0), Vector3(14, 0, 0), Vector3(16, 0, 0)))
	assert_false(boss._is_in_charge_sweep(Vector3(5.0, 5.0, 0), Vector3(4, 0, 0), Vector3(6, 0, 0)))

func test_gorgon_warning_projects_the_same_lane_onto_voxel_tops() -> void:
	var terrain: StairTerrain = StairTerrain.new()
	autofree(terrain)
	var warning: ArrayMesh = ChargeWarning.create_mesh(Vector3(-2.0, 0.0, 0.0), Vector3.RIGHT, 16.0, 1.65, terrain)
	assert_eq(warning.get_surface_count(), 1)
	var vertices: PackedVector3Array = warning.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lower_surface_seen: bool = false
	var upper_surface_seen: bool = false
	for vertex: Vector3 in vertices:
		assert_between(vertex.x, -1.65 - 0.001, 1.65 + 0.001, "Projected warning must keep its damaging width")
		assert_between(vertex.z, -8.0 - 1.65 - 0.001, 8.0 + 1.65 + 0.001, "Projected warning must keep its damaging length")
		lower_surface_seen = lower_surface_seen or is_equal_approx(vertex.y, 0.0)
		upper_surface_seen = upper_surface_seen or is_equal_approx(vertex.y, 1.0)
	assert_true(lower_surface_seen and upper_surface_seen, "Warning must remain visible on both stair surfaces")

func test_first_wave_opens_with_a_group_and_replenishes_two_enemies() -> void:
	_box_ground(Vector3(0.0, -0.5, 0.0), Vector3(100.0, 1.0, 100.0))
	var target: DamageTarget = DamageTarget.new()
	target.add_to_group("player")
	add_child_autoqfree(target)
	target.global_position = Vector3(0.0, 0.9, 0.0)
	var director: WaveDirector = WaveDirector.new()
	add_child_autoqfree(director)
	director.set_process(false)
	director.player = target
	await wait_physics_frames(2)
	var registry: Node = get_node("/root/EntityRegistry")
	director._on_phase_changed(true, 1)
	assert_eq(registry.get_enemy_count(), 6, "First night immediately opens with six threats")
	director._process(1.01)
	assert_eq(registry.get_enemy_count(), 8, "Night pressure replenishes in pairs")
	for enemy: Node in registry.get_enemies().duplicate():
		autoqfree(enemy)

func test_opening_group_still_respects_boss_minion_limit() -> void:
	_box_ground(Vector3(0.0, -0.5, 0.0), Vector3(100.0, 1.0, 100.0))
	var target: DamageTarget = DamageTarget.new()
	target.add_to_group("player")
	add_child_autoqfree(target)
	target.global_position = Vector3(0.0, 0.9, 0.0)
	var boss: CharacterBody3D = BOSS_SCENE.instantiate()
	add_child_autoqfree(boss)
	boss.global_position = Vector3(40, 0, 40)
	boss.set_physics_process(false)
	var director: WaveDirector = WaveDirector.new()
	add_child_autoqfree(director)
	director.set_process(false)
	director.player = target
	await wait_physics_frames(2)
	var registry: Node = get_node("/root/EntityRegistry")
	director._on_phase_changed(true, 10)
	assert_eq(registry.get_enemy_count(), 4, "Boss fight keeps three minions plus the boss")
	director._process(1.01)
	assert_eq(registry.get_enemy_count(), 4, "Replenishment must not bypass boss fight limit")
	for enemy: Node in registry.get_enemies().duplicate():
		if enemy != boss:
			autoqfree(enemy)

func test_boss_night_does_not_end_when_its_normal_timer_expires() -> void:
	var cycle: EncounterCycle = EncounterCycle.new()
	add_child_autoqfree(cycle)
	cycle.set_process(false)
	cycle.current_day = 10
	cycle.is_night = true
	cycle.time_left = 0.1
	var boss: CharacterBody3D = BOSS_SCENE.instantiate()
	add_child_autoqfree(boss)
	boss.set_physics_process(false)
	cycle._process(1.0)
	assert_true(cycle.is_night, "Boss must survive the 120-second timer and remain fightable")
	assert_eq(cycle.time_left, 0.0, "Boss overtime must not show a negative countdown")
	assert_eq(cycle.dawn_count, 0)
	boss.die()
	assert_eq(cycle.dawn_count, 1, "Defeating Gorgon completes night ten immediately")
	assert_false(cycle.is_night)
	boss.die()
	assert_eq(cycle.dawn_count, 1, "Repeated damage/death cannot duplicate boss completion")

func test_normal_night_still_ends_after_120_seconds() -> void:
	var cycle: EncounterCycle = EncounterCycle.new()
	add_child_autoqfree(cycle)
	cycle.set_process(false)
	cycle.is_night = true
	cycle.time_left = 120.0
	cycle._process(119.0)
	assert_true(cycle.is_night)
	cycle._process(1.0)
	assert_false(cycle.is_night)
	assert_eq(cycle.time_left, 180.0)

func test_night_ten_spawns_gorgon_without_debug_input() -> void:
	_box_ground(Vector3(0.0, -0.5, 0.0), Vector3(100.0, 1.0, 100.0))
	var main: Node3D = MainScript.new()
	var target: DamageTarget = DamageTarget.new()
	target.name = "Player"
	target.add_to_group("player")
	main.add_child(target)
	add_child_autoqfree(main)
	await wait_physics_frames(2)
	main._on_night_started(9)
	await wait_process_frames(1)
	var registry: Node = get_node("/root/EntityRegistry")
	assert_false(registry.has_active_boss(), "Ordinary nights should keep their normal enemies")
	main._on_night_started(10)
	await wait_process_frames(2)
	assert_true(registry.has_active_boss(), "Canonical wave-ten boss must appear from the phase event")
	assert_false(main.spawn_boss_gorgon(), "The phase event and debug hotkey cannot duplicate an active boss")

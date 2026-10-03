extends GutTest

class Target extends Node3D:
	var hits: int = 0
	var total_damage: float = 0.0
	func receive(amount: float, _knockback: Vector3, _kind: String, _attacker: Node) -> void:
		hits += 1
		total_damage += amount

func before_each() -> void:
	get_node("/root/EntityRegistry").clear()

func after_each() -> void:
	for child: Node in get_children():
		if child is EliteSkillHazard:
			(child as EliteSkillHazard).cancel()
		elif child.scene_file_path == "res://scenes/floating_text.tscn":
			child.queue_free()
	get_node("/root/EntityRegistry").clear()
	await get_tree().process_frame

func _target(point: Vector3 = Vector3(0.0, 0.9, -3.0)) -> Target:
	var result: Target = Target.new()
	result.add_to_group("player")
	var hurtbox: HurtboxArea = HurtboxArea.new()
	hurtbox.name = "Hurtbox"
	result.add_child(hurtbox)
	hurtbox.damaged.connect(result.receive)
	add_child_autoqfree(result)
	result.global_position = point
	return result

func _actor(id: String, target: Node3D) -> EnemyBase:
	var spec: EliteSkillSpec = EliteSkillCatalog.create_spec(id)
	var enemy: EnemyBase = (load(spec.scene_path) as PackedScene).instantiate() as EnemyBase
	add_child_autoqfree(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = Vector3(0.0, enemy.half_height, 0.0)
	enemy.target_player = target
	EliteSkillController.attach(enemy, id, func(_x: int, _z: int) -> int: return 0)
	return enemy

func _hazard(enemy: EnemyBase, target: Node3D, mode: EliteSkillHazard.Mode, shape: BossAttackSpec.Shape, point: Vector3 = Vector3.ZERO) -> EliteSkillHazard:
	var spec: EliteSkillSpec = enemy.elite_skill_controller.spec
	var hazard: EliteSkillHazard = EliteSkillHazard.new()
	add_child_autoqfree(hazard)
	hazard.setup(spec, enemy, target, mode, spec.footprint(shape, spec.radius if shape == BossAttackSpec.Shape.CIRCLE else spec.reach), point, Vector3.FORWARD, func(_x: int, _z: int) -> int: return 0)
	hazard.set_physics_process(false)
	return hazard

func test_all_nine_catalogue_entries_have_actual_scene_and_canonical_page() -> void:
	var seen: PackedStringArray = []
	for entry: EliteSkillCatalog.Entry in EliteSkillCatalog.entries():
		assert_false(seen.has(entry.id))
		seen.append(entry.id)
		assert_true(ResourceLoader.exists(entry.scene_path))
		assert_true(entry.source_page.begins_with("https://chatgpt.com/space/page_"))
		assert_eq(EliteSkillCatalog.create_spec(entry.id).source_page, entry.source_page)
	assert_eq(seen.size(), 9)
	assert_null(EliteSkillCatalog.create_spec("invented"))
	assert_eq(EliteSkillCatalog.ids_for_scene(EliteSkillCatalog.GRUNT).size(), 3)

func test_triple_throw_locks_three_current_positions_and_never_arms_traps() -> void:
	var target: Target = _target()
	var enemy: EnemyBase = _actor("triple_throw", target)
	var controller: EliteSkillController = enemy.elite_skill_controller
	assert_true(controller.start_attack())
	controller.hazards[0].set_physics_process(false)
	var first_point: Vector3 = controller.hazards[0].global_position
	target.position.x = 2.0
	controller.advance(controller.spec.interval)
	controller.hazards[1].set_physics_process(false)
	target.position.x = 4.0
	controller.advance(controller.spec.interval)
	assert_eq(controller.hazards.size(), 3)
	assert_eq(controller.hazards[0].global_position, first_point)
	assert_eq(controller.hazards[1].global_position.x, 2.0)
	assert_eq(controller.hazards[2].global_position.x, 4.0)
	for hazard: EliteSkillHazard in controller.hazards:
		assert_eq(hazard.mode, EliteSkillHazard.Mode.LOB)
		hazard.set_physics_process(false)
		hazard._physics_process(controller.spec.flight_time)
		hazard._physics_process(0.3)
		assert_null(hazard._solid)
		assert_true(hazard.cancelled)

func test_triple_throw_target_freed_between_throws_returns_and_preserves_released_lob() -> void:
	var target: Target = _target()
	var enemy: EnemyBase = _actor("triple_throw", target)
	var controller: EliteSkillController = enemy.elite_skill_controller
	assert_true(controller.start_attack())
	var released: EliteSkillHazard = controller.hazards[0]
	released.set_physics_process(false)
	assert_eq(controller._throws, 1)
	target.free()
	# Run this regression under an external process deadline: the old while
	# loop never returned after _throw_lob rejected the freed target.
	controller.advance(controller.spec.interval)
	assert_eq(controller.state, EliteSkillController.State.RECOVERY)
	assert_eq(controller._throws, 1)
	assert_eq(controller.hazards.size(), 1)
	assert_false(released.cancelled)
	controller.advance(controller.spec.recovery + 0.01)
	assert_eq(controller.state, EliteSkillController.State.COOLDOWN)
	assert_false(controller.advance(controller.spec.cooldown + 0.01))
	assert_eq(controller.cast_count, 1, "No replacement target or further throws are invented")
	released._physics_process(controller.spec.flight_time + 0.3)
	assert_true(released.cancelled, "The released projectile finishes safely without its old target")

func test_triple_throw_rejects_queued_or_detached_target_without_new_releases() -> void:
	for removal: String in ["queued", "detached"]:
		var target: Target = _target()
		var enemy: EnemyBase = _actor("triple_throw", target)
		var controller: EliteSkillController = enemy.elite_skill_controller
		controller.start_attack()
		controller.hazards[0].set_physics_process(false)
		if removal == "queued":
			target.queue_free()
		else:
			remove_child(target)
		controller.advance(controller.spec.interval)
		assert_eq(controller._throws, 1)
		assert_eq(controller.state, EliteSkillController.State.RECOVERY)
		assert_eq(controller.hazards.size(), 1)
		if removal == "detached":
			target.free()

func test_fire_terminal_callback_stops_remaining_cadence_doses_and_visual_updates() -> void:
	var target: Target = _target(Vector3(0.0, 0.9, -2.0))
	var enemy: EnemyBase = _actor("fire_breath", target)
	var controller: EliteSkillController = enemy.elite_skill_controller
	controller.start_attack()
	var hazard: EliteSkillHazard = controller.hazards[0]
	hazard.set_physics_process(false)
	hazard.hit_confirmed.connect(func(_target: Node3D, _amount: float) -> void: controller.cancel_attack())
	hazard._physics_process(hazard.warning_duration + 0.5)
	assert_true(hazard.cancelled)
	assert_eq(target.hits, 1, "The first terminal callback stops later doses in this same frame")
	assert_almost_eq(target.total_damage, hazard.spec.damage * 0.1, 0.001)
	hazard._physics_process(10.0)
	assert_eq(target.hits, 1, "Cancellation cannot flush residual or future exposure")

func test_released_blade_owner_free_during_first_hit_stops_second_pass() -> void:
	var target: Target = _target(Vector3(0.0, 0.9, -4.0))
	var enemy: EnemyBase = _actor("returning_blade", target)
	var controller: EliteSkillController = enemy.elite_skill_controller
	controller.start_attack()
	var hazard: EliteSkillHazard = controller.hazards[0]
	hazard.set_physics_process(false)
	hazard.hit_confirmed.connect(func(_target: Node3D, _amount: float) -> void: enemy.free())
	hazard._physics_process(hazard.warning_duration + 2.0 * hazard.spec.reach / hazard.spec.speed + hazard.spec.interval + 0.1)
	assert_false(is_instance_valid(enemy))
	assert_true(hazard.cancelled)
	assert_eq(target.hits, 1)
	assert_eq(hazard.hit_count, 1)

func test_spit_contact_callback_can_remove_owner_or_target_without_stale_access() -> void:
	for removal: String in ["owner", "target"]:
		var target: Target = _target(Vector3(0.0, 0.9, -4.0))
		var enemy: EnemyBase = _actor("spit_puddle", target)
		var controller: EliteSkillController = enemy.elite_skill_controller
		controller.start_attack()
		var hazard: EliteSkillHazard = controller.hazards[0]
		hazard.set_physics_process(false)
		if removal == "owner":
			hazard.hit_confirmed.connect(func(_target: Node3D, _amount: float) -> void: enemy.free())
		else:
			hazard.hit_confirmed.connect(func(_target: Node3D, _amount: float) -> void: target.free())
		hazard._physics_process(hazard.warning_duration + 0.6)
		assert_eq(hazard.hit_count, 1)
		if removal == "owner":
			assert_true(hazard.cancelled)
			assert_false(hazard._spit_landed, "A terminal impact cannot create a new puddle")
		else:
			assert_true(hazard._spit_landed)
			assert_false(is_instance_valid(target))
			hazard._physics_process(hazard.spec.lifetime + 0.1)
			assert_true(hazard.cancelled)

func test_backswing_both_front_sectors_exist_from_start_and_hit_separately() -> void:
	var target: Target = _target(Vector3(0.0, 0.9, -2.0))
	var enemy: EnemyBase = _actor("backswing", target)
	var controller: EliteSkillController = enemy.elite_skill_controller
	controller.start_attack()
	assert_eq(controller.hazards.size(), 2)
	var first: EliteSkillHazard = controller.hazards[0]
	var second: EliteSkillHazard = controller.hazards[1]
	first.set_physics_process(false)
	second.set_physics_process(false)
	assert_true(second._visual.visible)
	assert_eq(second.footprint.reach, first.footprint.reach * 0.75)
	assert_eq(first.direction, second.direction, "Reverse is the swing motion, not a rear-facing second footprint")
	first._physics_process(first.warning_duration - 0.01)
	second._physics_process(first.warning_duration - 0.01)
	assert_eq(target.hits, 0)
	first._physics_process(0.02)
	assert_eq(target.hits, 1)
	second._physics_process(controller.spec.interval + 0.02)
	assert_eq(target.hits, 2)

func test_returning_blade_hits_actual_out_and_back_passes_but_safe_lane_does_not() -> void:
	var target: Target = _target(Vector3(0.0, 0.9, -4.0))
	var enemy: EnemyBase = _actor("returning_blade", target)
	var hazard: EliteSkillHazard = _hazard(enemy, target, EliteSkillHazard.Mode.BLADE, BossAttackSpec.Shape.LINE)
	hazard._physics_process(0.99)
	assert_eq(target.hits, 0)
	for step: int in range(120):
		hazard._physics_process(1.0 / 60.0)
	assert_eq(target.hits, 2)
	assert_eq(hazard._hit_passes.size(), 2)
	assert_almost_eq(target.total_damage, hazard.spec.damage * 2.0, 0.01)

func test_mine_arming_is_not_an_explosion_then_step_triggers_once() -> void:
	var target: Target = _target(Vector3(3.0, 0.9, 0.0))
	var enemy: EnemyBase = _actor("foot_mine", target)
	var hazard: EliteSkillHazard = _hazard(enemy, target, EliteSkillHazard.Mode.MINE, BossAttackSpec.Shape.CIRCLE)
	hazard._physics_process(hazard.spec.windup)
	assert_true(hazard._armed)
	assert_eq(target.hits, 0)
	hazard._physics_process(0.1)
	assert_eq(target.hits, 0)
	target.position.x = 0.0
	hazard._physics_process(0.1)
	hazard._physics_process(0.2)
	assert_eq(target.hits, 1)
	assert_true(hazard.cancelled)

func test_unstepped_mine_expires_without_damage() -> void:
	var target: Target = _target(Vector3(5.0, 0.9, 0.0))
	var enemy: EnemyBase = _actor("foot_mine", target)
	var hazard: EliteSkillHazard = _hazard(enemy, target, EliteSkillHazard.Mode.MINE, BossAttackSpec.Shape.CIRCLE)
	hazard._physics_process(hazard.spec.windup)
	hazard._physics_process(hazard.spec.lifetime + 0.1)
	assert_true(hazard.cancelled)
	assert_eq(target.hits, 0)

func test_spike_hits_emergence_once_and_owns_a_temporary_physical_nav_obstacle() -> void:
	var target: Target = _target(Vector3(0.5, 0.9, 0.5))
	var enemy: EnemyBase = _actor("underground_spike", target)
	var hazard: EliteSkillHazard = _hazard(enemy, target, EliteSkillHazard.Mode.SPIKE, BossAttackSpec.Shape.CIRCLE, Vector3(0.5, 0.0, 0.5))
	hazard._physics_process(hazard.spec.windup)
	assert_eq(target.hits, 1)
	assert_true(is_instance_valid(hazard._solid))
	assert_eq(hazard._solid.collision_layer, 1)
	assert_true(get_node("/root/EntityRegistry").monster_flowfield.blocked_cells.has(Vector2i.ZERO))
	for step: int in range(20):
		hazard._physics_process(0.05)
	assert_eq(target.hits, 1, "An emerged spike never deals repeated proximity damage")
	hazard._physics_process(hazard.spec.lifetime)
	assert_false(get_node("/root/EntityRegistry").monster_flowfield.blocked_cells.has(Vector2i.ZERO))

func test_fire_damage_is_continuous_for_exact_duration_and_direction_is_locked() -> void:
	var target: Target = _target(Vector3(0.0, 0.9, -2.0))
	var enemy: EnemyBase = _actor("fire_breath", target)
	var hazard: EliteSkillHazard = _hazard(enemy, target, EliteSkillHazard.Mode.FIRE, BossAttackSpec.Shape.SECTOR)
	hazard._physics_process(hazard.spec.windup)
	assert_eq(target.total_damage, 0.0)
	for step: int in range(16):
		hazard._physics_process(0.1)
	assert_almost_eq(target.total_damage, hazard.spec.damage * hazard.spec.duration, 0.01)
	assert_gt(target.hits, 10, "This is integrated active DPS rather than one explosion")
	assert_eq(hazard.direction, Vector3.FORWARD)

func test_fire_exit_to_side_stops_damage_without_reaiming() -> void:
	var target: Target = _target(Vector3(0.0, 0.9, -2.0))
	var enemy: EnemyBase = _actor("fire_breath", target)
	var hazard: EliteSkillHazard = _hazard(enemy, target, EliteSkillHazard.Mode.FIRE, BossAttackSpec.Shape.SECTOR)
	hazard._physics_process(hazard.spec.windup + 0.2)
	var damage_before: float = target.total_damage
	target.position = Vector3(3.0, 0.9, 0.0)
	hazard._physics_process(0.5)
	assert_eq(target.total_damage, damage_before)
	assert_eq(hazard.direction, Vector3.FORWARD)

func test_straight_spit_hits_then_puddle_damages_at_impact_position() -> void:
	var target: Target = _target(Vector3(0.0, 0.9, -4.0))
	var enemy: EnemyBase = _actor("spit_puddle", target)
	var hazard: EliteSkillHazard = _hazard(enemy, target, EliteSkillHazard.Mode.SPIT, BossAttackSpec.Shape.LINE)
	hazard._physics_process(hazard.spec.windup)
	for step: int in range(25):
		hazard._physics_process(1.0 / 60.0)
	assert_true(hazard._spit_landed)
	assert_lt(absf(hazard._spit_land_position.z - target.position.z), hazard.spec.width * 0.5 + 0.01, "Puddle originates at projectile contact, not a teleport to target center")
	assert_eq(hazard.direction, Vector3.FORWARD)
	assert_gt(target.total_damage, hazard.spec.damage)
	var before: float = target.total_damage
	target.position.x = 4.0
	hazard._physics_process(0.5)
	assert_lte(target.total_damage - before, hazard.spec.residue_damage_per_second * 0.1, "Exit may settle only already-accrued sub-tick exposure")
	var settled: float = target.total_damage
	hazard._physics_process(0.5)
	assert_eq(target.total_damage, settled, "Remaining outside creates no new exposure")

func test_lunge_damage_requires_moving_body_contact_and_recovery_is_a_pause() -> void:
	var target: Target = _target(Vector3(0.0, 0.9, -5.0))
	var enemy: EnemyBase = _actor("short_lunge", target)
	var hazard: EliteSkillHazard = _hazard(enemy, target, EliteSkillHazard.Mode.LUNGE, BossAttackSpec.Shape.LINE)
	hazard._physics_process(0.1)
	assert_eq(target.hits, 0, "Standing inside the long route is safe before the mob arrives")
	enemy.position.z = -6.0
	hazard._physics_process(hazard.spec.windup + 0.1)
	assert_eq(target.hits, 1, "Fast real body sweep catches the contact between ticks")
	var controller: EliteSkillController = enemy.elite_skill_controller
	controller.start_attack()
	controller.advance(controller.spec.windup)
	controller.advance(controller.spec.reach / controller.spec.speed + 0.01)
	assert_eq(controller.state, EliteSkillController.State.RECOVERY)
	assert_eq(enemy.desired_velocity_h, Vector3.ZERO)
	assert_gt(controller.timer, 0.0)

func test_elite_stun_halves_duration_and_cancels_pending_damage() -> void:
	var target: Target = _target()
	var enemy: EnemyBase = _actor("foot_mine", target)
	var controller: EliteSkillController = enemy.elite_skill_controller
	controller.start_attack()
	var hazard: EliteSkillHazard = controller.hazards[0]
	hazard.set_physics_process(false)
	enemy.apply_stun(4.0)
	assert_almost_eq(enemy.status_effects.stuns[0].remaining, 2.0, 0.001)
	assert_true(hazard.cancelled)
	hazard._physics_process(10.0)
	assert_eq(target.hits, 0)
	assert_eq(controller.hazards.size(), 0)

func test_wall_resource_and_overlapping_spikes_never_clear_each_other() -> void:
	var registry: Node = get_node("/root/EntityRegistry")
	var wall: Node3D = Node3D.new()
	wall.add_to_group("walls")
	add_child_autoqfree(wall)
	var resource: Node3D = Node3D.new()
	add_child_autoqfree(resource)
	var first: Node3D = Node3D.new()
	add_child_autoqfree(first)
	var second: Node3D = Node3D.new()
	add_child_autoqfree(second)
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	registry.register_building(wall)
	registry.register_resource(resource)
	registry.register_temporary_obstacle(first, cells)
	registry.register_temporary_obstacle(second, cells)
	registry.unregister_building(wall)
	registry.unregister_resource(resource)
	assert_true(registry.monster_flowfield.blocked_cells.has(Vector2i.ZERO))
	registry.unregister_temporary_obstacle(first)
	assert_true(registry.monster_flowfield.blocked_cells.has(Vector2i.ZERO))
	registry.unregister_temporary_obstacle(second)
	assert_false(registry.monster_flowfield.blocked_cells.has(Vector2i.ZERO))
	registry.register_building(wall)
	registry.register_temporary_obstacle(first, cells)
	registry.unregister_temporary_obstacle(first)
	assert_true(registry.monster_flowfield.blocked_cells.has(Vector2i.ZERO), "Removing a spike preserves a wall still present")

func _registry_owner(cell: Vector2i = Vector2i.ZERO, wall: bool = false) -> Node3D:
	var owner: Node3D = Node3D.new()
	owner.position = Vector3(float(cell.x) + 0.2, 0.0, float(cell.y) + 0.2)
	if wall:
		owner.add_to_group("walls")
	add_child_autoqfree(owner)
	return owner

func test_duplicate_registrations_and_removals_preserve_each_remaining_cell_owner() -> void:
	var registry: Node = get_node("/root/EntityRegistry")
	var first_wall: Node3D = _registry_owner(Vector2i.ZERO, true)
	var last_wall: Node3D = _registry_owner(Vector2i.ZERO, true)
	var first_resource: Node3D = _registry_owner()
	var last_resource: Node3D = _registry_owner()
	var spike: Node3D = _registry_owner()
	var duplicated_cells: Array[Vector2i] = [Vector2i.ZERO, Vector2i.ZERO]
	for repeat: int in range(3):
		registry.register_building(first_wall)
		registry.register_resource(first_resource)
		registry.register_temporary_obstacle(spike, duplicated_cells)
	registry.register_building(last_wall)
	registry.register_resource(last_resource)
	registry.unregister_building(first_wall)
	registry.unregister_building(first_wall)
	registry.unregister_resource(first_resource)
	registry.unregister_resource(first_resource)
	registry.unregister_temporary_obstacle(spike)
	registry.unregister_temporary_obstacle(spike)
	assert_true(registry.monster_flowfield.blocked_cells.has(Vector2i.ZERO))
	registry.unregister_building(last_wall)
	assert_true(registry.monster_flowfield.blocked_cells.has(Vector2i.ZERO), "The last resource still owns the shared cell")
	registry.unregister_resource(last_resource)
	assert_false(registry.monster_flowfield.blocked_cells.has(Vector2i.ZERO), "Duplicate callbacks cannot leave leaked occupancy after the final owner is removed")

func test_wall_moves_between_shared_cells_without_clearing_resource_or_spike() -> void:
	var registry: Node = get_node("/root/EntityRegistry")
	var origin: Vector2i = Vector2i.ZERO
	var middle: Vector2i = Vector2i(-2, 3)
	var destination: Vector2i = Vector2i(4, -1)
	var wall: Node3D = _registry_owner(origin, true)
	var resource: Node3D = _registry_owner(origin)
	var destination_resource: Node3D = _registry_owner(destination)
	var spike: Node3D = _registry_owner(origin)
	var spike_cells: Array[Vector2i] = [origin]
	registry.register_building(wall)
	registry.register_resource(resource)
	registry.register_resource(destination_resource)
	registry.register_temporary_obstacle(spike, spike_cells)
	wall.position = Vector3(-1.8, 0.0, 3.2)
	registry.register_building(wall)
	registry.register_building(wall)
	assert_true(registry.monster_flowfield.blocked_cells.has(origin))
	assert_true(registry.monster_flowfield.blocked_cells.has(middle))
	registry.unregister_resource(resource)
	assert_true(registry.monster_flowfield.blocked_cells.has(origin))
	registry.unregister_temporary_obstacle(spike)
	assert_false(registry.monster_flowfield.blocked_cells.has(origin))
	wall.position = Vector3(4.2, 0.0, -0.8)
	registry.register_building(wall)
	assert_false(registry.monster_flowfield.blocked_cells.has(middle), "Moving the final owner clears only its previous cell")
	registry.unregister_building(wall)
	assert_true(registry.monster_flowfield.blocked_cells.has(destination), "A destination resource survives wall removal")
	registry.unregister_resource(destination_resource)
	assert_false(registry.monster_flowfield.blocked_cells.has(destination))

func test_resource_move_preserves_other_resource_and_wall_then_clears_final_owners() -> void:
	var registry: Node = get_node("/root/EntityRegistry")
	var moving: Node3D = _registry_owner()
	var remaining: Node3D = _registry_owner()
	var wall: Node3D = _registry_owner(Vector2i.ZERO, true)
	registry.register_resource(moving)
	registry.register_resource(remaining)
	registry.register_building(wall)
	moving.position.x = 2.2
	registry.register_resource(moving)
	registry.register_resource(moving)
	registry.unregister_resource(remaining)
	assert_true(registry.monster_flowfield.blocked_cells.has(Vector2i.ZERO))
	registry.unregister_building(wall)
	assert_false(registry.monster_flowfield.blocked_cells.has(Vector2i.ZERO))
	assert_true(registry.monster_flowfield.blocked_cells.has(Vector2i(2, 0)))
	registry.unregister_resource(moving)
	registry.unregister_resource(moving)
	assert_false(registry.monster_flowfield.blocked_cells.has(Vector2i(2, 0)))

func test_clear_resets_occupancy_and_late_old_owner_callbacks_cannot_remove_new_owner() -> void:
	var registry: Node = get_node("/root/EntityRegistry")
	var wall: Node3D = _registry_owner(Vector2i.ZERO, true)
	var resource: Node3D = _registry_owner()
	var spike: Node3D = _registry_owner()
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	registry.register_building(wall)
	registry.register_resource(resource)
	registry.register_temporary_obstacle(spike, cells)
	registry.clear()
	assert_true(registry.monster_flowfield.blocked_cells.is_empty())
	var replacement: Node3D = _registry_owner()
	registry.register_resource(replacement)
	registry.unregister_building(wall)
	registry.unregister_resource(resource)
	registry.unregister_temporary_obstacle(spike)
	assert_true(registry.monster_flowfield.blocked_cells.has(Vector2i.ZERO))
	registry.unregister_resource(replacement)
	assert_false(registry.monster_flowfield.blocked_cells.has(Vector2i.ZERO), "No old resource/building/temp count survives clear")
	registry.register_building(wall)
	registry.unregister_building(wall)
	assert_false(registry.monster_flowfield.blocked_cells.has(Vector2i.ZERO), "An old owner can register anew without stale counts")

func test_nearest_building_cleanup_releases_freed_wall_but_preserves_resource() -> void:
	var registry: Node = get_node("/root/EntityRegistry")
	var dead_wall: Node3D = _registry_owner(Vector2i.ZERO, true)
	var live_wall: Node3D = _registry_owner(Vector2i(2, 0), true)
	var resource: Node3D = _registry_owner()
	registry.register_building(dead_wall)
	registry.register_building(live_wall)
	registry.register_resource(resource)
	dead_wall.free()
	assert_eq(registry.get_nearest_building(Vector3.ZERO), live_wall)
	assert_true(registry.monster_flowfield.blocked_cells.has(Vector2i.ZERO))
	registry.unregister_resource(resource)
	assert_false(registry.monster_flowfield.blocked_cells.has(Vector2i.ZERO), "Nearest-building cleanup removed the invalid wall's cell ownership")
	registry.unregister_building(live_wall)
	assert_true(registry.monster_flowfield.blocked_cells.is_empty())

func test_leap_moves_actual_character_along_arc_and_keeps_new_position() -> void:
	var target: Target = _target(Vector3(0.0, 0.9, -4.0))
	var enemy: EnemyBase = _actor("leap_strike", target)
	var controller: EliteSkillController = enemy.elite_skill_controller
	controller.start_attack()
	for hazard: EliteSkillHazard in controller.hazards:
		hazard.set_physics_process(false)
	target.position.x = 5.0
	controller.advance(controller.spec.windup)
	controller.advance(controller.spec.flight_time * 0.5)
	assert_true(controller.uses_custom_motion())
	assert_gt(enemy.global_position.y, 2.0)
	assert_almost_eq(enemy.global_position.z, -2.0, 0.02)
	controller.advance(controller.spec.flight_time * 0.5)
	assert_almost_eq(enemy.global_position.z, -4.0, 0.02)
	assert_almost_eq(enemy.global_position.x, 0.0, 0.02, "Landing was locked before the target moved")
	assert_eq(controller.state, EliteSkillController.State.RECOVERY)
	assert_true(controller.uses_custom_motion(), "The final landing frame still bypasses ordinary gravity")
	controller.advance(0.01)
	assert_false(controller.uses_custom_motion())
	assert_almost_eq(enemy.global_position.z, -4.0, 0.02)

func test_invalid_building_cleanup_preserves_active_spike_cell_ownership() -> void:
	var registry: Node = get_node("/root/EntityRegistry")
	var wall: Node3D = Node3D.new()
	wall.add_to_group("walls")
	add_child(wall)
	var spike: Node3D = Node3D.new()
	add_child_autoqfree(spike)
	var cells: Array[Vector2i] = [Vector2i.ZERO]
	registry.register_building(wall)
	registry.register_temporary_obstacle(spike, cells)
	wall.free()
	registry.get_buildings()
	assert_true(registry.monster_flowfield.blocked_cells.has(Vector2i.ZERO), "Cleanup of a freed building cannot erase the surviving spike")
	registry.unregister_temporary_obstacle(spike)
	assert_false(registry.monster_flowfield.blocked_cells.has(Vector2i.ZERO))

func test_owner_death_cancels_every_pending_effect_and_temp_blocker() -> void:
	var target: Target = _target(Vector3(0.5, 0.9, 0.5))
	var enemy: EnemyBase = _actor("underground_spike", target)
	var controller: EliteSkillController = enemy.elite_skill_controller
	controller.start_attack()
	var hazard: EliteSkillHazard = controller.hazards[0]
	hazard.set_physics_process(false)
	hazard._physics_process(controller.spec.windup)
	assert_true(get_node("/root/EntityRegistry").monster_flowfield.blocked_cells.has(Vector2i.ZERO))
	enemy.die()
	assert_true(hazard.cancelled)
	assert_eq(controller.hazards.size(), 0)
	assert_false(get_node("/root/EntityRegistry").monster_flowfield.blocked_cells.has(Vector2i.ZERO))

func test_direct_owner_free_releases_sidecar_hazards_synchronously() -> void:
	var target: Target = _target()
	var enemy: EnemyBase = _actor("triple_throw", target)
	var controller: EliteSkillController = enemy.elite_skill_controller
	controller.start_attack()
	var hazard: EliteSkillHazard = controller.hazards[0]
	hazard.set_physics_process(false)
	enemy.free()
	assert_true(hazard.cancelled)
	hazard._physics_process(10.0)
	assert_eq(target.hits, 0)

func test_stun_preserves_released_lob_but_prevents_remaining_throws() -> void:
	var target: Target = _target()
	var enemy: EnemyBase = _actor("triple_throw", target)
	var controller: EliteSkillController = enemy.elite_skill_controller
	controller.start_attack()
	var lob: EliteSkillHazard = controller.hazards[0]
	lob.set_physics_process(false)
	enemy.apply_stun(4.0)
	assert_false(lob.cancelled)
	assert_eq(controller.hazards.size(), 1)
	controller.advance(2.0)
	assert_eq(controller._throws, 1)
	lob._physics_process(controller.spec.flight_time)
	assert_eq(target.hits, 1, "The already-released projectile still lands while its shooter is stunned")

func test_stun_keeps_released_blade_but_cancels_unreleased_blade() -> void:
	var target: Target = _target(Vector3(0.0, 0.9, -4.0))
	var enemy: EnemyBase = _actor("returning_blade", target)
	var controller: EliteSkillController = enemy.elite_skill_controller
	controller.start_attack()
	var blade: EliteSkillHazard = controller.hazards[0]
	blade.set_physics_process(false)
	blade._physics_process(controller.spec.windup + 0.1)
	enemy.apply_stun(2.0)
	assert_false(blade.cancelled)
	for step: int in range(120):
		blade._physics_process(1.0 / 60.0)
	assert_eq(target.hits, 2)
	enemy.status_effects.stuns.clear()
	controller.advance(0.0) # Drop completed projectile sidecars before the next cast.
	controller.start_attack()
	var pending: EliteSkillHazard = controller.hazards[0]
	pending.set_physics_process(false)
	enemy.apply_stun(2.0)
	assert_true(pending.cancelled)

func test_stun_keeps_armed_mine_but_death_removes_it() -> void:
	var target: Target = _target(Vector3(4.0, 0.9, 0.0))
	var enemy: EnemyBase = _actor("foot_mine", target)
	var controller: EliteSkillController = enemy.elite_skill_controller
	controller.start_attack()
	var mine: EliteSkillHazard = controller.hazards[0]
	mine.set_physics_process(false)
	mine._physics_process(controller.spec.windup)
	enemy.apply_stun(2.0)
	assert_false(mine.cancelled)
	enemy.die()
	assert_true(mine.cancelled)

func test_fire_cadence_preserves_total_at30_and144hz_without_per_frame_callbacks() -> void:
	for step: float in [1.0 / 30.0, 1.0 / 144.0]:
		var target: Target = _target(Vector3(0.0, 0.9, -2.0))
		var enemy: EnemyBase = _actor("fire_breath", target)
		var hazard: EliteSkillHazard = _hazard(enemy, target, EliteSkillHazard.Mode.FIRE, BossAttackSpec.Shape.SECTOR)
		hazard._physics_process(hazard.spec.windup)
		for frame: int in range(int(ceilf((hazard.spec.duration + 0.1) / step))):
			hazard._physics_process(step)
		assert_almost_eq(target.total_damage, hazard.spec.damage * hazard.spec.duration, 0.001)
		assert_lte(target.hits, 17, "Counterattack event count follows .1s cadence and contact boundaries, not physics Hz")

func test_spit_puddle_full_exposure_has_exact_total_and_bounded_pulse_count() -> void:
	var target: Target = _target(Vector3(0.0, 0.9, -4.0))
	var enemy: EnemyBase = _actor("spit_puddle", target)
	var hazard: EliteSkillHazard = _hazard(enemy, target, EliteSkillHazard.Mode.SPIT, BossAttackSpec.Shape.LINE)
	hazard._physics_process(hazard.spec.windup)
	for frame: int in range(240):
		hazard._physics_process(1.0 / 60.0)
	assert_almost_eq(target.total_damage, hazard.spec.damage + hazard.spec.residue_damage_per_second * hazard.spec.lifetime, 0.001)
	assert_lte(target.hits, 33)
	assert_true(hazard.cancelled)

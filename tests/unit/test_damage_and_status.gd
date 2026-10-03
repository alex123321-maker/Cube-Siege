extends GutTest

func test_breaking_shield_absorbs_overflow_and_limits_reflection() -> void:
	var receipt: DamageReceipt = DamageReceipt.resolve(1000.0, 100.0, 50.0, 0.1)
	assert_eq(receipt.health_loss, 0.0)
	assert_eq(receipt.shield_loss, 50.0)
	assert_eq(receipt.remaining_health, 100.0)
	assert_eq(receipt.reflection_base() * 0.2, 10.0)

func test_health_loss_is_clamped_for_overkill_life_steal() -> void:
	var receipt: DamageReceipt = DamageReceipt.resolve(1000.0, 30.0, 0.0)
	assert_eq(receipt.health_loss, 30.0)
	assert_eq(receipt.remaining_health, 0.0)

func test_slows_multiply_and_expire_independently() -> void:
	var statuses: StatusEffectState = StatusEffectState.new()
	statuses.apply_slow("a", 0.5, 5.0)
	statuses.apply_slow("b", 0.25, 10.0)
	assert_almost_eq(statuses.movement_multiplier(), 0.375, 0.0001)
	statuses.advance(5.0)
	assert_almost_eq(statuses.movement_multiplier(), 0.75, 0.0001)
	statuses.advance(5.0)
	assert_eq(statuses.movement_multiplier(), 1.0)

func test_same_source_refreshes_and_resistance_weakens_each_slow() -> void:
	var statuses: StatusEffectState = StatusEffectState.new()
	statuses.apply_slow("a", 0.5, 1.0)
	statuses.apply_slow("a", 0.5, 3.0)
	assert_eq(statuses.slows.size(), 1)
	assert_almost_eq(statuses.movement_multiplier(0.8), 0.9, 0.0001)
	statuses.advance(1.0)
	assert_eq(statuses.slows.size(), 1)

func test_enemy_death_keeps_an_invertible_transform_until_removal() -> void:
	var enemy: EnemyBase = EnemyBase.new()
	add_child_autoqfree(enemy)
	enemy.set_physics_process(false)
	var observed: Dictionary = {"removed": false, "determinant": 0.0}
	enemy.tree_exiting.connect(func() -> void:
		observed.removed = true
		observed.determinant = enemy.transform.basis.determinant()
	)
	enemy.current_health = 0.0
	enemy.die()
	await wait_seconds(0.4)
	assert_true(observed.removed)
	assert_gt(float(observed.determinant), 0.0, "Physics bodies must never reach a singular zero-scale basis during death")

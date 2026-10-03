extends GutTest

func test_catalogue_has_unique_implemented_ids_and_valid_acyclic_parents() -> void:
	var ids: Array[String] = []
	for definition: WarriorTalentDefinition in WarriorTalentCatalog.get_all():
		assert_false(ids.has(definition.id))
		ids.append(definition.id)
		assert_true(definition.implemented)
		assert_true(FileAccess.file_exists(definition.icon_path))
		assert_true(WarriorTalentCatalog.BRANCH_COLORS.has(definition.branch))
		if not definition.parent_id.is_empty():
			var parent: WarriorTalentDefinition = WarriorTalentCatalog.get_talent(definition.parent_id)
			assert_not_null(parent)
			assert_lt(parent.ring, definition.ring)
	assert_eq(ids.size(), 9)

func test_checkpoint_sequence_and_six_slot_limit() -> void:
	var build: WarriorRunBuild = WarriorRunBuild.new()
	build.initialize(WarriorTalentCatalog.TALENT_IDS)
	assert_true(build.offer_checkpoint(1, true))
	assert_false(build.offer_checkpoint(1, true), "Initial reward cannot duplicate")
	assert_false(build.offer_checkpoint(1))
	for wave: int in [0, 2, 5, 10, 15, 20]:
		if wave != 0:
			assert_true(build.offer_checkpoint(wave))
		var options: Array[WarriorTalentDefinition] = build.get_talent_options()
		assert_gt(options.size(), 0)
		assert_true(build.choose_talent(options[0].id, build.active_reward_id))
		await get_tree().process_frame
	assert_eq(build.selected_talents.size(), 6)
	assert_false(build.offer_checkpoint(25))
	assert_false(build.offer_checkpoint(30))
	assert_eq(build.active_reward_id, -1)

func test_small_and_empty_pools_have_spendable_focus() -> void:
	for count: int in range(4):
		var build: WarriorRunBuild = WarriorRunBuild.new()
		var pool: Array = WarriorTalentCatalog.STARTER_IDS.slice(0, count)
		build.initialize(pool)
		build.offer_checkpoint(1, true)
		assert_eq(build.get_talent_options().size(), count)
		assert_true(build.focus(build.active_reward_id))
		assert_eq(build.unspent_specialization_points, 2)
		assert_false(build.focus(), "A consumed reward cannot be taken twice")

func test_queue_preserves_rewards_and_rejects_stale_callback() -> void:
	var build: WarriorRunBuild = WarriorRunBuild.new()
	build.initialize(WarriorTalentCatalog.STARTER_IDS)
	build.offer_checkpoint(1, true)
	build.offer_checkpoint(2)
	build.offer_checkpoint(5)
	var first_id: int = build.active_reward_id
	assert_true(build.choose_talent(build.get_talent_options()[0].id, first_id))
	assert_false(build.focus(first_id), "Immediate double input cannot consume next reward")
	await get_tree().process_frame
	assert_gt(build.active_reward_id, first_id)
	assert_false(build.focus(first_id), "Old UI callback cannot consume a newer reward")
	assert_true(build.focus(build.active_reward_id))
	await get_tree().process_frame
	assert_true(build.focus(build.active_reward_id))
	await get_tree().process_frame
	assert_eq(build.active_reward_id, -1)
	assert_eq(build.unspent_specialization_points, 4)

func test_pool_snapshot_does_not_reroll_and_rejects_closed_talent() -> void:
	var build: WarriorRunBuild = WarriorRunBuild.new()
	build.initialize(["hot_blood", "unknown", "hot_blood"])
	build.offer_checkpoint(1, true)
	assert_eq(build.get_talent_options().size(), 1)
	assert_eq(build.get_talent_options()[0].id, "hot_blood")
	assert_false(build.choose_talent("counterattack"))
	assert_eq(build.get_talent_options()[0].id, "hot_blood")
	assert_true(build.choose_talent("hot_blood"))
	assert_false(build.choose_talent("hot_blood"))

func test_synergy_is_automatic_once_and_uses_no_slot_or_point() -> void:
	var build: WarriorRunBuild = WarriorRunBuild.new()
	build.initialize(["counterattack", "tempered_blade"])
	var revealed: Array[String] = []
	build.synergy_discovered.connect(func(synergy_id: String) -> void: revealed.append(synergy_id))
	assert_false(build.has_synergy("blood_tempering"))
	build.offer_checkpoint(1, true)
	assert_true(build.choose_talent("counterattack"))
	await get_tree().process_frame
	assert_false(build.has_synergy("blood_tempering"))
	build.offer_checkpoint(2)
	assert_true(build.choose_talent("tempered_blade"))
	assert_true(build.has_synergy("blood_tempering"))
	assert_eq(revealed, ["blood_tempering"])
	assert_eq(build.selected_talents.size(), 2)
	assert_eq(build.unspent_specialization_points, 0)

func test_specializations_have_unlimited_ranks_and_free_complete_refund() -> void:
	var build: WarriorRunBuild = WarriorRunBuild.new()
	build.initialize(WarriorTalentCatalog.STARTER_IDS)
	build.grant_specialization_point(1000)
	for _index: int in range(1000):
		assert_true(build.invest_specialization("cleave_cooldown"))
	assert_eq(int(build.specializations.cleave_cooldown), 1000)
	assert_gt(build.get_property_multiplier("cleave_cooldown"), 0.0)
	assert_lt(build.get_property_multiplier("cleave_cooldown"), 1.0)
	assert_false(build.invest_specialization("unreal_axis"))
	build.reset_specializations()
	assert_eq(build.unspent_specialization_points, 1000)
	assert_eq(build.get_property_multiplier("cleave_cooldown"), 1.0)
	assert_true(build.invest_specialization("attack_damage"))
	assert_false(build.invest_specialization("vampirism"), "Properties only appear after their mechanic exists")

func test_level_rewards_are_exact_and_extraction_counts_collected_resources() -> void:
	var progression: PlayerProgression = PlayerProgression.new()
	progression.initialize_run(WarriorTalentCatalog.STARTER_IDS)
	progression.add_xp(180.0)
	assert_eq(progression.player_level, 3)
	assert_eq(progression.run_build.unspent_specialization_points, 2)
	progression.add_xp(30.0)
	var fractional_xp: float = progression.current_xp
	progression.grant_level()
	assert_eq(progression.player_level, 4)
	assert_eq(progression.current_xp, fractional_xp, "Boss reward is one full level without clearing kill XP")
	assert_eq(progression.run_build.unspent_specialization_points, 3)
	var old_reward: int = progression.get_extraction_xp()
	progression.record_resource_gathered(50)
	progression.record_resource_gathered(-50)
	assert_eq(progression.get_extraction_xp(), old_reward + 100)

func test_death_or_extraction_disables_pending_build_and_next_run_resets_it() -> void:
	var build: WarriorRunBuild = WarriorRunBuild.new()
	build.initialize(["hot_blood"])
	build.offer_checkpoint(1, true)
	build.grant_specialization_point()
	build.end_run()
	assert_false(build.choose_talent("hot_blood"))
	assert_false(build.invest_specialization("attack_damage"))
	assert_false(build.offer_checkpoint(2))
	build.initialize(["hot_blood"])
	assert_eq(build.selected_talents.size(), 0)
	assert_eq(build.unspent_specialization_points, 0)
	assert_eq(build.get_talent_options().size(), 0)

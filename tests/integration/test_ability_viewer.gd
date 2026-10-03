extends GutTest

const LAB_SCENE: PackedScene = preload("res://scenes/tools/ability_lab.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player.tscn")
var arena: AbilityLabArena
var entries: Array[AbilityViewerCatalog.Entry]

func before_each() -> void:
	entries = AbilityViewerCatalog.entries()
	arena = AbilityLabArena.new()
	add_child_autoqfree(arena)

func after_each() -> void:
	arena.clear_preview()
	await wait_seconds(1.6)
	get_node("/root/VFXManager").clear_effects()

func _prepare(index: int, variant: AbilityViewerCatalog.VariantKind = AbilityViewerCatalog.VariantKind.BASE) -> void:
	arena.prepare(entries[index], variant)
	await wait_physics_frames(2)

func test_catalogue_has_all_class_actions_and_always_uses_warrior_and_zombie_models() -> void:
	assert_eq(entries.size(), 27, "15 legacy actions, nine production talents, three combinations")
	for i: int in range(entries.size()):
		await _prepare(i)
		assert_eq(int(arena.actor.current_class), entries[i].class_id, "The gameplay class remains native")
		assert_true(arena.actor.hero_warrior.visible)
		assert_false(arena.actor.hero_archer.visible)
		assert_false(arena.actor.hero_engineer.visible)
		assert_gt(AbilityViewerCatalog.properties(entries[i], arena.actor, AbilityViewerCatalog.VariantKind.BASE).size(), 0)
		assert_eq(arena.targets[0].get_node("Visuals/Model").scene_file_path, "res://assets/models/enemies/zombie.tscn")
		assert_not_null(arena.targets[0].presentation.anim_player)

func test_viewer_is_read_only_and_has_no_recipe_or_manual_step_operations() -> void:
	var lab: AbilityLab = LAB_SCENE.instantiate() as AbilityLab
	add_child_autoqfree(lab)
	assert_eq(lab.find_children("*", "LineEdit", true, false).size(), 0)
	assert_eq(lab.find_children("*", "SpinBox", true, false).size(), 0)
	assert_eq(lab.find_children("*", "FileDialog", true, false).size(), 0)
	assert_false(lab.has_method("_file_selected"))
	assert_false(lab.arena.has_method("step_frame"), "Native timers and physics are never manually advanced from UI")
	lab.select_ability(6)
	assert_eq(lab.catalogue[lab.selected_index].title, "Сквозная стрела")
	await lab.play_demo()
	await wait_seconds(0.7)
	assert_gt(lab._damage, 0.0, "UI dispatch reaches actual projectile damage")

func test_native_melee_and_sharp_edge_match_displayed_damage() -> void:
	for i: int in [0, 1, 10]:
		await _prepare(i, AbilityViewerCatalog.VariantKind.SHARP_EDGE)
		var rows: Array[AbilityViewerCatalog.Property] = AbilityViewerCatalog.properties(entries[i], arena.actor, AbilityViewerCatalog.VariantKind.SHARP_EDGE)
		var expected: float = 0.0
		for row: AbilityViewerCatalog.Property in rows:
			if row.title == "Урон попадания":
				expected = row.effective.to_float()
		assert_gt(expected, 0.0)
		arena.demonstrate(entries[i], AbilityViewerCatalog.VariantKind.SHARP_EDGE)
		await wait_seconds(0.45)
		assert_almost_eq(1000.0 - arena.targets[0].current_health, expected, 0.001, "Displayed value matches native hit for " + entries[i].title)

func test_native_archer_attacks_use_real_projectiles_and_piercing() -> void:
	await _prepare(5)
	var hit_amounts: Array[float] = []
	arena.targets[0].damage_observed.connect(func(amount: float, _type: String) -> void: hit_amounts.append(amount))
	arena.demonstrate(entries[5], AbilityViewerCatalog.VariantKind.BASE)
	await wait_seconds(0.6)
	assert_gt(hit_amounts.size(), 0)
	for amount: float in hit_amounts:
		assert_eq(amount, PlayerCombat.new().attack_damage)
	assert_eq(arena.targets[0].current_health, 1000.0 - hit_amounts.size() * PlayerCombat.new().attack_damage)
	assert_eq(arena.targets[1].current_health, 1000.0)
	await _prepare(6)
	arena.demonstrate(entries[6], AbilityViewerCatalog.VariantKind.BASE)
	await wait_seconds(0.8)
	for i: int in range(3):
		assert_lte(arena.targets[i].current_health, 1000.0 - PlayerCombat.new().special_damage * PlayerCombat.PIERCING_DAMAGE_MULTIPLIER)

func test_native_parry_success_blocks_attack_and_applies_counter_stun() -> void:
	await _prepare(2, AbilityViewerCatalog.VariantKind.PARRY_SUCCESS)
	arena.demonstrate(entries[2], AbilityViewerCatalog.VariantKind.PARRY_SUCCESS)
	await wait_seconds(0.4)
	assert_eq(arena.actor.current_health, arena.actor.max_health)
	assert_eq(arena.targets[0].current_health, 1000.0 - PlayerHealth.COUNTER_DAMAGE)
	assert_true(arena.targets[0].is_stunned)
	assert_lt(arena.actor.parry_cooldown_timer, PlayerHealth.PARRY_SUCCESS_COOLDOWN)
	assert_gt(arena.actor.parry_cooldown_timer, 2.0)

func test_vampirism_properties_distinguish_card_value_from_observed_healing() -> void:
	await _prepare(0, AbilityViewerCatalog.VariantKind.VAMPIRISM)
	var before: float = arena.actor.current_health
	assert_eq(arena.actor.vampirism_heal, 4.0, "The actual card handler applies the modifier")
	assert_string_contains(AbilityViewerCatalog.variant_explanation(AbilityViewerCatalog.VariantKind.VAMPIRISM), "позднее попадание")
	arena.demonstrate(entries[0], AbilityViewerCatalog.VariantKind.VAMPIRISM)
	await wait_seconds(0.4)
	assert_lt(arena.targets[0].current_health, 1000.0)
	assert_between(arena.actor.current_health, before, before + arena.actor.vampirism_heal, "Viewer exposes observed native health without inventing a heal")

func test_native_turret_and_mine_deal_their_own_damage() -> void:
	await _prepare(11)
	arena.demonstrate(entries[11], AbilityViewerCatalog.VariantKind.BASE)
	await wait_seconds(1.1)
	assert_lt(arena.targets[0].current_health, 1000.0)
	await _prepare(12, AbilityViewerCatalog.VariantKind.DETONATE)
	arena.demonstrate(entries[12], AbilityViewerCatalog.VariantKind.DETONATE)
	await wait_seconds(1.2)
	assert_eq(arena.targets[0].current_health, 750.0)
	assert_false(is_instance_valid(arena.actor.active_remote_mine))

func test_native_nuke_applies_impact_and_burn_to_fixed_preview_target() -> void:
	await _prepare(13)
	arena.demonstrate(entries[13], AbilityViewerCatalog.VariantKind.BASE)
	await wait_seconds(PlayerAbilities.NUKE_WINDUP + 0.1)
	assert_eq(arena.targets[0].current_health, 1000.0 - PlayerAbilities.NUKE_DAMAGE)
	await wait_seconds(PlayerAbilities.NUKE_BURN_INTERVAL)
	assert_lte(arena.targets[0].current_health, 1000.0 - PlayerAbilities.NUKE_DAMAGE - PlayerAbilities.NUKE_BURN_DAMAGE)

func test_native_duel_decoy_eagle_eye_and_dash_are_dispatched() -> void:
	await _prepare(3)
	arena.demonstrate(entries[3], AbilityViewerCatalog.VariantKind.BASE)
	assert_true(arena.actor.is_dueling)
	assert_eq(arena.actor.duel_target, arena.targets[0])
	await _prepare(7)
	arena.demonstrate(entries[7], AbilityViewerCatalog.VariantKind.BASE)
	await wait_seconds(0.35)
	assert_true(arena.targets[0].target_player.is_in_group("decoy"))
	await _prepare(8)
	arena.demonstrate(entries[8], AbilityViewerCatalog.VariantKind.BASE)
	assert_true(arena.actor.is_eagle_eye)
	for i: int in [4, 9, 14]:
		await _prepare(i, AbilityViewerCatalog.VariantKind.WINDSTRIDER)
		var before: Vector3 = arena.actor.position
		arena.demonstrate(entries[i], AbilityViewerCatalog.VariantKind.WINDSTRIDER)
		await wait_seconds(0.25)
		assert_gt(arena.actor.position.distance_to(before), 1.0)
		assert_almost_eq(arena.actor.dash_cooldown, PlayerMovement.new().dash_cooldown * 0.65, 0.0001)

func test_reset_cancels_delayed_preview_actions() -> void:
	await _prepare(12, AbilityViewerCatalog.VariantKind.DETONATE)
	arena.demonstrate(entries[12], AbilityViewerCatalog.VariantKind.DETONATE)
	await _prepare(0)
	await wait_seconds(1.2)
	assert_eq(arena.targets[0].current_health, 1000.0)
	assert_false(is_instance_valid(arena.actor.active_remote_mine))

func test_unavailable_native_special_preserves_buffered_public_attack() -> void:
	var player: CharacterBody3D = PLAYER_SCENE.instantiate() as CharacterBody3D
	add_child_autoqfree(player)
	player.set_physics_process(false)
	player.orientation.setup(Vector3.FORWARD)
	player.orientation.aim_direction = Vector3.RIGHT
	player.special_cooldown_timer = 2.0
	player.perform_attack()
	var pending: Dictionary = player.orientation.pending_action.duplicate()
	assert_eq(pending.get("action_id"), "attack")
	player.perform_special_attack()
	assert_eq(player.orientation.pending_action, pending)
	for i: int in range(60):
		player.orientation.process_orientation(player, 1.0 / 60.0, Vector3.RIGHT, Vector3.ZERO)
	assert_gt(player.attack_cooldown_timer, 0.0)
	await wait_seconds(0.3)

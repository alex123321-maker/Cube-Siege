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

func _property(rows: Array[AbilityViewerCatalog.Property], title: String) -> AbilityViewerCatalog.Property:
	for row: AbilityViewerCatalog.Property in rows:
		if row.title == title:
			return row
	fail_test("Missing displayed property: " + title)
	return null

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

func test_parry_properties_match_native_base_and_counterattack_window_and_damage() -> void:
	for index: int in [2, 19]:
		var variant: AbilityViewerCatalog.VariantKind = AbilityViewerCatalog.VariantKind.PARRY_SUCCESS if index == 2 else AbilityViewerCatalog.VariantKind.BASE
		await _prepare(index, variant)
		var rows: Array[AbilityViewerCatalog.Property] = AbilityViewerCatalog.properties(entries[index], arena.actor, variant)
		var window: AbilityViewerCatalog.Property = _property(rows, "Защитное окно")
		var counter: AbilityViewerCatalog.Property = _property(rows, "Ответный урон")
		assert_almost_eq(window.base.to_float(), PlayerHealth.PARRY_WINDOW, 0.001)
		assert_almost_eq(counter.base.to_float(), PlayerHealth.COUNTER_DAMAGE, 0.001)
		if index == 19:
			assert_gt(window.effective.to_float(), window.base.to_float())
			assert_gt(counter.effective.to_float(), counter.base.to_float())
		var player_health: float = arena.actor.current_health
		var target_health: float = arena.targets[0].current_health
		arena.demonstrate(entries[index], variant)
		assert_true(arena.actor.health.is_parrying)
		assert_almost_eq(arena.actor.health.parry_timer, window.effective.to_float(), 0.001, "Displayed duration is the real native parry window")
		await wait_seconds(0.4)
		assert_eq(arena.actor.current_health, player_health, "The native zombie attack is blocked")
		assert_almost_eq(target_health - arena.targets[0].current_health, counter.effective.to_float(), 0.001, "Displayed counter damage matches actual target HP loss")

func test_dash_properties_describe_actual_base_and_perfect_dash_damage_immunity() -> void:
	for index: int in [4, 23]:
		await _prepare(index)
		var rows: Array[AbilityViewerCatalog.Property] = AbilityViewerCatalog.properties(entries[index], arena.actor, AbilityViewerCatalog.VariantKind.BASE)
		var duration: AbilityViewerCatalog.Property = _property(rows, "Длительность")
		var before: float = arena.actor.current_health
		arena.demonstrate(entries[index], AbilityViewerCatalog.VariantKind.BASE)
		assert_true(arena.actor.movement.is_dashing)
		assert_almost_eq(arena.actor.movement.dash_timer, duration.effective.to_float(), 0.001, "Displayed duration matches the native dash timer")
		assert_eq(arena.actor.is_dash_invulnerable(), index == 23)
		arena.actor.take_damage(10.0, arena.targets[0])
		if index == 23:
			assert_eq(arena.actor.current_health, before)
			assert_string_contains(duration.explanation, "игнорируется")
		else:
			assert_eq(arena.actor.current_health, before - 10.0)
			assert_string_contains(duration.explanation, "проходит")
		await wait_seconds(duration.effective.to_float() + 0.1)
		assert_false(arena.actor.is_dash_invulnerable(), "Immunity ends with the native dash")
		before = arena.actor.current_health
		arena.actor.take_damage(10.0, arena.targets[0])
		assert_eq(arena.actor.current_health, before - 10.0)

func test_sword_target_limit_properties_match_native_base_and_sweeping_hits() -> void:
	for index: int in [0, 15]:
		await _prepare(index)
		var rows: Array[AbilityViewerCatalog.Property] = AbilityViewerCatalog.properties(entries[index], arena.actor, AbilityViewerCatalog.VariantKind.BASE)
		var limit: AbilityViewerCatalog.Property = _property(rows, "Предел целей")
		arena.demonstrate(entries[index], AbilityViewerCatalog.VariantKind.BASE)
		await wait_seconds(0.3)
		var slash: HitboxArea = arena.actor.get_node("SlashHitbox") as HitboxArea
		assert_eq(slash.can_hit_multiple, index == 15)
		if index == 15:
			assert_eq(limit.effective, "Все в области")
			assert_gt(slash.hits_landed, 1, "The production Sweeping Strike actually reaches multiple targets")
		else:
			assert_eq(limit.effective.to_int(), slash.hits_landed, "Displayed one-target limit matches the native sword hit")
			assert_eq(slash.hits_landed, 1)

func test_cleave_properties_match_native_sector_radius_and_endpoint_or_travelling_windows() -> void:
	for profile: int in range(4):
		var index: int = [1, 17, 21, 21][profile]
		await _prepare(index)
		if profile == 3:
			arena.actor.configure_talents(["wide_lunge", "whirlwind_cleave"])
		var rows: Array[AbilityViewerCatalog.Property] = AbilityViewerCatalog.properties(entries[index], arena.actor, AbilityViewerCatalog.VariantKind.BASE)
		var radius: AbilityViewerCatalog.Property = _property(rows, "Радиус")
		var angle: AbilityViewerCatalog.Property = _property(rows, "Угол сектора")
		var active: AbilityViewerCatalog.Property = _property(rows, "Активное окно")
		var shape: AbilityViewerCatalog.Property = _property(rows, "Форма попадания")
		var before: Vector3 = arena.actor.position
		arena.demonstrate(entries[index], AbilityViewerCatalog.VariantKind.BASE)
		for _frame: int in range(45):
			await wait_physics_frames(1)
			if is_instance_valid(arena.actor.combat._active_slash):
				break
		assert_not_null(arena.actor.combat._active_slash, "Native Cleave releases within the bounded observation window")
		var slash: HitboxArea = arena.actor.get_node("SlashHitbox") as HitboxArea
		var collider: CollisionShape3D = slash.get_node("CollisionShape3D") as CollisionShape3D
		assert_true(collider.shape is CylinderShape3D)
		assert_almost_eq(slash.frontal_radius, radius.effective.to_float(), 0.001)
		assert_almost_eq((collider.shape as CylinderShape3D).radius, radius.effective.to_float(), 0.001)
		assert_almost_eq(slash.frontal_arc_degrees, angle.effective.to_float(), 0.001)
		assert_almost_eq(arena.actor.combat._slash_remaining, active.effective.to_float(), 0.02, "Displayed active window matches the released production cast within one physics tick")
		assert_eq(shape.effective, "Круг" if index == 21 else "Полукруг")
		if profile == 1:
			assert_false(arena.actor.movement.is_lunging, "Standalone Lunge releases its frontal strike only at the endpoint")
			assert_string_contains(active.explanation, "после завершения")
		if profile == 3:
			assert_true(arena.actor.movement.is_lunging, "Lunge plus Whirlwind has a real travelling hit window")
			assert_string_contains(active.explanation, "по всей траектории")
		await wait_seconds(0.4)
		assert_gt(slash.hits_landed, 0)
		if index == 17:
			assert_gt(arena.actor.position.distance_to(before), 1.0, "The longer window belongs to a real moving lunge")
		if index == 21:
			assert_lt(arena.targets[3].current_health, 1000.0, "The displayed full circle actually hits the target behind the Warrior")

func test_tempered_blade_percentage_property_matches_native_overkill_limited_healing() -> void:
	await _prepare(20)
	var rows: Array[AbilityViewerCatalog.Property] = AbilityViewerCatalog.properties(entries[20], arena.actor, AbilityViewerCatalog.VariantKind.BASE)
	var healing: AbilityViewerCatalog.Property = _property(rows, "Лечение от урона здоровью")
	assert_string_contains(healing.effective, "%")
	for row: AbilityViewerCatalog.Property in rows:
		assert_ne(row.title, "Параметр лечения", "Talent healing is distinguished from the unused legacy flat-heal field")
	arena.targets[0].current_health = 10.0
	var target_health: float = arena.targets[0].current_health
	var player_health: float = arena.actor.current_health
	arena.demonstrate(entries[20], AbilityViewerCatalog.VariantKind.BASE)
	await wait_seconds(0.3)
	var health_loss: float = target_health - arena.targets[0].current_health
	assert_almost_eq(health_loss, target_health, 0.001, "The native attack kills a target with less HP than its attack damage")
	assert_almost_eq(arena.actor.current_health - player_health, health_loss * healing.effective.to_float() / 100.0, 0.001, "Displayed percentage predicts actual HP healing, excluding overkill")

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

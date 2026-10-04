extends GutTest

const MAIN_SCENE = preload("res://scenes/main.tscn")
const PORTAL_SCENE = preload("res://scenes/portal.tscn")
const WORKBENCH_MODAL_SCENE = preload("res://scenes/workbench_modal.tscn")

func test_day_night_cycle_has_no_hud_coupling() -> void:
	var cycle = DayNightCycle.new()
	add_child_autoqfree(cycle)

	# Verify DayNightCycle does not define or hold hud_path / hud reference
	assert_false("hud_path" in cycle, "DayNightCycle must not have hud_path export property")
	assert_false("hud" in cycle, "DayNightCycle must not hold hud reference")
	assert_false(cycle.has_method("update_hud_display"), "DayNightCycle must not contain update_hud_display presentation method")

func test_hud_renders_visible_day_night_phase_from_event() -> void:
	var main = MAIN_SCENE.instantiate()
	add_child_autoqfree(main)

	var hud = main.get_node_or_null("HUD")
	assert_not_null(hud, "HUD node should exist in main.tscn")
	var label = hud.day_night_phase_label
	assert_not_null(label, "visible PhaseLabel should be resolved on HUD")

	hud._update_day_night_label(120.0, false, 2)
	assert_eq(label.text, "ДЕНЬ 2", "HUD should show the localized daytime phase")
	assert_eq(hud.day_night_timer_label.text, "02:00", "HUD should show the remaining daytime timer")
	assert_eq(label.modulate, Color.WHITE, "Daytime text color should be WHITE")

	hud._update_day_night_label(25.0, false, 2)
	assert_eq(label.text, "ДЕНЬ 2  ·  ЗАКАТ", "HUD should mark localized sunset in the visible phase label")
	assert_eq(label.modulate, Color(1.0, 0.6, 0.1, 1.0), "Sunset text color should be orange")

	hud._update_day_night_label(90.0, true, 2)
	assert_eq(label.text, "НОЧЬ 2  ·  ОСАДА", "HUD should show the localized night siege phase")
	assert_eq(hud.day_night_timer_label.text, "01:30", "HUD should keep timer visible during night")
	assert_eq(label.modulate, Color(1.0, 0.3, 0.3, 1.0), "Night text color should be reddish")

func test_hud_initializes_health_from_player_on_ready() -> void:
	var main = MAIN_SCENE.instantiate()
	add_child_autoqfree(main)

	var player = main.get_node("Player")
	var hud = main.get_node("HUD")
	assert_eq(hud.player_hp_bar.value, player.current_health, "Floating HP bar should show the player's current health at startup")
	assert_eq(hud.player_hp_bar.max_value, player.max_health, "Floating HP bar should use the player's current max health at startup")
	assert_eq(hud.player_hp_label.text, "%d / %d HP" % [int(player.current_health), int(player.max_health)], "Floating HP label should match the player's startup health")

func test_action_slot_keycap_fits_without_overlapping_icon() -> void:
	var main = MAIN_SCENE.instantiate()
	add_child_autoqfree(main)
	await get_tree().process_frame

	var slot: Control = main.get_node("HUD/Margin/BottomCenter/SkillsActionBar/SlotSpace")
	var keycap: TextureRect = slot.get_node("Keycap")
	var icon: TextureRect = slot.get_node("VisualRegion/Icon")
	assert_eq(keycap.size, Vector2(39, 17), "Keycap should fit its authored layout size")
	assert_false(keycap.get_global_rect().intersects(icon.get_global_rect()), "Keycap should not overlap the action icon")
	assert_eq(keycap.get_node("KeyLabel").text, "SPACE", "Space binding should remain readable in the resized keycap")

func test_hud_uses_one_full_rect_control_root_and_six_slots() -> void:
	var main = MAIN_SCENE.instantiate()
	add_child_autoqfree(main)
	var hud = main.get_node("HUD")
	var root: Control = hud.get_node("Margin")
	var bar: HBoxContainer = root.get_node("BottomCenter/SkillsActionBar")
	assert_eq(hud.get_child_count(), 1, "All HUD controls should be anchored under one full-rect root")
	assert_eq(root.anchor_right, 1.0, "HUD root should span the viewport width")
	assert_eq(root.anchor_bottom, 1.0, "HUD root should span the viewport height")
	assert_eq(bar.get_child_count(), 6, "Action bar should keep five ability slots plus Build")
	assert_false(root.has_node("MiniMap"), "The HUD must not add a minimap")

func test_cooldown_mask_stays_inside_icon_region() -> void:
	var main = MAIN_SCENE.instantiate()
	add_child_autoqfree(main)
	await get_tree().process_frame
	var slot: HUDActionSlot = main.get_node("HUD/Margin/BottomCenter/SkillsActionBar/SlotSpace")
	slot.set_cooldown(9.5)
	var cooldown: ColorRect = slot.get_node("VisualRegion/CooldownOverlay")
	var icon: TextureRect = slot.get_node("VisualRegion/Icon")
	var keycap: TextureRect = slot.get_node("Keycap")
	var name_label: Label = slot.get_node("NameLabel")
	assert_true(cooldown.visible, "Cooldown mask should appear while an ability recharges")
	assert_true(icon.get_global_rect().intersects(cooldown.get_global_rect()), "Cooldown mask should cover the icon")
	assert_false(cooldown.get_global_rect().intersects(keycap.get_global_rect()), "Cooldown mask should not cover the key")
	assert_false(cooldown.get_global_rect().intersects(name_label.get_global_rect()), "Cooldown mask should not cover the action name")

func test_class_ability_names_and_engineer_mine_state_are_visible() -> void:
	var main = MAIN_SCENE.instantiate()
	add_child_autoqfree(main)
	await get_tree().process_frame
	var player: PlayerPrototype = main.get_node("Player")
	var bar: HBoxContainer = main.get_node("HUD/Margin/BottomCenter/SkillsActionBar")
	var f_slot: HUDActionSlot = bar.get_node("SlotF")
	var q_slot: HUDActionSlot = bar.get_node("SlotQ")

	player.set_class(PlayerPrototype.CharacterClass.ARCHER, false)
	await get_tree().process_frame
	assert_eq(f_slot.action_name, "ОРЛ. ГЛАЗ", "Archer F slot should be named Eagle Eye")
	assert_true(f_slot.icon_texture.resource_path.ends_with("archer_eagle_eye.png"), "Archer F should use Eagle Eye art")

	player.set_class(PlayerPrototype.CharacterClass.ENGINEER, false)
	await get_tree().process_frame
	assert_eq(f_slot.action_name, "ЯДЕРНЫЙ", "Engineer F slot should be named Tactical Nuke")
	assert_true(f_slot.icon_texture.resource_path.ends_with("engineer_tactical_nuke.png"), "Engineer F should use Tactical Nuke art")
	assert_eq(q_slot.action_name, "ПОСТАВИТЬ", "Engineer Q should describe placing a mine")
	player.abilities.toggle_remote_mine(player)
	assert_not_null(player.active_remote_mine, "The gameplay owner should create the mine")
	await get_tree().process_frame
	assert_eq(q_slot.action_name, "ПОДОРВАТЬ", "Engineer Q should switch to detonating an active mine")
	player.abilities.toggle_remote_mine(player)
	await get_tree().process_frame
	assert_eq(q_slot.action_name, "ПОСТАВИТЬ", "Detonation should restore the placement prompt")
	assert_true(q_slot.cooldown_overlay.visible, "Actual mine reload should reach the HUD")

func test_hero_portrait_frames_front_of_each_class_model() -> void:
	var main = MAIN_SCENE.instantiate()
	add_child_autoqfree(main)
	await get_tree().process_frame
	var player: PlayerPrototype = main.get_node("Player")
	var portrait: HUDHeroPortrait = main.get_node("HUD/Margin/Resources/ResourceRows/HeroPortrait")
	assert_eq(portrait.custom_minimum_size, Vector2(64, 64), "Hero portrait should have enough HUD space for a readable model crop")
	assert_eq(portrait.viewport.size, Vector2i(64, 64), "Hero portrait SubViewport should render at its authored size")

	for state in [
		{"class_id": PlayerPrototype.CharacterClass.WARRIOR, "yaw": 0.0},
		{"class_id": PlayerPrototype.CharacterClass.ARCHER, "yaw": PI},
		{"class_id": PlayerPrototype.CharacterClass.ENGINEER, "yaw": PI},
	]:
		player.set_class(state.class_id, false)
		await get_tree().process_frame
		var model: Node3D = portrait.model_root.get_child(0) as Node3D
		assert_eq(portrait._active_class_id, state.class_id, "Portrait should follow the selected class")
		assert_true(absf(model.rotation.y - state.yaw) < 0.001, "Portrait model should face its camera")

func test_hud_skip_night_uses_explicit_dependency() -> void:
	var main = MAIN_SCENE.instantiate()
	add_child_autoqfree(main)

	var hud = main.get_node_or_null("HUD")
	var cycle: DayNightCycle = main.get_node_or_null("DayNightCycle") as DayNightCycle
	assert_not_null(hud, "HUD node should exist")
	assert_not_null(cycle, "DayNightCycle node should exist")
	assert_eq(hud.day_night_cycle, cycle, "HUD should resolve DayNightCycle via explicit exported path")

	cycle.is_night = false
	hud._on_skip_night_pressed()
	assert_true(cycle.is_night, "Skip night button should trigger skip_to_night on explicit day_night_cycle dependency")

func test_portal_evacuation_emits_eventbus_signal() -> void:
	var portal = PORTAL_SCENE.instantiate()
	add_child_autoqfree(portal)
	portal.current_state = PortalController.State.ACTIVE
	portal.current_day = 3

	var received_events: Array = []
	var eb = get_node_or_null("/root/EventBus")
	if eb:
		var cb = func(day_num: int, xp: int):
			received_events.append({"day": day_num, "xp": xp})
		eb.portal_evacuated.connect(cb)
		portal.evacuate_player(null)
		eb.portal_evacuated.disconnect(cb)

		assert_eq(received_events.size(), 1, "EventBus.portal_evacuated should be emitted on evacuation")
		if not received_events.is_empty():
			assert_eq(received_events[0].day, 3, "Evacuated day should match portal current_day")
			assert_gt(received_events[0].xp, 0, "Earned XP should be positive")
	else:
		pass_test("EventBus autoload not present in isolated test environment")

func test_workbench_modal_resolves_building_system_without_find_child() -> void:
	var main = MAIN_SCENE.instantiate()
	add_child_autoqfree(main)

	var modal = main.get_node_or_null("HUD/Margin/WorkbenchModal")
	var bs = main.get_node_or_null("BuildingSystem")
	assert_not_null(modal, "WorkbenchModal should exist under the full-rect HUD root")
	assert_not_null(bs, "BuildingSystem should exist in main.tscn")
	assert_eq(modal._get_building_system(), bs, "WorkbenchModal should resolve BuildingSystem via explicit NodePath")


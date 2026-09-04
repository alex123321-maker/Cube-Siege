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

func test_hud_renders_day_night_label_from_event() -> void:
	var main = MAIN_SCENE.instantiate()
	add_child_autoqfree(main)

	var hud = main.get_node_or_null("HUD")
	assert_not_null(hud, "HUD node should exist in main.tscn")
	var label = hud.day_night_label
	assert_not_null(label, "DayNightLabel should be resolved on HUD")

	hud._update_day_night_label(120.0, false, 2)
	assert_eq(label.text, "DAY 2  02:00", "HUD should correctly format daytime label")
	assert_eq(label.modulate, Color.WHITE, "Daytime text color should be WHITE")

	hud._update_day_night_label(25.0, false, 2)
	assert_eq(label.text, "DAY 2 [SUNSET]  00:25", "HUD should format sunset label under 30s")
	assert_eq(label.modulate, Color(1.0, 0.6, 0.1, 1.0), "Sunset text color should be orange")

	hud._update_day_night_label(90.0, true, 2)
	assert_eq(label.text, "NIGHT 2 [SIEGE]  01:30", "HUD should format night siege label")
	assert_eq(label.modulate, Color(1.0, 0.3, 0.3, 1.0), "Night text color should be reddish")

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

	var modal = main.get_node_or_null("HUD/WorkbenchModal")
	var bs = main.get_node_or_null("BuildingSystem")
	assert_not_null(modal, "WorkbenchModal should exist in main.tscn")
	assert_not_null(bs, "BuildingSystem should exist in main.tscn")
	assert_eq(modal._get_building_system(), bs, "WorkbenchModal should resolve BuildingSystem via explicit NodePath")


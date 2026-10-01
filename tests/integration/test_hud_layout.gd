extends GutTest

const HUD_SCENE: PackedScene = preload("res://scenes/hud.tscn")
const SLOT_SCENE: PackedScene = preload("res://scenes/hud_action_slot.tscn")
const ICON: Texture2D = preload("res://assets/ui/hud_visual_kit/icons/warrior_dash.png")

func test_hud_initializes_resources_before_the_first_wallet_event() -> void:
	var viewport := SubViewport.new()
	add_child_autoqfree(viewport)
	var building_system := BuildingSystem.new()
	building_system.name = "BuildingSystem"
	viewport.add_child(building_system)
	var hud := HUD_SCENE.instantiate()
	viewport.add_child(hud)
	assert_eq(hud.wood_label.text, str(building_system.wallet.get_wood()), "Initial wood must not stay at zero until the next purchase")
	assert_eq(hud.stone_label.text, str(building_system.wallet.get_stone()))
	assert_eq(hud.iron_label.text, str(building_system.wallet.get_iron()))
	building_system.add_resource(10, 20, 30, 40)
	assert_eq(hud.wood_label.text, "26", "Wallet events should update the initial snapshot")
	assert_eq(hud.magic_label.text, "40")

func test_resolved_regions_and_all_slots_after_resize() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	add_child_autoqfree(viewport)
	var hud := HUD_SCENE.instantiate()
	viewport.add_child(hud)
	# canvas_items + expand uses these logical bounds for the five target sizes.
	for logical_size: Vector2i in [Vector2i(1280, 720), Vector2i(1706, 720), Vector2i(1280, 800), Vector2i(1280, 720)]:
		viewport.size = logical_size
		for night: bool in [false, true]:
			hud._update_day_night_label(25.0, night, 999)
			hud._on_resources_changed(999, 12345, 1234567, 999999999)
			await get_tree().process_frame
			await get_tree().process_frame
			var root: Control = hud.get_node("Margin")
			var top: Control = root.get_node("TopCenter")
			var resources: Control = root.get_node("Resources")
			var boss: Control = root.get_node("BossBarContainer")
			var bottom: Control = root.get_node("BottomCenter")
			for path: String in ["TopCenter/DayNightRow/DayNightIcon", "TopCenter/DayNightRow/TimerLabel", "PlayerFloatingHP/Bar", "PlayerFloatingHP/Bar/Label", "PlayerFloatingHP/XPBar", "PlayerFloatingHP/XPLabel", "BossBarContainer/BossHPBar"]:
				assert_eq(root.get_node(path).mouse_filter, Control.MOUSE_FILTER_IGNORE, "Decorative HUD layers must pass input to gameplay")
			assert_eq(top.size, Vector2(360, 56), "Day/night panel must not grow with its icon or phase text")
			assert_eq(resources.size, Vector2(420, 80), "Portrait and large counters must fit the resource panel")
			assert_eq(root.size, Vector2(logical_size), "HUD root should follow viewport resize")
			assert_false(top.get_rect().intersects(resources.get_rect()), "Top panels must remain separate")
			assert_false(top.get_rect().intersects(boss.get_rect()), "Boss bar has a reserved region below day/night")
			assert_true(Rect2(Vector2.ZERO, root.size).encloses(bottom.get_rect()), "All action slots must fit the screen")
			var settings: Button = top.get_node("DayNightRow/BtnSettings")
			assert_eq(settings.size, Vector2(30, 30), "64/256px settings art must not set the button minimum")
			var bar: HBoxContainer = bottom.get_node("SkillsActionBar")
			var previous: Control
			for slot: HUDActionSlot in bar.get_children():
				var visual: Control = slot.get_node("VisualRegion")
				assert_eq(slot.size, Vector2(82, 120), "All six slot bounds must agree")
				assert_eq(visual.size, Vector2(72, 72), "Visual region must be square")
				for layer_name: String in ["Frame", "Icon", "CooldownOverlay"]:
					assert_eq(visual.get_node(layer_name).get_rect(), Rect2(Vector2.ZERO, visual.size), "Every visual layer uses the same bounds")
				assert_false(visual.get_global_rect().intersects(slot.get_node("Keycap").get_global_rect()), "Key binding must stay outside the visual region")
				assert_false(visual.get_global_rect().intersects(slot.name_label.get_global_rect()), "Name must stay outside the visual region")
				if previous:
					assert_eq(slot.position.x - previous.position.x, 90.0, "All six slots use equal spacing")
				previous = slot
	assert_eq(hud.magic_label.tooltip_text, "999999999", "Compact resource text must retain the exact count in its tooltip")

func test_action_switch_and_unavailable_clear_stale_cooldown() -> void:
	var slot: HUDActionSlot = SLOT_SCENE.instantiate()
	add_child_autoqfree(slot)
	slot.set_action(ICON, "РЫВОК", "SPACE")
	assert_eq(slot.mouse_filter, Control.MOUSE_FILTER_PASS, "Slots should support tooltips while passing clicks to gameplay")
	assert_eq(slot.name_label.mouse_filter, Control.MOUSE_FILTER_IGNORE, "Decorative labels must not consume input")
	slot.set_cooldown(8.0)
	assert_true(slot.cooldown_overlay.visible)
	slot.set_unavailable(true)
	assert_false(slot.cooldown_overlay.visible)
	assert_eq(slot.cooldown_label.text, "", "Unavailable slots must immediately clear the countdown")
	slot.set_action(ICON, "КУВЫРОК", "SPACE")
	assert_true(slot.icon.visible, "A new valid action should recover from unavailable")
	assert_false(slot.cooldown_overlay.visible, "A new action must not inherit the old cooldown")
	assert_eq(slot.cooldown_label.text, "")
	slot.set_cooldown(0.0)
	assert_true(slot.frame.texture.resource_path.ends_with("action_slot_normal_64.png"))

func test_missing_required_icon_is_diagnosed_and_unavailable() -> void:
	var slot: HUDActionSlot = SLOT_SCENE.instantiate()
	add_child_autoqfree(slot)
	slot.set_action(null, "MISSING", "F")
	assert_push_error("missing required icon")
	assert_false(slot.icon.visible)
	slot.set_unavailable(false)
	assert_true(slot._is_unavailable, "A missing texture must not become a ready slot")
	assert_false(slot.cooldown_overlay.visible)

func test_overhead_projection_updates_with_viewport_and_camera() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.own_world_3d = true
	add_child_autoqfree(viewport)
	var target := preload("res://scenes/player.tscn").instantiate() as PlayerPrototype
	viewport.add_child(target)
	target.set_process(false)
	target.set_physics_process(false)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(0, 8, 10)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	var hud := HUD_SCENE.instantiate()
	hud.player_path = NodePath("../Player")
	viewport.add_child(hud)
	# The isolated headless viewport has no rendered first frame yet.
	hud.set_process(false)
	await get_tree().process_frame
	await get_tree().process_frame
	for view_size: Vector2i in [Vector2i(1280, 720), Vector2i(1706, 720), Vector2i(1280, 800)]:
		viewport.size = view_size
		camera.position.x += 2.0
		camera.size += 3.0
		camera.force_update_transform()
		await get_tree().process_frame
		await get_tree().process_frame
		hud._process(0.0)
		var projected: Vector2 = camera.unproject_position(target.global_position + Vector3(0, 2.2, 0))
		var center: Vector2 = hud.player_floating_hp.position + hud.player_floating_hp.size * 0.5
		assert_lt(center.distance_to(projected), 0.01, "Overhead bars must follow viewport and camera changes")
	assert_eq(hud.process_mode, Node.PROCESS_MODE_ALWAYS, "HUD must continue positioning when settings pause gameplay")
	hud.set_process(false)

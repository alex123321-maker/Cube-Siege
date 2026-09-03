extends GutTest

func test_core_game_scenes_loadable() -> void:
	var core_scenes: Array[String] = [
		"res://scenes/portal.tscn",
		"res://scenes/radial_menu.tscn",
		"res://scenes/workbench_modal.tscn",
		"res://scenes/card_draft_popup.tscn",
		"res://scenes/game_over_overlay.tscn",
		"res://scenes/skills_action_bar.tscn",
		"res://scenes/floating_text.tscn"
	]
	
	for scene_path in core_scenes:
		assert_true(ResourceLoader.exists(scene_path), "Scene should exist: " + scene_path)
		var res = load(scene_path)
		assert_not_null(res, "Scene should load cleanly without missing resources: " + scene_path)

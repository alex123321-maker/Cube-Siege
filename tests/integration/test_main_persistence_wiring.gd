extends GutTest

const MAIN_SCENE = preload("res://scenes/main.tscn")

func test_main_scene_has_no_local_save_manager() -> void:
	var main = MAIN_SCENE.instantiate()
	add_child_autoqfree(main)
	
	# Verify that no child named SaveManager exists directly on Main
	var local_sm = main.get_node_or_null("SaveManager")
	assert_null(local_sm, "scenes/main.tscn must NOT have a duplicate scene-local SaveManager node")
	
	# Verify that main.save_manager resolves to autoload /root/SaveManager
	var root_sm = get_node_or_null("/root/SaveManager")
	if root_sm:
		assert_eq(main.save_manager, root_sm, "Main script should reference the autoload SaveManager")

func test_persistence_delegation_without_sidecar_files() -> void:
	var roster = get_node_or_null("/root/RosterManager")
	var mastery = get_node_or_null("/root/MasteryManager")
	var save_mgr = get_node_or_null("/root/SaveManager")

	if not roster or not mastery or not save_mgr:
		pass_test("Autoloads not present in this test runner context")
		return

	# Clear any existing legacy sidecar files
	var legacy_roster_path = "user://character_roster.json"
	var legacy_mastery_path = "user://mastery_save.json"
	if FileAccess.file_exists(legacy_roster_path):
		DirAccess.remove_absolute(legacy_roster_path)
	if FileAccess.file_exists(legacy_mastery_path):
		DirAccess.remove_absolute(legacy_mastery_path)

	# Mutate roster and mastery
	var orig_available = roster.slots[0].available_points
	if orig_available > 0:
		roster.invest_talent(0, "bloodlust")
		assert_eq(save_mgr.roster_slots[0].bloodlust, roster.slots[0].bloodlust, "SaveManager should reflect RosterManager talent investment")

	var orig_pts = mastery.available_points
	if orig_pts > 0:
		mastery.invest_point("survival")
		assert_eq(save_mgr.mastery.get("survival", 0), mastery.survival, "SaveManager should reflect MasteryManager point investment")

	# Verify that no legacy sidecar files were generated
	assert_false(FileAccess.file_exists(legacy_roster_path), "RosterManager must not write to legacy sidecar character_roster.json")
	assert_false(FileAccess.file_exists(legacy_mastery_path), "MasteryManager must not write to legacy sidecar mastery_save.json")

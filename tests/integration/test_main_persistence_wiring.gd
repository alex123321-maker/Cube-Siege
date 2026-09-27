extends GutTest

const MAIN_SCENE = preload("res://scenes/main.tscn")

var _save_snapshot: Dictionary = {}

func before_each() -> void:
	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr:
		_save_snapshot = save_mgr.snapshot_state()

func after_each() -> void:
	var save_mgr = get_node_or_null("/root/SaveManager")
	if save_mgr and not _save_snapshot.is_empty():
		save_mgr.restore_state(_save_snapshot)
		if save_mgr.is_test_environment():
			if FileAccess.file_exists(save_mgr.save_file_path):
				DirAccess.remove_absolute(save_mgr.save_file_path)
			if FileAccess.file_exists(save_mgr.legacy_roster_path):
				DirAccess.remove_absolute(save_mgr.legacy_roster_path)
			if FileAccess.file_exists(save_mgr.legacy_mastery_path):
				DirAccess.remove_absolute(save_mgr.legacy_mastery_path)

func test_main_scene_has_no_local_save_manager() -> void:
	var main = MAIN_SCENE.instantiate()
	add_child_autoqfree(main)
	
	# Verify that no child named SaveManager exists directly on Main
	var local_sm = main.get_node_or_null("SaveManager")
	assert_null(local_sm, "scenes/main.tscn must NOT have a duplicate scene-local SaveManager node")
	
	# Verify that main.save_manager resolves to autoload /root/SaveManager
	var root_sm = get_node_or_null("/root/SaveManager")
	assert_not_null(root_sm, "SaveManager autoload must be present")
	if root_sm:
		assert_eq(main.save_manager, root_sm, "Main script should reference the autoload SaveManager")

func test_persistence_delegation_without_sidecar_files() -> void:
	var roster = get_node_or_null("/root/RosterManager")
	var mastery = get_node_or_null("/root/MasteryManager")
	var save_mgr = get_node_or_null("/root/SaveManager")

	assert_not_null(roster, "RosterManager autoload must be present in integration tests")
	assert_not_null(mastery, "MasteryManager autoload must be present in integration tests")
	assert_not_null(save_mgr, "SaveManager autoload must be present in integration tests")
	if not roster or not mastery or not save_mgr:
		return

	assert_true(save_mgr.is_test_environment(), "Tests must run in isolated test storage environment")

	# Clear any existing legacy sidecar files in test storage
	var legacy_roster_path = save_mgr.legacy_roster_path
	var legacy_mastery_path = save_mgr.legacy_mastery_path
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

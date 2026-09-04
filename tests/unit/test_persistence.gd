extends GutTest

const SaveManager = preload("res://scripts/save_manager.gd")
const TEST_SAVE_PATH = "user://test_cube_siege_save.json"

func before_each() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)

func after_each() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(TEST_SAVE_PATH)

func test_save_and_load_round_trip() -> void:
	var mgr = SaveManager.new()
	mgr.auto_load = false
	add_child_autoqfree(mgr)
	mgr.meta_xp = 1250
	mgr.survived_runs = 3
	mgr.selected_slot_index = 1
	mgr.mastery = {
		"total_battle_xp": 350,
		"available_points": 7,
		"bloodlust": 2,
		"survival": 1,
		"agility": 0,
		"crafting": 0
	}

	var saved: bool = mgr.save_to_disk(TEST_SAVE_PATH)
	assert_true(saved, "Save to disk should succeed")
	assert_true(FileAccess.file_exists(TEST_SAVE_PATH), "Save file should exist on disk")

	# Load with fresh manager
	var mgr2 = SaveManager.new()
	mgr2.auto_load = false
	add_child_autoqfree(mgr2)
	var loaded: bool = mgr2.load_from_disk(TEST_SAVE_PATH)
	assert_true(loaded, "Load from disk should succeed")
	assert_eq(int(mgr2.meta_xp), 1250, "meta_xp should match")
	assert_eq(int(mgr2.survived_runs), 3, "survived_runs should match")
	assert_eq(int(mgr2.selected_slot_index), 1, "selected_slot_index should match")
	assert_eq(int(mgr2.mastery.get("total_battle_xp", 0)), 350, "mastery total_battle_xp should match")
	assert_eq(int(mgr2.mastery.get("bloodlust", 0)), 2, "mastery bloodlust should match")

func test_migration_from_v1_schema() -> void:
	# Create a v1 format save file
	var v1_data: Dictionary = {
		"version": 1,
		"meta_xp": 500,
		"survived_runs": 1,
		"heroes_roster": [
			{"name": "Warrior", "class": "warrior", "days_survived": 2}
		],
		"unlocked_classes": ["warrior", "archer"]
	}
	var file = FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string(JSON.stringify(v1_data))
	file.close()

	var mgr = SaveManager.new()
	mgr.auto_load = false
	add_child_autoqfree(mgr)
	var loaded: bool = mgr.load_from_disk(TEST_SAVE_PATH)
	assert_true(loaded, "Loading v1 save should succeed")
	assert_eq(int(mgr.meta_xp), 500, "meta_xp should be loaded")
	assert_eq(int(mgr.survived_runs), 1, "survived_runs should be loaded")
	assert_eq(mgr.roster_slots.size(), 3, "roster_slots should be populated with default 3 classes")
	assert_eq(mgr.run_history.size(), 1, "run_history should be populated from v1 heroes_roster")

func test_corrupted_json_recovery() -> void:
	# Write invalid/corrupt JSON
	var file = FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string("{ corrupted json [ invalid syntax")
	file.close()

	var mgr = SaveManager.new()
	mgr.auto_load = false
	add_child_autoqfree(mgr)
	var loaded: bool = mgr.load_from_disk(TEST_SAVE_PATH)
	assert_false(loaded, "Corrupted file should report load failure")
	# Safe default state should remain intact without crashing
	assert_eq(int(mgr.meta_xp), 0, "Default meta_xp preserved")
	assert_eq(mgr.roster_slots.size(), 3, "Default slots preserved")

func test_run_end_victory_and_defeat_resolution() -> void:
	var mgr = SaveManager.new()
	mgr.auto_load = false
	add_child_autoqfree(mgr)
	mgr.selected_slot_index = 0 # Warrior

	# Victory
	mgr.record_run_end(true, 5, 200, 0, TEST_SAVE_PATH)
	var warrior_slot: Dictionary = mgr.roster_slots[0]
	assert_true(warrior_slot.get("is_alive", false), "Hero remains alive")
	assert_eq(int(warrior_slot.get("max_day", 0)), 5, "Max day updated to 5")
	assert_eq(int(warrior_slot.get("battle_xp", 0)), 200, "Battle XP increased")
	assert_eq(int(mgr.meta_xp), 500, "Meta XP awarded on victory")
	assert_eq(int(mgr.survived_runs), 1, "Survived runs count incremented")

	# Defeat
	mgr.record_run_end(false, 3, 0, 0, TEST_SAVE_PATH)
	var defeated_slot: Dictionary = mgr.roster_slots[0]
	assert_true(defeated_slot.get("is_alive", false), "Slot remains playable")
	assert_eq(int(defeated_slot.get("level", 0)), 1, "Level reset to 1 on defeat")
	assert_eq(int(defeated_slot.get("battle_xp", 0)), 0, "Battle XP reset to 0 on defeat")
	assert_eq(int(defeated_slot.get("available_points", 0)), 5, "Points reset to 5 on defeat")
	assert_eq(mgr.run_history.size(), 2, "Both victory and defeat logged in run_history")

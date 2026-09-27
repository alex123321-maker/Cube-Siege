extends GutTest

## Tests that persistence and autoload managers execute under isolated test storage.
## Guarantees that running tests never mutates, overwrites, or deletes real user save data.

const SENTINEL_FILE_NAME = "sentinel_persistence_guard.tmp"

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

	# Clean sentinel guard from user root
	var sentinel_path = "user://" + SENTINEL_FILE_NAME
	if FileAccess.file_exists(sentinel_path):
		DirAccess.remove_absolute(sentinel_path)

func test_test_environment_is_active_and_isolated() -> void:
	var save_mgr = get_node_or_null("/root/SaveManager")
	assert_not_null(save_mgr, "SaveManager autoload must be present")
	assert_true(save_mgr.is_test_environment(), "SaveManager must be operating in test storage profile")
	assert_ne(save_mgr.storage_dir, "user://", "storage_dir must not be user root")
	assert_true(save_mgr.save_file_path.begins_with(save_mgr.storage_dir), "save_file_path must reside in test profile")
	assert_true(save_mgr.legacy_roster_path.begins_with(save_mgr.storage_dir), "legacy_roster_path must reside in test profile")
	assert_true(save_mgr.legacy_mastery_path.begins_with(save_mgr.storage_dir), "legacy_mastery_path must reside in test profile")

func test_sentinel_files_in_user_root_remain_byte_for_byte_unmodified() -> void:
	var save_mgr = get_node_or_null("/root/SaveManager")
	assert_not_null(save_mgr)

	var sentinel_path = "user://" + SENTINEL_FILE_NAME
	var sentinel_content = "SENTINEL_USER_DATA_HASH_%d" % Time.get_ticks_msec()
	var file = FileAccess.open(sentinel_path, FileAccess.WRITE)
	assert_not_null(file)
	file.store_string(sentinel_content)
	file.close()

	# Execute save through SaveManager
	save_mgr.meta_xp += 1000
	save_mgr.save_to_disk()

	# Read sentinel back and verify byte-for-byte identity
	var read_file = FileAccess.open(sentinel_path, FileAccess.READ)
	assert_not_null(read_file)
	var content = read_file.get_as_text()
	read_file.close()

	assert_eq(content, sentinel_content, "Sentinel file in user:// root must be byte-for-byte untouched by save operations")

	# Check that save_to_disk wrote into test profile directory, not root
	assert_true(FileAccess.file_exists(save_mgr.save_file_path), "Save file must be written into test profile path")

func test_save_manager_snapshot_and_restore() -> void:
	var save_mgr = get_node_or_null("/root/SaveManager")
	assert_not_null(save_mgr)

	var snapshot = save_mgr.snapshot_state()

	# Mutate state heavily
	save_mgr.meta_xp = 99999
	save_mgr.survived_runs = 88
	save_mgr.selected_slot_index = 2
	save_mgr.roster_slots[0].battle_xp = 7777
	save_mgr.mastery["bloodlust"] = 99

	# Restore state
	save_mgr.restore_state(snapshot)

	assert_eq(save_mgr.meta_xp, snapshot["meta_xp"], "meta_xp must be restored")
	assert_eq(save_mgr.survived_runs, snapshot["survived_runs"], "survived_runs must be restored")
	assert_eq(save_mgr.selected_slot_index, snapshot["selected_slot_index"], "selected_slot_index must be restored")
	assert_eq(save_mgr.roster_slots[0].battle_xp, snapshot["roster_slots"][0]["battle_xp"], "slot battle_xp must be restored")
	assert_eq(save_mgr.mastery.get("bloodlust", 0), snapshot["mastery"].get("bloodlust", 0), "mastery must be restored")

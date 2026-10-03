extends GutTest

const SAVE_SCRIPT = preload("res://scripts/save_manager.gd")
const PROFILE: String = "user://test_warrior_meta/"

class FailedWriteSave:
	extends "res://scripts/save_manager.gd"

	func _store_and_flush(file: FileAccess, _content: String) -> Error:
		# Simulate a disk that accepted open() and part of the payload but
		# rejected completion. This must fail before primary/backup rotation.
		file.store_string("{ partial write")
		file.flush()
		return ERR_FILE_CANT_WRITE

var _save: Node
var _roster: Node
var _snapshot: Dictionary
var _storage: String

func before_each() -> void:
	_save = get_node("/root/SaveManager")
	_roster = get_node("/root/RosterManager")
	_snapshot = _save.snapshot_state()
	_storage = _save.storage_dir
	_save.set_storage_dir(PROFILE)
	_save.reset_to_defaults()
	_roster.run_active = false
	_roster.selected_slot_index = 0

func after_each() -> void:
	_save.restore_state(_snapshot)
	_save.set_storage_dir(_storage)
	_roster.run_active = false
	for filename: String in ["cube_siege_save.json", "cube_siege_save.json.tmp", "cube_siege_save.json.bak", "character_roster.json"]:
		if FileAccess.file_exists(PROFILE + filename):
			DirAccess.remove_absolute(PROFILE + filename)

func test_fresh_hero_is_playable_and_each_opening_grants_branch_passive() -> void:
	assert_eq(_roster.get_unlocked_talents().size(), 3)
	var before: Dictionary = _roster.get_character_multipliers(0)
	assert_almost_eq(float(before.damage_mult), 1.03, 0.001)
	assert_eq(float(before.max_hp_bonus), 5.0)
	assert_almost_eq(float(before.speed_mult), 1.02, 0.001)
	_save.roster_slots[0].talent_xp = 1000
	assert_true(_roster.unlock_talent(0, "loud_triumph"))
	var after: Dictionary = _roster.get_character_multipliers(0)
	assert_almost_eq(float(after.damage_mult), 1.06, 0.001)
	assert_eq(int(_save.roster_slots[0].talent_xp), 0)
	assert_false(_roster.unlock_talent(0, "loud_triumph"))
	assert_eq(_roster.get_unlocked_talents().size(), 4)

func test_unlock_rejects_unknown_wrong_class_insufficient_and_in_run() -> void:
	assert_false(_roster.unlock_talent(0, "unknown"))
	assert_false(_roster.unlock_talent(1, "loud_triumph"))
	assert_false(_roster.unlock_talent(0, "loud_triumph"))
	_save.roster_slots[0].talent_xp = 1000
	_roster.begin_run()
	assert_false(_roster.unlock_talent(0, "loud_triumph"))
	assert_eq(int(_save.roster_slots[0].talent_xp), 1000)

func test_unlock_save_failure_rolls_back_spending_and_opening() -> void:
	_save.roster_slots[0].talent_xp = 1000
	_save.save_file_path = PROFILE + "missing/subfolder/save.json"
	assert_false(_roster.unlock_talent(0, "loud_triumph"))
	assert_push_error("Failed to open save file")
	assert_eq(int(_save.roster_slots[0].talent_xp), 1000)
	assert_false(_roster.get_unlocked_talents().has("loud_triumph"))
	assert_true(_roster.last_error.contains("возвращён"))

func test_success_roundtrip_retains_unlock_and_death_replaces_hero() -> void:
	_save.roster_slots[0].talent_xp = 2000
	assert_true(_roster.unlock_talent(0, "loud_triumph"))
	assert_true(_roster.record_run_end(true, 30, 1400, true))
	assert_true(_roster.get_unlocked_talents().has("loud_triumph"))
	assert_eq(int(_save.roster_slots[0].victories), 1)
	var manager: Node = SAVE_SCRIPT.new()
	manager.auto_load = false
	add_child_autoqfree(manager)
	assert_true(manager.load_from_disk(PROFILE + "cube_siege_save.json"))
	assert_true(manager.roster_slots[0].unlocked_talents.has("loud_triumph"))
	assert_eq(int(manager.roster_slots[0].talent_xp), 2400)
	assert_true(_roster.record_run_end(false, 5, 0))
	assert_eq(_roster.get_unlocked_talents(), WarriorTalentCatalog.STARTER_IDS)
	assert_eq(int(_save.roster_slots[0].talent_xp), 0)
	assert_eq(int(_save.roster_slots[0].victories), 0)
	assert_eq(_save.run_history.size(), 2)

func test_v2_migration_compensates_once_and_preserves_other_classes_history_and_global_mastery() -> void:
	var legacy: Dictionary = _save.serialize_to_dict().duplicate(true)
	legacy.version = 2
	var warrior: Dictionary = legacy.roster_slots[0]
	for key: String in ["talent_xp", "unlocked_talents", "purchased_talents", "completed_runs", "victories"]:
		warrior.erase(key)
	warrior.bloodlust = 7
	warrior.survival = 3
	warrior.available_points = 5
	legacy.mastery.bloodlust = 99
	legacy.roster_slots[1].battle_xp = 5000
	legacy.run_history = [{"outcome": "evacuated"}]
	_save._migrate_and_load_data(legacy)
	assert_eq(int(_save.roster_slots[0].talent_xp), 750)
	assert_eq(int(_save.roster_slots[0].legacy_progression.bloodlust), 7)
	assert_eq(int(_save.mastery.bloodlust), 99)
	assert_eq(int(_save.roster_slots[1].battle_xp), 5000)
	assert_eq(_save.run_history.size(), 1)
	var migrated: Dictionary = _save.serialize_to_dict().duplicate(true)
	_save._migrate_and_load_data(migrated)
	assert_eq(int(_save.roster_slots[0].talent_xp), 750)
	assert_eq(_roster.get_character_multipliers(0).damage_mult, 1.03, "Legacy ranks no longer stack with new passives")

func test_existing_v3_primary_is_not_overwritten_by_legacy_sidecar() -> void:
	_save.roster_slots[0].talent_xp = 1234
	assert_true(_save.save_to_disk())
	var file: FileAccess = FileAccess.open(PROFILE + "character_roster.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"slots": SAVE_SCRIPT.get_default_roster_slots(), "selected_slot": 2}))
	file.close()
	assert_true(_save.load_from_disk())
	assert_eq(int(_save.roster_slots[0].talent_xp), 1234)
	assert_eq(_save.selected_slot_index, 0)

func test_corrupt_talent_ids_are_discarded_without_becoming_another_talent() -> void:
	var data: Dictionary = _save.serialize_to_dict().duplicate(true)
	data.roster_slots[0].unlocked_talents = ["hot_blood", "hot_blood", "foreign", 4]
	data.roster_slots[0].purchased_talents = ["foreign", "loud_triumph"]
	data.roster_slots[0].talent_xp = "bad"
	_save._migrate_and_load_data(data)
	assert_eq(_roster.get_unlocked_talents(), WarriorTalentCatalog.STARTER_IDS)
	assert_eq(int(_save.roster_slots[0].talent_xp), 0)
	assert_eq(_save.roster_slots[0].purchased_talents.size(), 0)

func test_interrupted_rename_recovers_valid_backup_before_legacy_or_newer_temporary() -> void:
	_save.roster_slots[0].talent_xp = 2000
	assert_true(_roster.unlock_talent(0, "loud_triumph"))
	assert_true(_roster.record_run_end(true, 30, 1400, true))
	var path: String = PROFILE + "cube_siege_save.json"
	assert_eq(DirAccess.rename_absolute(path, path + ".bak"), OK)
	# A not-yet-committed temporary and stale sidecar must not replace the
	# durable pre-rename hero snapshot.
	var temporary: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	temporary.store_string(JSON.stringify({"version": 3, "roster_slots": SAVE_SCRIPT.get_default_roster_slots()}))
	temporary.close()
	var sidecar: FileAccess = FileAccess.open(PROFILE + "character_roster.json", FileAccess.WRITE)
	sidecar.store_string(JSON.stringify({"slots": SAVE_SCRIPT.get_default_roster_slots(), "selected_slot": 2}))
	sidecar.close()
	_save.reset_to_defaults()
	assert_true(_save.load_from_disk())
	assert_true(_roster.get_unlocked_talents(0).has("loud_triumph"))
	assert_eq(int(_save.roster_slots[0].talent_xp), 2400)
	assert_eq(int(_save.roster_slots[0].victories), 1)
	assert_eq(_save.run_history.size(), 1)
	assert_true(FileAccess.file_exists(path))
	assert_false(FileAccess.file_exists(path + ".bak"))
	assert_true(_save.load_from_disk())
	assert_eq(int(_save.roster_slots[0].talent_xp), 2400, "Recovery and subsequent load are idempotent")

func test_complete_first_save_temporary_is_recovered_when_no_primary_or_backup_exists() -> void:
	_save.roster_slots[0].talent_xp = 321
	var path: String = PROFILE + "cube_siege_save.json"
	var temporary: FileAccess = FileAccess.open(path + ".tmp", FileAccess.WRITE)
	temporary.store_string(JSON.stringify(_save.serialize_to_dict()))
	temporary.close()
	_save.reset_to_defaults()
	assert_true(_save.load_from_disk())
	assert_eq(int(_save.roster_slots[0].talent_xp), 321)
	assert_true(FileAccess.file_exists(path))
	assert_false(FileAccess.file_exists(path + ".tmp"))

func test_invalid_backup_does_not_overwrite_artifact_with_default_primary() -> void:
	var path: String = PROFILE + "cube_siege_save.json"
	var backup: FileAccess = FileAccess.open(path + ".bak", FileAccess.WRITE)
	backup.store_string(JSON.stringify({"version": 3, "roster_slots": [{"class_id": 9}]}))
	backup.close()
	assert_false(_save.load_from_disk())
	assert_push_warning("Interrupted save artifacts are invalid")
	assert_false(FileAccess.file_exists(path))
	assert_true(FileAccess.file_exists(path + ".bak"))

func test_corrupt_existing_primary_is_reported_without_replacing_it_from_backup() -> void:
	_save.roster_slots[0].talent_xp = 321
	var path: String = PROFILE + "cube_siege_save.json"
	var backup: FileAccess = FileAccess.open(path + ".bak", FileAccess.WRITE)
	backup.store_string(JSON.stringify(_save.serialize_to_dict()))
	backup.close()
	var primary: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	primary.store_string("{ damaged primary")
	primary.close()
	_save.reset_to_defaults()
	assert_false(_save.load_from_disk())
	assert_push_warning("Failed to parse save JSON")
	assert_eq(int(_save.roster_slots[0].talent_xp), 0)
	assert_true(FileAccess.file_exists(path + ".bak"))

func test_partial_write_preserves_primary_backup_and_rolls_back_run_end() -> void:
	_save.roster_slots[0].talent_xp = 1000
	assert_true(_roster.unlock_talent(0, "loud_triumph"))
	var path: String = PROFILE + "cube_siege_save.json"
	var primary_before: String = FileAccess.get_file_as_string(path)
	var backup_before: String = "previous durable backup"
	var backup: FileAccess = FileAccess.open(path + ".bak", FileAccess.WRITE)
	backup.store_string(backup_before)
	backup.close()
	var manager: Node = FailedWriteSave.new()
	manager.auto_load = false
	manager.set_storage_dir(PROFILE)
	add_child_autoqfree(manager)
	manager.restore_state(_save.snapshot_state())
	var before: Dictionary = manager.snapshot_state()
	assert_false(manager.record_run_end(true, 30, 1400, 0, "", true))
	assert_push_error("Failed to write save file")
	assert_eq(manager.snapshot_state(), before, "Failed write rolls back all character, XP, victory and history changes")
	assert_eq(FileAccess.get_file_as_string(path), primary_before, "Durable primary is never replaced by a partial payload")
	assert_eq(FileAccess.get_file_as_string(path + ".bak"), backup_before, "Existing backup remains intact")
	assert_false(FileAccess.file_exists(path + ".tmp"))

func test_failed_first_save_reports_load_failure_and_removes_partial_temporary() -> void:
	var manager: Node = FailedWriteSave.new()
	manager.auto_load = false
	manager.set_storage_dir(PROFILE)
	add_child_autoqfree(manager)
	assert_false(manager.load_from_disk(), "First profile creation must propagate a failed write")
	assert_push_error("Failed to write save file")
	var path: String = PROFILE + "cube_siege_save.json"
	assert_false(FileAccess.file_exists(path))
	assert_false(FileAccess.file_exists(path + ".tmp"))
	assert_false(FileAccess.file_exists(path + ".bak"))

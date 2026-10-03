extends RefCounted
class_name GameplaySandboxSession

## Reversible in-memory/profile boundary shared by menu entry and direct scene launch.
const PROFILE_DIR: String = "user://gameplay_sandbox/profile/"
static var _active: bool = false
static var _snapshot: Dictionary = {}
static var _storage_dir: String = ""
static var _roster_running: bool = false
static var _roster_return: bool = false
static var _roster_error: String = ""
static var _height_lookup: Callable
static var _loaded_lookup: Callable
static var _world_seed: int = 0

static func is_active() -> bool:
	return _active

static func begin(owner: Node) -> bool:
	if _active:
		return true
	var save: Node = owner.get_node_or_null("/root/SaveManager")
	var roster: Node = owner.get_node_or_null("/root/RosterManager")
	var registry: Node = owner.get_node_or_null("/root/EntityRegistry")
	if not save or not roster or not registry:
		push_error("GameplaySandbox: required autoloads are missing")
		return false
	_snapshot = save.snapshot_state()
	_storage_dir = save.storage_dir
	_roster_running = roster.run_active
	_roster_return = roster.return_to_character_select
	_roster_error = roster.last_error
	_height_lookup = registry.monster_flowfield.height_lookup
	_loaded_lookup = registry.monster_flowfield.chunk_loaded_lookup
	_world_seed = registry.monster_flowfield.world_seed
	# Redirect first: even an unexpected legacy save action stays in this profile.
	save.set_storage_dir(PROFILE_DIR)
	save.reset_to_defaults()
	save.roster_slots[0]["unlocked_talents"] = WarriorTalentCatalog.TALENT_IDS.duplicate()
	roster.run_active = false
	roster.return_to_character_select = false
	roster.last_error = ""
	_active = true
	return true

static func leave(owner: Node) -> void:
	if not _active:
		return
	var save: Node = owner.get_node_or_null("/root/SaveManager")
	var roster: Node = owner.get_node_or_null("/root/RosterManager")
	var registry: Node = owner.get_node_or_null("/root/EntityRegistry")
	if save:
		save.restore_state(_snapshot)
		save.set_storage_dir(_storage_dir)
	if roster:
		roster.run_active = _roster_running
		roster.return_to_character_select = _roster_return
		roster.last_error = _roster_error
	if registry:
		registry.monster_flowfield.clear_all()
		registry.monster_flowfield.world_seed = _world_seed
		registry.monster_flowfield.set_height_lookup(_height_lookup)
		registry.monster_flowfield.set_chunk_loaded_lookup(_loaded_lookup)
	_snapshot.clear()
	_height_lookup = Callable()
	_loaded_lookup = Callable()
	_active = false

extends RefCounted
class_name AbilityLabDocument

signal changed()
var definition: AbilityDefinition
var dirty: bool = false
var path: String = ""
var _undo: Array[AbilityDefinition] = []
var _redo: Array[AbilityDefinition] = []

func open_definition(value: AbilityDefinition, source_path: String = "") -> void:
	definition = value.duplicate(true) as AbilityDefinition
	path = source_path
	dirty = false
	_undo.clear()
	_redo.clear()
	changed.emit()

func checkpoint() -> void:
	_undo.append(definition.duplicate(true) as AbilityDefinition)
	if _undo.size() > 64:
		_undo.pop_front()
	_redo.clear()
	dirty = true

func undo() -> void:
	if _undo.is_empty():
		return
	_redo.append(definition.duplicate(true) as AbilityDefinition)
	definition = _undo.pop_back()
	dirty = true
	changed.emit()

func redo() -> void:
	if _redo.is_empty():
		return
	_undo.append(definition.duplicate(true) as AbilityDefinition)
	definition = _redo.pop_back()
	dirty = true
	changed.emit()

func save_to(destination: String) -> Error:
	if destination.get_extension().to_lower() != "tres":
		return ERR_FILE_UNRECOGNIZED
	var error: Error = ResourceSaver.save(definition, destination)
	if error == OK:
		path = destination
		dirty = false
	return error

func load_from(source: String) -> Error:
	var loaded: AbilityDefinition = ResourceLoader.load(source, "", ResourceLoader.CACHE_MODE_IGNORE) as AbilityDefinition
	if loaded == null or loaded.schema_version != AbilityDefinition.SCHEMA_VERSION:
		return ERR_FILE_UNRECOGNIZED
	# Fail before deep-copying a malformed/cyclic recipe. Draft validation is visible.
	var plan: AbilityPlan = AbilityCompiler.compile(loaded)
	for error: String in plan.errors:
		if error.begins_with("Циклический") or error.begins_with("Глубина"):
			return ERR_INVALID_DATA
	open_definition(loaded, source)
	return OK

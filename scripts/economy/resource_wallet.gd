extends RefCounted
class_name ResourceWallet

## Authoritative domain component managing player resource balances (Wood, Stone, Iron).
## Enforces non-negative balances and emits change signals.

signal resources_changed(wood: int, stone: int, iron: int)

var _wood: int = 0
var _stone: int = 0
var _iron: int = 0

func _init(initial_wood: int = 16, initial_stone: int = 8, initial_iron: int = 4) -> void:
	_wood = maxi(0, initial_wood)
	_stone = maxi(0, initial_stone)
	_iron = maxi(0, initial_iron)

func get_wood() -> int:
	return _wood

func get_stone() -> int:
	return _stone

func get_iron() -> int:
	return _iron

func get_balances() -> Dictionary:
	return {
		"wood": _wood,
		"stone": _stone,
		"iron": _iron
	}

func add_resource(wood: int = 0, stone: int = 0, iron: int = 0) -> void:
	if wood < 0 or stone < 0 or iron < 0:
		push_warning("ResourceWallet: Cannot add negative resource amounts.")
		return

	if wood == 0 and stone == 0 and iron == 0:
		return

	_wood += wood
	_stone += stone
	_iron += iron
	_emit_changes()

func has_resources(wood: int = 0, stone: int = 0, iron: int = 0) -> bool:
	if wood < 0 or stone < 0 or iron < 0:
		return false
	return _wood >= wood and _stone >= stone and _iron >= iron

func spend_resources(wood: int = 0, stone: int = 0, iron: int = 0) -> bool:
	if wood < 0 or stone < 0 or iron < 0:
		push_warning("ResourceWallet: Cannot spend negative resource amounts.")
		return false

	if not has_resources(wood, stone, iron):
		return false

	_wood -= wood
	_stone -= stone
	_iron -= iron
	_emit_changes()
	return true

func _emit_changes() -> void:
	resources_changed.emit(_wood, _stone, _iron)

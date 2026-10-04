class_name HUDStatusBar
extends HFlowContainer

var player: PlayerPrototype
var _slots: Dictionary[StringName, HUDStatusSlot] = {}

func setup(target: PlayerPrototype) -> void:
	player = target
	refresh()

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	var snapshots: Array[PlayerStatusEffect] = []
	if is_instance_valid(player):
		snapshots = player.status_effects.get_active_effects()
	var present: Array[StringName] = []
	for snapshot: PlayerStatusEffect in snapshots:
		present.append(snapshot.id)
		if not _slots.has(snapshot.id):
			var slot: HUDStatusSlot = HUDStatusSlot.new()
			slot.name = String(snapshot.id).to_pascal_case()
			_slots[snapshot.id] = slot
			add_child(slot)
		_slots[snapshot.id].set_effect(snapshot)
	for effect_id: StringName in _slots.keys():
		if not present.has(effect_id):
			remove_child(_slots[effect_id])
			_slots[effect_id].queue_free()
			_slots.erase(effect_id)
	visible = not snapshots.is_empty()

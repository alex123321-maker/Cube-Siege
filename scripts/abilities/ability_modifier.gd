extends Resource
class_name AbilityModifier

enum Operation { SET_RADIUS, SET_ARC, SCALE_DAMAGE, ADD_KNOCKBACK, ADD_ACTION }

@export var label: String = "Модификатор"
@export var enabled: bool = true
## Full semantic path, e.g. active/hit. Never a row index or scene NodePath.
@export var target_slot: String = "hit"
@export var operation: Operation = Operation.SET_ARC
@export var value: float = 360.0
## ADD_ACTION uses the target's start time plus this action's relative start.
@export var action: AbilityStep

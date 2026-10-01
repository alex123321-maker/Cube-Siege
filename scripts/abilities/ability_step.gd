extends Resource
class_name AbilityStep

## Authored data only. Times are relative to the containing recipe.
enum Kind { AREA, MOVE, WAIT, RECIPE }

@export var slot: String = "hit"
@export var kind: Kind = Kind.AREA
@export var start: float = 0.0
@export var duration: float = 0.25
@export var damage: float = 25.0
@export var knockback: float = 0.0
@export var radius: float = 2.5
@export var arc_degrees: float = 90.0
@export var follow_actor: bool = true
## Zero means once per target per action; positive values mean periodic hits.
@export var repeat_interval: float = 0.0
@export var terrain_mode: TerrainCombatRules.TerrainMode = TerrainCombatRules.TerrainMode.TERRAIN_DEPENDENT
@export var distance: float = 0.0
## Resource array avoids a Godot 4.6 self-typed script reference cycle.
## The compiler validates every element as AbilityStep before execution.
@export var children: Array[Resource] = []

func kind_label() -> String:
	if kind < Kind.AREA or kind > Kind.RECIPE:
		return "Неизвестный блок"
	return ["Область", "Движение", "Ожидание", "Рецепт"][kind]

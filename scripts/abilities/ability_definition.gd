extends Resource
class_name AbilityDefinition

const SCHEMA_VERSION: int = 1

@export var schema_version: int = SCHEMA_VERSION
@export var title: String = "Новая способность"
@export_multiline var description: String = "Эксперимент лаборатории; не утверждённый баланс."
@export var draft: bool = true
@export var cooldown: float = 4.0
@export var steps: Array[Resource] = []
@export var modifiers: Array[AbilityModifier] = []

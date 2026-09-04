extends Resource
class_name CharacterDefinition

@export var class_id: int = 0
@export var character_name: String = ""
@export var title: String = ""
@export var base_health: float = 100.0
@export var base_speed: float = 7.0
@export var dash_speed: float = 18.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 3.0
@export var base_attack_damage: float = 25.0
@export var base_special_damage: float = 60.0
@export var ultimate_cooldown: float = 25.0

static var _character_catalog: Dictionary = {}

static func get_character_catalog() -> Dictionary:
	if _character_catalog.is_empty():
		_init_catalog()
	return _character_catalog

static func get_definition(c_id: int) -> CharacterDefinition:
	var cat = get_character_catalog()
	return cat.get(c_id, cat.get(0))

static func _init_catalog() -> void:
	# Warrior
	var warrior: CharacterDefinition = CharacterDefinition.new()
	warrior.class_id = 0
	warrior.character_name = "Воин"
	warrior.title = "Рыцарь Авангарда"
	warrior.base_health = 100.0
	warrior.base_speed = 7.0
	warrior.dash_speed = 18.0
	warrior.dash_duration = 0.15
	warrior.dash_cooldown = 3.0
	warrior.base_attack_damage = 25.0
	warrior.base_special_damage = 60.0
	warrior.ultimate_cooldown = 25.0
	_character_catalog[warrior.class_id] = warrior

	# Archer
	var archer: CharacterDefinition = CharacterDefinition.new()
	archer.class_id = 1
	archer.character_name = "Лучник"
	archer.title = "Следопыт Лесов"
	archer.base_health = 80.0
	archer.base_speed = 8.0
	archer.dash_speed = 20.0
	archer.dash_duration = 0.15
	archer.dash_cooldown = 2.5
	archer.base_attack_damage = 18.0
	archer.base_special_damage = 45.0
	archer.ultimate_cooldown = 30.0
	_character_catalog[archer.class_id] = archer

	# Engineer
	var eng: CharacterDefinition = CharacterDefinition.new()
	eng.class_id = 2
	eng.character_name = "Инженер"
	eng.title = "Мастер Фортификаций"
	eng.base_health = 110.0
	eng.base_speed = 6.5
	eng.dash_speed = 16.0
	eng.dash_duration = 0.15
	eng.dash_cooldown = 3.5
	eng.base_attack_damage = 22.0
	eng.base_special_damage = 50.0
	eng.ultimate_cooldown = 60.0
	_character_catalog[eng.class_id] = eng

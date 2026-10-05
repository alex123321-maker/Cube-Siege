extends Resource
class_name BuildingDefinition

@export var id: int = 0
@export var type_name: String = ""
@export var display_name: String = ""
@export var wood_cost: int = 0
@export var stone_cost: int = 0
@export var iron_cost: int = 0
@export var scene_path: String = ""
@export var visual_scene_path: String = ""
@export var icon_path: String = ""
@export var preview_size: Vector3 = Vector3(1.0, 2.0, 1.0)
@export var preview_offset_y: float = 1.0
@export var description: String = ""

# Authoritative catalog of all building definitions
static var _catalog: Dictionary = {}

static func get_catalog() -> Dictionary:
	if _catalog.is_empty():
		_initialize_catalog()
	return _catalog

static func get_definition(type_id: int) -> BuildingDefinition:
	var cat: Dictionary = get_catalog()
	return cat.get(type_id, null)

static func _initialize_catalog() -> void:
	# Wood Wall
	var wood_wall: BuildingDefinition = BuildingDefinition.new()
	wood_wall.id = 1
	wood_wall.type_name = "wood_wall"
	wood_wall.display_name = "Деревянная стена"
	wood_wall.wood_cost = 4
	wood_wall.stone_cost = 0
	wood_wall.iron_cost = 0
	wood_wall.scene_path = "res://scenes/prefabs/wood_wall.tscn"
	wood_wall.preview_size = Vector3(1.0, 2.0, 1.0)
	wood_wall.preview_offset_y = 1.0
	wood_wall.visual_scene_path = "res://assets/models/buildings/wood_wall.gltf"
	wood_wall.icon_path = PixelUI.path("building_wood_wall")
	wood_wall.description = "Деревянный частокол • 250 HP. Перекрывает путь врагам. Замкнутый контур стен защищает базу от появления монстров внутри."
	_catalog[wood_wall.id] = wood_wall

	# Floor Spikes
	var spikes: BuildingDefinition = BuildingDefinition.new()
	spikes.id = 2
	spikes.type_name = "floor_spikes"
	spikes.display_name = "Напольные шипы"
	spikes.wood_cost = 2
	spikes.stone_cost = 1
	spikes.iron_cost = 0
	spikes.scene_path = "res://scenes/prefabs/floor_spikes.tscn"
	spikes.preview_size = Vector3(1.0, 0.2, 1.0)
	spikes.preview_offset_y = 0.1
	spikes.visual_scene_path = "res://assets/models/buildings/floor_spikes.gltf"
	spikes.icon_path = PixelUI.path("building_floor_spikes")
	spikes.description = "Напольная ловушка • 100 HP. Наносит 25 урона врагам каждую секунду. Не мешает движению героя."
	_catalog[spikes.id] = spikes

	# Archer Tower
	var tower: BuildingDefinition = BuildingDefinition.new()
	tower.id = 3
	tower.type_name = "archer_tower"
	tower.display_name = "Башня лучников"
	tower.wood_cost = 6
	tower.stone_cost = 2
	tower.iron_cost = 0
	tower.scene_path = "res://scenes/prefabs/archer_tower.tscn"
	tower.preview_size = Vector3(1.0, 3.5, 1.0)
	tower.preview_offset_y = 1.75
	tower.visual_scene_path = "res://assets/models/buildings/archer_tower.gltf"
	tower.icon_path = PixelUI.path("building_archer_tower")
	tower.description = "Деревянная вышка • 350 HP. Автоматически стреляет по ближайшему врагу: 30 урона, дальность 10 м, интервал 1,2 с."
	_catalog[tower.id] = tower

	# Iron Wall
	var iron_wall: BuildingDefinition = BuildingDefinition.new()
	iron_wall.id = 4
	iron_wall.type_name = "iron_wall"
	iron_wall.display_name = "Железная стена"
	iron_wall.wood_cost = 0
	iron_wall.stone_cost = 2
	iron_wall.iron_cost = 2
	iron_wall.scene_path = "res://scenes/prefabs/iron_wall.tscn"
	iron_wall.preview_size = Vector3(1.0, 2.0, 1.0)
	iron_wall.preview_offset_y = 1.0
	iron_wall.visual_scene_path = "res://assets/models/buildings/iron_wall.gltf"
	iron_wall.icon_path = PixelUI.path("building_iron_wall")
	iron_wall.description = "Железная шипованная стена • 1200 HP. Возвращает атакующему врагу 25% полученного урона."
	_catalog[iron_wall.id] = iron_wall

	# Ballista
	var ballista: BuildingDefinition = BuildingDefinition.new()
	ballista.id = 5
	ballista.type_name = "ballista"
	ballista.display_name = "Баллиста"
	ballista.wood_cost = 0
	ballista.stone_cost = 4
	ballista.iron_cost = 4
	ballista.scene_path = "res://scenes/prefabs/ballista_tower.tscn"
	ballista.preview_size = Vector3(1.2, 2.8, 1.2)
	ballista.preview_offset_y = 1.4
	ballista.visual_scene_path = "res://assets/models/buildings/ballista.gltf"
	ballista.icon_path = PixelUI.path("building_ballista")
	ballista.description = "Тяжёлая баллиста • 600 HP. Пробивающий болт поражает до 3 врагов: 120 урона, дальность 14 м, интервал 2,4 с."
	_catalog[ballista.id] = ballista

	# Demo utility, configurable gameplay values live on Campfire.
	var campfire: BuildingDefinition = BuildingDefinition.new()
	campfire.id = 6
	campfire.type_name = "campfire"
	campfire.display_name = "Костёр"
	campfire.wood_cost = 6
	campfire.stone_cost = 3
	campfire.scene_path = "res://scenes/prefabs/campfire.tscn"
	campfire.visual_scene_path = "res://assets/models/buildings/campfire.gltf"
	campfire.icon_path = PixelUI.path("building_campfire")
	campfire.preview_size = Vector3(1.0, 1.0, 1.0)
	campfire.preview_offset_y = 0.5
	campfire.description = "Уютный очаг • 180 HP. Восстанавливает 3 HP/с герою в радиусе 5 м. Регенерация действует рядом с костром; лечение от разных источников складывается."
	_catalog[campfire.id] = campfire

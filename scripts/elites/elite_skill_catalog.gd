extends RefCounted
class_name EliteSkillCatalog

const GRUNT: String = "res://scenes/enemy_dummy.tscn"
const RANGED: String = "res://scenes/enemies/ranged_skirmisher.tscn"
const SIEGE: String = "res://scenes/enemies/siege_breaker.tscn"
const IDS: PackedStringArray = ["triple_throw", "backswing", "underground_spike", "returning_blade", "leap_strike", "fire_breath", "spit_puddle", "foot_mine", "short_lunge"]
const TITLES: PackedStringArray = ["Тройной бросок", "Удар с обратным взмахом", "Подземный шип", "Возвращающийся клинок", "Прыжок с ударом", "Короткий огненный выдох", "Плевок с лужей", "Мина под ногами", "Короткий выпад"]
const PAGES: PackedStringArray = ["page_c14fe5d9b1a08191a5968b81ced0b9a5", "page_95353da2b24c8191b3649aa6c0c34e62", "page_e4fdddd56b18819183f15900be113f28", "page_076791485d348191819e52d0ab06d326", "page_6d69c835c8588191a7014f560e7cc316", "page_de0c96cedcd881918c5ea95cb92489e8", "page_173c42cbdf048191ac8692c15d465d4c", "page_d96b8e0da0308191b51fc243dee0aab7", "page_5cc04eec6084819189df66965ec34fb7"]
const SCENES: PackedStringArray = [RANGED, GRUNT, SIEGE, RANGED, GRUNT, SIEGE, RANGED, SIEGE, GRUNT]
const KINDS: Array[EliteSkillSpec.Kind] = [EliteSkillSpec.Kind.TRIPLE_THROW, EliteSkillSpec.Kind.BACKSWING, EliteSkillSpec.Kind.UNDERGROUND_SPIKE, EliteSkillSpec.Kind.RETURNING_BLADE, EliteSkillSpec.Kind.LEAP_STRIKE, EliteSkillSpec.Kind.FIRE_BREATH, EliteSkillSpec.Kind.SPIT_PUDDLE, EliteSkillSpec.Kind.FOOT_MINE, EliteSkillSpec.Kind.SHORT_LUNGE]

class Entry extends RefCounted:
	var id: String
	var title: String
	var scene_path: String
	var source_page: String
	func _init(p_id: String, p_title: String, p_scene: String, p_page: String) -> void:
		id = p_id
		title = p_title
		scene_path = p_scene
		source_page = p_page

## Typed catalogue shared by waves and sandbox; it contains no duplicate rules.
static func entries() -> Array[Entry]:
	var result: Array[Entry] = []
	for index: int in range(IDS.size()):
		result.append(Entry.new(IDS[index], TITLES[index], SCENES[index], "https://chatgpt.com/space/" + PAGES[index]))
	return result

static func ids_for_scene(scene_path: String) -> PackedStringArray:
	var result: PackedStringArray = []
	for index: int in range(IDS.size()):
		if SCENES[index] == scene_path:
			result.append(IDS[index])
	return result

static func create_spec(skill_id: String) -> EliteSkillSpec:
	var index: int = IDS.find(skill_id)
	if index < 0:
		return null
	var spec: EliteSkillSpec = EliteSkillSpec.new()
	spec.id = skill_id
	spec.title = TITLES[index]
	spec.source_page = "https://chatgpt.com/space/" + PAGES[index]
	spec.scene_path = SCENES[index]
	spec.kind = KINDS[index]
	match spec.kind:
		EliteSkillSpec.Kind.TRIPLE_THROW:
			spec.radius = 1.2
			spec.windup = 0.0
			spec.flight_time = 0.8
			spec.interval = 0.65
		EliteSkillSpec.Kind.BACKSWING:
			spec.reach = 4.25
			spec.arc_degrees = 100.0
			spec.interval = 0.6
			spec.trigger_range = 4.0
		EliteSkillSpec.Kind.UNDERGROUND_SPIKE:
			spec.lifetime = 2.0
			spec.color = Color(0.72, 0.40, 1.0)
		EliteSkillSpec.Kind.RETURNING_BLADE:
			spec.reach = 10.0
			spec.width = 1.0
			spec.interval = 0.25
		EliteSkillSpec.Kind.LEAP_STRIKE:
			spec.radius = 1.8
			spec.windup = 0.8
			spec.flight_time = 0.7
		EliteSkillSpec.Kind.FIRE_BREATH:
			spec.reach = 5.0
			spec.damage = 14.0 # Actual continuous HP/second, integrated in the active window.
			spec.trigger_range = 4.5
		EliteSkillSpec.Kind.SPIT_PUDDLE:
			spec.reach = 12.0
			spec.width = 1.0
			spec.radius = 1.5
			spec.damage = 14.0
			spec.color = Color(0.42, 0.88, 0.20)
		EliteSkillSpec.Kind.FOOT_MINE:
			spec.damage = 22.0
		EliteSkillSpec.Kind.SHORT_LUNGE:
			spec.reach = 7.0
			spec.speed = 15.0
			spec.recovery = 0.65
			spec.trigger_range = 6.0
	return spec

extends RefCounted
class_name WarriorTalentCatalog

const STARTER_IDS: Array[String] = ["sweeping_strike", "hot_blood", "wide_lunge"]
const TALENT_IDS: Array[String] = [
	"sweeping_strike", "hot_blood", "wide_lunge", "loud_triumph", "counterattack",
	"tempered_blade", "whirlwind_cleave", "dismemberment", "perfect_dash"
]
const BRANCH_COLORS: Dictionary = {
	"bloodlust": Color(0.96, 0.30, 0.36),
	"endurance": Color(0.30, 0.85, 0.58),
	"mobility": Color(0.28, 0.70, 1.0)
}
const SYNERGY_PAIRS: Dictionary = {
	"blood_tempering": ["counterattack", "tempered_blade"],
	"carnage": ["whirlwind_cleave", "dismemberment"],
	"dangerous_movement": ["loud_triumph", "perfect_dash"]
}
const SYNERGY_TITLES: Dictionary = {
	"blood_tempering": "Закалка кровью", "carnage": "Резня", "dangerous_movement": "Опасные движения"
}
## One shared set of playtest numbers for runtime, descriptions and viewer.
const HOT_BLOOD_RATE: float = 5.0
const HOT_BLOOD_DURATION: float = 3.0
const LUNGE_DISTANCE: float = 2.7
const LUNGE_DURATION: float = 0.30
const TRIUMPH_BONUS: float = 0.08
const COUNTER_PARRY_WINDOW: float = 0.75
const VAMPIRISM_FRACTION: float = 0.08
const DISMEMBER_SLOW: float = 0.40
const DISMEMBER_RADIUS: float = 5.0
const MORALE_DURATION: float = 4.0
const MORALE_SPEED: float = 0.20
const MORALE_DODGE: float = 0.15
const CARNAGE_CHANCE: float = 0.25
const PERFECT_DASH_DISTANCE_MULTIPLIER: float = 2.0

static func get_all() -> Array[WarriorTalentDefinition]:
	var definitions: Array[WarriorTalentDefinition] = []
	definitions.append(_make("sweeping_strike", "Разящий удар", "Обычная атака поражает всех врагов в секторе меча.", "bloodlust", "", 0, 1, -90.0))
	definitions.append(_make("hot_blood", "Горячая кровь", "Успешное парирование восстанавливает 5 HP/с в течение 3 секунд. Повторный успех обновляет время.", "endurance", "", 0, 1, 30.0))
	definitions.append(_make("wide_lunge", "Широкий выпад", "Рассечение сопровождается выпадом на 2.7 м. Выпад сохраняет столкновения и не даёт неуязвимость.", "mobility", "", 0, 1, 150.0))
	definitions.append(_make("loud_triumph", "Громкий триумф", "Каждая победа в Дуэли увеличивает урон обычных атак на 8% до конца забега.", "bloodlust", "sweeping_strike", 1000, 2, -110.0))
	definitions.append(_make("counterattack", "Контратака", "Парирование длится 0.75 с, поглощает все атаки в окне и отвечает атакующему уроном обычной атаки.", "bloodlust", "sweeping_strike", 1400, 2, -70.0))
	definitions.append(_make("tempered_blade", "Закалённый клинок", "Прямые атаки лечат на 8% фактического урона здоровью монстра. Щиты и отражение не лечат.", "endurance", "hot_blood", 1000, 2, 10.0))
	definitions.append(_make("whirlwind_cleave", "Вихревое рассечение", "Рассечение поражает врагов вокруг Воина. С выпадом вращение продолжается по всей траектории.", "endurance", "hot_blood", 1400, 2, 50.0))
	definitions.append(_make("dismemberment", "Расчленение трупа", "Победа в Дуэли замедляет врагов рядом на 40% и даёт на 4 с +20% скорости и 15% уклонения. Сопротивление замедлению: 80%.", "mobility", "wide_lunge", 1000, 2, 130.0))
	definitions.append(_make("perfect_dash", "Идеальный рывок", "Рывок вдвое дальше и делает Воина неуязвимым на время движения.", "mobility", "wide_lunge", 1400, 2, 170.0))
	return definitions

static func get_talent(talent_id: String) -> WarriorTalentDefinition:
	for definition: WarriorTalentDefinition in get_all():
		if definition.id == talent_id:
			return definition
	return null

static func sanitize_ids(raw: Variant, include_starters: bool = false) -> Array[String]:
	var ids: Array[String] = []
	if include_starters:
		ids.assign(STARTER_IDS)
	if raw is Array:
		for value: Variant in raw:
			if value is String and TALENT_IDS.has(value) and not ids.has(value):
				ids.append(value)
	return ids

static func _make(talent_id: String, talent_title: String, text: String, talent_branch: String, parent: String, cost: int, talent_ring: int, degrees: float) -> WarriorTalentDefinition:
	var definition: WarriorTalentDefinition = WarriorTalentDefinition.new()
	definition.id = talent_id
	definition.title = talent_title
	definition.description = text
	definition.branch = talent_branch
	definition.parent_id = parent
	definition.unlock_cost = cost
	definition.ring = talent_ring
	definition.angle = deg_to_rad(degrees)
	var icon_id: String = talent_id
	if talent_id == "sweeping_strike":
		icon_id = "splash_strike"
	elif talent_id == "dismemberment":
		icon_id = "corpse_dismemberment"
	definition.icon_path = PixelUI.path("warrior_" + icon_id)
	return definition

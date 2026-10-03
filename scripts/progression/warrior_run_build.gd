extends RefCounted
class_name WarriorRunBuild

signal build_changed()
signal checkpoint_ready()
signal synergy_discovered(synergy_id: String)

const MAX_TALENTS: int = 6
const FOCUS_POINTS: int = 2
const CHECKPOINT_WAVES: Array[int] = [2, 5, 10, 15, 20, 25, 30]
const BASE_AXES: Array[String] = ["attack_damage", "attack_speed", "cleave_damage", "cleave_radius", "cleave_cooldown", "dash_distance", "dash_cooldown", "parry_window", "parry_cooldown", "duel_bonus", "duel_resistance", "duel_reflection"]
const AXIS_TITLES: Dictionary = {
	"attack_damage": "Обычная атака · урон", "attack_speed": "Обычная атака · скорость",
	"cleave_damage": "Рассечение · урон", "cleave_radius": "Рассечение · радиус", "cleave_cooldown": "Рассечение · перезарядка",
	"dash_distance": "Рывок · дистанция", "dash_cooldown": "Рывок · перезарядка",
	"parry_window": "Парирование · окно", "parry_cooldown": "Парирование · перезарядка",
	"duel_bonus": "Дуэль · урон", "duel_resistance": "Дуэль · защита", "duel_reflection": "Дуэль · отражение",
	"hot_blood_healing": "Горячая кровь · лечение", "lunge_distance": "Выпад · дистанция",
	"vampirism": "Закалённый клинок · лечение", "triumph_power": "Триумф · усиление", "morale_duration": "Мораль · длительность"
}

var selected_talents: Array[String] = []
var specializations: Dictionary = {}
var unspent_specialization_points: int = 0
var unlocked_talents: Array[String] = []
var discovered_synergies: Array[String] = []
var active_reward_id: int = -1
var active: bool = true
var _rewards: Array[int] = []
var _offered: Array[WarriorTalentDefinition] = []
var _seen_checkpoints: Array[int] = []
var _next_reward_id: int = 1

func initialize(unlocked_ids: Array) -> void:
	selected_talents.clear()
	specializations.clear()
	unspent_specialization_points = 0
	unlocked_talents = WarriorTalentCatalog.sanitize_ids(unlocked_ids)
	discovered_synergies.clear()
	_rewards.clear()
	_offered.clear()
	_seen_checkpoints.clear()
	active_reward_id = -1
	_next_reward_id = 1
	active = true
	build_changed.emit()

func end_run() -> void:
	active = false
	_rewards.clear()
	_offered.clear()
	active_reward_id = -1
	build_changed.emit()

func offer_checkpoint(wave: int, initial: bool = false) -> bool:
	var key: int = 0 if initial else wave
	if not active or selected_talents.size() >= MAX_TALENTS or _seen_checkpoints.has(key):
		return false
	if not initial and not CHECKPOINT_WAVES.has(wave):
		return false
	_seen_checkpoints.append(key)
	_rewards.append(_next_reward_id)
	_next_reward_id += 1
	if active_reward_id < 0:
		_activate_next_reward()
	return true

func get_talent_options() -> Array[WarriorTalentDefinition]:
	return _offered.duplicate()

func choose_talent(talent_id: String, reward_id: int = -1) -> bool:
	if not _can_resolve(reward_id) or selected_talents.size() >= MAX_TALENTS or selected_talents.has(talent_id):
		return false
	var offered: bool = false
	for definition: WarriorTalentDefinition in _offered:
		if definition.id == talent_id:
			offered = true
			break
	if not offered:
		return false
	selected_talents.append(talent_id)
	_reveal_synergies()
	_finish_reward()
	return true

func focus(reward_id: int = -1) -> bool:
	if not _can_resolve(reward_id):
		return false
	unspent_specialization_points += FOCUS_POINTS
	_finish_reward()
	return true

func grant_specialization_point(amount: int = 1) -> void:
	if active and amount > 0:
		unspent_specialization_points += amount
		build_changed.emit()

func get_available_axes() -> Array[String]:
	var axes: Array[String] = BASE_AXES.duplicate()
	var extra: Dictionary = {"hot_blood": "hot_blood_healing", "wide_lunge": "lunge_distance", "tempered_blade": "vampirism", "loud_triumph": "triumph_power", "dismemberment": "morale_duration"}
	for talent_id: String in extra:
		if has_talent(talent_id):
			axes.append(extra[talent_id])
	return axes

func invest_specialization(axis: String) -> bool:
	if not active or unspent_specialization_points <= 0 or not get_available_axes().has(axis):
		return false
	specializations[axis] = int(specializations.get(axis, 0)) + 1
	unspent_specialization_points -= 1
	build_changed.emit()
	return true

func reset_specializations() -> void:
	if not active:
		return
	for rank: Variant in specializations.values():
		unspent_specialization_points += int(rank)
	specializations.clear()
	build_changed.emit()

func refund_specializations() -> void:
	reset_specializations()

func has_talent(talent_id: String) -> bool:
	return active and selected_talents.has(talent_id)

func has_synergy(synergy_id: String) -> bool:
	return active and discovered_synergies.has(synergy_id)

func get_property_multiplier(axis: String) -> float:
	var rank: float = float(specializations.get(axis, 0)) if active else 0.0
	if axis.ends_with("cooldown") or axis == "attack_speed":
		return 1.0 / (1.0 + rank * 0.08)
	return 1.0 + rank * (0.05 if axis == "cleave_radius" else 0.08)

func _can_resolve(reward_id: int) -> bool:
	return active and active_reward_id >= 0 and (reward_id < 0 or reward_id == active_reward_id)

func _activate_next_reward() -> void:
	if not active or _rewards.is_empty() or selected_talents.size() >= MAX_TALENTS:
		_rewards.clear()
		active_reward_id = -1
		_offered.clear()
		return
	active_reward_id = _rewards.pop_front()
	_offered.clear()
	var candidates: Array[WarriorTalentDefinition] = []
	for definition: WarriorTalentDefinition in WarriorTalentCatalog.get_all():
		if definition.implemented and unlocked_talents.has(definition.id) and not selected_talents.has(definition.id):
			candidates.append(definition)
	candidates.shuffle()
	for index: int in range(mini(3, candidates.size())):
		_offered.append(candidates[index])
	## An exhausted pool is an explicit, spendable Focus reward.
	checkpoint_ready.emit()

func _finish_reward() -> void:
	active_reward_id = -1
	_offered.clear()
	build_changed.emit()
	## Deferred UI refresh cannot consume the next reward in the same click.
	_activate_next_reward.call_deferred()

func _reveal_synergies() -> void:
	for synergy_id: String in WarriorTalentCatalog.SYNERGY_PAIRS:
		var pair: Array = WarriorTalentCatalog.SYNERGY_PAIRS[synergy_id]
		if selected_talents.has(pair[0]) and selected_talents.has(pair[1]) and not discovered_synergies.has(synergy_id):
			discovered_synergies.append(synergy_id)
			synergy_discovered.emit(synergy_id)

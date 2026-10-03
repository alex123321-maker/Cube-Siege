class_name PlayerStatusEffects
extends RefCounted

## Regeneration owns independent source timers; other statuses inspect existing state.
## No gameplay component knows about HUD nodes or textures.
class RegenerationSource extends RefCounted:
	var remaining: float
	var strength: float
	var radius: float
	var eligibility_check: Callable
	var requires_eligibility_check: bool
	func _init(seconds: float, hp_per_second: float, aura_radius: float, can_apply: Callable) -> void:
		remaining = seconds
		strength = hp_per_second
		radius = aura_radius
		eligibility_check = can_apply
		requires_eligibility_check = not can_apply.is_null()
	func is_eligible() -> bool:
		return not requires_eligibility_check or (eligibility_check.is_valid() and bool(eligibility_check.call()))

var _player: PlayerPrototype
var _regeneration: Dictionary[int, RegenerationSource] = {}
var _finished: bool = false

func setup(player: PlayerPrototype) -> void:
	_player = player
	_finished = false
	_regeneration.clear()

func refresh_regeneration(source_id: int, heal_per_second: float, refresh_duration: float = 0.6, radius: float = 5.0, eligibility_check: Callable = Callable()) -> void:
	if _finished:
		return
	if heal_per_second <= 0.0 or refresh_duration <= 0.0:
		remove_source(source_id)
		return
	_regeneration[source_id] = RegenerationSource.new(refresh_duration, heal_per_second, radius, eligibility_check)

func remove_source(source_id: int) -> void:
	_regeneration.erase(source_id)

func clear_regeneration() -> void:
	_regeneration.clear()

## Explicit run lifecycle; standalone prefabs do not require an active run build.
func finish_run() -> void:
	_finished = true
	clear_regeneration()

func regeneration_per_second() -> float:
	var total: float = 0.0
	for source: RegenerationSource in _regeneration.values():
		total += source.strength
	return total

func advance(delta: float) -> void:
	if _finished or not is_instance_valid(_player) or _player.current_health <= 0.0:
		_regeneration.clear()
		return
	var heal_amount: float = 0.0
	var expired: Array[int] = []
	for source_id: int in _regeneration:
		var source: RegenerationSource = _regeneration[source_id]
		# Validate at the point of healing, independent of the aura's refresh
		# interval or physics order. A freed guarded source is also ineligible.
		if not source.is_eligible():
			expired.append(source_id)
			continue
		# A large frame only heals for time during which each source was alive.
		heal_amount += source.strength * minf(maxf(delta, 0.0), source.remaining)
		source.remaining -= maxf(delta, 0.0)
		if source.remaining <= 0.0:
			expired.append(source_id)
	for source_id: int in expired:
		_regeneration.erase(source_id)
	if heal_amount > 0.0 and _player.current_health < _player.max_health:
		_player.heal(heal_amount)

func get_active_effects() -> Array[PlayerStatusEffect]:
	var effects: Array[PlayerStatusEffect] = []
	if _finished or not is_instance_valid(_player) or _player.current_health <= 0.0:
		return effects
	if not _regeneration.is_empty():
		var source: RegenerationSource = _regeneration.values()[0]
		effects.append(PlayerStatusEffect.new(&"regeneration", "Тепло костра", "Восстанавливает %s HP/с в зоне костра (радиус %s м).\nИсточников: %d. Лечение складывается; каждый костёр действует независимо.\nДлительность: пока герой находится в зоне." % [snappedf(regeneration_per_second(), 0.01), snappedf(source.radius, 0.1), _regeneration.size()], &"regeneration", 0.0, 0.0, Color(0.4, 0.95, 0.5), "АУРА"))
	if _player.health.is_parrying:
		var counter: bool = _player.talents.has("counterattack")
		var detail: String = "Поглощает все входящие удары в защитном окне и отвечает атакующему уроном %s." % snappedf(_player.talents.attack_based_ability_damage(), 0.01) if counter else "Поглощает первый входящий удар."
		detail += "\nПри успехе оглушает обычных врагов в радиусе %s м на %s с; элитных — на %s с. Боссы не оглушаются." % [PlayerHealth.COUNTER_RADIUS, PlayerHealth.COUNTER_STUN, PlayerHealth.COUNTER_STUN * 0.5]
		effects.append(PlayerStatusEffect.new(&"parry", "Контратака" if counter else "Парирование", detail, &"counter" if counter else &"parry", _player.health.parry_timer, _player.health.parry_total_duration, Color(0.45, 0.75, 1.0)))
	if _player.movement.is_dashing:
		var invulnerable: bool = _player.is_dash_invulnerable()
		effects.append(PlayerStatusEffect.new(&"dash", "Неуязвимость" if invulnerable else "Боевой рывок", "Входящий урон игнорируется до окончания рывка." if invulnerable else "Быстрое перемещение. Входящий урон проходит; парирование продолжает работать.", &"invulnerability" if invulnerable else &"dash", _player.movement.dash_timer, _player.dash_duration, Color(0.3, 0.85, 1.0)))
	if _player.abilities.is_dueling:
		var bonus: float = 20.0 * _player.talents.multiplier("duel_bonus")
		var reduction: float = 100.0 * (1.0 - 1.0 / (1.0 + (2.0 / 3.0) * _player.talents.multiplier("duel_resistance")))
		var reflection: float = 100.0 * minf(1.0, 0.2 * _player.talents.multiplier("duel_reflection"))
		effects.append(PlayerStatusEffect.new(&"duel", "Вызов на дуэль", "Урон взмахов по цели дуэли +%s%%. Сторонний урон здоровью −%s%%; отражение %s%%.\nГерой автоматически сближается с целью.\nДлительность: до смерти одной из сторон." % [snappedf(bonus, 0.01), snappedf(reduction, 0.01), snappedf(reflection, 0.01)], &"duel", 0.0, 0.0, Color(1.0, 0.75, 0.25)))
	if _player.abilities.is_eagle_eye:
		effects.append(PlayerStatusEffect.new(&"eagle_eye", "Око снайпера", "Расширяет обзор камеры.\nДлительность: до конца забега.", &"eagle_eye", 0.0, 0.0, Color(0.5, 0.95, 0.75)))
	_append_talent_effects(effects)
	if _player.health.shield_health > 0.0:
		effects.append(PlayerStatusEffect.new(&"shield", "Щит", "Поглощает урон до здоровья.\nОсталось %d единиц щита. Действует до разрушения." % ceili(_player.health.shield_health), &"shield", 0.0, 0.0, Color(0.4, 0.8, 1.0), "%dHP" % ceili(_player.health.shield_health)))
	if _player.vampirism_heal > 0.0 and _player.current_class != PlayerPrototype.CharacterClass.WARRIOR:
		effects.append(PlayerStatusEffect.new(&"vampirism", "Вампирический удар", "Ближнее попадание восстанавливает %s HP за взмах.\nДлительность: до конца забега." % snappedf(_player.vampirism_heal, 0.1), &"vampirism", 0.0, 0.0, Color(1.0, 0.35, 0.5)))
	if _player.resource_multiplier > 1:
		effects.append(PlayerStatusEffect.new(&"harvest", "Жадный добытчик", "Количество собираемых ресурсов ×%d.\nДлительность: до конца забега." % _player.resource_multiplier, &"harvest", 0.0, 0.0, Color(1.0, 0.8, 0.35)))
	return effects

func _append_talent_effects(effects: Array[PlayerStatusEffect]) -> void:
	var runtime: WarriorTalentRuntime = _player.talents
	if runtime.regeneration_remaining > 0.0:
		effects.append(PlayerStatusEffect.new(&"hot_blood", "Горячая кровь", "Восстанавливает %s HP/с после успешного парирования. Повторный успех обновляет время. Лечение складывается с теплом костра." % snappedf(WarriorTalentCatalog.HOT_BLOOD_RATE * runtime.multiplier("hot_blood_healing"), 0.01), &"hot_blood", runtime.regeneration_remaining, WarriorTalentCatalog.HOT_BLOOD_DURATION, Color(1.0, 0.45, 0.35)))
	if runtime.morale_remaining > 0.0:
		effects.append(PlayerStatusEffect.new(&"morale", "Боевой дух", "Скорость движения +%s%%; шанс уклонения от входящего удара %s%%." % [_number(WarriorTalentCatalog.MORALE_SPEED * 100.0), _number(WarriorTalentCatalog.MORALE_DODGE * 100.0)], &"morale", runtime.morale_remaining, runtime.morale_duration, Color(0.45, 0.9, 1.0)))
	if runtime.triumph_stacks > 0 and runtime.has("loud_triumph"):
		effects.append(PlayerStatusEffect.new(&"triumph", "Громкий триумф", "Побед в дуэли: %d. Урон обычной атаки +%s%% до конца забега." % [runtime.triumph_stacks, snappedf(runtime.triumph_stacks * WarriorTalentCatalog.TRIUMPH_BONUS * runtime.multiplier("triumph_power") * 100.0, 0.01)], &"triumph", 0.0, 0.0, Color(1.0, 0.8, 0.3), "×%d" % runtime.triumph_stacks))
	if runtime.has("tempered_blade"):
		effects.append(PlayerStatusEffect.new(&"tempered_blade", "Закалённый клинок", "Прямые атаки, рассечение и рывок лечат на %s%% фактического урона здоровью монстра. Щиты и отражение не лечат.%s" % [snappedf(WarriorTalentCatalog.VAMPIRISM_FRACTION * runtime.multiplier("vampirism") * 100.0, 0.01), "\nСинергия «Закалка кровью»: контратака тоже лечит." if runtime.build().has_synergy("blood_tempering") else ""], &"tempered_blade", 0.0, 0.0, Color(1.0, 0.35, 0.5)))
	var resistance: float = 0.8 if runtime.has("dismemberment") else 0.0
	for slow: StatusEffectState.TimedEffect in runtime.statuses.slows:
		effects.append(PlayerStatusEffect.new(StringName("slow:" + slow.source), "Замедление", "Снижает скорость движения на %s%% с учётом сопротивления.\nСуммарное замедление от всех источников: %s%%. Источники действуют независимо." % [_number(slow.strength * (1.0 - resistance) * 100.0), _number((1.0 - runtime.statuses.movement_multiplier(resistance)) * 100.0)], &"slow", slow.remaining, slow.duration, Color(0.65, 0.6, 1.0)))
	for stun: StatusEffectState.TimedEffect in runtime.statuses.stuns:
		effects.append(PlayerStatusEffect.new(StringName("stun:" + stun.source), "Оглушение", "Оглушён до окончания эффекта.", &"stun", stun.remaining, stun.duration, Color(1.0, 0.8, 0.3)))

func _number(value: float) -> String:
	var rounded: float = snappedf(value, 0.01)
	return str(int(rounded)) if is_equal_approx(rounded, roundf(rounded)) else str(rounded)

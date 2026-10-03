class_name PlayerStatusEffects
extends RefCounted

## Regeneration owns independent source timers; other statuses inspect existing state.
## No gameplay component knows about HUD nodes or textures.
class RegenerationSource extends RefCounted:
	var remaining: float
	var strength: float
	var radius: float
	func _init(seconds: float, hp_per_second: float, aura_radius: float) -> void:
		remaining = seconds
		strength = hp_per_second
		radius = aura_radius

var _player: PlayerPrototype
var _regeneration: Dictionary[int, RegenerationSource] = {}

func setup(player: PlayerPrototype) -> void:
	_player = player

func refresh_regeneration(source_id: int, heal_per_second: float, refresh_duration: float = 0.6, radius: float = 5.0) -> void:
	if heal_per_second <= 0.0 or refresh_duration <= 0.0:
		remove_source(source_id)
		return
	_regeneration[source_id] = RegenerationSource.new(refresh_duration, heal_per_second, radius)

func remove_source(source_id: int) -> void:
	_regeneration.erase(source_id)

func regeneration_per_second() -> float:
	var total: float = 0.0
	for source: RegenerationSource in _regeneration.values():
		total += source.strength
	return total

func advance(delta: float) -> void:
	if not is_instance_valid(_player) or _player.current_health <= 0.0:
		_regeneration.clear()
		return
	var heal_amount: float = 0.0
	var expired: Array[int] = []
	for source_id: int in _regeneration:
		var source: RegenerationSource = _regeneration[source_id]
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
	if not is_instance_valid(_player) or _player.current_health <= 0.0:
		return effects
	if not _regeneration.is_empty():
		var source: RegenerationSource = _regeneration.values()[0]
		effects.append(PlayerStatusEffect.new(&"regeneration", "Тепло костра", "Восстанавливает %s HP/с в зоне костра (радиус %s м).\nИсточников: %d. Лечение складывается; каждый костёр действует независимо.\nДлительность: пока герой находится в зоне." % [snappedf(regeneration_per_second(), 0.01), snappedf(source.radius, 0.1), _regeneration.size()], &"regeneration", 0.0, 0.0, Color(0.4, 0.95, 0.5), "АУРА"))
	if _player.health.is_parrying:
		effects.append(PlayerStatusEffect.new(&"parry", "Парирование", "Поглощает первый входящий удар.\nПри успехе оглушает врагов в радиусе %s м на %s с." % [PlayerHealth.COUNTER_RADIUS, PlayerHealth.COUNTER_STUN], &"parry", _player.health.parry_timer, PlayerHealth.PARRY_WINDOW, Color(0.45, 0.75, 1.0)))
	if _player.movement.is_dashing:
		var invulnerable: bool = _player.is_dash_invulnerable()
		effects.append(PlayerStatusEffect.new(&"dash", "Неуязвимость" if invulnerable else "Боевой рывок", "Входящий урон игнорируется до окончания рывка." if invulnerable else "Быстрое перемещение. Входящий урон проходит; парирование продолжает работать.", &"invulnerability" if invulnerable else &"dash", _player.movement.dash_timer, _player.dash_duration, Color(0.3, 0.85, 1.0)))
	if _player.abilities.is_dueling:
		effects.append(PlayerStatusEffect.new(&"duel", "Вызов на дуэль", "Урон взмахов +20%. Урон от сторонних врагов −40%; 20% отражается.\nГерой автоматически сближается с целью.\nДлительность: до смерти одной из сторон.", &"duel", 0.0, 0.0, Color(1.0, 0.75, 0.25)))
	if _player.abilities.is_eagle_eye:
		effects.append(PlayerStatusEffect.new(&"eagle_eye", "Око снайпера", "Расширяет обзор камеры.\nДлительность: до конца забега.", &"eagle_eye", 0.0, 0.0, Color(0.5, 0.95, 0.75)))
	if _player.vampirism_heal > 0.0:
		effects.append(PlayerStatusEffect.new(&"vampirism", "Вампирический удар", "Ближнее попадание восстанавливает %s HP за взмах.\nДлительность: до конца забега." % snappedf(_player.vampirism_heal, 0.1), &"vampirism", 0.0, 0.0, Color(1.0, 0.35, 0.5)))
	if _player.resource_multiplier > 1:
		effects.append(PlayerStatusEffect.new(&"harvest", "Жадный добытчик", "Количество собираемых ресурсов ×%d.\nДлительность: до конца забега." % _player.resource_multiplier, &"harvest", 0.0, 0.0, Color(1.0, 0.8, 0.35)))
	return effects

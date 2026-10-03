class_name HUDAbilityDetails
extends RefCounted

## Tooltips consume the executing combat values and prefab defaults, including upgrades.
const TURRET_SCRIPT: GDScript = preload("res://scripts/temp_turret.gd")
const MINE_SCRIPT: GDScript = preload("res://scripts/remote_mine.gd")
const DECOY_SCRIPT: GDScript = preload("res://scripts/decoy_dummy.gd")
const ARROW_SCRIPT: GDScript = preload("res://scripts/arrow_projectile.gd")

class PrefabValues extends RefCounted:
	var turret_damage: float
	var turret_interval: float
	var turret_range: float
	var turret_duration: float
	var mine_damage: float
	var mine_radius: float
	var decoy_duration: float
	var decoy_health: float
	var arrow_duration: float

static var _prefabs: PrefabValues

static func _values() -> PrefabValues:
	if _prefabs:
		return _prefabs
	_prefabs = PrefabValues.new()
	var turret: TURRET_SCRIPT = PlayerAbilities.TEMP_TURRET_SCENE.instantiate() as TURRET_SCRIPT
	_prefabs.turret_damage = turret.damage
	_prefabs.turret_interval = turret.fire_rate
	_prefabs.turret_range = turret.attack_range
	_prefabs.turret_duration = turret.lifetime
	turret.free()
	var mine: MINE_SCRIPT = PlayerAbilities.REMOTE_MINE_SCENE.instantiate() as MINE_SCRIPT
	_prefabs.mine_damage = mine.blast_damage
	_prefabs.mine_radius = mine.blast_radius
	mine.free()
	var decoy: DECOY_SCRIPT = PlayerAbilities.DECOY_DUMMY_SCENE.instantiate() as DECOY_SCRIPT
	_prefabs.decoy_duration = decoy.lifetime
	_prefabs.decoy_health = decoy.max_health
	decoy.free()
	var arrow: ARROW_SCRIPT = PlayerCombat.ARROW_PROJECTILE_SCENE.instantiate() as ARROW_SCRIPT
	_prefabs.arrow_duration = arrow.lifetime
	arrow.free()
	return _prefabs

static func describe(player: PlayerPrototype, slot: int) -> String:
	if not is_instance_valid(player):
		return ""
	var c: int = int(player.current_class)
	var values: PrefabValues = _values()
	var rows: PackedStringArray = []
	match slot:
		0:
			var damage: float = player.attack_damage * (PlayerCombat.HAMMER_DAMAGE_MULTIPLIER if c == 2 else 1.0)
			if player.is_dueling and c != 1:
				damage *= PlayerCombat.DUEL_DAMAGE_MULTIPLIER
			rows.append(["Удар мечом [ЛКМ]\nПоражает первую цель перед героем.", "Выстрел из лука [ЛКМ]\nСтрела летит по направлению прицеливания.", "Удар молотом [ЛКМ]\nТяжёлый взмах поражает несколько целей и ремонтирует ближайшие постройки."][c])
			rows.append(_attribute("Урон", damage))
			rows.append(_attribute("Перезарядка", PlayerCombat.ATTACK_COOLDOWNS[c], "с"))
			rows.append(_attribute("Замах", PlayerCombat.ATTACK_WINDUPS[c], "с"))
			if c == 1:
				_arrow_rows(rows, PlayerCombat.ARROW_SPEED, values.arrow_duration, 1)
			else:
				_melee_rows(rows, player)
				rows.append("Целей: 1" if c == 0 else "Целей: все в области удара")
				rows.append(_attribute("Отбрасывание", 5.0 if c == 0 else 6.0, "м/с"))
				rows.append(_attribute("Активное окно", PlayerCombat.SLASH_ACTIVE_DURATION, "с"))
				if c == 2:
					rows.append("Ремонт: 40 HP · радиус 2,8 м")
				if player.vampirism_heal > 0.0:
					rows.append(_attribute("Лечение за взмах", player.vampirism_heal, "HP"))
		1:
			rows.append(["Рассечение [ПКМ]\nШирокий взмах поражает всех врагов в секторе перед героем.", "Сквозная стрела [ПКМ]\nУсиленная стрела пробивает несколько целей на одной линии.", "Временная турель [ПКМ]\nАвтоматически стреляет в ближайшего врага; исчезает по окончании времени жизни."][c])
			rows.append(_attribute("Перезарядка", PlayerCombat.SPECIAL_COOLDOWNS[c], "с"))
			rows.append(_attribute("Замах", PlayerCombat.CLEAVE_SPEC.windup if c == 0 else PlayerCombat.SPECIAL_WINDUPS[c], "с"))
			if c == 2:
				rows.append(_attribute("Урон снаряда", values.turret_damage))
				rows.append(_attribute("Радиус поиска", values.turret_range, "м"))
				rows.append(_attribute("Интервал выстрелов", values.turret_interval, "с"))
				rows.append(_attribute("Длительность", values.turret_duration, "с"))
				rows.append("Урон турели независим от урона героя.")
			else:
				var damage: float = player.special_damage * (PlayerCombat.PIERCING_DAMAGE_MULTIPLIER if c == 1 else 1.0)
				if player.is_dueling and c == 0:
					damage *= PlayerCombat.DUEL_DAMAGE_MULTIPLIER
				rows.append(_attribute("Урон", damage))
				if c == 0:
					rows.append(_attribute("Радиус", PlayerCombat.CLEAVE_SPEC.radius, "м"))
					rows.append(_attribute("Сектор", PlayerCombat.CLEAVE_SPEC.arc_degrees, "°"))
					rows.append(_attribute("Отбрасывание", 12.0, "м/с"))
					rows.append(_attribute("Восстановление базовой атаки", PlayerCombat.CLEAVE_SPEC.recovery, "с"))
					if player.vampirism_heal > 0.0:
						rows.append(_attribute("Лечение за взмах", player.vampirism_heal, "HP"))
				else:
					_arrow_rows(rows, PlayerCombat.PIERCING_SPEED, values.arrow_duration, PlayerCombat.PIERCING_TARGETS)
		2:
			rows.append(["Боевой рывок [SPACE]", "Кувырок [SPACE]", "Тактический рывок [SPACE]"][c])
			rows.append("Перемещение по WASD; без ввода — по направлению взгляда. Стены и обрывы блокируют путь.")
			rows.append(_attribute("Перезарядка", player.dash_cooldown, "с"))
			rows.append(_attribute("Длительность", player.dash_duration, "с"))
			rows.append(_attribute("Скорость", player.dash_speed, "м/с"))
			rows.append(_attribute("Дальность на ровной поверхности", player.dash_speed * player.dash_duration, "м"))
			rows.append("Воин получает урон во время рывка. Парирование действует." if c == 0 else "Неуязвимость к урону на всё время рывка.")
		3:
			if c == 0:
				rows.append("Парирование [Q]\nЗащитная стойка поглощает один первый удар или снаряд и оглушает окружающих врагов.")
				rows.append(_attribute("Защитное окно", PlayerHealth.PARRY_WINDOW, "с"))
				rows.append(_attribute("Перезарядка при промахе", PlayerHealth.PARRY_COOLDOWN, "с"))
				rows.append(_attribute("Перезарядка при успехе", PlayerHealth.PARRY_SUCCESS_COOLDOWN, "с"))
				rows.append(_attribute("Радиус оглушения", PlayerHealth.COUNTER_RADIUS, "м"))
				rows.append(_attribute("Длительность оглушения", PlayerHealth.COUNTER_STUN, "с"))
				rows.append(_attribute("Ответный урон", PlayerHealth.COUNTER_DAMAGE))
			elif c == 1:
				rows.append("Приманка [Q]\nЧучело появляется перед героем и отвлекает ближайших врагов. Может быть разрушено раньше срока.")
				rows.append(_attribute("Перезарядка", PlayerAbilities.DECOY_COOLDOWN, "с"))
				rows.append(_attribute("Радиус агро", DECOY_SCRIPT.AGGRO_RADIUS, "м"))
				rows.append(_attribute("Длительность", values.decoy_duration, "с"))
				rows.append(_attribute("Здоровье чучела", values.decoy_health, "HP"))
			else:
				rows.append("Управляемая мина [Q]\nПервое нажатие закладывает мину у ног героя. Повторное — подрывает её в любой момент.")
				rows.append(_attribute("Урон взрыва", values.mine_damage))
				rows.append(_attribute("Радиус взрыва", values.mine_radius, "м"))
				rows.append(_attribute("Перезарядка после подрыва", PlayerAbilities.MINE_RELOAD, "с"))
				rows.append("Длительность: до подрыва. Урон независим от урона героя.")
		4:
			if c == 0:
				rows.append("Вызов на дуэль [F]\nВыбирает врага под курсором. Герой и цель автоматически сближаются; атаки и умения остаются доступны.")
				rows.append(_attribute("Перезарядка", player.ultimate_cooldown, "с"))
				rows.append("Урон взмахов: +20%\nУрон от сторонних врагов: −40%\nОтражение стороннего урона: 20%\nДлительность: до смерти одной из сторон.")
			elif c == 1:
				rows.append("Око снайпера [F]\nРасширяет обзор камеры для дальнего прицеливания.")
				rows.append("Перезарядка: 25 с\nДлительность: до конца забега. Повторная активация не требуется.")
			else:
				rows.append("Орбитальный удар [F]\nПомечает точку под курсором. Взрыв поражает всех врагов в горизонтальном радиусе независимо от высоты и оставляет горящую область.")
				rows.append(_attribute("Перезарядка", PlayerAbilities.NUKE_COOLDOWN, "с"))
				rows.append(_attribute("Время до взрыва", PlayerAbilities.NUKE_WINDUP, "с"))
				rows.append(_attribute("Урон взрыва", PlayerAbilities.NUKE_DAMAGE))
				rows.append(_attribute("Радиус", PlayerAbilities.NUKE_RADIUS, "м"))
				rows.append(_attribute("Урон горения за тик", PlayerAbilities.NUKE_BURN_DAMAGE))
				rows.append(_attribute("Интервал тиков", PlayerAbilities.NUKE_BURN_INTERVAL, "с"))
				rows.append(_attribute("Длительность горения", PlayerAbilities.NUKE_BURN_INTERVAL * PlayerAbilities.NUKE_BURN_TICKS, "с"))
				rows.append("Тиков: %d · снимает сопротивление осадных врагов." % PlayerAbilities.NUKE_BURN_TICKS)
	return "\n".join(rows)

static func _attribute(title: String, value: float, unit: String = "") -> String:
	var rounded: float = snappedf(value, 0.01)
	var number: String = str(int(rounded)) if is_equal_approx(rounded, roundf(rounded)) else str(rounded)
	return ("%s: %s %s" % [title, number, unit]).strip_edges()

static func _arrow_rows(rows: PackedStringArray, speed: float, duration: float, targets: int) -> void:
	rows.append(_attribute("Скорость стрелы", speed, "м/с"))
	rows.append(_attribute("Время полёта", duration, "с"))
	rows.append(_attribute("Предельная дальность", speed * duration, "м"))
	rows.append("Целей: %d · рельеф и стены ограничивают полёт." % targets)

static func _melee_rows(rows: PackedStringArray, player: PlayerPrototype) -> void:
	# The regular footprint survives the temporary cleave cylinder replacement.
	var shape: Shape3D = player.combat._regular_slash_shape
	if not shape and player.slash_area:
		var collider: CollisionShape3D = player.slash_area.get_node("CollisionShape3D") as CollisionShape3D
		shape = collider.shape
	if shape is BoxShape3D:
		var box: BoxShape3D = shape as BoxShape3D
		rows.append("Область перед героем: %s × %s м" % [snappedf(box.size.x, 0.01), snappedf(box.size.z, 0.01)])
	rows.append("Попадания по связанному рельефу; уступы 2+ блока блокируют удар.")

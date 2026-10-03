extends RefCounted
class_name AbilityViewerCatalog

## Read-only catalogue of existing gameplay entry points and supported scenarios.
enum Slot { ATTACK, SPECIAL, UTILITY, ULTIMATE, DASH }
enum VariantKind { BASE, SHARP_EDGE, VAMPIRISM, DUEL, WINDSTRIDER, PARRY_SUCCESS, DETONATE }

class Entry extends RefCounted:
	var class_id: int
	var slot: Slot
	var title: String
	var description: String
	var planned: String
	var preview_talents: Array[String] = []
	func _init(owner_class: int, action: Slot, caption: String, detail: String, future: String = "") -> void:
		class_id = owner_class
		slot = action
		title = caption
		description = detail
		planned = future

class Property extends RefCounted:
	var title: String
	var base: String
	var effective: String
	var explanation: String
	func _init(caption: String, original: String, current: String, detail: String) -> void:
		title = caption
		base = original
		effective = current
		explanation = detail

static func entries() -> Array[Entry]:
	var result: Array[Entry] = [
		Entry.new(0, Slot.ATTACK, "Удар мечом", "Ближний удар настоящим SlashHitbox. Направление и попадания определяет игровой код."),
		Entry.new(0, Slot.SPECIAL, "Рассечение", "Широкий взмах с усиленным уроном и отбрасыванием. Таланты доступны ниже как отдельные игровые демонстрации."),
		Entry.new(0, Slot.UTILITY, "Парирование", "Защитная стойка. В варианте успеха зомби атакует во время защитного окна."),
		Entry.new(0, Slot.ULTIMATE, "Вызов на дуэль", "Выбранный зомби становится целью дуэли. Воин сближается с ним; атаки получают бонус."),
		Entry.new(0, Slot.DASH, "Боевой рывок", "Рывок Воина без неуязвимости к урону: Воин получает входящий урон во время перемещения."),
		Entry.new(1, Slot.ATTACK, "Выстрел из лука", "Настоящий снаряд Лучника, показанный моделью Воина."),
		Entry.new(1, Slot.SPECIAL, "Сквозная стрела", "Усиленная стрела проходит через несколько целей.", "Осколки, сбивание с ног и срез брони описаны в GDD; в коде пока не реализованы."),
		Entry.new(1, Slot.UTILITY, "Приманка", "Создаёт игровое чучело и переназначает цели ближайших зомби."),
		Entry.new(1, Slot.ULTIMATE, "Око снайпера", "Текущий код включает состояние Eagle Eye и отдаляет камеру.", "Пассивный режим и +50% дальности из GDD пока не подключены к расчёту полёта стрел. Просмотр показывает текущую реализацию."),
		Entry.new(1, Slot.DASH, "Кувырок", "Сейчас использует общий механизм рывка.", "Отдельные 6 м и бонус бега из GDD пока не реализованы."),
		Entry.new(2, Slot.ATTACK, "Удар молотом", "Повышенный урон ближнего удара. Игровой обработчик также ремонтирует союзные постройки рядом."),
		Entry.new(2, Slot.SPECIAL, "Временная турель", "Создаёт настоящую автоматическую турель; стреляет по ближайшим целям."),
		Entry.new(2, Slot.UTILITY, "Управляемая мина", "Первое применение устанавливает мину, второе взрывает её.", "Оглушение из GDD пока не применяется игровым обработчиком мины."),
		Entry.new(2, Slot.ULTIMATE, "Орбитальный удар", "Телеграф, взрыв и периодический урон горящей области. Используется игровой обработчик удара."),
		Entry.new(2, Slot.DASH, "Тактический отскок", "Сейчас использует общий механизм рывка.", "Отскок назад и замедляющие шипы из GDD пока не реализованы.")
	]
	var slots: Array[Slot] = [Slot.ATTACK, Slot.UTILITY, Slot.SPECIAL, Slot.ULTIMATE, Slot.UTILITY, Slot.ATTACK, Slot.SPECIAL, Slot.ULTIMATE, Slot.DASH]
	var definitions: Array[WarriorTalentDefinition] = WarriorTalentCatalog.get_all()
	for index: int in range(definitions.size()):
		var entry: Entry = Entry.new(0, slots[index], definitions[index].title, definitions[index].description)
		entry.preview_talents.append(definitions[index].id)
		result.append(entry)
	# Recipes are confined to the diagnostic viewer, never the player talent tree.
	for id: String in WarriorTalentCatalog.SYNERGY_PAIRS:
		var entry: Entry = Entry.new(0, Slot.UTILITY if id == "blood_tempering" else (Slot.SPECIAL if id == "carnage" else Slot.DASH), "Комбинация: " + WarriorTalentCatalog.SYNERGY_TITLES[id], "Проверка автоматической комбинации на настоящем боевом коде.")
		for talent: String in WarriorTalentCatalog.SYNERGY_PAIRS[id]:
			entry.preview_talents.append(talent)
		result.append(entry)
	return result

static func variants(entry: Entry) -> Array[VariantKind]:
	var result: Array[VariantKind] = [VariantKind.BASE]
	if not entry.preview_talents.is_empty():
		return result
	if entry.slot == Slot.ATTACK or (entry.slot == Slot.SPECIAL and entry.class_id != 2):
		result.append(VariantKind.SHARP_EDGE)
	if (entry.class_id == 0 and entry.slot in [Slot.ATTACK, Slot.SPECIAL]) or (entry.class_id == 2 and entry.slot == Slot.ATTACK):
		result.append(VariantKind.VAMPIRISM)
	if entry.class_id == 0 and entry.slot in [Slot.ATTACK, Slot.SPECIAL]:
		result.append(VariantKind.DUEL)
	if entry.slot == Slot.DASH:
		result.append(VariantKind.WINDSTRIDER)
	if entry.class_id == 0 and entry.slot == Slot.UTILITY:
		result.append(VariantKind.PARRY_SUCCESS)
	if entry.class_id == 2 and entry.slot == Slot.UTILITY:
		result.append(VariantKind.DETONATE)
	return result

static func variant_title(kind: VariantKind) -> String:
	return ["Базовая способность", "Карта: Острый край", "Карта: Вампирический удар", "Во время дуэли", "Карта: Ветроход", "Успешное парирование", "Установка и подрыв"][kind]

static func variant_explanation(kind: VariantKind) -> String:
	return [
		"Показаны исходные свойства текущей реализации.",
		"Игровая карта SHARP_EDGE увеличивает базовый урон на 25% с округлением. Затем применяется множитель выбранной атаки.",
		"Карта VAMPIRIC_STRIKE задаёт 4 HP лечения. Воин начинает с неполным здоровьем. Известная особенность текущего кода: позднее попадание может пройти после проверки лечения; в этом случае HP не восстанавливается.",
		"Состояние дуэли умножает урон взмахов на 1.2. Защита от сторонних атак: 40% снижения и 20% отражения.",
		"Игровая карта WINDSTRIDER умножает скорость бега на 1.2, перезарядку рывка — на 0.65. Скорость самого рывка не меняется.",
		"Входящий удар попадает в окно парирования: урон блокируется, срабатывает AoE оглушение врагов без ответного урона, перезарядка сокращается.",
		"Демонстрация выполняет два обычных применения утилиты с интервалом 1 с. Урон и радиус берутся из настоящей сцены мины."
	][kind]

static func properties(entry: Entry, player: CharacterBody3D, variant: VariantKind) -> Array[Property]:
	var rows: Array[Property] = []
	if not entry.preview_talents.is_empty():
		for talent: String in entry.preview_talents:
			var definition: WarriorTalentDefinition = WarriorTalentCatalog.get_talent(talent)
			rows.append(Property.new(definition.title, "Не выбран", "Взят в этом просмотре", definition.description))
	var base_combat: PlayerCombat = PlayerCombat.new()
	var base_movement: PlayerMovement = PlayerMovement.new()
	var c: int = entry.class_id
	var runtime: WarriorTalentRuntime = (player as PlayerPrototype).talents if c == 0 and player is PlayerPrototype else null
	match entry.slot:
		Slot.ATTACK, Slot.SPECIAL:
			var special: bool = entry.slot == Slot.SPECIAL
			var cooldown: float = PlayerCombat.SPECIAL_COOLDOWNS[c] if special else PlayerCombat.ATTACK_COOLDOWNS[c]
			var windup: float = (PlayerCombat.CLEAVE_SPEC.windup if c == 0 else PlayerCombat.SPECIAL_WINDUPS[c]) if special else PlayerCombat.ATTACK_WINDUPS[c]
			_value(rows, "Перезарядка", cooldown, cooldown, "с", "Минимальный интервал между применениями.")
			_value(rows, "Подготовка", windup, windup, "с", "Время от запуска анимации до игрового действия.")
			if special and c == 2:
				var turret: Node3D = PlayerAbilities.TEMP_TURRET_SCENE.instantiate() as Node3D
				_value(rows, "Урон снаряда", turret.damage, turret.damage, "", "Собственный урон турели; карта урона игрока его не меняет.")
				_value(rows, "Интервал выстрелов", turret.fire_rate, turret.fire_rate, "с", "Меньше интервал — чаще выстрелы.")
				_value(rows, "Дальность", turret.attack_range, turret.attack_range, "м", "Поиск ближайшей цели в этом радиусе.")
				_value(rows, "Время жизни", turret.lifetime, turret.lifetime, "с", "После этого турель исчезает.")
				turret.free()
			else:
				var multiplier: float = PlayerCombat.HAMMER_DAMAGE_MULTIPLIER if c == 2 else (PlayerCombat.PIERCING_DAMAGE_MULTIPLIER if c == 1 and special else 1.0)
				var base: float = (base_combat.special_damage if special else base_combat.attack_damage) * multiplier
				var effective: float = (player.special_damage if special else player.attack_damage) * multiplier
				if variant == VariantKind.DUEL:
					effective *= PlayerCombat.DUEL_DAMAGE_MULTIPLIER
				_value(rows, "Урон попадания", base, effective, "", "Базовый урон × множитель умения; состояние дуэли учитывается после карты.")
				if c == 1:
					rows.append(Property.new("Регистрация урона", "Игровые обработчики", "Смотрите журнал", "В текущей сцене стрелы урон передают два обработчика. Один контакт может дать два вызова урона; журнал показывает оба. Это существующая ошибка, а не бонус варианта."))
					var speed: float = PlayerCombat.PIERCING_SPEED if special else PlayerCombat.ARROW_SPEED
					_value(rows, "Скорость стрелы", speed, speed, "м/с", "Скорость движения настоящего снаряда.")
					var targets: float = PlayerCombat.PIERCING_TARGETS if special else 1
					_value(rows, "Предел целей", targets, targets, "", "После этого числа попаданий стрела исчезает.")
				else:
					var moving_cleave: bool = c == 0 and special and runtime != null and runtime.has("wide_lunge")
					var active_window: float = WarriorTalentCatalog.LUNGE_DURATION if moving_cleave else PlayerCombat.SLASH_ACTIVE_DURATION
					_value(rows, "Активное окно", PlayerCombat.SLASH_ACTIVE_DURATION, active_window, "с", "В это время SlashHitbox принимает столкновения; при выпаде область движется вместе с Воином." if moving_cleave else "В это время SlashHitbox принимает столкновения.")
					if c == 0 and special:
						var circular: bool = runtime != null and runtime.has("whirlwind_cleave")
						var radius: float = PlayerCombat.CLEAVE_SPEC.radius * (runtime.multiplier("cleave_radius") if runtime else 1.0)
						rows.append(Property.new("Форма попадания", "Полукруг", "Круг" if circular else "Полукруг", "Область поражения ограничивается игровым сектором. Несколько целей, не более одного попадания в каждую за применение."))
						_value(rows, "Радиус", PlayerCombat.CLEAVE_SPEC.radius, radius, "м", "Радиус из игрового WarriorCleaveSpec с текущей специализацией.")
						_value(rows, "Угол сектора", PlayerCombat.CLEAVE_SPEC.arc_degrees, 360.0 if circular else PlayerCombat.CLEAVE_SPEC.arc_degrees, "°", "Вихревое рассечение проверяет цели вокруг Воина; обычное — впереди.")
					else:
						var shape: Shape3D = player.get_node("SlashHitbox/CollisionShape3D").shape
						var shape_text: String = str((shape as BoxShape3D).size) if shape is BoxShape3D else "Цилиндр"
						rows.append(Property.new("Форма попадания", shape_text, shape_text, "Размеры игрового прямоугольного хитбокса в метрах. Визуальная дуга не задаёт сектор попадания."))
						if c == 0:
							rows.append(Property.new("Предел целей", "1", "Все в области" if runtime != null and runtime.has("sweeping_strike") else "1", "«Разящий удар» разрешает несколько целей; базовая атака поражает одну. Каждая цель получает один удар за применение."))
					if runtime != null and runtime.has("tempered_blade"):
						_value(rows, "Лечение от урона здоровью", 0.0, WarriorTalentCatalog.VAMPIRISM_FRACTION * runtime.multiplier("vampirism") * 100.0, "%", "Процент фактической потери HP цели. Щит, избыточный урон и отражение не лечат; ответный удар лечит только с «Закалкой кровью».")
					else:
						_value(rows, "Параметр лечения", 0.0, player.vampirism_heal, "HP", "Параметр прежней карты. Лечение Воина в забеге задаёт талант «Закалённый клинок», а не это значение." if c == 0 else "Значение прежней карты; фактическое восстановление HP показано под сценой.")
		Slot.DASH:
			_value(rows, "Перезарядка", base_movement.dash_cooldown, player.dash_cooldown, "с", "Карта Ветроход сокращает ожидание следующего рывка.")
			_value(rows, "Скорость рывка", base_movement.dash_speed, player.dash_speed, "м/с", "Отдельна от скорости обычного бега.")
			var dash_invulnerable: bool = c != 0 or (player is PlayerPrototype and (player as PlayerPrototype).talents.has("perfect_dash"))
			var dash_expl: String = "Пока состояние рывка активно, входящий урон игнорируется." if dash_invulnerable else "У Воина без «Идеального рывка» входящий урон во время рывка проходит."
			_value(rows, "Длительность", base_movement.dash_duration, player.dash_duration, "с", dash_expl)
			_value(rows, "Скорость бега", base_movement.speed, player.speed, "м/с", "Показано влияние карты; это не скорость рывка.")
		Slot.UTILITY:
			if c == 0:
				var parry_window: float = runtime.parry_duration() if runtime else PlayerHealth.PARRY_WINDOW
				var counter: bool = runtime != null and runtime.has("counterattack")
				var counter_damage: float = runtime.attack_based_ability_damage() if counter else PlayerHealth.COUNTER_DAMAGE
				_value(rows, "Защитное окно", PlayerHealth.PARRY_WINDOW, parry_window, "с", "Попавший в окно удар блокируется.")
				_value(rows, "Перезарядка", PlayerHealth.PARRY_COOLDOWN, PlayerHealth.PARRY_SUCCESS_COOLDOWN if variant == VariantKind.PARRY_SUCCESS else PlayerHealth.PARRY_COOLDOWN, "с", "При успешном парировании используется сокращённая перезарядка.")
				var counter_expl: String = "«Контратака» возвращает удар атакующему; урон берётся из игрового расчёта способности без постоянного бонуса урона профиля." if counter else "Базовое парирование не наносит ответного урона (вынесен в талант «Контратака»)."
				_value(rows, "Ответный урон", PlayerHealth.COUNTER_DAMAGE, counter_damage, "", counter_expl)
				_value(rows, "Радиус оглушения", PlayerHealth.COUNTER_RADIUS, PlayerHealth.COUNTER_RADIUS, "м", "Оглушение применяется ко всем врагам в радиусе 3.5м.")
				_value(rows, "Оглушение", PlayerHealth.COUNTER_STUN, PlayerHealth.COUNTER_STUN, "с", "Останавливает действия врага после парирования.")
			elif c == 1:
				var decoy: Node3D = PlayerAbilities.DECOY_DUMMY_SCENE.instantiate() as Node3D
				_value(rows, "Перезарядка", PlayerAbilities.DECOY_COOLDOWN, PlayerAbilities.DECOY_COOLDOWN, "с", "Ожидание следующей приманки.")
				_value(rows, "Время жизни", decoy.lifetime, decoy.lifetime, "с", "На это время приманка отвлекает врагов.")
				_value(rows, "Здоровье", decoy.max_health, decoy.max_health, "HP", "Приманку можно разрушить раньше срока.")
				decoy.free()
			else:
				var mine: Node3D = PlayerAbilities.REMOTE_MINE_SCENE.instantiate() as Node3D
				_value(rows, "Урон взрыва", mine.blast_damage, mine.blast_damage, "", "Собственный урон мины; не масштабируется уроном игрока.")
				_value(rows, "Радиус взрыва", mine.blast_radius, mine.blast_radius, "м", "Цели проверяются по трёхмерной дистанции от мины.")
				_value(rows, "Перезарядка после подрыва", PlayerAbilities.MINE_RELOAD, PlayerAbilities.MINE_RELOAD, "с", "Отсчитывается после второго применения.")
				mine.free()
		Slot.ULTIMATE:
			if c == 0:
				_value(rows, "Перезарядка", player.ultimate_cooldown, player.ultimate_cooldown, "с", "Дуэль продолжается до смерти одной из сторон.")
				_value(rows, "Множитель взмахов", 1.0, PlayerCombat.DUEL_DAMAGE_MULTIPLIER, "×", "Бонус действует в состоянии дуэли.")
			elif c == 1:
				rows.append(Property.new("Текущий эффект", "Обычная камера", "Камера отдаляется", "Включается Eagle Eye. Увеличение дальности стрел пока не реализовано."))
			else:
				_value(rows, "Перезарядка", PlayerAbilities.NUKE_COOLDOWN, PlayerAbilities.NUKE_COOLDOWN, "с", "Ожидание следующего удара.")
				_value(rows, "Телеграф", PlayerAbilities.NUKE_WINDUP, PlayerAbilities.NUKE_WINDUP, "с", "Задержка до взрыва.")
				_value(rows, "Урон взрыва", PlayerAbilities.NUKE_DAMAGE, PlayerAbilities.NUKE_DAMAGE, "", "Разовый урон всем целям в области.")
				_value(rows, "Радиус", PlayerAbilities.NUKE_RADIUS, PlayerAbilities.NUKE_RADIUS, "м", "Горизонтальный радиус; перепад высоты не блокирует удар.")
				_value(rows, "Урон за тик горения", PlayerAbilities.NUKE_BURN_DAMAGE, PlayerAbilities.NUKE_BURN_DAMAGE, "", "Последующие попадания оставшейся области.")
				rows.append(Property.new("Горение", "%d × %.2f с" % [PlayerAbilities.NUKE_BURN_TICKS, PlayerAbilities.NUKE_BURN_INTERVAL], "%d × %.2f с" % [PlayerAbilities.NUKE_BURN_TICKS, PlayerAbilities.NUKE_BURN_INTERVAL], "Количество тиков × интервал между ними."))
	return rows

static func _value(rows: Array[Property], title: String, base: float, effective: float, unit: String, explanation: String) -> void:
	rows.append(Property.new(title, "%s %s" % [str(snappedf(base, 0.001)), unit], "%s %s" % [str(snappedf(effective, 0.001)), unit], explanation))

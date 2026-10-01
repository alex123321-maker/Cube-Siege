extends VBoxContainer
class_name AbilityLabInspector

signal edited()
var document: AbilityLabDocument
var selected: AbilityStep
var _fields: VBoxContainer

func inspect(doc: AbilityLabDocument, step: AbilityStep) -> void:
	document = doc
	selected = step
	for child: Node in get_children():
		remove_child(child)
		child.queue_free()
	var tabs: TabContainer = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(tabs)
	var parameters: ScrollContainer = ScrollContainer.new()
	parameters.name = "Блок"
	tabs.add_child(parameters)
	_fields = VBoxContainer.new()
	_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fields.add_theme_constant_override("separation", 10)
	parameters.add_child(_fields)
	_label("ПАРАМЕТРЫ БЛОКА")
	if selected:
		_step_fields()
	else:
		_label("Выберите блок слева.")
	var modifiers: ScrollContainer = ScrollContainer.new()
	modifiers.name = "Модификаторы"
	tabs.add_child(modifiers)
	_fields = VBoxContainer.new()
	_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fields.add_theme_constant_override("separation", 10)
	modifiers.add_child(_fields)
	_modifier_fields()
	var settings: ScrollContainer = ScrollContainer.new()
	settings.name = "Общее"
	tabs.add_child(settings)
	_fields = VBoxContainer.new()
	_fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fields.add_theme_constant_override("separation", 10)
	settings.add_child(_fields)
	_label("ПРАВИЛА ПРИМЕНЕНИЯ")
	_number("Перезарядка · с", document.definition.cooldown, 0, 60, 0.1, func(v: float) -> void: document.definition.cooldown = v)
	_check("Черновик (только лаборатория)", document.definition.draft, func(v: bool) -> void: document.definition.draft = v)
	_label("Снятие отметки разрешает использовать ресурс в поле Constructed Special игрока. Текущие классовые умения автоматически не заменяются.")
	_text("Описание", document.definition.description, func(v: String) -> void: document.definition.description = v)

func _step_fields() -> void:
	_text("Имя слота", selected.slot, func(v: String) -> void: selected.slot = v)
	_label(selected.kind_label())
	_number("Начало · с", selected.start, 0, 60, 0.05, func(v: float) -> void: selected.start = v)
	if selected.kind == AbilityStep.Kind.RECIPE:
		_label("Дочерние блоки используют относительное время. Выберите рецепт и нажмите + для добавления внутрь.")
		return
	_number("Длительность · с", selected.duration, 0, 60, 0.01, func(v: float) -> void: selected.duration = v)
	if selected.kind == AbilityStep.Kind.AREA:
		_number("Урон", selected.damage, 0, 10000, 1, func(v: float) -> void: selected.damage = v)
		_number("Радиус · м", selected.radius, 0.1, 30, 0.1, func(v: float) -> void: selected.radius = v)
		_number("Угол · °", selected.arc_degrees, 0, 360, 1, func(v: float) -> void: selected.arc_degrees = v)
		_number("Отбрасывание", selected.knockback, 0, 100, 0.5, func(v: float) -> void: selected.knockback = v)
		_number("Повтор · с (0 = один раз)", selected.repeat_interval, 0, 60, 0.05, func(v: float) -> void: selected.repeat_interval = v)
		_check("Следовать за источником", selected.follow_actor, func(v: bool) -> void: selected.follow_actor = v)
		_choice("Рельеф", ["Связность и препятствия", "Независимая область"], selected.terrain_mode, func(v: int) -> void: selected.terrain_mode = v as TerrainCombatRules.TerrainMode)
	elif selected.kind == AbilityStep.Kind.MOVE:
		_number("Дистанция · м", selected.distance, -30, 30, 0.1, func(v: float) -> void: selected.distance = v)
		_label("Направление фиксируется при применении. Движение учитывает твёрдые препятствия.")

func _modifier_fields() -> void:
	_label("ПРЕОБРАЗОВАНИЯ СБОРКИ")
	var add: Button = Button.new()
	add.text = "+ Модификатор"
	_fields.add_child(add)
	add.pressed.connect(func() -> void:
		document.checkpoint()
		document.definition.modifiers.append(AbilityModifier.new())
		inspect(document, selected)
		edited.emit()
	)
	for modifier: AbilityModifier in document.definition.modifiers:
		if modifier == null:
			continue
		_fields.add_child(HSeparator.new())
		_check(modifier.label, modifier.enabled, func(v: bool) -> void: modifier.enabled = v)
		_text("Название", modifier.label, func(v: String) -> void: modifier.label = v)
		_text("Слот (например recipe/hit)", modifier.target_slot, func(v: String) -> void: modifier.target_slot = v)
		_choice("Операция", ["Заменить радиус", "Заменить угол", "Умножить урон", "Добавить отбрасывание", "Добавить действие"], modifier.operation, func(v: int) -> void:
			modifier.operation = v as AbilityModifier.Operation
			if modifier.operation == AbilityModifier.Operation.ADD_ACTION and modifier.action == null:
				modifier.action = AbilityStep.new()
				modifier.action.kind = AbilityStep.Kind.MOVE
				modifier.action.slot = "advance"
				modifier.action.distance = 2.0
			call_deferred("inspect", document, selected)
		)
		if modifier.operation == AbilityModifier.Operation.ADD_ACTION and modifier.action:
			_choice("Добавляемый блок", ["Область", "Движение", "Ожидание"], modifier.action.kind, func(v: int) -> void:
				modifier.action.kind = v as AbilityStep.Kind
				call_deferred("inspect", document, selected)
			)
			_number("Задержка · с", modifier.action.start, 0, 60, 0.05, func(v: float) -> void: modifier.action.start = v)
			_number("Длительность · с", modifier.action.duration, 0, 60, 0.01, func(v: float) -> void: modifier.action.duration = v)
			if modifier.action.kind == AbilityStep.Kind.MOVE:
				_number("Дистанция · м", modifier.action.distance, -30, 30, 0.1, func(v: float) -> void: modifier.action.distance = v)
			elif modifier.action.kind == AbilityStep.Kind.AREA:
				_number("Урон", modifier.action.damage, 0, 10000, 1, func(v: float) -> void: modifier.action.damage = v)
				_number("Радиус · м", modifier.action.radius, 0, 30, 0.1, func(v: float) -> void: modifier.action.radius = v)
				_number("Угол · °", modifier.action.arc_degrees, 0, 360, 1, func(v: float) -> void: modifier.action.arc_degrees = v)
		else:
			_number("Значение", modifier.value, 0, 10000, 0.1, func(v: float) -> void: modifier.value = v)
		var remove: Button = Button.new()
		remove.text = "Удалить модификатор"
		_fields.add_child(remove)
		remove.pressed.connect(func() -> void:
			document.checkpoint()
			document.definition.modifiers.erase(modifier)
			inspect(document, selected)
			edited.emit()
		)

func _label(text_value: String) -> void:
	var label: Label = Label.new()
	label.text = text_value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fields.add_child(label)

func _number(caption: String, value: float, lower: float, upper: float, increment: float, setter: Callable) -> void:
	_label(caption)
	var field: SpinBox = SpinBox.new()
	field.min_value = lower
	field.max_value = upper
	field.step = increment
	field.value = value
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fields.add_child(field)
	field.value_changed.connect(func(v: float) -> void:
		document.checkpoint()
		setter.call(v)
		edited.emit()
	)

func _text(caption: String, value: String, setter: Callable) -> void:
	_label(caption)
	var field: LineEdit = LineEdit.new()
	field.text = value
	_fields.add_child(field)
	field.text_changed.connect(func(v: String) -> void:
		document.checkpoint()
		setter.call(v)
		edited.emit()
	)

func _check(caption: String, value: bool, setter: Callable) -> void:
	var field: CheckButton = CheckButton.new()
	field.text = caption
	field.button_pressed = value
	_fields.add_child(field)
	field.toggled.connect(func(v: bool) -> void:
		document.checkpoint()
		setter.call(v)
		edited.emit()
	)

func _choice(caption: String, choices: Array[String], value: int, setter: Callable) -> void:
	_label(caption)
	var field: OptionButton = OptionButton.new()
	for choice: String in choices:
		field.add_item(choice)
	field.selected = value
	_fields.add_child(field)
	field.item_selected.connect(func(v: int) -> void:
		document.checkpoint()
		setter.call(v)
		edited.emit()
	)

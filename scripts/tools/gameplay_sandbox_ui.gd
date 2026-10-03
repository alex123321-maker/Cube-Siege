extends CanvasLayer
class_name GameplaySandboxUI

signal resume_ready()
var sandbox: GameplaySandbox
var panel: PanelContainer
var toggle: Button
var class_choice: OptionButton
var monster_choice: OptionButton
var count: SpinBox
var distance: SpinBox
var notice: Label
var synergy: Label
var _talent_controls: Dictionary = {}
var _rank_controls: Dictionary = {}
var _rank_body: VBoxContainer
var _talent_body: VBoxContainer
var _warrior_note: Label
var _bonus: CheckBox
var _resume_frames: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	var screen: Control = Control.new()
	screen.theme = preload("res://resources/hud_theme.tres")
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	toggle = Button.new()
	toggle.text = "Арена · F2"
	toggle.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	toggle.offset_left = -180.0
	toggle.offset_right = -18.0
	toggle.offset_top = 18.0
	toggle.offset_bottom = 54.0
	toggle.pressed.connect(func() -> void: sandbox.toggle_editor(not panel.visible))
	screen.add_child(toggle)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 18.0
	panel.offset_top = 68.0
	panel.offset_right = -18.0
	panel.offset_bottom = -18.0
	panel.add_theme_stylebox_override("panel", _panel_style())
	screen.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	panel.add_child(margin)
	var outer: VBoxContainer = VBoxContainer.new()
	margin.add_child(outer)
	var header: HBoxContainer = HBoxContainer.new()
	outer.add_child(header)
	var title: Label = _label("ИГРОВАЯ ПЕСОЧНИЦА · БОЙ НА ПАУЗЕ")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_button("Продолжить · F2", func() -> void: sandbox.toggle_editor(false)))
	header.add_child(_button("В меню", func() -> void: sandbox.return_to_menu()))
	notice = _label("Обычное управление: WASD, мышь, ЛКМ/ПКМ, Space, Q, F, Tab, E. Профиль игры изолирован.")
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outer.add_child(notice)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var columns: HBoxContainer = HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	scroll.add_child(columns)
	var controls: VBoxContainer = VBoxContainer.new()
	controls.custom_minimum_size.x = 320.0
	columns.add_child(controls)
	controls.add_child(_label("ПЕРСОНАЖ И АРЕНА"))
	class_choice = OptionButton.new()
	for caption: String in ["Воин", "Лучник · существующая версия", "Инженер · существующая версия"]:
		class_choice.add_item(caption)
	class_choice.item_selected.connect(func(id: int) -> void: sandbox.select_character(id))
	controls.add_child(class_choice)
	controls.add_child(_button("Сбросить бой / возродиться", func() -> void: sandbox.clear_encounter()))
	controls.add_child(_button("Удалить врагов и их эффекты", func() -> void: sandbox.clear_monsters()))
	controls.add_child(_button("+1000 дерева, камня и железа", func() -> void: sandbox.add_resources()))
	for kind: int in range(3):
		controls.add_child(_button(["Добавить дерево", "Добавить камень", "Добавить железную жилу"][kind], func() -> void: sandbox.spawn_resource(kind)))
	var night: CheckBox = CheckBox.new()
	night.text = "Ночное освещение"
	night.toggled.connect(func(enabled: bool) -> void: sandbox.set_night(enabled))
	controls.add_child(night)
	controls.add_child(_label("СПАВН ПЕРЕД ПЕРСОНАЖЕМ"))
	monster_choice = OptionButton.new()
	for entry: GameplaySandboxCatalog.SpawnEntry in GameplaySandboxCatalog.entries():
		monster_choice.add_item(entry.title)
		monster_choice.set_item_metadata(monster_choice.item_count - 1, entry.id)
	controls.add_child(monster_choice)
	count = _spin(1.0, 100.0, 1.0, 1.0)
	controls.add_child(_field("Количество", count))
	distance = _spin(3.0, 60.0, 1.0, 8.0)
	distance.value_changed.connect(func(value: float) -> void: sandbox.spawn_distance = value)
	controls.add_child(_field("Дистанция", distance))
	controls.add_child(_button("Добавить выбранного врага", func() -> void: sandbox.spawn_monster(str(monster_choice.get_item_metadata(monster_choice.selected)), int(count.value))))
	var builds: VBoxContainer = VBoxContainer.new()
	builds.custom_minimum_size.x = 300.0
	builds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(builds)
	builds.add_child(_label("ТАЛАНТЫ ВОИНА"))
	_warrior_note = _label("В песочнице можно выбрать все девять одновременно. В обычном забеге предел остаётся шесть.")
	_warrior_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	builds.add_child(_warrior_note)
	_talent_body = VBoxContainer.new()
	builds.add_child(_talent_body)
	_talent_body.add_child(_button("Взять все девять", func() -> void: sandbox.configure_talents(WarriorTalentCatalog.TALENT_IDS)))
	_talent_body.add_child(_button("Убрать все таланты", func() -> void: sandbox.configure_talents([])))
	for definition: WarriorTalentDefinition in WarriorTalentCatalog.get_all():
		var check: CheckBox = CheckBox.new()
		check.text = definition.title
		check.tooltip_text = definition.description
		check.toggled.connect(func(enabled: bool) -> void: _select_talent(definition.id, enabled))
		_talent_controls[definition.id] = check
		_talent_body.add_child(check)
	_bonus = CheckBox.new()
	_bonus.text = "Постоянные бонусы всех открытых талантов"
	_bonus.tooltip_text = "Все девять открыты только в изолированном профиле арены. По умолчанию постоянные бонусы отключены."
	_bonus.toggled.connect(func(enabled: bool) -> void: sandbox.set_opening_bonuses(enabled))
	_talent_body.add_child(_bonus)
	synergy = _label("")
	synergy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_talent_body.add_child(synergy)
	var ranks: VBoxContainer = VBoxContainer.new()
	ranks.custom_minimum_size.x = 330.0
	columns.add_child(ranks)
	ranks.add_child(_label("СПЕЦИАЛИЗАЦИИ ВОИНА"))
	var rank_note: Label = _label("Введите любой неотрицательный ранг. Дополнительные свойства появляются с соответствующим талантом.")
	rank_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ranks.add_child(rank_note)
	ranks.add_child(_button("Сбросить ранги", func() -> void: sandbox.clear_specializations()))
	_rank_body = VBoxContainer.new()
	ranks.add_child(_rank_body)
	panel.hide()

func bind_sandbox(owner: GameplaySandbox) -> void:
	sandbox = owner
	sandbox.configuration_changed.connect(refresh)
	sandbox.message_changed.connect(func(message: String) -> void: notice.text = message)
	resume_ready.connect(sandbox.resume_play)

func configure_native_hud(native_hud: CanvasLayer) -> void:
	# A manual arena has no automatic waves or evacuation timer. Combat HUD stays.
	native_hud.get_node("Margin/TopCenter").hide()
	set_native_editor_open(native_hud, panel.visible or _resume_frames >= 0)

func set_native_editor_open(native_hud: CanvasLayer, open: bool) -> void:
	var native_panel: WarriorBuildPanel = native_hud.build_panel
	if open and native_panel.visible:
		native_panel.close_panel()
	# The native panel handles P in _input before this editor's unhandled input.
	native_panel.set_process_input(not open)

func clear_boss_display(native_hud: CanvasLayer) -> void:
	# Administrative removal has no victory event to close the ordinary boss HUD.
	native_hud.get_node("Margin/BossBarContainer").hide()

func _select_talent(id: String, enabled: bool) -> void:
	var selected: Array[String] = sandbox.player.progression.run_build.selected_talents.duplicate()
	if enabled and not selected.has(id):
		selected.append(id)
	elif not enabled:
		selected.erase(id)
	sandbox.configure_talents(selected)

func refresh() -> void:
	if not is_instance_valid(sandbox.player):
		return
	class_choice.select(sandbox.character_class)
	var warrior: bool = sandbox.character_class == 0
	_talent_body.visible = warrior
	_warrior_note.text = "Можно выбрать все девять одновременно; обычный забег ограничен шестью." if warrior else "Дерево талантов и специализации сейчас реализованы для Воина. Другие классы используют свои существующие игровые способности."
	_bonus.set_pressed_no_signal(sandbox.opening_bonuses)
	var build: WarriorRunBuild = sandbox.player.progression.run_build
	for id: String in _talent_controls:
		(_talent_controls[id] as CheckBox).set_pressed_no_signal(build.has_talent(id))
	var titles: Array[String] = []
	for id: String in build.discovered_synergies:
		titles.append(WarriorTalentCatalog.SYNERGY_TITLES[id])
	synergy.text = "Активные сочетания: " + (", ".join(titles) if not titles.is_empty() else "нет")
	var axes: Array[String] = []
	if warrior:
		axes = build.get_available_axes()
	if axes != _rank_controls.keys():
		for child: Node in _rank_body.get_children():
			_rank_body.remove_child(child)
			child.queue_free()
		_rank_controls.clear()
		for axis: String in axes:
			var rank: SpinBox = _spin(0.0, 100.0, 1.0, 0.0)
			rank.allow_greater = true
			rank.value_changed.connect(func(value: float) -> void: sandbox.set_specialization(axis, int(value)))
			_rank_controls[axis] = rank
			_rank_body.add_child(_field(WarriorRunBuild.AXIS_TITLES[axis], rank))
	for axis: String in _rank_controls:
		(_rank_controls[axis] as SpinBox).set_value_no_signal(float(build.specializations.get(axis, 0)))

func set_editor_open(open: bool) -> void:
	panel.visible = open
	toggle.text = "Закрыть · F2" if open else "Арена · F2"
	if open:
		_resume_frames = -1
		refresh()
	else:
		get_viewport().gui_release_focus()

func request_resume() -> void:
	_resume_frames = 2

func _process(_delta: float) -> void:
	if _resume_frames < 0:
		return
	if _resume_frames > 0:
		_resume_frames -= 1
		return
	# A GUI click must finish before native physics polls the same mouse button.
	if not Input.is_action_pressed("attack_lmb") and not Input.is_action_pressed("special_rmb"):
		_resume_frames = -1
		resume_ready.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		sandbox.toggle_editor(not panel.visible)
		get_viewport().set_input_as_handled()
	elif panel.visible:
		get_viewport().set_input_as_handled()

func _button(caption: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = caption
	button.pressed.connect(action)
	return button

func _label(caption: String) -> Label:
	var label: Label = Label.new()
	label.text = caption
	return label

func _spin(minimum: float, maximum: float, step: float, value: float) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.custom_minimum_size.x = 100.0
	return spin

func _field(caption: String, control: Control) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = _label(caption)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	row.add_child(control)
	return row

func _panel_style() -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.085, 0.98)
	style.border_color = Color(0.18, 0.35, 0.48)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style

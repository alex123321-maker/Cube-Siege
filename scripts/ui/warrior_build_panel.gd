extends Control
class_name WarriorBuildPanel

var player: PlayerPrototype
var build: WarriorRunBuild
var _body: VBoxContainer
var _title: Label
var _close: Button
var _paused_before: bool = false
var _reward: int = -1
var _mandatory: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.015, 0.025, 0.04, 0.92)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(860, 540)
	center.add_child(panel)
	var margin: MarginContainer = MarginContainer.new()
	for side: String in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(margin)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	layout.add_child(_title)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(800, 390)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 10)
	scroll.add_child(_body)
	_close = Button.new()
	_close.text = "Продолжить · P / Esc"
	_close.pressed.connect(close_panel)
	layout.add_child(_close)
	hide()

func bind_player(actor: PlayerPrototype) -> void:
	player = actor
	build = actor.progression.run_build
	build.checkpoint_ready.connect(open_checkpoint)
	build.build_changed.connect(_on_build_changed)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_P, KEY_ESCAPE]:
		if visible:
			get_viewport().set_input_as_handled()
			if not _mandatory:
				close_panel()
		elif event.keycode == KEY_P and build and build.active:
			get_viewport().set_input_as_handled()
			open_specializations()
	elif visible and (event is InputEventMouseButton or event is InputEventKey):
		# GUI gets first chance; unhandled gameplay actions cannot leak through this modal.
		if event is InputEventKey and event.keycode in [KEY_SPACE, KEY_Q, KEY_F, KEY_TAB]:
			get_viewport().set_input_as_handled()

func open_checkpoint() -> void:
	if not build or build.active_reward_id < 0:
		return
	_reward = build.active_reward_id
	_mandatory = true
	_open()
	_render_checkpoint()

func open_specializations() -> void:
	if not build or not build.active:
		return
	if build.active_reward_id >= 0:
		open_checkpoint()
		return
	_mandatory = false
	_open()
	_render_specializations()

func _open() -> void:
	if not visible:
		_paused_before = get_tree().paused
	show()
	get_tree().paused = true
	_close.visible = not _mandatory

func close_panel() -> void:
	if _mandatory:
		return
	hide()
	get_tree().paused = _paused_before

func _clear() -> void:
	for child: Node in _body.get_children():
		_body.remove_child(child)
		child.queue_free()

func _label(text: String) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_child(label)
	return label

func _render_checkpoint() -> void:
	_clear()
	_title.text = "Выберите талант · %d / %d" % [build.selected_talents.size(), WarriorRunBuild.MAX_TALENTS]
	_label("Талант действует до конца этого забега. Вместо него можно получить два очка специализации.")
	for definition: WarriorTalentDefinition in build.get_talent_options():
		var card: Button = Button.new()
		card.text = definition.title + "\n" + definition.description
		card.icon = load(definition.icon_path) as Texture2D
		card.expand_icon = true
		card.add_theme_constant_override("icon_max_width", 44)
		card.custom_minimum_size.y = 88
		card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.pressed.connect(_choose.bind(definition.id, _reward))
		_body.add_child(card)
	if build.get_talent_options().is_empty():
		_label("Все доступные открытые таланты уже взяты. Можно выбрать Сосредоточенность.")
	var focus: Button = Button.new()
	focus.text = "Сосредоточенность · +2 очка специализации"
	focus.pressed.connect(_focus.bind(_reward))
	_body.add_child(focus)
	if _body.get_child_count() > 1 and _body.get_child(1) is Button:
		(_body.get_child(1) as Button).grab_focus()

func _choose(id: String, reward_id: int) -> void:
	if build.choose_talent(id, reward_id):
		_resolve_checkpoint()

func _focus(reward_id: int) -> void:
	if build.focus(reward_id):
		_resolve_checkpoint()

func _resolve_checkpoint() -> void:
	_mandatory = false
	close_panel()

func _render_specializations() -> void:
	_clear()
	_title.text = "Специализации · свободно очков: %d" % build.unspent_specialization_points
	_label("Каждый уровень даёт одно очко. Ранги не ограничены. Перераспределение бесплатно и доступно в любой момент.")
	for axis: String in build.get_available_axes():
		var row: HBoxContainer = HBoxContainer.new()
		_body.add_child(row)
		var text: Label = Label.new()
		text.text = "%s · ранг %d · ×%.2f" % [WarriorRunBuild.AXIS_TITLES[axis], int(build.specializations.get(axis, 0)), build.get_property_multiplier(axis)]
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var add: Button = Button.new()
		add.text = "+"
		add.disabled = build.unspent_specialization_points <= 0
		add.pressed.connect(_invest.bind(axis))
		row.add_child(add)
	var reset: Button = Button.new()
	reset.text = "Вернуть все очки специализации"
	reset.pressed.connect(build.reset_specializations)
	_body.add_child(reset)
	_label("Таланты: " + _talent_names())
	for synergy: String in build.discovered_synergies:
		_label("Открыта синергия: " + WarriorTalentCatalog.SYNERGY_TITLES[synergy]).modulate = Color.GOLD

func _talent_names() -> String:
	var names: PackedStringArray = []
	for id: String in build.selected_talents:
		names.append(WarriorTalentCatalog.get_talent(id).title)
	return ", ".join(names) if not names.is_empty() else "пока нет"

func _invest(axis: String) -> void:
	build.invest_specialization(axis)

func _on_build_changed() -> void:
	if visible and not _mandatory:
		_render_specializations()

func _exit_tree() -> void:
	if visible and get_tree():
		get_tree().paused = _paused_before

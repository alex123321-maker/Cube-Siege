extends Control
class_name WarriorTalentTree

## Menu presentation only: the preview is a model, never a combat player.
signal play_requested(slot_index: int)
signal back_requested()

var inspected_slot: int = 0
var _roster: Node = null
var _wallet_label: Label
var _detail_title: Label
var _detail_text: Label
var _purchase_button: Button
var _graph: TalentGraph
var _selected_id: String = "sweeping_strike"

func _ready() -> void:
	_build_ui()

func setup(roster: Node, slot_index: int) -> void:
	_roster = roster
	inspected_slot = slot_index
	refresh()

func refresh() -> void:
	if not _roster or not _graph:
		return
	var slot: Dictionary = _roster.slots[inspected_slot]
	_wallet_label.text = "ОПЫТ ДЛЯ ОТКРЫТИЙ: %d  ·  ТАЛАНТЫ: %d / 9" % [int(slot.get("talent_xp", 0)), _roster.get_unlocked_talents(inspected_slot).size()]
	_graph.refresh(_roster.get_unlocked_talents(inspected_slot))
	_show_detail(_selected_id)

func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	add_child(margin)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	margin.add_child(rows)
	_wallet_label = Label.new()
	_wallet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wallet_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	rows.add_child(_wallet_label)
	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	rows.add_child(body)
	_create_preview(body)
	var right: VBoxContainer = VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.5
	body.add_child(right)
	_graph = TalentGraph.new()
	_graph.custom_minimum_size = Vector2(380, 260)
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.talent_focused.connect(_show_detail)
	_graph.talent_activated.connect(_select_talent)
	right.add_child(_graph)
	var info: PanelContainer = PanelContainer.new()
	info.custom_minimum_size.y = 125
	right.add_child(info)
	var info_rows: VBoxContainer = VBoxContainer.new()
	info_rows.add_theme_constant_override("separation", 5)
	info.add_child(info_rows)
	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", 20)
	info_rows.add_child(_detail_title)
	_detail_text = Label.new()
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_rows.add_child(_detail_text)
	_purchase_button = Button.new()
	_purchase_button.custom_minimum_size.y = 38
	_purchase_button.pressed.connect(_purchase_selected)
	info_rows.add_child(_purchase_button)
	var hint: Label = Label.new()
	hint.text = "Открытие допускает талант в выбор забега. Механика включается после выбора.\nБонус ветки действует всегда: +3% обычной атаки / +5 HP / +2% скорости за открытие."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 12)
	rows.add_child(hint)
	var actions: HBoxContainer = HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 20)
	rows.add_child(actions)
	var back: Button = Button.new()
	back.text = "НАЗАД К ГЕРОЯМ"
	back.custom_minimum_size = Vector2(220, 40)
	back.pressed.connect(func() -> void: back_requested.emit())
	actions.add_child(back)
	var play: Button = Button.new()
	play.text = "НАЧАТЬ ЗАБЕГ ВОИНОМ"
	play.custom_minimum_size = Vector2(280, 40)
	play.pressed.connect(func() -> void: play_requested.emit(inspected_slot))
	actions.add_child(play)

func _create_preview(parent: Control) -> void:
	var column: VBoxContainer = VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(column)
	var title: Label = Label.new()
	title.text = "ВОИН\nРыцарь Авангарда"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)
	var container: SubViewportContainer = SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(container)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(420, 420)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_PARENT_VISIBLE
	container.add_child(viewport)
	var model_scene: PackedScene = preload("res://assets/models/characters/hero_warrior.tscn")
	var model: Node3D = model_scene.instantiate() as Node3D
	model.rotation.y = 0.4
	viewport.add_child(model)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(3.4, 2.6, 4.8)
	viewport.add_child(camera)
	camera.look_at(Vector3(0, 0.9, 0))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.6
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -35, 0)
	light.light_energy = 1.4
	viewport.add_child(light)
	var fill: DirectionalLight3D = DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-10, 120, 0)
	fill.light_energy = 0.7
	fill.light_color = Color(0.4, 0.6, 1.0)
	viewport.add_child(fill)

func _select_talent(talent_id: String) -> void:
	_selected_id = talent_id
	_show_detail(talent_id)

func _show_detail(talent_id: String) -> void:
	if not _roster:
		return
	var definition: WarriorTalentDefinition = WarriorTalentCatalog.get_talent(talent_id)
	if not definition:
		return
	_selected_id = talent_id
	_detail_title.text = definition.title
	_detail_title.modulate = WarriorTalentCatalog.BRANCH_COLORS[definition.branch]
	_detail_text.text = definition.description
	var opened: Array[String] = _roster.get_unlocked_talents(inspected_slot)
	_purchase_button.disabled = not _roster.can_unlock_talent(inspected_slot, talent_id)
	if opened.has(talent_id):
		_purchase_button.text = "ОТКРЫТ · ДОСТУПЕН В ЗАБЕГЕ"
	elif not definition.parent_id.is_empty() and not opened.has(definition.parent_id):
		_purchase_button.text = "ЗАКРЫТ · СНАЧАЛА ОТКРОЙТЕ ПРЕДЫДУЩИЙ ТАЛАНТ"
	else:
		_purchase_button.text = "ОТКРЫТЬ · %d ОПЫТА" % definition.unlock_cost
		if _purchase_button.disabled:
			_purchase_button.text += " · НЕДОСТАТОЧНО"

func _purchase_selected() -> void:
	if _roster.unlock_talent(inspected_slot, _selected_id):
		refresh()
	else:
		_detail_text.text = _roster.last_error

class TalentGraph extends Control:
	signal talent_focused(talent_id: String)
	signal talent_activated(talent_id: String)
	var _opened: Array[String] = []
	var _buttons: Dictionary = {}
	var _clock: float = 0.0

	func _ready() -> void:
		for definition: WarriorTalentDefinition in WarriorTalentCatalog.get_all():
			var button: Button = Button.new()
			button.name = definition.id
			button.size = Vector2(52, 52)
			button.expand_icon = true
			button.icon = load(definition.icon_path) as Texture2D
			button.tooltip_text = definition.title
			button.pressed.connect(func() -> void: talent_activated.emit(definition.id))
			button.mouse_entered.connect(func() -> void: talent_focused.emit(definition.id))
			button.focus_entered.connect(func() -> void: talent_focused.emit(definition.id))
			add_child(button)
			_buttons[definition.id] = button
		resized.connect(_layout_buttons)
		_layout_buttons()

	func refresh(opened: Array[String]) -> void:
		_opened = opened.duplicate()
		for definition: WarriorTalentDefinition in WarriorTalentCatalog.get_all():
			var button: Button = _buttons.get(definition.id) as Button
			if not button:
				continue
			var color: Color = WarriorTalentCatalog.BRANCH_COLORS[definition.branch]
			button.modulate = color if opened.has(definition.id) else Color(0.50, 0.52, 0.60)
			button.text = "✓" if opened.has(definition.id) else ("" if opened.has(definition.parent_id) else "🔒")
		queue_redraw()

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_clock += delta
			queue_redraw()

	func _center() -> Vector2:
		return size * Vector2(0.5, 0.48)

	func _position_for(definition: WarriorTalentDefinition) -> Vector2:
		var radius: float = minf(size.x * 0.31, size.y * 0.40)
		return _center() + Vector2.from_angle(definition.angle) * radius * (0.55 if definition.ring == 1 else 1.0)

	func _layout_buttons() -> void:
		for definition: WarriorTalentDefinition in WarriorTalentCatalog.get_all():
			var button: Button = _buttons.get(definition.id) as Button
			if button:
				button.position = _position_for(definition) - button.size * 0.5
		queue_redraw()

	func _draw() -> void:
		var center: Vector2 = _center()
		draw_circle(center, 23, Color(0.08, 0.14, 0.22))
		draw_arc(center, 24, 0, TAU, 32, Color(0.6, 0.8, 1.0), 2, true)
		var font: Font = ThemeDB.fallback_font
		draw_string(font, center + Vector2(-7, 6), "В", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.85, 0.95, 1.0))
		for definition: WarriorTalentDefinition in WarriorTalentCatalog.get_all():
			var start: Vector2 = center
			if not definition.parent_id.is_empty():
				start = _position_for(WarriorTalentCatalog.get_talent(definition.parent_id))
			var finish: Vector2 = _position_for(definition)
			var direction: Vector2 = finish - start
			var normal: Vector2 = direction.orthogonal().normalized()
			var points: PackedVector2Array = []
			for index: int in range(25):
				var t: float = float(index) / 24.0
				points.append(start.lerp(finish, t) + normal * sin(t * PI) * sin(t * TAU + definition.angle) * 10.0)
			var active_path: bool = _opened.has(definition.id)
			var color: Color = WarriorTalentCatalog.BRANCH_COLORS[definition.branch] if active_path else Color(0.17, 0.20, 0.28)
			draw_polyline(points, color, 2.4 if active_path else 1.5, true)
			if active_path:
				var pulse: int = int(fposmod(_clock * 8.0 + definition.angle, 24.0))
				draw_circle(points[pulse], 2.5, color.lightened(0.6))
		var label_y: float = size.y - 12.0
		draw_string(font, Vector2(8, label_y), "КРОВОЖАДНОСТЬ   ·   ВЫНОСЛИВОСТЬ   ·   МАНЁВРЕННОСТЬ", HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 12, Color(0.6, 0.7, 0.85))

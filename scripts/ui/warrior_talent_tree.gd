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
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	var rows: VBoxContainer = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	margin.add_child(rows)
	_wallet_label = Label.new()
	_wallet_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wallet_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_wallet_label.add_theme_font_size_override("font_size", 14)
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
	right.add_theme_constant_override("separation", 8)
	body.add_child(right)
	_graph = TalentGraph.new()
	_graph.custom_minimum_size = Vector2(460, 270)
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.talent_focused.connect(_show_detail)
	_graph.talent_activated.connect(_select_talent)
	right.add_child(_graph)
	var info: PanelContainer = PanelContainer.new()
	info.custom_minimum_size.y = 125
	info.add_theme_stylebox_override("panel", PixelUI.panel("ui_action_slot_normal", Vector4(12, 10, 12, 10)))
	right.add_child(info)
	var info_rows: VBoxContainer = VBoxContainer.new()
	info_rows.add_theme_constant_override("separation", 5)
	info.add_child(info_rows)
	_detail_title = Label.new()
	_detail_title.add_theme_font_size_override("font_size", 18)
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_rows.add_child(_detail_title)
	_detail_text = Label.new()
	_detail_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_text.add_theme_font_size_override("font_size", 14)
	_detail_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_rows.add_child(_detail_text)
	_purchase_button = Button.new()
	_purchase_button.custom_minimum_size.y = 38
	_purchase_button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_purchase_button.add_theme_font_size_override("font_size", 13)
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
	back.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	back.pressed.connect(func() -> void: back_requested.emit())
	actions.add_child(back)
	var play: Button = Button.new()
	play.text = "НАЧАТЬ ЗАБЕГ ВОИНОМ"
	play.custom_minimum_size = Vector2(280, 40)
	play.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	var _buttons: Dictionary[String, Button] = {}
	var _state_badges: Dictionary[String, Label] = {}
	const NODE_SIZE: Vector2 = Vector2(48, 48)
	var _clock: float = 0.0

	func _ready() -> void:
		for definition: WarriorTalentDefinition in WarriorTalentCatalog.get_all():
			var button: Button = Button.new()
			button.name = definition.id
			button.size = NODE_SIZE
			button.custom_minimum_size = NODE_SIZE
			button.expand_icon = true
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.add_theme_constant_override("icon_max_width", 30)
			button.add_theme_constant_override("h_separation", 0)
			button.icon = load(definition.icon_path) as Texture2D
			button.tooltip_text = definition.title
			button.pressed.connect(func() -> void: talent_activated.emit(definition.id))
			button.mouse_entered.connect(func() -> void: talent_focused.emit(definition.id))
			button.focus_entered.connect(func() -> void: talent_focused.emit(definition.id))
			var badge: Label = Label.new()
			badge.name = "StateBadge"
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.add_theme_font_size_override("font_size", 10)
			badge.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
			badge.add_theme_constant_override("outline_size", 2)
			badge.add_theme_color_override("font_outline_color", Color(0.015, 0.025, 0.04))
			badge.text = "×"
			button.add_child(badge)
			badge.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
			badge.offset_left = -16.0
			badge.offset_right = -2.0
			badge.offset_top = -26.0
			badge.offset_bottom = -2.0
			_state_badges[definition.id] = badge
			add_child(button)
			_buttons[definition.id] = button
			_set_node_style(button, "ui_talent_node_locked")
		resized.connect(_layout_buttons)
		_layout_buttons()

	func refresh(opened: Array[String]) -> void:
		_opened = opened.duplicate()
		for definition: WarriorTalentDefinition in WarriorTalentCatalog.get_all():
			var button: Button = _buttons.get(definition.id) as Button
			if not button:
				continue
			var state: String = "ui_talent_node_locked"
			if opened.has(definition.id):
				state = "ui_talent_node_learned"
			elif definition.parent_id.is_empty() or opened.has(definition.parent_id):
				state = "ui_talent_node_available"
			_set_node_style(button, state)
			button.modulate = Color(0.65, 0.67, 0.72) if state == "ui_talent_node_locked" else Color.WHITE
			button.text = ""
			var badge: Label = _state_badges[definition.id]
			badge.text = "✓" if state == "ui_talent_node_learned" else ("×" if state == "ui_talent_node_locked" else "")
			badge.visible = not badge.text.is_empty()
			badge.add_theme_color_override("font_color", Color(1.0, 0.84, 0.40) if state == "ui_talent_node_learned" else Color(0.9, 0.91, 0.94))
		queue_redraw()

	func _set_node_style(button: Button, state: String) -> void:
		var style: StyleBoxTexture = PixelUI.panel(state, Vector4(8, 7, 8, 12))
		for style_name: String in ["normal", "hover", "pressed"]:
			button.add_theme_stylebox_override(style_name, style)
		var focus: StyleBoxFlat = StyleBoxFlat.new()
		focus.draw_center = false
		focus.border_color = Color(1.0, 0.84, 0.42)
		focus.set_border_width_all(1)
		button.add_theme_stylebox_override("focus", focus)

	func _process(delta: float) -> void:
		if is_visible_in_tree():
			_clock += delta
			queue_redraw()

	func _center() -> Vector2:
		return size * Vector2(0.5, 0.5)

	func _position_for(definition: WarriorTalentDefinition) -> Vector2:
		var radius: float = minf(size.x * 0.31, size.y * 0.40)
		return _center() + Vector2.from_angle(definition.angle) * radius * (0.48 if definition.ring == 1 else 1.0)

	func _layout_buttons() -> void:
		for definition: WarriorTalentDefinition in WarriorTalentCatalog.get_all():
			var button: Button = _buttons.get(definition.id) as Button
			if button:
				button.size = NODE_SIZE
				button.position = _position_for(definition) - button.size * 0.5
		queue_redraw()

	func _draw() -> void:
		var center: Vector2 = _center()
		var font: Font = get_theme_default_font()
		for definition: WarriorTalentDefinition in WarriorTalentCatalog.get_all():
			var start: Vector2 = center
			if not definition.parent_id.is_empty():
				start = _position_for(WarriorTalentCatalog.get_talent(definition.parent_id))
			var finish: Vector2 = _position_for(definition)
			var active_path: bool = _opened.has(definition.id)
			_draw_connection(start, finish, active_path)
		draw_texture_rect(PixelUI.texture("ui_talent_root"), Rect2(center - Vector2(20, 20), Vector2(40, 40)), false)
		draw_string(font, center + Vector2(-6, 5), "В", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.95, 0.96, 1.0))
		var label_y: float = size.y - 12.0
		draw_string(font, Vector2(8, label_y), "КРОВОЖАДНОСТЬ   ·   ВЫНОСЛИВОСТЬ   ·   МАНЁВРЕННОСТЬ", HORIZONTAL_ALIGNMENT_CENTER, size.x - 16, 11, Color(0.72, 0.77, 0.85))

	func _draw_connection(start: Vector2, finish: Vector2, active: bool) -> void:
		var direction: Vector2 = finish - start
		var length: float = direction.length()
		if length <= 1.0:
			return
		var height: float = minf(24.0, length * 0.22)
		var local_start: Vector2 = Vector2(0, height * 0.2)
		var local_finish: Vector2 = Vector2(length, height * 0.8)
		var local_direction: Vector2 = local_finish - local_start
		var rotation: float = direction.angle() - local_direction.angle()
		var scale_factor: float = length / local_direction.length()
		draw_set_transform(start - local_start.rotated(rotation) * scale_factor, rotation, Vector2.ONE * scale_factor)
		draw_texture_rect(PixelUI.texture("ui_talent_connection_active" if active else "ui_talent_connection_idle"), Rect2(Vector2.ZERO, Vector2(length, height)), false)
		if active:
			var phase: float = fposmod(_clock * 0.3, 1.0) * 3.0
			var corners: Array[Vector2] = [local_start, Vector2(length * 0.46, local_start.y), Vector2(length * 0.46, local_finish.y), local_finish]
			var segment: int = mini(int(phase), 2)
			var pulse: Vector2 = corners[segment].lerp(corners[segment + 1], phase - float(segment))
			draw_rect(Rect2(pulse - Vector2.ONE, Vector2(2, 2)), Color(1.0, 0.94, 0.64))
		draw_set_transform(Vector2.ZERO)

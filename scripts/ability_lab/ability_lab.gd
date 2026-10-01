extends Control
class_name AbilityLab

var arena: AbilityLabArena
var catalogue: Array[AbilityViewerCatalog.Entry] = AbilityViewerCatalog.entries()
var selected_index: int = 1
var selected_variant: AbilityViewerCatalog.VariantKind = AbilityViewerCatalog.VariantKind.BASE
var _class_picker: OptionButton
var _list: ItemList
var _variants: OptionButton
var _description: RichTextLabel
var _properties: RichTextLabel
var _title: Label
var _metrics: Label
var _journal: RichTextLabel
var _play: Button
var _damage: float = 0.0
var _hits: int = 0
var _generation: int = 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_theme()
	arena = AbilityLabArena.new()
	add_child(arena)
	_build_ui()
	arena.event_recorded.connect(func(message: String) -> void: _journal.append_text(message + "\n"))
	arena.damage_recorded.connect(func(amount: float) -> void:
		_damage += amount
		_hits += 1
	)
	_select_class(0)
	select_ability(1)
	print("ABILITY_LAB_READY")
	if "--lab-capture" in OS.get_cmdline_user_args():
		_capture_demo.call_deferred()

func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margin.add_child(layout)
	var header: Label = Label.new()
	header.text = "CUBE SIEGE  /  ПРОСМОТР СПОСОБНОСТЕЙ"
	header.add_theme_font_size_override("font_size", 23)
	layout.add_child(header)
	var workspace: HBoxContainer = HBoxContainer.new()
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 16)
	layout.add_child(workspace)
	var left: VBoxContainer = _panel(workspace, 280)
	_label(left, "КЛАСС СПОСОБНОСТИ")
	_class_picker = OptionButton.new()
	for title: String in ["Воин", "Лучник", "Инженер"]:
		_class_picker.add_item(title)
	left.add_child(_class_picker)
	_class_picker.item_selected.connect(_select_class)
	_list = ItemList.new()
	_list.custom_minimum_size.y = 175
	_list.add_theme_constant_override("v_separation", 12)
	left.add_child(_list)
	_list.item_selected.connect(func(index: int) -> void: select_ability(_class_picker.selected * 5 + index))
	_label(left, "ВАРИАНТ ДЕМОНСТРАЦИИ")
	_variants = OptionButton.new()
	_variants.fit_to_longest_item = false
	left.add_child(_variants)
	_variants.item_selected.connect(func(index: int) -> void:
		selected_variant = _variants.get_item_id(index) as AbilityViewerCatalog.VariantKind
		_reset_preview()
	)
	_description = RichTextLabel.new()
	_description.bbcode_enabled = true
	_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_description)
	var middle: VBoxContainer = VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.custom_minimum_size.x = 380
	workspace.add_child(middle)
	_title = _label(middle, "")
	_title.add_theme_font_size_override("font_size", 23)
	var controls: HBoxContainer = HBoxContainer.new()
	middle.add_child(controls)
	_play = _button(controls, "▶ Показать / повторить", play_demo)
	_button(controls, "Сбросить сцену", _reset_preview)
	var hint: Label = _label(middle, "Модель Воина · игровые умения · зомби")
	hint.modulate = Color("a4becd")
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	middle.add_child(spacer)
	var result_panel: VBoxContainer = _panel(middle, 0)
	_metrics = _label(result_panel, "")
	_journal = RichTextLabel.new()
	_journal.custom_minimum_size.y = 130
	_journal.scroll_following = true
	result_panel.add_child(_journal)
	var right: VBoxContainer = _panel(workspace, 335)
	_label(right, "СВОЙСТВА И ИХ ВЛИЯНИЕ")
	_properties = RichTextLabel.new()
	_properties.bbcode_enabled = true
	_properties.selection_enabled = true
	_properties.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_properties)
	var footer: Label = _label(layout, "Текущая реализация игры · выбор готовых вариантов · зомби имеют 1000 HP для демонстрации")
	footer.modulate = Color("a4becd")

func _select_class(class_id: int) -> void:
	_class_picker.select(class_id)
	_list.clear()
	for i: int in range(5):
		_list.add_item(catalogue[class_id * 5 + i].title)
	select_ability(class_id * 5)

func select_ability(index: int) -> void:
	_generation += 1
	selected_index = clampi(index, 0, catalogue.size() - 1)
	var entry: AbilityViewerCatalog.Entry = catalogue[selected_index]
	if _class_picker.selected != entry.class_id:
		_class_picker.select(entry.class_id)
		_list.clear()
		for i: int in range(5):
			_list.add_item(catalogue[entry.class_id * 5 + i].title)
	_list.select(selected_index % 5)
	_title.text = entry.title
	_variants.clear()
	for variant: AbilityViewerCatalog.VariantKind in AbilityViewerCatalog.variants(entry):
		_variants.add_item(AbilityViewerCatalog.variant_title(variant), variant)
	selected_variant = AbilityViewerCatalog.VariantKind.BASE
	_reset_preview()

func _reset_preview() -> void:
	_generation += 1
	_play.disabled = false
	_damage = 0.0
	_hits = 0
	_journal.clear()
	var entry: AbilityViewerCatalog.Entry = catalogue[selected_index]
	arena.prepare(entry, selected_variant)
	_description.text = entry.description + "\n\n[color=#6be1d7]" + AbilityViewerCatalog.variant_explanation(selected_variant) + "[/color]"
	if not entry.planned.is_empty():
		_description.append_text("\n\n[color=#e4b47b]" + entry.planned + "[/color]")
	_properties.clear()
	for row: AbilityViewerCatalog.Property in AbilityViewerCatalog.properties(entry, arena.actor, selected_variant):
		_properties.append_text("[b]" + row.title + "[/b]\n")
		if row.base.strip_edges() != row.effective.strip_edges():
			_properties.append_text("[color=#9cabbf]" + row.base + "[/color] → [color=#6be1d7]" + row.effective + "[/color]\n")
		else:
			_properties.append_text("[color=#6be1d7]" + row.effective + "[/color]\n")
		_properties.append_text("[color=#bac8d7]" + row.explanation + "[/color]\n\n")

func play_demo() -> void:
	_reset_preview()
	_play.disabled = true
	var generation: int = _generation
	# Let real collision shapes enter the physics server before dispatching input.
	await get_tree().physics_frame
	await get_tree().physics_frame
	if generation != _generation:
		return
	_play.disabled = false
	arena.demonstrate(catalogue[selected_index], selected_variant)

func _process(_delta: float) -> void:
	if is_instance_valid(arena.actor) and is_instance_valid(_metrics):
		_metrics.text = "%.2f с · %d попаданий · %s урона\nЗдоровье Воина: %.0f / %.0f" % [arena.elapsed, _hits, str(snappedf(_damage, 0.001)), arena.actor.current_health, arena.actor.max_health]

func _panel(parent: Control, width: float) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size.x = width
	parent.add_child(panel)
	var contents: VBoxContainer = VBoxContainer.new()
	contents.add_theme_constant_override("separation", 12)
	panel.add_child(contents)
	return contents

func _label(parent: Node, value: String) -> Label:
	var label: Label = Label.new()
	label.text = value
	parent.add_child(label)
	return label

func _button(parent: Node, caption: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = caption
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _build_theme() -> void:
	theme = Theme.new()
	theme.default_font_size = 15
	var panel: StyleBoxFlat = StyleBoxFlat.new()
	panel.bg_color = Color("182334")
	panel.content_margin_left = 14
	panel.content_margin_right = 14
	panel.content_margin_top = 14
	panel.content_margin_bottom = 14
	theme.set_stylebox("panel", "PanelContainer", panel)

func _capture_demo() -> void:
	var index: int = 1
	var delay: float = 0.23
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--viewer-entry="):
			index = argument.get_slice("=", 1).to_int()
		if argument.begins_with("--viewer-delay="):
			delay = clampf(argument.get_slice("=", 1).to_float(), 0.05, 6.5)
	select_ability(index)
	if AbilityViewerCatalog.VariantKind.SHARP_EDGE in AbilityViewerCatalog.variants(catalogue[selected_index]):
		selected_variant = AbilityViewerCatalog.VariantKind.SHARP_EDGE
		_variants.select(1)
	await play_demo()
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var destination: String = "res://.review_loop/ability-laboratory.png"
	get_viewport().get_texture().get_image().save_png(destination)
	print("ABILITY_LAB_CAPTURE: " + destination)
	# Cancel the captured scene, then let native callbacks observe its removal.
	arena.clear_preview()
	await get_tree().create_timer(1.6).timeout
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit()

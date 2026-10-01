extends Control
class_name AbilityLab

var document: AbilityLabDocument = AbilityLabDocument.new()
var arena: AbilityLabArena
var inspector: AbilityLabInspector
var block_tree: Tree
var selected: AbilityStep
var examples: Array[AbilityDefinition] = AbilityLibrary.examples()
var _title: LineEdit
var _plan_text: RichTextLabel
var _journal: RichTextLabel
var _status: Label
var _metrics: Label
var _play: Button
var _kind: OptionButton
var _catalog: OptionButton
var _file: FileDialog
var _file_operation: String
var _discard: ConfirmationDialog
var _pending_open: Callable
var _damage: float = 0.0
var _hits: int = 0
var _reference: String = ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_theme()
	_build_ui()
	document.changed.connect(_document_opened)
	document.open_definition(examples[0])
	print("ABILITY_LAB_READY")
	if "--lab-capture" in OS.get_cmdline_user_args():
		_capture_demo.call_deferred()

func _build_ui() -> void:
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	add_child(margin)
	var layout: VBoxContainer = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	var heading: HBoxContainer = HBoxContainer.new()
	layout.add_child(heading)
	var brand: Label = _label(heading, "CUBE SIEGE  /  ЛАБОРАТОРИЯ СПОСОБНОСТЕЙ")
	brand.add_theme_font_size_override("font_size", 22)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var badge: Label = _label(heading, "ЭКСПЕРИМЕНТ")
	badge.modulate = Color("f6ba77")
	var toolbar: HBoxContainer = HBoxContainer.new()
	layout.add_child(toolbar)
	_title = LineEdit.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_title)
	_title.text_changed.connect(func(value: String) -> void:
		document.checkpoint()
		document.definition.title = value
		_refresh_plan()
	)
	_button(toolbar, "Новый", _new_document)
	_button(toolbar, "Открыть", func() -> void: _choose_file("load"))
	_button(toolbar, "Сохранить как…", func() -> void: _choose_file("save"))
	_button(toolbar, "↶", document.undo)
	_button(toolbar, "↷", document.redo)
	var workspace: HBoxContainer = HBoxContainer.new()
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 14)
	layout.add_child(workspace)
	var left: VBoxContainer = _panel(workspace, 255)
	_label(left, "ОБРАЗЦЫ · ЧЕРНОВИКИ")
	var catalog: OptionButton = OptionButton.new()
	_catalog = catalog
	for example: AbilityDefinition in examples:
		catalog.add_item(example.title)
	catalog.add_item("Пользовательский документ")
	catalog.set_item_disabled(examples.size(), true)
	left.add_child(catalog)
	catalog.item_selected.connect(func(index: int) -> void:
		_request_open(func() -> void: document.open_definition(examples[index]))
	)
	_label(left, "БЛОКИ ПОВЕДЕНИЯ")
	block_tree = Tree.new()
	block_tree.hide_root = true
	block_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	block_tree.custom_minimum_size.y = 150
	left.add_child(block_tree)
	block_tree.item_selected.connect(_select_block)
	var add_row: HBoxContainer = HBoxContainer.new()
	left.add_child(add_row)
	_kind = OptionButton.new()
	for caption: String in ["Область", "Движение", "Ожидание", "Рецепт"]:
		_kind.add_item(caption)
	_kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_row.add_child(_kind)
	_button(add_row, "+", _add_block)
	var edit_row: HBoxContainer = HBoxContainer.new()
	left.add_child(edit_row)
	_button(edit_row, "Копия", _duplicate_block)
	_button(edit_row, "Удалить", _delete_block)
	_button(left, "Сохранить блок как рецепт…", func() -> void: _choose_file("recipe_save"))
	_button(left, "Вставить рецепт…", func() -> void: _choose_file("recipe_load"))
	_label(left, "ИТОГОВАЯ ВРЕМЕННАЯ ШКАЛА")
	_plan_text = RichTextLabel.new()
	_plan_text.custom_minimum_size.y = 180
	_plan_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(_plan_text)
	var middle: VBoxContainer = VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.add_child(middle)
	var controls: HBoxContainer = HBoxContainer.new()
	middle.add_child(controls)
	_play = _button(controls, "▶ Испытать", _run)
	_button(controls, "Пауза", func() -> void:
		arena.paused = not arena.paused
		_status.text = "Пауза" if arena.paused else "Выполнение"
	)
	_button(controls, "Шаг", func() -> void: arena.step_frame())
	_button(controls, "Стоп", func() -> void: arena.runner.cancel("Прервано пользователем"))
	_button(controls, "Сброс", _reset_arena)
	var scenario: OptionButton = OptionButton.new()
	for caption: String in ["Группа целей", "Препятствие", "Перепад высоты"]:
		scenario.add_item(caption)
	middle.add_child(scenario)
	scenario.item_selected.connect(func(index: int) -> void:
		arena.scenario = index
		_reset_arena()
	)
	var viewport_container: SubViewportContainer = SubViewportContainer.new()
	viewport_container.stretch = true
	viewport_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	viewport_container.custom_minimum_size = Vector2(420, 200)
	middle.add_child(viewport_container)
	var viewport: SubViewport = SubViewport.new()
	viewport.size = Vector2i(640, 420)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport_container.add_child(viewport)
	arena = AbilityLabArena.new()
	viewport.add_child(arena)
	arena.runner.trace_emitted.connect(_trace)
	arena.runner.hit_applied.connect(func(amount: float) -> void:
		_hits += 1
		_damage += amount
		_update_metrics()
	)
	arena.runner.cast_finished.connect(_finished)
	_metrics = _label(middle, "0 попаданий · 0 урона")
	var compare: HBoxContainer = HBoxContainer.new()
	middle.add_child(compare)
	_button(compare, "Зафиксировать результат A", func() -> void:
		_reference = "%d попаданий / %.1f урона" % [_hits, _damage]
		_update_metrics()
	)
	_label(middle, "ПОЧЕМУ ЭТО ПРОИЗОШЛО")
	_journal = RichTextLabel.new()
	_journal.custom_minimum_size.y = 160
	_journal.scroll_following = true
	middle.add_child(_journal)
	var right: VBoxContainer = _panel(workspace, 300)
	inspector = AbilityLabInspector.new()
	inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(inspector)
	inspector.edited.connect(func() -> void:
		_refresh_tree()
		_refresh_plan()
	)
	_status = _label(layout, "")
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_file = FileDialog.new()
	_file.access = FileDialog.ACCESS_FILESYSTEM
	_file.filters = PackedStringArray(["*.tres ; Способность / рецепт"])
	_file.size = Vector2i(900, 600)
	_file.file_selected.connect(_file_selected)
	add_child(_file)
	_discard = ConfirmationDialog.new()
	_discard.dialog_text = "Есть несохранённые изменения. Открыть другой документ?"
	_discard.confirmed.connect(func() -> void: _pending_open.call())
	add_child(_discard)

func _document_opened() -> void:
	_title.text = document.definition.title
	_catalog.select(examples.size())
	for i: int in range(examples.size()):
		if examples[i].title == document.definition.title:
			_catalog.select(i)
	selected = document.definition.steps[0] as AbilityStep if not document.definition.steps.is_empty() else null
	_refresh_tree()
	inspector.inspect(document, selected)
	_refresh_plan()

func _refresh_tree() -> void:
	block_tree.set_block_signals(true)
	block_tree.clear()
	var root: TreeItem = block_tree.create_item()
	_tree_children(document.definition.steps, root)
	block_tree.set_block_signals(false)

func _tree_children(steps: Array[Resource], parent: TreeItem) -> void:
	for resource: Resource in steps:
		var step: AbilityStep = resource as AbilityStep
		if step == null:
			continue
		var item: TreeItem = block_tree.create_item(parent)
		item.set_text(0, "%s · %s" % [step.slot, step.kind_label()])
		item.set_metadata(0, step)
		if step == selected:
			item.select(0)
		_tree_children(step.children, item)

func _select_block() -> void:
	var item: TreeItem = block_tree.get_selected()
	if item:
		selected = item.get_metadata(0) as AbilityStep
		inspector.inspect(document, selected)

func _refresh_plan() -> void:
	var plan: AbilityPlan = AbilityCompiler.compile(document.definition)
	_plan_text.text = plan.describe()
	_plan_text.modulate = Color.WHITE if plan.valid() else Color("ff968d")
	_play.disabled = not plan.valid()
	_status.text = ("● Не сохранено · " if document.dirty else "") + (document.path if not document.path.is_empty() else "Черновик лаборатории · параметры образцов не утверждают баланс")

func _destination() -> Array[Resource]:
	return selected.children if selected and selected.kind == AbilityStep.Kind.RECIPE else document.definition.steps

func _add_block() -> void:
	document.checkpoint()
	var step: AbilityStep = AbilityStep.new()
	step.kind = _kind.selected as AbilityStep.Kind
	step.slot = "block_%d" % Time.get_ticks_usec()
	_destination().append(step)
	selected = step
	_refresh_tree()
	inspector.inspect(document, selected)
	_refresh_plan()

func _duplicate_block() -> void:
	if selected:
		document.checkpoint()
		var duplicate: AbilityStep = selected.duplicate(true) as AbilityStep
		duplicate.slot += "_copy_%d" % Time.get_ticks_usec()
		document.definition.steps.append(duplicate)
		selected = duplicate
		_refresh_tree()
		inspector.inspect(document, selected)
		_refresh_plan()

func _delete_block() -> void:
	if selected:
		document.checkpoint()
		_erase(document.definition.steps, selected)
		selected = null
		_refresh_tree()
		inspector.inspect(document, null)
		_refresh_plan()

func _erase(steps: Array[Resource], target: AbilityStep) -> void:
	if steps.has(target):
		steps.erase(target)
		return
	for resource: Resource in steps:
		var step: AbilityStep = resource as AbilityStep
		if step:
			_erase(step.children, target)

func _new_document() -> void:
	_request_open(func() -> void: document.open_definition(AbilityDefinition.new()))

func _request_open(action: Callable) -> void:
	if document.dirty:
		_pending_open = action
		_discard.popup_centered()
	else:
		action.call()

func _choose_file(operation: String) -> void:
	if operation == "recipe_save" and selected == null:
		_status.text = "Сначала выберите блок или составной рецепт."
		return
	_file_operation = operation
	_file.file_mode = FileDialog.FILE_MODE_OPEN_FILE if operation.ends_with("load") else FileDialog.FILE_MODE_SAVE_FILE
	DirAccess.make_dir_recursive_absolute("user://ability_lab")
	_file.current_dir = ProjectSettings.globalize_path("user://ability_lab")
	_file.current_file = "recipe.tres" if operation.begins_with("recipe") else "ability.tres"
	_file.popup_centered()

func _file_selected(path: String) -> void:
	match _file_operation:
		"save":
			var error: Error = document.save_to(path)
			_refresh_plan()
			if error != OK: _status.text = "Не удалось сохранить: " + error_string(error)
		"load":
			_request_open(func() -> void:
				var error: Error = document.load_from(path)
				if error != OK: _status.text = "Не удалось открыть: " + error_string(error)
			)
		"recipe_save":
			var recipe: AbilityDefinition = AbilityDefinition.new()
			recipe.title = selected.slot
			recipe.steps.append(selected.duplicate(true) as AbilityStep)
			var error: Error = ResourceSaver.save(recipe, path)
			_status.text = "Рецепт сохранён: " + path if error == OK else error_string(error)
		"recipe_load":
			var loaded: AbilityLabDocument = AbilityLabDocument.new()
			var error: Error = loaded.load_from(path)
			if error != OK:
				_status.text = "Не удалось вставить рецепт: " + error_string(error)
				return
			document.checkpoint()
			var recipe: AbilityStep = AbilityStep.new()
			recipe.kind = AbilityStep.Kind.RECIPE
			recipe.slot = "recipe_%d" % Time.get_ticks_usec()
			recipe.children = loaded.definition.steps
			_destination().append(recipe)
			selected = recipe
			_refresh_tree()
			inspector.inspect(document, selected)
			_refresh_plan()

func _run() -> void:
	_reset_arena()
	arena.paused = false
	if not arena.play(document.definition):
		_status.text = "Применение отклонено. Проверьте итоговую сборку."

func _reset_arena() -> void:
	arena.reset()
	_journal.clear()
	_damage = 0.0
	_hits = 0
	_update_metrics()

func _trace(event: AbilityTrace) -> void:
	if not is_instance_valid(_journal):
		return
	_journal.append_text(event.describe() + "\n")

func _update_metrics() -> void:
	_metrics.text = "%d попаданий · %.1f урона" % [_hits, _damage]
	if not _reference.is_empty():
		_metrics.text += "  |  A: " + _reference

func _finished(cancelled: bool) -> void:
	if not is_instance_valid(_status):
		return
	_status.text = "Прервано" if cancelled else "Испытание завершено · %.2f с" % arena.runner.elapsed

func _panel(parent: Control, width: float) -> VBoxContainer:
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size.x = width
	parent.add_child(panel)
	var contents: VBoxContainer = VBoxContainer.new()
	contents.add_theme_constant_override("separation", 10)
	panel.add_child(contents)
	return contents

func _label(parent: Node, text_value: String) -> Label:
	var label: Label = Label.new()
	label.text = text_value
	parent.add_child(label)
	return label

func _button(parent: Node, text_value: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _build_theme() -> void:
	theme = Theme.new()
	theme.default_font_size = 14
	var panel: StyleBoxFlat = StyleBoxFlat.new()
	panel.bg_color = Color("182334")
	panel.content_margin_left = 12
	panel.content_margin_right = 12
	panel.content_margin_top = 12
	panel.content_margin_bottom = 12
	theme.set_stylebox("panel", "PanelContainer", panel)
	var background: ColorRect = ColorRect.new()
	background.color = Color("0d1522")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

func _capture_demo() -> void:
	document.open_definition(examples[1])
	await get_tree().physics_frame
	_run()
	arena.paused = true
	for i: int in range(14):
		arena.step_frame()
	await RenderingServer.frame_post_draw
	var destination: String = "res://.review_loop/ability-laboratory.png"
	get_viewport().get_texture().get_image().save_png(destination)
	print("ABILITY_LAB_CAPTURE: " + destination)

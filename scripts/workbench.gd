class_name Workbench
extends StaticBody3D

@onready var prompt_label: Label3D = $PromptLabel

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("buildings")
	add_to_group("workbench")
	if prompt_label:
		prompt_label.text = "[E] ВЕРСТАК\n(КРАФТ & РАЗБОР)"
		prompt_label.visible = false
	_ensure_interaction_zone()

func _ensure_interaction_zone() -> void:
	for child in get_children():
		if child is InteractionZone:
			return
	var zone = InteractionZone.create_zone(self, BoxShape3D.new(), Vector3(0, 0.7, 0))
	var shape = zone.get_child(0).shape as BoxShape3D
	shape.size = Vector3(1.8, 1.4, 1.4)
	add_child(zone)

func is_ready_for_pickup() -> bool:
	return true

func is_interactable() -> bool:
	return true

func set_focused(focused: bool) -> void:
	if prompt_label:
		prompt_label.visible = focused
		prompt_label.text = "[E] ВЕРСТАК\n(КРАФТ, РАЗБОР, ТАЛАНТЫ)"
		prompt_label.modulate = Color(0.3, 0.9, 1.0) if focused else Color.WHITE

func set_interaction_progress(progress: float) -> void:
	if not prompt_label:
		return
	var bars: int = int(progress * 10.0)
	var bar_str: String = ""
	for i in range(10):
		bar_str += "█" if i < bars else "░"
	prompt_label.text = "[%s] %d%%\nОТКРЫТИЕ ВЕРСТАКА..." % [bar_str, int(progress * 100)]
	prompt_label.modulate = Color(0.2, 1.0, 0.4)

func interact(_player: Node = null, _is_shift: bool = false) -> void:
	open_workbench()

func harvest(_player: Node = null) -> void:
	open_workbench()

func open_workbench(_player: Node = null) -> void:
	var bus = get_node_or_null("/root/EventBus") if is_inside_tree() else null
	if not bus:
		var ml = Engine.get_main_loop()
		if ml and "root" in ml and ml.root:
			bus = ml.root.get_node_or_null("EventBus")
	if bus and bus.has_signal("workbench_opened"):
		bus.workbench_opened.emit()

extends StaticBody3D

@onready var prompt_label: Label3D = $PromptLabel

func _ready() -> void:
	add_to_group("interactables")
	add_to_group("buildings")
	if prompt_label:
		prompt_label.text = "[E] ВЕРСТАК\n(КРАФТ & РАЗБОР)"
		prompt_label.visible = false

func is_ready_for_pickup() -> bool:
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

func harvest(_player: Node) -> void:
	open_workbench()

func open_workbench() -> void:
	var hud: Node = get_tree().root.find_child("HUD", true, false)
	if hud and hud.has_node("WorkbenchModal"):
		var modal = hud.get_node("WorkbenchModal")
		if modal.has_method("open"):
			modal.open()

extends Node3D

@onready var label: Label3D = $Label3D

func setup(amount: float, is_crit: bool = false, custom_color: Color = Color.WHITE) -> void:
	if not label:
		label = $Label3D
	label.text = str(int(amount))
	if is_crit:
		label.modulate = Color(1.0, 0.2, 0.2, 1.0)
		label.font_size = 48
	else:
		label.modulate = custom_color
		label.font_size = 36

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y + 1.6, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tween.chain().tween_callback(queue_free)

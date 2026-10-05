class_name PixelResourceCell
extends HBoxContainer

var _frame: StyleBoxTexture = PixelUI.panel("ui_resource_counter_cell", Vector4.ZERO)

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	draw_style_box(_frame, Rect2(Vector2.ZERO, size))

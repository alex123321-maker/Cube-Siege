class_name HUDHeroPortrait
extends TextureRect

const PORTRAIT_KEYS: Array[String] = ["portrait_warrior", "portrait_archer", "portrait_engineer"]
var _active_class_id: int = -1

func _ready() -> void:
	set_class(0)

func set_class(class_id: int) -> void:
	var safe_class_id: int = clampi(class_id, 0, PORTRAIT_KEYS.size() - 1)
	if safe_class_id == _active_class_id:
		return
	texture = PixelUI.texture(PORTRAIT_KEYS[safe_class_id])
	_active_class_id = safe_class_id

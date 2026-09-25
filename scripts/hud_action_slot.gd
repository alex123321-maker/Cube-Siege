extends Control
class_name HUDActionSlot

@export var icon_texture: Texture2D
@export var action_name: String = ""
@export var key_binding: String = ""

@onready var frame: TextureRect = $Frame
@onready var icon: TextureRect = $Icon
@onready var name_label: Label = $NameLabel
@onready var key_label: Label = $Keycap/KeyLabel
@onready var cooldown_overlay: ColorRect = $CooldownOverlay
@onready var cooldown_label: Label = $CooldownOverlay/CooldownLabel

var _is_unavailable: bool = false
var _is_on_cooldown: bool = false

func _ready() -> void:
	icon.texture = icon_texture
	name_label.text = action_name
	key_label.text = key_binding
	_update_frame()

func set_action(texture: Texture2D, short_name: String, binding: String) -> void:
	icon_texture = texture
	action_name = short_name
	key_binding = binding
	if not is_node_ready():
		return
	icon.visible = true
	icon.texture = icon_texture
	name_label.text = action_name
	name_label.modulate = Color.WHITE
	key_label.text = key_binding
	_is_unavailable = false
	_update_frame()

func set_cooldown(seconds_left: float) -> void:
	var on_cooldown := seconds_left > 0.08
	cooldown_overlay.visible = on_cooldown and not _is_unavailable
	if on_cooldown:
		cooldown_label.text = "%.1f" % seconds_left
	if _is_on_cooldown != on_cooldown:
		_is_on_cooldown = on_cooldown
		_update_frame()

func set_unavailable(unavailable: bool) -> void:
	if _is_unavailable == unavailable:
		return
	_is_unavailable = unavailable
	icon.visible = not unavailable
	name_label.modulate = Color(0.52, 0.58, 0.65, 1.0) if unavailable else Color.WHITE
	_update_frame()

func _update_frame() -> void:
	if not is_node_ready():
		return
	if _is_unavailable:
		frame.texture = preload("res://assets/ui/hud_visual_kit/frames/action_slot_disabled_64.png")
	elif _is_on_cooldown:
		frame.texture = preload("res://assets/ui/hud_visual_kit/frames/action_slot_cooldown_64.png")
	else:
		frame.texture = preload("res://assets/ui/hud_visual_kit/frames/action_slot_normal_64.png")

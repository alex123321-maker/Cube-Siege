extends Control
class_name HUDActionSlot

@export var icon_texture: Texture2D
@export var action_name: String = ""
@export var key_binding: String = ""

@onready var frame: TextureRect = $VisualRegion/Frame
@onready var icon: TextureRect = $VisualRegion/Icon
@onready var name_label: Label = $NameLabel
@onready var key_label: Label = $Keycap/KeyLabel
@onready var cooldown_overlay: ColorRect = $VisualRegion/CooldownOverlay
@onready var cooldown_label: Label = $VisualRegion/CooldownOverlay/CooldownLabel

var _is_unavailable: bool = false
var _is_on_cooldown: bool = false
var _cooldown_seconds: float = 0.0

func _ready() -> void:
    if icon_texture != null or not action_name.is_empty():
        set_action(icon_texture, action_name, key_binding, tooltip_text)
    else:
        set_unavailable(true)

func set_action(texture: Texture2D, short_name: String, binding: String, detail: String = "") -> void:
    icon_texture = texture
    action_name = short_name
    key_binding = binding
    _is_unavailable = icon_texture == null
    _is_on_cooldown = false
    _cooldown_seconds = 0.0
    if _is_unavailable:
        push_error("HUDActionSlot: missing required icon for %s (%s)" % [short_name, binding])
    if not is_node_ready():
        return
    icon.texture = icon_texture
    icon.visible = not _is_unavailable
    name_label.text = action_name
    name_label.modulate = Color(0.52, 0.58, 0.65, 1.0) if _is_unavailable else Color.WHITE
    key_label.text = key_binding
    tooltip_text = detail
    _update_cooldown()
    _update_frame()

func set_cooldown(seconds_left: float) -> void:
    _cooldown_seconds = maxf(seconds_left, 0.0)
    var on_cooldown: bool = _cooldown_seconds > 0.08
    _update_cooldown()
    if _is_on_cooldown != on_cooldown:
        _is_on_cooldown = on_cooldown
        _update_frame()

func set_unavailable(unavailable: bool) -> void:
    _is_unavailable = unavailable or icon_texture == null
    icon.visible = not _is_unavailable
    _update_cooldown()
    name_label.modulate = Color(0.52, 0.58, 0.65, 1.0) if _is_unavailable else Color.WHITE
    _update_frame()

func _update_cooldown() -> void:
    var show_cooldown: bool = _cooldown_seconds > 0.08 and not _is_unavailable
    cooldown_overlay.visible = show_cooldown
    cooldown_label.text = "%.1f" % _cooldown_seconds if show_cooldown else ""

func _update_frame() -> void:
    if not is_node_ready():
        return
    if _is_unavailable:
        frame.texture = preload("res://assets/ui/hud_visual_kit/frames/action_slot_disabled_64.png")
    elif _is_on_cooldown:
        frame.texture = preload("res://assets/ui/hud_visual_kit/frames/action_slot_cooldown_64.png")
    else:
        frame.texture = preload("res://assets/ui/hud_visual_kit/frames/action_slot_normal_64.png")

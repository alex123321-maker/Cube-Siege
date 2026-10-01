extends SubViewportContainer
class_name HUDHeroPortrait

const MODEL_SCENES: Array[PackedScene] = [
    preload("res://assets/models/characters/hero_warrior.tscn"),
    preload("res://assets/models/characters/hero_archer.tscn"),
    preload("res://assets/models/characters/hero_engineer.tscn"),
]
const MODEL_SCALES: Array[float] = [0.8, 0.8, 0.8]
const MODEL_CENTER_Y: Array[float] = [0.0, 0.106, 0.194]
const MODEL_ROTATION_Y: Array[float] = [0.0, PI, PI]

@onready var viewport: SubViewport = $SubViewport
@onready var model_root: Node3D = $SubViewport/World/ModelRoot

var _active_class_id: int = -1

func _ready() -> void:
    set_class(0)

func set_class(class_id: int) -> void:
    var safe_class_id: int = clampi(class_id, 0, MODEL_SCENES.size() - 1)
    if safe_class_id == _active_class_id:
        return
    for child: Node in model_root.get_children():
        child.queue_free()
    var model: Node3D = MODEL_SCENES[safe_class_id].instantiate() as Node3D
    model.scale = Vector3.ONE * MODEL_SCALES[safe_class_id]
    model.position.y = -MODEL_CENTER_Y[safe_class_id] * MODEL_SCALES[safe_class_id]
    model.rotation.y = MODEL_ROTATION_Y[safe_class_id]
    model_root.add_child(model)
    _active_class_id = safe_class_id
    viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

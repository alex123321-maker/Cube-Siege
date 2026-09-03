extends "res://scripts/building_base.gd"

@export var spike_damage: float = 20.0
@export var trigger_interval: float = 1.0

var trigger_timer: float = 0.0

@onready var damage_area: Area3D = $DamageArea
@onready var spikes_mesh: MeshInstance3D = $Visuals/SpikesMesh

func _ready() -> void:
	super._ready()
	building_name = "Floor Spikes"
	max_health = 100.0
	current_health = 100.0

func _physics_process(delta: float) -> void:
	trigger_timer -= delta
	if trigger_timer <= 0.0:
		trigger_timer = trigger_interval
		check_and_damage_enemies()

func check_and_damage_enemies() -> void:
	if not damage_area:
		return

	var overlapping_areas: Array[Area3D] = damage_area.get_overlapping_areas()
	var triggered: bool = false
	for area in overlapping_areas:
		if area.has_method("take_damage"):
			var target: Node = area.get_target_node() if area.has_method("get_target_node") else area.get_parent()
			if target and target.is_in_group("enemies"):
				area.take_damage(spike_damage, Vector3.UP * 2.0, "spikes", self)
				triggered = true

	if triggered and spikes_mesh:
		# Quick visual pop animation
		var tween: Tween = create_tween()
		tween.tween_property(spikes_mesh, "position:y", 0.35, 0.06)
		tween.chain().tween_property(spikes_mesh, "position:y", 0.05, 0.15)

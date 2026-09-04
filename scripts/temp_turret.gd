extends Node3D

@export var lifetime: float = 12.0
@export var fire_rate: float = 0.8
@export var damage: float = 24.0
@export var attack_range: float = 11.0

var fire_timer: float = 0.0
const ARROW_SCENE = preload("res://scenes/prefabs/arrow_projectile.tscn")
const TowerTargeting = preload("res://scripts/tower_targeting.gd")

@onready var swivel: Node3D = get_node_or_null("TempTurretModel/root/swivel")
@onready var life_label: Label3D = $LifeLabel

func _ready() -> void:
	add_to_group("buildings")
	add_to_group("allies")
	if not swivel:
		swivel = find_child("swivel", true, false)

	# Deploy mechanical VFX
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx:
		vfx.spawn_sparks(global_position + Vector3(0, 0.4, 0), Vector3.UP, Color(0.9, 0.7, 0.2), 14, 4.0)
		vfx.spawn_shockwave(global_position, 1.8, Color(0.8, 0.5, 0.2), 0.25)

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if life_label:
		life_label.text = "TURRET: %.1fs" % max(0.0, lifetime)
	if lifetime <= 0.0:
		explode_and_free()
		return

	fire_timer -= delta
	if fire_timer <= 0.0:
		var target: Node3D = TowerTargeting.find_nearest_enemy(get_tree(), global_position, attack_range)
		if target:
			fire_at(target)
			fire_timer = fire_rate

func fire_at(target: Node3D) -> void:
	var target_pos: Vector3 = target.global_position + Vector3(0, 0.8, 0)
	var spawn_pos: Vector3 = global_position + Vector3(0, 0.8, 0)
	var to_target: Vector3 = target_pos - spawn_pos
	if to_target.length_squared() < 0.01:
		return
	var aim_dir: Vector3 = to_target.normalized()

	if swivel:
		var horiz: Vector3 = Vector3(aim_dir.x, 0, aim_dir.z)
		if horiz.length_squared() > 0.01:
			swivel.look_at(swivel.global_position + horiz.normalized(), Vector3.UP)

	# Muzzle flash VFX
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx:
		vfx.spawn_turret_muzzle_flash(spawn_pos + aim_dir * 0.7, aim_dir)

	var proj: Node3D = ARROW_SCENE.instantiate()
	get_parent().add_child(proj)
	proj.global_position = spawn_pos + aim_dir * 0.8
	proj.setup(aim_dir, damage, self, 1)

func explode_and_free() -> void:
	var vfx = get_node_or_null("/root/VFXManager")
	if vfx:
		vfx.spawn_sparks(global_position + Vector3(0, 0.5, 0), Vector3.UP, Color(0.5, 0.5, 0.5), 16, 5.0)
		vfx.spawn_puff(global_position + Vector3(0, 0.6, 0), Color(0.2, 0.2, 0.2), 16, 3.5)

	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3(0.01, 0.01, 0.01), 0.2)
	tween.chain().tween_callback(queue_free)

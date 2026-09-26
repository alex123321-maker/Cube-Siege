extends RefCounted
class_name EnemyPresentation

## Handles presentation, animation playback, and visual state for enemy characters.
## Architecture rule: Gameplay scripts remain source of truth for damage, cooldowns,
## timings, and death. Presentation reacts to state and plays animations.

var anim_player: AnimationPlayer = null
var body_mesh: MeshInstance3D = null
var model_root: Node3D = null
var is_dying: bool = false
var current_action: StringName = &""

func setup(enemy: CharacterBody3D, model: Node3D = null) -> void:
	if model:
		model_root = model
	elif enemy.has_node("Visuals/Model"):
		model_root = enemy.get_node("Visuals/Model") as Node3D
	elif enemy.has_node("Visuals"):
		model_root = enemy.get_node("Visuals") as Node3D

	if model_root:
		anim_player = model_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var meshes: Array[Node] = model_root.find_children("*", "MeshInstance3D", true, false)
		if not meshes.is_empty():
			body_mesh = meshes[0] as MeshInstance3D

	if is_instance_valid(anim_player):
		if anim_player.has_animation("idle"):
			anim_player.play("idle")
		if not anim_player.animation_finished.is_connected(_on_animation_finished):
			anim_player.animation_finished.connect(_on_animation_finished)

func update(_delta: float, velocity: Vector3, gait_speed: float = 3.2) -> void:
	if not is_instance_valid(anim_player) or is_dying:
		return

	# Do not interrupt action animations (attack, hit) with locomotion cycles
	if current_action != &"" and anim_player.is_playing() and anim_player.current_animation == current_action:
		return

	current_action = &""
	var horizontal_speed: float = Vector2(velocity.x, velocity.z).length()
	if horizontal_speed > 0.1:
		if anim_player.has_animation("move"):
			if anim_player.current_animation != "move":
				anim_player.play("move", 0.15)
			# Scale animation playback rate to match locomotion velocity and prevent foot sliding
			var speed_ratio: float = horizontal_speed / maxf(0.1, gait_speed)
			anim_player.speed_scale = clampf(speed_ratio, 0.5, 2.0)
	else:
		if anim_player.has_animation("idle"):
			if anim_player.current_animation != "idle":
				anim_player.play("idle", 0.2)
			anim_player.speed_scale = 1.0

func play_attack(start_time: float = -1.0) -> void:
	if not is_instance_valid(anim_player) or is_dying:
		return
	if anim_player.has_animation("attack"):
		current_action = &"attack"
		anim_player.speed_scale = 1.0
		if start_time >= 0.0:
			anim_player.play("attack", 0.04)
			anim_player.seek(start_time, true)
		else:
			anim_player.stop()
			anim_player.play("attack", 0.08)

func advance_to_attack_phase(phase_time: float) -> void:
	if not is_instance_valid(anim_player) or is_dying:
		return
	if anim_player.has_animation("attack"):
		current_action = &"attack"
		anim_player.speed_scale = 1.0
		if anim_player.current_animation != "attack" or not anim_player.is_playing():
			anim_player.play("attack", 0.04)
			anim_player.seek(phase_time, true)
		elif anim_player.current_animation_position < phase_time:
			anim_player.seek(phase_time, true)

func play_hit() -> void:
	if not is_instance_valid(anim_player) or is_dying:
		return
	# Do not cancel active attack action with hit twitch
	if current_action == &"attack" and anim_player.is_playing():
		return
	if anim_player.has_animation("hit"):
		current_action = &"hit"
		anim_player.speed_scale = 1.0
		anim_player.stop()
		anim_player.play("hit", 0.05)

func play_death() -> void:
	is_dying = true
	current_action = &"death"
	if is_instance_valid(anim_player) and anim_player.has_animation("death"):
		anim_player.speed_scale = 1.0
		anim_player.stop()
		anim_player.play("death", 0.08)

func get_animation_length(anim_name: StringName) -> float:
	if is_instance_valid(anim_player) and anim_player.has_animation(anim_name):
		return anim_player.get_animation(anim_name).length
	return 0.0

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == current_action and not is_dying:
		current_action = &""
		if is_instance_valid(anim_player) and anim_player.has_animation("idle"):
			anim_player.play("idle", 0.15)

extends RefCounted
class_name PlayerPresentation

## Handles player animations, floating combat text popups, and the portal compass indicator.

const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

var anim_player: AnimationPlayer = null
var active_model: Node3D = null
var portal_compass: Node3D = null
var compass_label_3d: Label3D = null
var cached_portal: Node3D = null

var pose_layer: CharacterPoseLayer = null
var animation_profile: CharacterAnimationProfile = null
var procedural_enabled: bool = true
var debug_enabled: bool = false
var _debug_label: Label3D = null
var _debug_elapsed: float = 0.0

const WARRIOR_PROFILE = preload("res://assets/animations/profiles/warrior.tres")
const ARCHER_PROFILE = preload("res://assets/animations/profiles/archer.tres")
const ENGINEER_PROFILE = preload("res://assets/animations/profiles/engineer.tres")
const ACTIONS: Array[StringName] = [&"attack", &"special", &"utility", &"ultimate"]

func setup(player_node: CharacterBody3D) -> void:
	portal_compass = player_node.get_node_or_null("PortalCompass") as Node3D
	if portal_compass:
		compass_label_3d = portal_compass.get_node_or_null("CompassLabel") as Label3D
	set_active_model(player_node.get_node_or_null("Visuals/HeroWarrior") as Node3D, WARRIOR_PROFILE)

func set_active_model(model: Node3D, profile: CharacterAnimationProfile = null) -> void:
	if pose_layer:
		pose_layer.reset()
	if is_instance_valid(anim_player):
		anim_player.stop()
	if is_instance_valid(_debug_label):
		_debug_label.free()
	_debug_label = null
	pose_layer = null
	anim_player = null
	active_model = model
	if not is_instance_valid(model):
		return
	animation_profile = profile if profile else WARRIOR_PROFILE
	anim_player = model.get_node_or_null(animation_profile.animation_player_path) as AnimationPlayer
	if not anim_player:
		return
	anim_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	pose_layer = CharacterPoseLayer.new()
	pose_layer.bind(model, animation_profile)
	anim_player.play("idle")

func update_animations(body: CharacterBody3D, is_parrying: bool, is_dashing: bool,
		delta: float = 1.0 / 60.0, orientation: PlayerOrientation = null) -> void:
	if not is_instance_valid(anim_player) or not pose_layer:
		return
	pose_layer.restore_authored()
	var cur: StringName = anim_player.current_animation
	var action_active: bool = cur in ACTIONS and anim_player.is_playing()
	var actual_velocity: Vector3 = body.get_real_velocity()
	if not action_active:
		var next: StringName = &"idle"
		if is_parrying:
			next = &"block" if anim_player.has_animation("block") else &"utility"
		elif is_dashing or Vector2(actual_velocity.x, actual_velocity.z).length() > animation_profile.movement_threshold:
			next = &"walk"
		if cur != next:
			anim_player.play(next, animation_profile.action_blend_seconds)
	# Only locomotion speed follows movement. Actions keep their authored clock.
	anim_player.speed_scale = 1.0
	if anim_player.current_animation == &"walk":
		anim_player.speed_scale = clampf(Vector2(actual_velocity.x, actual_velocity.z).length()
			/ animation_profile.gait_reference_speed, animation_profile.min_playback_rate, animation_profile.max_playback_rate)
	# Sparse Node3D clips do not key every joint. Start untouched channels from
	# the rig rest pose so an ended action/walk cannot leave a leg or arm behind.
	pose_layer.reset()
	anim_player.advance(delta)
	var facing: Vector3 = orientation.body_facing_direction if orientation else -body.global_basis.z
	var aim: Vector3 = orientation.aim_direction if orientation else facing
	var move: Vector3 = orientation.move_direction if orientation else actual_velocity.normalized()
	var turn: float = orientation.angular_velocity if orientation else 0.0
	pose_layer.enabled = procedural_enabled
	pose_layer.update(delta, facing, aim, move, actual_velocity, turn, is_dashing,
		cur if action_active else &"", is_parrying)
	_update_debug(delta)

func _play_action(animation: StringName, fallback: StringName = &"") -> void:
	if not is_instance_valid(anim_player):
		return
	var selected: StringName = animation if anim_player.has_animation(animation) else fallback
	if selected.is_empty() or not anim_player.has_animation(selected):
		return
	if pose_layer:
		pose_layer.restore_authored()
	anim_player.speed_scale = 1.0
	# Restart only for a new gameplay request, never at a placement/hit event.
	anim_player.stop(true)
	anim_player.play(selected, animation_profile.action_blend_seconds)

func play_attack_animation() -> void:
	_play_action(&"attack")

func play_special_animation() -> void:
	_play_action(&"special", &"attack")

func play_utility_animation() -> void:
	_play_action(&"utility", &"block")

func play_ultimate_animation() -> void:
	_play_action(&"ultimate")

func _update_debug(delta: float) -> void:
	if not debug_enabled:
		if is_instance_valid(_debug_label):
			_debug_label.visible = false
		return
	if not is_instance_valid(_debug_label):
		_debug_label = Label3D.new()
		_debug_label.font_size = 20
		_debug_label.pixel_size = 0.006
		_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_debug_label.no_depth_test = true
		_debug_label.position.y = 3.7
		active_model.add_child(_debug_label)
	_debug_label.visible = true
	_debug_elapsed += delta
	if _debug_elapsed >= 0.1:
		_debug_label.text = pose_layer.debug_text()
		_debug_elapsed = 0.0

func spawn_popup_text(player: CharacterBody3D, text: String, color: Color) -> void:
	if not player or not player.is_inside_tree():
		return
	var popup: Node3D = FLOATING_TEXT_SCENE.instantiate()
	player.get_parent().add_child(popup)
	popup.global_position = player.global_position + Vector3(0, 2.2, 0)
	var lbl: Label3D = popup.get_node_or_null("Label3D") as Label3D
	if lbl:
		lbl.text = text
		lbl.modulate = color

	var tween: Tween = popup.create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y + 1.6, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if lbl:
		tween.tween_property(lbl, "modulate:a", 0.0, 0.6).set_delay(0.2)
	tween.chain().tween_callback(popup.queue_free)

func update_portal_compass(player: CharacterBody3D) -> void:
	if not portal_compass or not is_instance_valid(portal_compass):
		return

	if not cached_portal or not is_instance_valid(cached_portal):
		if "portal" in player and player.portal:
			cached_portal = player.portal
	if not cached_portal:
		return

	var to_p: Vector3 = cached_portal.global_position - player.global_position
	to_p.y = 0.0
	if to_p.length_squared() > 0.1:
		portal_compass.look_at(portal_compass.global_position + to_p.normalized(), Vector3.UP)

	var dist: float = to_p.length()
	var status_str: String = "[РЕМОНТ]"
	var col: Color = Color(0.2, 0.9, 1.0)

	var state: int = cached_portal.get("current_state") if cached_portal.get("current_state") != null else 0
	if state == 1: # CHARGING
		status_str = "[ЗАРЯДКА: %ds]" % int(cached_portal.get("charge_timer"))
		col = Color(1.0, 0.85, 0.2)
	elif state == 2: # ACTIVE
		status_str = "[ЭВАКУАЦИЯ ГОТОВА!]"
		col = Color(0.2, 1.0, 0.4)

	if compass_label_3d:
		compass_label_3d.text = "⮵ ПОРТАЛ: %dm\n%s" % [int(dist), status_str]
		compass_label_3d.modulate = col

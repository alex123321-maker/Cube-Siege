extends RefCounted
class_name PlayerPresentation

## Handles player animations, floating combat text popups, and the portal compass indicator.

const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

var anim_player: AnimationPlayer = null
var active_model: Node3D = null
var portal_compass: Node3D = null
var compass_label_3d: Label3D = null
var cached_portal: Node3D = null

func setup(player_node: CharacterBody3D) -> void:
	portal_compass = player_node.get_node_or_null("PortalCompass") as Node3D
	if portal_compass:
		compass_label_3d = portal_compass.get_node_or_null("CompassLabel") as Label3D

	var default_model = player_node.get_node_or_null("Visuals/HeroWarrior") as Node3D
	if not default_model:
		default_model = player_node.find_child("HeroWarrior", true, false) as Node3D
	set_active_model(default_model)

func set_active_model(model: Node3D) -> void:
	active_model = model
	if active_model and is_instance_valid(active_model):
		anim_player = active_model.get_node_or_null("AnimationPlayer") as AnimationPlayer
		if not anim_player:
			anim_player = active_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	else:
		anim_player = null

func update_animations(body: CharacterBody3D, is_parrying: bool, is_dashing: bool) -> void:
	if not anim_player:
		return

	var cur = anim_player.current_animation
	if cur in ["attack", "special", "utility", "ultimate"]:
		return

	if is_parrying:
		if cur != "block" and cur != "utility":
			if anim_player.has_animation("block"):
				anim_player.play("block")
			elif anim_player.has_animation("utility"):
				anim_player.play("utility")
	elif is_dashing or body.velocity.length_squared() > 0.5:
		if cur != "walk":
			anim_player.play("walk")
	else:
		if cur != "idle":
			anim_player.play("idle")

func play_attack_animation() -> void:
	if anim_player and anim_player.has_animation("attack"):
		anim_player.stop()
		anim_player.play("attack")

func play_special_animation() -> void:
	if anim_player and anim_player.has_animation("special"):
		anim_player.stop()
		anim_player.play("special")
	elif anim_player and anim_player.has_animation("attack"):
		anim_player.stop()
		anim_player.play("attack")

func play_utility_animation() -> void:
	if anim_player and anim_player.has_animation("utility"):
		anim_player.stop()
		anim_player.play("utility")
	elif anim_player and anim_player.has_animation("block"):
		anim_player.stop()
		anim_player.play("block")

func play_ultimate_animation() -> void:
	if anim_player and anim_player.has_animation("ultimate"):
		anim_player.stop()
		anim_player.play("ultimate")

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

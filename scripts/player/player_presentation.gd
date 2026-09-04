extends RefCounted
class_name PlayerPresentation

## Handles player animations, floating combat text popups, and the portal compass indicator.

const FLOATING_TEXT_SCENE = preload("res://scenes/floating_text.tscn")

var anim_player: AnimationPlayer = null
var portal_compass: Node3D = null
var compass_label_3d: Label3D = null
var cached_portal: Node3D = null

func setup(player_node: CharacterBody3D) -> void:
	anim_player = player_node.find_child("AnimationPlayer", true, false) as AnimationPlayer
	portal_compass = player_node.get_node_or_null("PortalCompass") as Node3D
	if portal_compass:
		compass_label_3d = portal_compass.get_node_or_null("CompassLabel") as Label3D

func update_animations(body: CharacterBody3D, is_parrying: bool, is_dashing: bool) -> void:
	if not anim_player:
		return

	if is_parrying:
		if anim_player.current_animation != "block":
			anim_player.play("block")
	elif is_dashing or body.velocity.length_squared() > 0.5:
		if anim_player.current_animation != "walk" and anim_player.current_animation != "attack":
			anim_player.play("walk")
	else:
		if anim_player.current_animation != "idle" and anim_player.current_animation != "attack":
			anim_player.play("idle")

func play_attack_animation() -> void:
	if anim_player and anim_player.has_animation("attack"):
		anim_player.stop()
		anim_player.play("attack")

func spawn_popup_text(player: CharacterBody3D, text: String, color: Color) -> void:
	if not player or not player.is_inside_tree():
		return
	var popup: Node3D = FLOATING_TEXT_SCENE.instantiate()
	player.get_parent().add_child(popup)
	popup.global_position = player.global_position + Vector3(0, 2.2, 0)
	if popup.has_node("Label3D"):
		popup.get_node("Label3D").text = text
		popup.get_node("Label3D").modulate = color

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

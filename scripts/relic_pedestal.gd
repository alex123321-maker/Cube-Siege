extends StaticBody3D

@onready var prompt_label: Label3D = $PromptLabel

func _ready() -> void:
	add_to_group("interactables")
	if prompt_label:
		prompt_label.text = "👑 [E] ЗАБРАТЬ РЕЛИКВИЮ БОССА"

func is_ready_for_pickup() -> bool:
	return true

func set_focused(focused: bool) -> void:
	if prompt_label:
		prompt_label.visible = focused
		prompt_label.modulate = Color.GOLD if focused else Color.WHITE

func set_interaction_progress(progress: float) -> void:
	if not prompt_label:
		return
	var bars: int = int(progress * 10.0)
	var bar_str: String = ""
	for i in range(10):
		bar_str += "█" if i < bars else "░"
	prompt_label.text = "[%s] %d%%\nПОЛУЧЕНИЕ РЕЛИКВИИ..." % [bar_str, int(progress * 100)]
	prompt_label.modulate = Color(1.0, 0.9, 0.2)

func harvest(player: Node) -> void:
	claim_relic(player)

func claim_relic(player: Node) -> void:
	# Randomly grant one of the 3 boss relics
	var relics = [
		{"name": "👑 СЕРДЦЕ КОЛОССА", "desc": "+100 HP и взрывной рывок!"},
		{"name": "🏹 НАКОНЕЧНИК БУРИ", "desc": "+2 Сквозных пробития стрелам и баллистам!"},
		{"name": "🏰 КОРОНА КОРОЛЯ ШИПОВ", "desc": "50% Отражения урона стенам!"}
	]
	var chosen = relics[randi() % relics.size()]

	if player:
		if chosen.name.begins_with("👑"):
			player.max_health += 100.0
			player.current_health += 100.0
			if player.has_signal("health_changed"):
				player.emit_signal("health_changed", player.current_health, player.max_health)
		elif chosen.name.begins_with("🏹"):
			player.attack_damage += 25.0
		elif chosen.name.begins_with("🏰"):
			var walls = get_tree().get_nodes_in_group("walls")
			for w in walls:
				if "reflect_percent" in w:
					w.reflect_percent = 0.5

		var popup = load("res://scenes/floating_text.tscn").instantiate()
		get_parent().add_child(popup)
		popup.global_position = global_position + Vector3(0, 2.5, 0)
		if popup.has_node("Label3D"):
			popup.get_node("Label3D").text = "РЕЛИКВИЯ ПОЛУЧЕНА!\n%s\n(%s)" % [chosen.name, chosen.desc]
			popup.get_node("Label3D").modulate = Color.GOLD

	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector3.ZERO, 0.3)
	tween.chain().tween_callback(queue_free)

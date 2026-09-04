extends RefCounted
class_name InteractableTarget

## Typed interface contract for objects that the Player can interact with.

enum ActionType {
	NONE,
	HARVEST,
	REPAIR,
	DEMOLISH,
	PORTAL_REPAIR,
	PORTAL_EVACUATE,
	WORKBENCH
}

static func can_interact(node: Node, player: Node, is_shift: bool = false) -> bool:
	if not node or not is_instance_valid(node):
		return false

	if node.has_method("is_ready_for_pickup") and not node.is_ready_for_pickup():
		return false

	if node.is_in_group("portal"):
		return true
	if node.is_in_group("buildings"):
		return true
	if node.is_in_group("resource_nodes") and node.has_method("is_ready_for_pickup"):
		return node.is_ready_for_pickup()
	if node.is_in_group("workbench"):
		return true

	return false

static func get_action_type(node: Node, _player: Node, is_shift: bool = false) -> ActionType:
	if not node or not is_instance_valid(node):
		return ActionType.NONE

	if node.is_in_group("portal"):
		var state = node.get("current_state")
		if state == 2: # State.ACTIVE
			return ActionType.PORTAL_EVACUATE
		elif state == 0: # State.BROKEN
			return ActionType.PORTAL_REPAIR
		return ActionType.NONE

	if node.is_in_group("buildings"):
		if is_shift:
			return ActionType.DEMOLISH
		else:
			return ActionType.REPAIR

	if node.is_in_group("resource_nodes"):
		return ActionType.HARVEST

	if node.is_in_group("workbench"):
		return ActionType.WORKBENCH

	return ActionType.NONE

static func execute_interaction(node: Node, player: Node, is_shift: bool = false) -> void:
	if not node or not is_instance_valid(node):
		return

	var action = get_action_type(node, player, is_shift)
	match action:
		ActionType.DEMOLISH:
			if node.has_method("demolish"):
				node.demolish(player)
		ActionType.REPAIR:
			if node.has_method("repair") and node.get("current_health") != null:
				if node.current_health < node.max_health:
					var bs: Node = player.get_tree().root.find_child("BuildingSystem", true, false)
					if bs and bs.has_method("spend_resources") and bs.spend_resources(1, 0, 0):
						node.repair(100.0)
					elif player.has_method("spawn_popup_text"):
						player.spawn_popup_text("NEED 1 WOOD!", Color.ORANGE)
		ActionType.HARVEST:
			if node.has_method("harvest"):
				node.harvest(player)
		ActionType.PORTAL_REPAIR, ActionType.PORTAL_EVACUATE:
			if node.has_method("interact_portal"):
				node.interact_portal(player)
		ActionType.WORKBENCH:
			if node.has_method("open_workbench"):
				node.open_workbench(player)

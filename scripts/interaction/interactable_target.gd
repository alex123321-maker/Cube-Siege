extends RefCounted
class_name InteractableTarget

## Explicit typed contract and interaction dispatch for interactable game objects.

enum ActionType {
	NONE,
	HARVEST,
	REPAIR,
	DEMOLISH,
	PORTAL_REPAIR,
	PORTAL_EVACUATE,
	WORKBENCH
}

static func can_interact(node: Node, _player: Node = null, _is_shift: bool = false) -> bool:
	if not node or not is_instance_valid(node):
		return false

	if node is Workbench:
		return (node as Workbench).is_interactable()
	elif node is PortalController:
		return (node as PortalController).is_interactable()
	elif node is BuildingBase:
		return (node as BuildingBase).is_interactable()
	elif node is ResourceTree:
		return (node as ResourceTree).is_interactable()
	elif node is ResourceRock:
		return (node as ResourceRock).is_interactable()
	elif node is RelicPedestal:
		return (node as RelicPedestal).is_interactable()

	# Polymorphic contract fallback
	if node.has_method("is_interactable"):
		return node.is_interactable()
	if node.has_method("is_ready_for_pickup"):
		return node.is_ready_for_pickup()
	if node.has_method("interact") or node.has_method("open_workbench") or node.has_method("harvest"):
		return true

	return false

static func get_action_type(node: Node, _player: Node = null, is_shift: bool = false) -> ActionType:
	if not node or not is_instance_valid(node):
		return ActionType.NONE

	if not can_interact(node):
		return ActionType.NONE

	# Typed classification (Workbench checked ahead of BuildingBase)
	if node is Workbench:
		return ActionType.WORKBENCH

	if node is PortalController:
		var portal = node as PortalController
		if portal.current_state == PortalController.State.ACTIVE:
			return ActionType.PORTAL_EVACUATE
		elif portal.current_state == PortalController.State.BROKEN:
			return ActionType.PORTAL_REPAIR
		return ActionType.NONE

	if node is BuildingBase:
		if is_shift:
			return ActionType.DEMOLISH
		else:
			return ActionType.REPAIR

	if node is ResourceTree or node is ResourceRock or node is RelicPedestal:
		return ActionType.HARVEST

	# Polymorphic fallback
	if node.has_method("get_interaction_type"):
		return node.get_interaction_type(_player, is_shift)
	if node.has_method("open_workbench"):
		return ActionType.WORKBENCH
	if node.has_method("interact_portal"):
		var state = node.get("current_state")
		if state == 2:
			return ActionType.PORTAL_EVACUATE
		elif state == 0:
			return ActionType.PORTAL_REPAIR
		return ActionType.NONE
	if node.has_method("demolish") or node.has_method("repair"):
		return ActionType.DEMOLISH if is_shift else ActionType.REPAIR
	if node.has_method("harvest"):
		return ActionType.HARVEST

	return ActionType.NONE

static func execute_interaction(node: Node, player: Node, is_shift: bool = false) -> void:
	if not node or not is_instance_valid(node) or not can_interact(node):
		return

	# Typed dispatch
	if node is Workbench:
		(node as Workbench).interact(player, is_shift)
		return
	elif node is PortalController:
		(node as PortalController).interact(player, is_shift)
		return
	elif node is BuildingBase:
		(node as BuildingBase).interact(player, is_shift)
		return
	elif node is ResourceTree:
		(node as ResourceTree).interact(player, is_shift)
		return
	elif node is ResourceRock:
		(node as ResourceRock).interact(player, is_shift)
		return
	elif node is RelicPedestal:
		(node as RelicPedestal).interact(player, is_shift)
		return

	# Polymorphic fallback
	if node.has_method("interact"):
		node.interact(player, is_shift)
		return

	var action = get_action_type(node, player, is_shift)
	match action:
		ActionType.DEMOLISH:
			if node.has_method("demolish"):
				node.demolish(player)
		ActionType.REPAIR:
			if node.has_method("interact_repair"):
				node.interact_repair(player)
			elif node.has_method("repair") and node.get("current_health") != null:
				if node.current_health < node.max_health:
					var bs: Node = player.building_system if ("building_system" in player and player.building_system) else null
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
				node.open_workbench()

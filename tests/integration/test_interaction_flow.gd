extends GutTest

const InteractableTarget = preload("res://scripts/interaction/interactable_target.gd")
const PlayerInteraction = preload("res://scripts/player/player_interaction.gd")

class MockBuilding extends Node3D:
	var demolished: bool = false
	var repaired: bool = false
	var current_health: float = 50.0
	var max_health: float = 100.0

	func _init() -> void:
		add_to_group("buildings")

	func demolish(_player: Node) -> void:
		demolished = true

	func repair(amount: float) -> void:
		repaired = true
		current_health += amount

class MockWorkbench extends Node3D:
	var opened: bool = false

	func _init() -> void:
		add_to_group("workbench")

	func open_workbench(_player: Node) -> void:
		opened = true

class MockResourceNode extends Node3D:
	var ready_for_pickup: bool = true
	var harvested: bool = false

	func _init() -> void:
		add_to_group("resource_nodes")

	func is_ready_for_pickup() -> bool:
		return ready_for_pickup

	func harvest(_player: Node) -> void:
		harvested = true

func test_interactable_target_can_interact() -> void:
	var dummy_player = Node.new()
	add_child_autoqfree(dummy_player)

	var b = MockBuilding.new()
	add_child_autoqfree(b)
	assert_true(InteractableTarget.can_interact(b, dummy_player))

	var wb = MockWorkbench.new()
	add_child_autoqfree(wb)
	assert_true(InteractableTarget.can_interact(wb, dummy_player))

	var rn = MockResourceNode.new()
	add_child_autoqfree(rn)
	assert_true(InteractableTarget.can_interact(rn, dummy_player))

	rn.ready_for_pickup = false
	assert_false(InteractableTarget.can_interact(rn, dummy_player))

	var inert = Node3D.new()
	add_child_autoqfree(inert)
	assert_false(InteractableTarget.can_interact(inert, dummy_player))

func test_interactable_target_action_types() -> void:
	var dummy_player = Node.new()
	add_child_autoqfree(dummy_player)

	var b = MockBuilding.new()
	add_child_autoqfree(b)
	assert_eq(InteractableTarget.get_action_type(b, dummy_player, false), InteractableTarget.ActionType.REPAIR)
	assert_eq(InteractableTarget.get_action_type(b, dummy_player, true), InteractableTarget.ActionType.DEMOLISH)

	var wb = MockWorkbench.new()
	add_child_autoqfree(wb)
	assert_eq(InteractableTarget.get_action_type(wb, dummy_player, false), InteractableTarget.ActionType.WORKBENCH)

	var rn = MockResourceNode.new()
	add_child_autoqfree(rn)
	assert_eq(InteractableTarget.get_action_type(rn, dummy_player, false), InteractableTarget.ActionType.HARVEST)

func test_interactable_target_execution() -> void:
	var dummy_player = Node.new()
	add_child_autoqfree(dummy_player)

	var b = MockBuilding.new()
	add_child_autoqfree(b)
	InteractableTarget.execute_interaction(b, dummy_player, true)
	assert_true(b.demolished, "Demolish should be called on building with shift")

	var wb = MockWorkbench.new()
	add_child_autoqfree(wb)
	InteractableTarget.execute_interaction(wb, dummy_player, false)
	assert_true(wb.opened, "Open workbench should be called")

	var rn = MockResourceNode.new()
	add_child_autoqfree(rn)
	InteractableTarget.execute_interaction(rn, dummy_player, false)
	assert_true(rn.harvested, "Harvest should be called on resource node")

func test_player_interaction_candidate_lifecycle() -> void:
	var interaction_system = PlayerInteraction.new()
	var n1 = Node3D.new()
	var n2 = Node3D.new()
	add_child_autoqfree(n1)
	add_child_autoqfree(n2)

	interaction_system.add_candidate(n1)
	assert_eq(interaction_system.candidate_nodes.size(), 1)
	assert_true(interaction_system.candidate_nodes.has(n1))

	interaction_system.add_candidate(n2)
	assert_eq(interaction_system.candidate_nodes.size(), 2)

	# Duplicate should not be added
	interaction_system.add_candidate(n1)
	assert_eq(interaction_system.candidate_nodes.size(), 2)

	interaction_system.remove_candidate(n1)
	assert_eq(interaction_system.candidate_nodes.size(), 1)
	assert_false(interaction_system.candidate_nodes.has(n1))

	interaction_system.remove_candidate(n2)
	assert_eq(interaction_system.candidate_nodes.size(), 0)

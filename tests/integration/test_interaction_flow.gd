extends GutTest

const InteractableTarget = preload("res://scripts/interaction/interactable_target.gd")
const PlayerInteraction = preload("res://scripts/player/player_interaction.gd")

const WORKBENCH_SCENE = preload("res://scenes/prefabs/workbench.tscn")
const WALL_SCENE = preload("res://scenes/prefabs/wall_wood.tscn")
const PORTAL_SCENE = preload("res://scenes/portal.tscn")
const RESOURCE_TREE_SCENE = preload("res://scenes/resource_tree.tscn")

func test_real_workbench_interaction() -> void:
	var dummy_player = Node.new()
	add_child_autoqfree(dummy_player)

	var wb = WORKBENCH_SCENE.instantiate()
	add_child_autoqfree(wb)

	# Must be recognized as Workbench and NOT Repair despite being in "buildings" group
	assert_true(InteractableTarget.can_interact(wb, dummy_player), "Real workbench should be interactable")
	assert_eq(InteractableTarget.get_action_type(wb, dummy_player, false), InteractableTarget.ActionType.WORKBENCH, "Real workbench must be WORKBENCH action, not REPAIR")

	# Interaction emits EventBus.workbench_opened cleanly without finding HUD
	var bus = get_node_or_null("/root/EventBus")
	var signal_emitted = false
	if bus:
		bus.workbench_opened.connect(func(): signal_emitted = true)

	InteractableTarget.execute_interaction(wb, dummy_player, false)
	if bus:
		assert_true(signal_emitted, "EventBus.workbench_opened must be emitted on workbench interact")

func test_real_building_interaction() -> void:
	var dummy_player = Node.new()
	add_child_autoqfree(dummy_player)

	var wall = WALL_SCENE.instantiate()
	add_child_autoqfree(wall)

	assert_true(InteractableTarget.can_interact(wall, dummy_player), "Real wall should be interactable")
	assert_eq(InteractableTarget.get_action_type(wall, dummy_player, false), InteractableTarget.ActionType.REPAIR, "Building without shift should be REPAIR")
	assert_eq(InteractableTarget.get_action_type(wall, dummy_player, true), InteractableTarget.ActionType.DEMOLISH, "Building with shift should be DEMOLISH")

	# Test demolish
	InteractableTarget.execute_interaction(wall, dummy_player, true)

func test_real_portal_interaction() -> void:
	var dummy_player = Node.new()
	add_child_autoqfree(dummy_player)

	var portal = PORTAL_SCENE.instantiate()
	add_child_autoqfree(portal)

	assert_true(InteractableTarget.can_interact(portal, dummy_player), "Real portal should be interactable")
	assert_eq(InteractableTarget.get_action_type(portal, dummy_player, false), InteractableTarget.ActionType.PORTAL_REPAIR, "Broken portal should be PORTAL_REPAIR")

	portal.current_state = PortalController.State.ACTIVE
	assert_eq(InteractableTarget.get_action_type(portal, dummy_player, false), InteractableTarget.ActionType.PORTAL_EVACUATE, "Active portal should be PORTAL_EVACUATE")

func test_real_resource_tree_interaction() -> void:
	var dummy_player = Node.new()
	add_child_autoqfree(dummy_player)

	var tree = RESOURCE_TREE_SCENE.instantiate()
	add_child_autoqfree(tree)

	# Standing tree is damaged via combat, not picked up yet
	assert_false(InteractableTarget.can_interact(tree, dummy_player), "Standing tree should not be interactable for pickup")

	# Fell tree so it becomes pickupable
	tree.fell_tree()
	assert_true(InteractableTarget.can_interact(tree, dummy_player), "Felled tree should be interactable for pickup")
	assert_eq(InteractableTarget.get_action_type(tree, dummy_player, false), InteractableTarget.ActionType.HARVEST, "Felled tree should be HARVEST")

func test_inert_node_non_interactable() -> void:
	var dummy_player = Node.new()
	add_child_autoqfree(dummy_player)

	var inert = Node3D.new()
	add_child_autoqfree(inert)
	assert_false(InteractableTarget.can_interact(inert, dummy_player))
	assert_eq(InteractableTarget.get_action_type(inert, dummy_player), InteractableTarget.ActionType.NONE)

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

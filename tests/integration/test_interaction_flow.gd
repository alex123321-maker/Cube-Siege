extends GutTest

const InteractableTarget = preload("res://scripts/interaction/interactable_target.gd")
const PlayerInteraction = preload("res://scripts/player/player_interaction.gd")

const WORKBENCH_SCENE = preload("res://scenes/prefabs/workbench.tscn")
const WALL_SCENE = preload("res://scenes/prefabs/wood_wall.tscn")
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
	var signal_emitted = [false]
	if bus:
		bus.workbench_opened.connect(func(): signal_emitted[0] = true)

	InteractableTarget.execute_interaction(wb, dummy_player, false)
	if bus:
		assert_true(signal_emitted[0], "EventBus.workbench_opened must be emitted on workbench interact")

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

func test_tree_and_rock_harvest_retention_and_no_duplicate_harvest() -> void:
	var dummy_player = CharacterBody3D.new()
	add_child_autoqfree(dummy_player)
	dummy_player.position = Vector3(0, 0, 0)

	var tree = RESOURCE_TREE_SCENE.instantiate()
	add_child_autoqfree(tree)
	tree.position = Vector3(1, 0, 0)

	tree.fell_tree()
	# Verify InteractionZone exists on dedicated layer 32 rather than relying on layer 8 body shift
	var tree_zone = tree.get_node_or_null("InteractionZone") as InteractionZone
	assert_not_null(tree_zone, "Felled tree must have an InteractionZone")
	if tree_zone:
		assert_eq(tree_zone.collision_layer, InteractionZone.INTERACTION_LAYER, "Zone must be on Layer 6 (32)")
		assert_eq(tree_zone.get_interaction_target(), tree, "Zone target must reference tree")

	assert_true(tree.is_destroyed, "Tree must be destroyed/felled")
	assert_false(tree.is_harvested, "Tree must not yet be harvested")
	assert_true(InteractableTarget.can_interact(tree, dummy_player), "Felled tree must be interactable")

	# Harvest attempt without BuildingSystem must fail and NOT mark as harvested
	var harvest_no_bs = tree.harvest(dummy_player)
	assert_false(harvest_no_bs, "Harvest without BuildingSystem must return false")
	assert_false(tree.is_harvested, "Tree must NOT be marked harvested when receiver is missing")
	assert_true(InteractableTarget.can_interact(tree, dummy_player), "Tree must remain interactable for retry")

	# Wire BuildingSystem to player
	var bs = BuildingSystem.new()
	bs.name = "BuildingSystem"
	add_child_autoqfree(bs)
	dummy_player.set("building_system", bs)
	dummy_player.set_meta("building_system", bs)
	var initial_wood = bs.wallet.get_wood()

	# Successful harvest
	var harvest_success = tree.harvest(dummy_player)
	assert_true(harvest_success, "Harvest with BuildingSystem must succeed")
	assert_true(tree.is_harvested, "Tree must be marked as harvested")
	assert_eq(bs.wallet.get_wood(), initial_wood + tree.wood_yield, "Wood must be added to wallet")
	assert_false(InteractableTarget.can_interact(tree, dummy_player), "Harvested tree must no longer be interactable")

	# Duplicate harvest attempt must fail and not add additional resources
	var duplicate_harvest = tree.harvest(dummy_player)
	assert_false(duplicate_harvest, "Duplicate harvest must return false")
	assert_eq(bs.wallet.get_wood(), initial_wood + tree.wood_yield, "No duplicate wood granted")

	# Rock test
	var rock = ResourceRock.new()
	add_child_autoqfree(rock)
	var col_shape = CollisionShape3D.new()
	col_shape.shape = BoxShape3D.new()
	rock.add_child(col_shape)
	rock.position = Vector3(2, 0, 0)

	rock.break_rock()
	var rock_zone = rock.get_node_or_null("InteractionZone") as InteractionZone
	assert_not_null(rock_zone, "Broken rock must have an InteractionZone")
	if rock_zone:
		assert_eq(rock_zone.collision_layer, InteractionZone.INTERACTION_LAYER, "Zone must be on Layer 6 (32)")
		assert_eq(rock_zone.get_interaction_target(), rock, "Zone target must reference rock")

	assert_true(rock.is_destroyed, "Rock must be destroyed")
	assert_false(rock.is_harvested, "Rock must not yet be harvested")
	assert_true(InteractableTarget.can_interact(rock, dummy_player), "Broken rock must be interactable")

	# Rock harvest with BuildingSystem
	var initial_stone = bs.wallet.get_stone()
	var rock_harvest_ok = rock.harvest(dummy_player)
	assert_true(rock_harvest_ok, "Rock harvest must succeed")
	assert_true(rock.is_harvested, "Rock must be marked as harvested")
	assert_eq(bs.wallet.get_stone(), initial_stone + rock.resource_yield, "Stone must be added to wallet")
	assert_false(InteractableTarget.can_interact(rock, dummy_player), "Harvested rock must no longer be interactable")

	# Duplicate harvest attempt on rock
	var rock_dup = rock.harvest(dummy_player)
	assert_false(rock_dup, "Duplicate rock harvest must return false")
	assert_eq(bs.wallet.get_stone(), initial_stone + rock.resource_yield, "No duplicate stone granted")


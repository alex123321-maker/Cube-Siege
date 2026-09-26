extends GutTest

const InteractableTarget = preload("res://scripts/interaction/interactable_target.gd")
const PlayerInteraction = preload("res://scripts/player/player_interaction.gd")
const InteractionZone = preload("res://scripts/interaction/interaction_zone.gd")

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const TREE_SCENE = preload("res://scenes/resource_tree.tscn")
const STONE_SCENE = preload("res://scenes/resource_stone.tscn")
const IRON_SCENE = preload("res://scenes/resource_iron.tscn")

func _create_player(pos: Vector3 = Vector3.ZERO) -> CharacterBody3D:
	var player = PLAYER_SCENE.instantiate() as CharacterBody3D
	add_child_autoqfree(player)
	player.global_position = pos
	var bs = BuildingSystem.new()
	bs.name = "BuildingSystem"
	player.add_child(bs)
	player.building_system = bs
	return player

func _get_expected_yield(player: Node, base_amount: int) -> int:
	var mult: int = 1
	if player.get("resource_multiplier") != null:
		mult = maxi(1, int(player.resource_multiplier))
	return base_amount * mult

func test_tree_destruction_right_next_to_player_and_hold_e_pickup() -> void:
	var player = _create_player(Vector3.ZERO)
	var initial_wood = player.building_system.wallet.get_wood()
	var tree = TREE_SCENE.instantiate() as ResourceTree
	add_child_autoqfree(tree)
	tree.global_position = Vector3(1.5, 0, 0)

	# 2 physics frames to populate overlapping areas
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Intact tree is not interactable (needs chopping via combat)
	assert_false(InteractableTarget.can_interact(tree, player), "Intact tree must not be interactable for pickup")

	# Destroy tree while standing right next to it without moving away
	tree.take_damage(200.0)
	assert_true(tree.is_destroyed, "Tree must be destroyed")
	assert_false(tree.is_harvested, "Tree must not yet be harvested")

	# Physics frame for collision updates
	await get_tree().physics_frame
	await get_tree().physics_frame

	# Candidate must be discovered without player moving away
	assert_true(InteractableTarget.can_interact(tree, player), "Felled tree must be interactable")

	# Process interaction to acquire focus
	player.interaction.process_interaction(player, 0.05)
	assert_eq(player.interaction.focused_interactable, tree, "Player must focus destroyed tree without moving away")

	# Simulate holding interact (partial hold: 0.5s / 1.0s)
	Input.action_press("interact")
	player.interaction.process_interaction(player, 0.5)
	assert_eq(player.building_system.wallet.get_wood(), initial_wood, "No wood granted before hold duration completes")
	assert_false(tree.is_harvested, "Tree must not be harvested prematurely")

	# Complete hold duration (additional 0.6s >= 1.0s)
	player.interaction.process_interaction(player, 0.6)
	Input.action_release("interact")

	var expected_wood = _get_expected_yield(player, tree.wood_yield)
	assert_true(tree.is_harvested, "Tree must be harvested after full hold")
	assert_eq(player.building_system.wallet.get_wood(), initial_wood + expected_wood, "Wood wallet must increment by wood_yield * multiplier")

	# Subsequent interaction checks
	player.interaction.process_interaction(player, 0.05)
	assert_null(player.interaction.focused_interactable, "Harvested tree must lose focus")

func test_stone_destruction_right_next_to_player_and_hold_e_pickup() -> void:
	var player = _create_player(Vector3.ZERO)
	var initial_stone = player.building_system.wallet.get_stone()
	var stone = STONE_SCENE.instantiate() as ResourceRock
	add_child_autoqfree(stone)
	stone.global_position = Vector3(1.5, 0, 0)

	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_false(InteractableTarget.can_interact(stone, player), "Intact stone rock must not be interactable")

	# Destroy rock standing next to it
	stone.take_damage(200.0)
	assert_true(stone.is_destroyed, "Stone must be destroyed")
	assert_false(stone.is_harvested, "Stone must not yet be harvested")

	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_true(InteractableTarget.can_interact(stone, player), "Broken stone must be interactable")

	player.interaction.process_interaction(player, 0.05)
	assert_eq(player.interaction.focused_interactable, stone, "Broken stone must be focused without moving away")

	# Full hold 1.0s
	Input.action_press("interact")
	player.interaction.process_interaction(player, 1.1)
	Input.action_release("interact")

	var expected_stone = _get_expected_yield(player, stone.resource_yield)
	assert_true(stone.is_harvested, "Stone rock must be marked harvested")
	assert_eq(player.building_system.wallet.get_stone(), initial_stone + expected_stone, "Stone must be added to wallet")

func test_iron_destruction_right_next_to_player_and_hold_e_pickup() -> void:
	var player = _create_player(Vector3.ZERO)
	var initial_iron = player.building_system.wallet.get_iron()
	var iron = IRON_SCENE.instantiate() as ResourceRock
	add_child_autoqfree(iron)
	iron.global_position = Vector3(1.5, 0, 0)

	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_false(InteractableTarget.can_interact(iron, player), "Intact iron deposit must not be interactable")

	iron.take_damage(200.0)
	assert_true(iron.is_destroyed, "Iron must be destroyed")
	assert_false(iron.is_harvested, "Iron must not yet be harvested")

	await get_tree().physics_frame
	await get_tree().physics_frame

	assert_true(InteractableTarget.can_interact(iron, player), "Broken iron must be interactable")

	player.interaction.process_interaction(player, 0.05)
	assert_eq(player.interaction.focused_interactable, iron, "Broken iron must be focused without moving away")

	# Full hold 1.0s
	Input.action_press("interact")
	player.interaction.process_interaction(player, 1.1)
	Input.action_release("interact")

	var expected_iron = _get_expected_yield(player, iron.resource_yield)
	assert_true(iron.is_harvested, "Iron must be marked harvested")
	assert_eq(player.building_system.wallet.get_iron(), initial_iron + expected_iron, "Iron must be added to wallet")

func test_destruction_outside_range_and_approach() -> void:
	var player = _create_player(Vector3.ZERO)
	var tree = TREE_SCENE.instantiate() as ResourceTree
	add_child_autoqfree(tree)
	tree.global_position = Vector3(8.0, 0, 0) # Outside 4.5m radius

	await get_tree().physics_frame
	await get_tree().physics_frame

	tree.take_damage(200.0)
	assert_true(tree.is_destroyed)

	await get_tree().physics_frame
	await get_tree().physics_frame

	# Should not be focused because it is outside interaction radius
	player.interaction.process_interaction(player, 0.05)
	assert_null(player.interaction.focused_interactable, "Target outside radius must not be focused")

	# Move player close to destroyed tree
	player.global_position = Vector3(7.0, 0, 0) # 1.0m away from tree
	await get_tree().physics_frame
	await get_tree().physics_frame

	player.interaction.process_interaction(player, 0.05)
	assert_eq(player.interaction.focused_interactable, tree, "Target within radius must be focused upon approach")

func test_hold_release_cancels_and_resets_progress() -> void:
	var player = _create_player(Vector3.ZERO)
	var initial_wood = player.building_system.wallet.get_wood()
	var tree = TREE_SCENE.instantiate() as ResourceTree
	add_child_autoqfree(tree)
	tree.global_position = Vector3(1.5, 0, 0)

	await get_tree().physics_frame
	await get_tree().physics_frame

	tree.take_damage(200.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	player.interaction.process_interaction(player, 0.05)
	assert_eq(player.interaction.focused_interactable, tree)

	# Partial hold
	Input.action_press("interact")
	player.interaction.process_interaction(player, 0.5)
	assert_gt(player.interaction.interact_hold_timer, 0.0)

	# Release key before completion
	Input.action_release("interact")
	player.interaction.process_interaction(player, 0.05)
	assert_eq(player.interaction.interact_hold_timer, 0.0, "Releasing key must reset hold timer")
	assert_false(tree.is_harvested, "Cancelled hold must not harvest")
	assert_eq(player.building_system.wallet.get_wood(), initial_wood, "No wood granted on cancelled hold")

func test_target_freed_during_hold_handles_gracefully() -> void:
	var player = _create_player(Vector3.ZERO)
	var initial_wood = player.building_system.wallet.get_wood()
	var tree = TREE_SCENE.instantiate() as ResourceTree
	add_child_autoqfree(tree)
	tree.global_position = Vector3(1.5, 0, 0)

	await get_tree().physics_frame
	await get_tree().physics_frame

	tree.take_damage(200.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	player.interaction.process_interaction(player, 0.05)
	assert_eq(player.interaction.focused_interactable, tree)

	# Start hold
	Input.action_press("interact")
	player.interaction.process_interaction(player, 0.5)

	# Target gets queued for deletion / unloaded mid-hold
	tree.queue_free()
	await get_tree().process_frame

	# Next tick should handle freed target without crashing or throwing errors
	player.interaction.process_interaction(player, 0.05)
	Input.action_release("interact")

	assert_null(player.interaction.focused_interactable, "Focus must be cleared when target is freed")
	assert_eq(player.interaction.interact_hold_timer, 0.0, "Hold timer must be reset when target is freed")
	assert_eq(player.building_system.wallet.get_wood(), initial_wood, "No resources should be granted for freed target")

func test_multi_zone_candidate_deduplication() -> void:
	var player = _create_player(Vector3.ZERO)
	var tree = TREE_SCENE.instantiate() as ResourceTree
	add_child_autoqfree(tree)
	tree.global_position = Vector3(1.5, 0, 0)

	# Attach a second InteractionZone referencing the same tree
	var extra_zone = InteractionZone.create_zone(tree, SphereShape3D.new(), Vector3(0, 0.5, 0))
	tree.add_child(extra_zone)

	await get_tree().physics_frame
	await get_tree().physics_frame

	tree.take_damage(200.0)
	await get_tree().physics_frame
	await get_tree().physics_frame

	player.interaction.process_interaction(player, 0.05)

	# Only one candidate entry should exist for the tree
	var tree_candidates: int = 0
	for candidate in player.interaction.candidate_nodes:
		if candidate == tree:
			tree_candidates += 1
	assert_eq(tree_candidates, 1, "Duplicate zones referencing the same target must be deduplicated")

class MockMapGen extends Node:
	var recorded_cells: Array[Vector3] = []
	func record_harvest(pos: Vector3) -> void:
		recorded_cells.append(pos)

func _setup_unwired_player_with_nearby_systems() -> Dictionary:
	var player = _create_player(Vector3.ZERO)
	var old_bs = player.building_system
	player.building_system = null
	if old_bs and is_instance_valid(old_bs):
		old_bs.queue_free()

	# 1. Child BuildingSystem named "BuildingSystem", but player.building_system remains null
	var child_bs = BuildingSystem.new()
	child_bs.name = "BuildingSystem"
	player.add_child(child_bs)

	# 2. Sibling BuildingSystem named "BuildingSystem"
	var sib_named_bs = BuildingSystem.new()
	sib_named_bs.name = "BuildingSystem"
	add_child_autoqfree(sib_named_bs)

	# 3. Sibling BuildingSystem with different name
	var sib_other_bs = BuildingSystem.new()
	sib_other_bs.name = "OtherBuildingSystem"
	add_child_autoqfree(sib_other_bs)

	# Mock MapGenerator in group
	var mock_map = MockMapGen.new()
	mock_map.add_to_group("map_generator")
	add_child_autoqfree(mock_map)

	var initial_balances = {
		"child_wood": child_bs.wallet.get_wood(),
		"child_stone": child_bs.wallet.get_stone(),
		"child_iron": child_bs.wallet.get_iron(),
		"sib1_wood": sib_named_bs.wallet.get_wood(),
		"sib1_stone": sib_named_bs.wallet.get_stone(),
		"sib1_iron": sib_named_bs.wallet.get_iron(),
		"sib2_wood": sib_other_bs.wallet.get_wood(),
		"sib2_stone": sib_other_bs.wallet.get_stone(),
		"sib2_iron": sib_other_bs.wallet.get_iron(),
	}

	return {
		"player": player,
		"child_bs": child_bs,
		"sib_named_bs": sib_named_bs,
		"sib_other_bs": sib_other_bs,
		"mock_map": mock_map,
		"initial_balances": initial_balances,
	}

func _assert_nearby_wallets_unchanged(ctx: Dictionary, desc: String) -> void:
	var init_b = ctx.initial_balances
	assert_eq(ctx.child_bs.wallet.get_wood(), init_b.child_wood, "%s: child_bs wood unchanged" % desc)
	assert_eq(ctx.child_bs.wallet.get_stone(), init_b.child_stone, "%s: child_bs stone unchanged" % desc)
	assert_eq(ctx.child_bs.wallet.get_iron(), init_b.child_iron, "%s: child_bs iron unchanged" % desc)

	assert_eq(ctx.sib_named_bs.wallet.get_wood(), init_b.sib1_wood, "%s: sib_named_bs wood unchanged" % desc)
	assert_eq(ctx.sib_named_bs.wallet.get_stone(), init_b.sib1_stone, "%s: sib_named_bs stone unchanged" % desc)
	assert_eq(ctx.sib_named_bs.wallet.get_iron(), init_b.sib1_iron, "%s: sib_named_bs iron unchanged" % desc)

	assert_eq(ctx.sib_other_bs.wallet.get_wood(), init_b.sib2_wood, "%s: sib_other_bs wood unchanged" % desc)
	assert_eq(ctx.sib_other_bs.wallet.get_stone(), init_b.sib2_stone, "%s: sib_other_bs stone unchanged" % desc)
	assert_eq(ctx.sib_other_bs.wallet.get_iron(), init_b.sib2_iron, "%s: sib_other_bs iron unchanged" % desc)

func test_unassigned_receiver_tree_with_nearby_systems() -> void:
	var ctx = _setup_unwired_player_with_nearby_systems()
	var player = ctx.player
	var mock_map = ctx.mock_map

	var tree = TREE_SCENE.instantiate() as ResourceTree
	add_child_autoqfree(tree)
	tree.global_position = Vector3(1.5, 0, 0)
	tree.fell_tree()

	# Attempt harvest without explicit receiver
	var harvest_res = tree.harvest(player)
	assert_false(harvest_res, "Tree harvest without receiver must return false")
	assert_false(tree.is_harvested, "Tree must NOT be marked harvested")
	assert_true(InteractableTarget.can_interact(tree, player), "Tree must remain interactable for retry")
	_assert_nearby_wallets_unchanged(ctx, "Tree harvest failure")
	assert_eq(mock_map.recorded_cells.size(), 0, "No cell harvest should be recorded on failure")

	# Assign valid receiver
	var assigned_bs = BuildingSystem.new()
	assigned_bs.name = "AssignedBuildingSystem"
	player.add_child(assigned_bs)
	player.building_system = assigned_bs

	var initial_wood = assigned_bs.wallet.get_wood()
	var expected_wood = _get_expected_yield(player, tree.wood_yield)

	var retry_res = tree.harvest(player)
	assert_true(retry_res, "Tree harvest must succeed once receiver is explicitly assigned")
	assert_true(tree.is_harvested, "Tree must now be marked harvested")
	assert_eq(assigned_bs.wallet.get_wood(), initial_wood + expected_wood, "Wood granted to assigned receiver")
	_assert_nearby_wallets_unchanged(ctx, "Tree harvest success")
	assert_eq(mock_map.recorded_cells.size(), 1, "Cell harvest must be recorded exactly once")

	# Duplicate attempt
	assert_false(tree.harvest(player), "Duplicate harvest must fail")
	assert_eq(assigned_bs.wallet.get_wood(), initial_wood + expected_wood, "No duplicate wood granted")
	assert_eq(mock_map.recorded_cells.size(), 1, "Cell harvest count remains 1")

func test_unassigned_receiver_stone_with_nearby_systems() -> void:
	var ctx = _setup_unwired_player_with_nearby_systems()
	var player = ctx.player
	var mock_map = ctx.mock_map

	var stone = STONE_SCENE.instantiate() as ResourceRock
	add_child_autoqfree(stone)
	stone.global_position = Vector3(1.5, 0, 0)
	stone.take_damage(200.0)

	var harvest_res = stone.harvest(player)
	assert_false(harvest_res, "Stone harvest without receiver must return false")
	assert_false(stone.is_harvested, "Stone must NOT be marked harvested")
	assert_true(InteractableTarget.can_interact(stone, player), "Stone must remain interactable for retry")
	_assert_nearby_wallets_unchanged(ctx, "Stone harvest failure")
	assert_eq(mock_map.recorded_cells.size(), 0, "No cell harvest should be recorded on failure")

	var assigned_bs = BuildingSystem.new()
	assigned_bs.name = "AssignedBuildingSystem"
	player.add_child(assigned_bs)
	player.building_system = assigned_bs

	var initial_stone = assigned_bs.wallet.get_stone()
	var expected_stone = _get_expected_yield(player, stone.resource_yield)

	var retry_res = stone.harvest(player)
	assert_true(retry_res, "Stone harvest must succeed once receiver is explicitly assigned")
	assert_true(stone.is_harvested, "Stone must now be marked harvested")
	assert_eq(assigned_bs.wallet.get_stone(), initial_stone + expected_stone, "Stone granted to assigned receiver")
	_assert_nearby_wallets_unchanged(ctx, "Stone harvest success")
	assert_eq(mock_map.recorded_cells.size(), 1, "Cell harvest must be recorded exactly once")

	assert_false(stone.harvest(player), "Duplicate harvest must fail")
	assert_eq(assigned_bs.wallet.get_stone(), initial_stone + expected_stone, "No duplicate stone granted")
	assert_eq(mock_map.recorded_cells.size(), 1, "Cell harvest count remains 1")

func test_unassigned_receiver_iron_with_nearby_systems() -> void:
	var ctx = _setup_unwired_player_with_nearby_systems()
	var player = ctx.player
	var mock_map = ctx.mock_map

	var iron = IRON_SCENE.instantiate() as ResourceRock
	add_child_autoqfree(iron)
	iron.global_position = Vector3(1.5, 0, 0)
	iron.take_damage(200.0)

	var harvest_res = iron.harvest(player)
	assert_false(harvest_res, "Iron harvest without receiver must return false")
	assert_false(iron.is_harvested, "Iron must NOT be marked harvested")
	assert_true(InteractableTarget.can_interact(iron, player), "Iron must remain interactable for retry")
	_assert_nearby_wallets_unchanged(ctx, "Iron harvest failure")
	assert_eq(mock_map.recorded_cells.size(), 0, "No cell harvest should be recorded on failure")

	var assigned_bs = BuildingSystem.new()
	assigned_bs.name = "AssignedBuildingSystem"
	player.add_child(assigned_bs)
	player.building_system = assigned_bs

	var initial_iron = assigned_bs.wallet.get_iron()
	var expected_iron = _get_expected_yield(player, iron.resource_yield)

	var retry_res = iron.harvest(player)
	assert_true(retry_res, "Iron harvest must succeed once receiver is explicitly assigned")
	assert_true(iron.is_harvested, "Iron must now be marked harvested")
	assert_eq(assigned_bs.wallet.get_iron(), initial_iron + expected_iron, "Iron granted to assigned receiver")
	_assert_nearby_wallets_unchanged(ctx, "Iron harvest success")
	assert_eq(mock_map.recorded_cells.size(), 1, "Cell harvest must be recorded exactly once")

	assert_false(iron.harvest(player), "Duplicate harvest must fail")
	assert_eq(assigned_bs.wallet.get_iron(), initial_iron + expected_iron, "No duplicate iron granted")
	assert_eq(mock_map.recorded_cells.size(), 1, "Cell harvest count remains 1")

func test_unassigned_receiver_free_pickup_with_nearby_systems() -> void:
	var ctx = _setup_unwired_player_with_nearby_systems()
	var player = ctx.player
	var mock_map = ctx.mock_map

	var pickup = FreeResourcePickup.new()
	pickup.yield_amount = 2
	add_child_autoqfree(pickup)
	pickup.global_position = Vector3(1.5, 0, 0)

	var harvest_res = pickup.harvest(player)
	assert_false(harvest_res, "Pickup harvest without receiver must return false")
	assert_false(pickup.is_harvested, "Pickup must NOT be marked harvested")
	assert_true(InteractableTarget.can_interact(pickup, player), "Pickup must remain interactable for retry")
	_assert_nearby_wallets_unchanged(ctx, "Pickup harvest failure")
	assert_eq(mock_map.recorded_cells.size(), 0, "No cell harvest should be recorded on failure")

	var assigned_bs = BuildingSystem.new()
	assigned_bs.name = "AssignedBuildingSystem"
	player.add_child(assigned_bs)
	player.building_system = assigned_bs

	var initial_wood = assigned_bs.wallet.get_wood()
	var expected_wood = _get_expected_yield(player, pickup.yield_amount)

	var retry_res = pickup.harvest(player)
	assert_true(retry_res, "Pickup harvest must succeed once receiver is explicitly assigned")
	assert_true(pickup.is_harvested, "Pickup must now be marked harvested")
	assert_eq(assigned_bs.wallet.get_wood(), initial_wood + expected_wood, "Wood granted to assigned receiver")
	_assert_nearby_wallets_unchanged(ctx, "Pickup harvest success")
	assert_eq(mock_map.recorded_cells.size(), 1, "Cell harvest must be recorded exactly once")

	assert_false(pickup.harvest(player), "Duplicate harvest must fail")
	assert_eq(assigned_bs.wallet.get_wood(), initial_wood + expected_wood, "No duplicate wood granted")
	assert_eq(mock_map.recorded_cells.size(), 1, "Cell harvest count remains 1")

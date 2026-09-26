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

func test_missing_receiver_safely_retains_harvest() -> void:
	var player = _create_player(Vector3.ZERO)
	# Remove building_system
	player.building_system.queue_free()
	player.building_system = null
	await get_tree().process_frame

	var tree = TREE_SCENE.instantiate() as ResourceTree
	add_child_autoqfree(tree)
	tree.global_position = Vector3(1.5, 0, 0)
	tree.fell_tree()

	# Attempt direct harvest without receiver
	var harvest_res = tree.harvest(player)
	assert_false(harvest_res, "Harvest without receiver must return false")
	assert_false(tree.is_harvested, "Object must NOT be marked harvested if receiver missing")
	assert_true(InteractableTarget.can_interact(tree, player), "Object must remain interactable for retry")

	# Now attach valid BuildingSystem
	var bs = BuildingSystem.new()
	bs.name = "BuildingSystem"
	player.add_child(bs)
	player.building_system = bs

	var initial_wood = bs.wallet.get_wood()
	var expected_wood = _get_expected_yield(player, tree.wood_yield)
	var harvest_retry = tree.harvest(player)
	assert_true(harvest_retry, "Harvest must succeed after receiver is attached")
	assert_true(tree.is_harvested, "Object must now be marked harvested")
	assert_eq(bs.wallet.get_wood(), initial_wood + expected_wood, "Wood must be granted once")

	# Duplicate attempt
	assert_false(tree.harvest(player), "Duplicate harvest must fail")
	assert_eq(bs.wallet.get_wood(), initial_wood + expected_wood, "No duplicate wood granted")

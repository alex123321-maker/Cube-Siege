extends GutTest

const PLAYER_SCENE = preload("res://scenes/player.tscn")
const TREE_SCENE = preload("res://scenes/resource_tree.tscn")
const STONE_SCENE = preload("res://scenes/resource_stone.tscn")
const IRON_SCENE = preload("res://scenes/resource_iron.tscn")
const FREE_PICKUP_SCRIPT = preload("res://scripts/world/free_resource_pickup.gd")
const FLOATING_TEXT_SCRIPT = preload("res://scripts/floating_text.gd")

var _world: Node3D = null
var _player: CharacterBody3D = null

func before_each() -> void:
	_world = Node3D.new()
	_world.name = "TestWorld"
	add_child_autoqfree(_world)

	_player = PLAYER_SCENE.instantiate() as CharacterBody3D
	_world.add_child(_player)
	_player.global_position = Vector3.ZERO

	var bs = BuildingSystem.new()
	bs.name = "BuildingSystem"
	_player.add_child(bs)
	_player.building_system = bs

func after_each() -> void:
	if get_tree().paused:
		get_tree().paused = false
	await wait_seconds(0.1)

func _get_floating_texts(parent: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child in parent.get_children():
		if is_instance_valid(child) and not child.is_queued_for_deletion():
			if child.name.begins_with("FloatingText") or (child.get_script() and child.get_script() == FLOATING_TEXT_SCRIPT):
				result.append(child as Node3D)
	return result

func _wait_for_popup_cleanup(popup: Node3D, timeout_seconds: float = 1.2) -> bool:
	var elapsed: float = 0.0
	var step: float = 0.05
	while elapsed < timeout_seconds:
		if not is_instance_valid(popup) or popup.is_queued_for_deletion():
			return true
		await wait_seconds(step)
		elapsed += step
	return not is_instance_valid(popup) or popup.is_queued_for_deletion()

func test_tree_harvest_notification_lifecycle() -> void:
	var tree = TREE_SCENE.instantiate() as ResourceTree
	_world.add_child(tree)
	tree.global_position = Vector3(2.0, 0, 0)
	await wait_seconds(0.05)

	tree.fell_tree()
	assert_true(tree.is_destroyed, "Tree must be destroyed")

	var harvest_ok = tree.harvest(_player)
	assert_true(harvest_ok, "Tree harvest must succeed")

	var popups = _get_floating_texts(_world)
	assert_eq(popups.size(), 1, "Exactly one popup must be spawned on tree harvest")
	if popups.is_empty():
		return

	var popup = popups[0]
	var label = popup.get_node("Label3D") as Label3D
	assert_not_null(label, "FloatingText must contain Label3D")
	assert_eq(label.text, "+4 WOOD", "Popup text must reflect harvested wood yield")
	assert_eq(label.modulate, Color.GREEN, "Popup color must be Color.GREEN for wood")

	var start_y: float = popup.global_position.y
	await wait_seconds(0.3)

	assert_true(is_instance_valid(popup), "Popup must still be active mid-animation")
	assert_gt(popup.global_position.y, start_y + 0.2, "Popup must rise upward during animation")

	var cleaned_up = await _wait_for_popup_cleanup(popup, 1.0)
	assert_true(cleaned_up, "Popup must be freed (queue_free) after animation finishes")

func test_stone_rock_harvest_notification_lifecycle() -> void:
	var stone = STONE_SCENE.instantiate() as ResourceRock
	_world.add_child(stone)
	stone.global_position = Vector3(2.0, 0, 0)
	await wait_seconds(0.05)

	stone.break_rock()
	assert_true(stone.is_destroyed, "Stone must be destroyed")

	var harvest_ok = stone.harvest(_player)
	assert_true(harvest_ok, "Stone harvest must succeed")

	var popups = _get_floating_texts(_world)
	assert_eq(popups.size(), 1, "Exactly one popup must be spawned on stone harvest")
	if popups.is_empty():
		return

	var popup = popups[0]
	var label = popup.get_node("Label3D") as Label3D
	assert_not_null(label, "FloatingText must contain Label3D")
	assert_eq(label.text, "+4 STONE", "Popup text must reflect harvested stone yield")
	assert_eq(label.modulate, Color(0.7, 0.75, 0.8), "Popup color must match stone harvest color")

	var start_y: float = popup.global_position.y
	await wait_seconds(0.3)
	assert_gt(popup.global_position.y, start_y + 0.2, "Stone popup must rise upward")

	var cleaned_up = await _wait_for_popup_cleanup(popup, 1.0)
	assert_true(cleaned_up, "Stone popup must be freed after animation finishes")

func test_iron_rock_harvest_notification_lifecycle() -> void:
	var iron = IRON_SCENE.instantiate() as ResourceRock
	_world.add_child(iron)
	iron.global_position = Vector3(2.0, 0, 0)
	await wait_seconds(0.05)

	iron.break_rock()
	assert_true(iron.is_destroyed, "Iron rock must be destroyed")

	var harvest_ok = iron.harvest(_player)
	assert_true(harvest_ok, "Iron harvest must succeed")

	var popups = _get_floating_texts(_world)
	assert_eq(popups.size(), 1, "Exactly one popup must be spawned on iron harvest")
	if popups.is_empty():
		return

	var popup = popups[0]
	var label = popup.get_node("Label3D") as Label3D
	assert_not_null(label, "FloatingText must contain Label3D")
	assert_eq(label.text, "+2 IRON", "Popup text must reflect iron yield")
	assert_eq(label.modulate, Color(1.0, 0.7, 0.3), "Popup color must match iron harvest color")

	var cleaned_up = await _wait_for_popup_cleanup(popup, 1.0)
	assert_true(cleaned_up, "Iron popup must be freed after animation finishes")

func test_resource_multiplier_affects_notification_and_wallet() -> void:
	_player.set("resource_multiplier", 3)

	var tree = TREE_SCENE.instantiate() as ResourceTree
	_world.add_child(tree)
	tree.global_position = Vector3(2.0, 0, 0)
	await wait_seconds(0.05)

	tree.fell_tree()
	var initial_wood = _player.building_system.wallet.get_wood()
	tree.harvest(_player)

	assert_eq(_player.building_system.wallet.get_wood(), initial_wood + 12, "Wallet must receive 3x yield")
	var popups = _get_floating_texts(_world)
	assert_eq(popups.size(), 1, "One popup spawned")
	if not popups.is_empty():
		var label = popups[0].get_node("Label3D") as Label3D
		assert_eq(label.text, "+12 WOOD", "Popup text must show multiplied yield")
		var cleaned_up = await _wait_for_popup_cleanup(popups[0], 1.0)
		assert_true(cleaned_up, "Multiplied popup must clean up")

func test_repeated_harvest_attempt_does_not_spawn_extra_popup_or_resources() -> void:
	var tree = TREE_SCENE.instantiate() as ResourceTree
	_world.add_child(tree)
	tree.global_position = Vector3(2.0, 0, 0)
	await wait_seconds(0.05)

	tree.fell_tree()
	var first_ok = tree.harvest(_player)
	assert_true(first_ok, "First harvest must succeed")

	var popups_first = _get_floating_texts(_world)
	assert_eq(popups_first.size(), 1, "First harvest creates one popup")

	var wood_after_first = _player.building_system.wallet.get_wood()
	var second_ok = tree.harvest(_player)
	assert_false(second_ok, "Second harvest must return false")
	assert_eq(_player.building_system.wallet.get_wood(), wood_after_first, "Wood wallet must not change on duplicate harvest")

	var popups_second = _get_floating_texts(_world)
	assert_eq(popups_second.size(), 1, "No extra popup must be spawned on duplicate harvest attempt")

	if not popups_first.is_empty():
		await _wait_for_popup_cleanup(popups_first[0], 1.0)

func test_multiple_concurrent_notifications_complete_independently() -> void:
	var tree1 = TREE_SCENE.instantiate() as ResourceTree
	var tree2 = TREE_SCENE.instantiate() as ResourceTree
	var stone1 = STONE_SCENE.instantiate() as ResourceRock
	var iron1 = IRON_SCENE.instantiate() as ResourceRock

	_world.add_child(tree1)
	_world.add_child(tree2)
	_world.add_child(stone1)
	_world.add_child(iron1)

	tree1.global_position = Vector3(1, 0, 0)
	tree2.global_position = Vector3(2, 0, 0)
	stone1.global_position = Vector3(3, 0, 0)
	iron1.global_position = Vector3(4, 0, 0)
	await wait_seconds(0.05)

	tree1.fell_tree()
	tree2.fell_tree()
	stone1.break_rock()
	iron1.break_rock()

	tree1.harvest(_player)
	tree2.harvest(_player)
	stone1.harvest(_player)
	iron1.harvest(_player)

	var popups = _get_floating_texts(_world)
	assert_eq(popups.size(), 4, "All 4 notifications must exist concurrently")

	await wait_seconds(1.1)
	var remaining = _get_floating_texts(_world)
	assert_eq(remaining.size(), 0, "All 4 concurrent notifications must be completely freed")

func test_free_resource_pickup_regression_lifecycle() -> void:
	var types: Array = [
		ResourceDistribution.ResourceType.WOOD,
		ResourceDistribution.ResourceType.STONE,
		ResourceDistribution.ResourceType.IRON,
		ResourceDistribution.ResourceType.MAGIC_STONE
	]
	var expected_names: Array[String] = ["WOOD", "STONE", "IRON", "MAGIC STONE"]

	for i in range(types.size()):
		var pickup = FREE_PICKUP_SCRIPT.new()
		pickup.resource_type = types[i]
		pickup.yield_amount = 2
		_world.add_child(pickup)
		pickup.global_position = Vector3(float(i * 2), 0, 0)
		await wait_seconds(0.02)

		var ok = pickup.harvest(_player)
		assert_true(ok, "Free resource pickup %s harvest must succeed" % expected_names[i])

		var popups = _get_floating_texts(_world)
		assert_gt(popups.size(), 0, "Popup must be spawned for %s" % expected_names[i])
		var popup = popups[popups.size() - 1]
		var label = popup.get_node("Label3D") as Label3D
		assert_eq(label.text, "+2 %s" % expected_names[i], "Text must match free resource name")

		var cleaned_up = await _wait_for_popup_cleanup(popup, 1.0)
		assert_true(cleaned_up, "Free resource %s popup must be freed" % expected_names[i])

func test_damage_numbers_regression_lifecycle() -> void:
	var tree = TREE_SCENE.instantiate() as ResourceTree
	var stone = STONE_SCENE.instantiate() as ResourceRock
	_world.add_child(tree)
	_world.add_child(stone)
	tree.global_position = Vector3(1, 0, 0)
	stone.global_position = Vector3(3, 0, 0)
	await wait_seconds(0.05)

	tree.take_damage(12.0)
	stone.take_damage(18.0)

	var popups = _get_floating_texts(_world)
	assert_eq(popups.size(), 2, "Two damage popups must be spawned")

	await wait_seconds(1.1)
	var remaining = _get_floating_texts(_world)
	assert_eq(remaining.size(), 0, "Both damage popups must be freed after animation")

func test_pause_and_resume_preserves_and_completes_notification() -> void:
	var tree = TREE_SCENE.instantiate() as ResourceTree
	_world.add_child(tree)
	tree.global_position = Vector3(2.0, 0, 0)
	await wait_seconds(0.05)

	tree.fell_tree()
	tree.harvest(_player)

	var popups = _get_floating_texts(_world)
	assert_eq(popups.size(), 1, "Popup must be spawned")
	if popups.is_empty():
		return

	var popup = popups[0]
	await wait_seconds(0.2)

	get_tree().paused = true
	await get_tree().create_timer(0.2, true, false, true).timeout
	assert_true(is_instance_valid(popup), "Popup must stay alive while paused")
	assert_false(popup.is_queued_for_deletion(), "Popup must not be queued for deletion while paused")

	get_tree().paused = false
	var cleaned_up = await _wait_for_popup_cleanup(popup, 1.0)
	assert_true(cleaned_up, "Popup must resume and be freed after unpause")

func test_scene_cleanup_during_animation() -> void:
	var temp_subworld = Node3D.new()
	_world.add_child(temp_subworld)

	var tree = TREE_SCENE.instantiate() as ResourceTree
	temp_subworld.add_child(tree)
	tree.global_position = Vector3(1, 0, 0)
	await wait_seconds(0.05)

	tree.fell_tree()
	tree.harvest(_player)

	var popups = _get_floating_texts(temp_subworld)
	assert_eq(popups.size(), 1, "Popup must be child of temp_subworld")

	await wait_seconds(0.2)
	temp_subworld.queue_free()
	await wait_seconds(0.5)

	assert_false(is_instance_valid(temp_subworld), "Subworld must be freed without residual popup errors")

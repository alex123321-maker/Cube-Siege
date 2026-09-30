extends GutTest

const PLAYER: PackedScene = preload("res://scenes/player.tscn")
const ENEMY: PackedScene = preload("res://scenes/enemy_dummy.tscn")

func test_repeated_sword_effects_release_every_registered_instance() -> void:
	var manager: Node = get_node("/root/VFXManager")
	await wait_seconds(0.6)
	var initial: int = manager.get_active_effect_count()
	for index in range(20):
		manager.spawn_warrior_slash(Vector3.ZERO, Vector3.FORWARD, 2.4, 90.0)
		manager.spawn_sword_contact(Vector3.FORWARD, Vector3.FORWARD)
	assert_eq(manager.get_active_effect_count(), initial + 40)
	await wait_seconds(0.7)
	assert_eq(manager.get_active_effect_count(), initial, "Repeated slash/contact pairs must settle without accumulating nodes")

func test_contact_requires_hit_and_uses_actual_target_position_without_changing_damage() -> void:
	var manager: Node = get_node("/root/VFXManager")
	await wait_seconds(0.6)
	var player: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	add_child_autoqfree(player)
	player.set_physics_process(false)
	player.global_position = Vector3(1000.0, 0.9, 1000.0)
	player.rotation = Vector3.ZERO
	player.set_class(0, false)
	var enemy: CharacterBody3D = ENEMY.instantiate() as CharacterBody3D
	add_child_autoqfree(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = player.global_position + Vector3(10.0, 0.0, 0.0)
	await wait_physics_frames(3)
	player.combat.trigger_slash(player, 25.0, 5.0, 90.0, false)
	await wait_seconds(0.06)
	assert_eq(_contacts(manager).size(), 0, "Swinging into empty space must not create a hit flash")
	assert_eq(enemy.current_health, 80.0)
	await wait_seconds(0.5)
	enemy.global_position = player.global_position + Vector3(0.65, 0.0, -1.6)
	await wait_physics_frames(3)
	player.combat.trigger_slash(player, 25.0, 5.0, 90.0, false)
	await wait_seconds(0.06)
	var contacts: Array[Node3D] = _contacts(manager)
	assert_eq(enemy.current_health, 55.0, "Presentation must not change the existing 25-point attack")
	assert_eq(contacts.size(), 1, "One struck target gets one contact effect")
	if contacts.size() == 1:
		assert_lt(contacts[0].global_position.distance_to(enemy.global_position + Vector3(0, 0.35, 0)), 0.001,
			"The contact must follow the off-center target, not a fixed point in front of the player")
	await wait_seconds(0.5)

func test_target_entering_active_swing_receives_one_contact() -> void:
	var manager: Node = get_node("/root/VFXManager")
	await wait_seconds(0.6)
	var player: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	add_child_autoqfree(player)
	player.set_physics_process(false)
	player.global_position = Vector3(1000.0, 0.9, 1000.0)
	player.rotation = Vector3.ZERO
	player.set_class(0, false)
	var enemy: CharacterBody3D = ENEMY.instantiate() as CharacterBody3D
	add_child_autoqfree(enemy)
	enemy.set_physics_process(false)
	enemy.global_position = player.global_position + Vector3(10.0, 0.0, 0.0)
	await wait_physics_frames(3)
	player.combat.trigger_slash(player, 25.0, 5.0, 90.0, false)
	await wait_seconds(0.045)
	enemy.global_position = player.global_position + Vector3(0.4, 0.0, -1.6)
	await wait_physics_frames(3)
	assert_eq(enemy.current_health, 55.0, "Late entry still uses the existing active hit window")
	assert_eq(_contacts(manager).size(), 1, "Every confirmed hit needs contact even after the first overlap query")
	await wait_seconds(0.5)

func _contacts(manager: Node) -> Array[Node3D]:
	var result: Array[Node3D] = []
	for child: Node in manager._container.get_children():
		if child is SwordVFX and child.name.begins_with("SteelSwordContact"):
			result.append(child as Node3D)
	return result

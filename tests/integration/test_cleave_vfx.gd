extends GutTest

const PLAYER: PackedScene = preload("res://scenes/player.tscn")
const ENEMY: PackedScene = preload("res://scenes/enemy_dummy.tscn")

func test_repeated_release_and_contacts_release_all_registered_effects() -> void:
	var manager: Node = get_node("/root/VFXManager")
	await wait_seconds(0.9)
	var initial: int = manager.get_active_effect_count()
	for index in range(16):
		manager.spawn_cleave_wave(Vector3.ZERO, Vector3.FORWARD)
		manager.spawn_cleave_contact(Vector3.FORWARD, Vector3.FORWARD)
	assert_eq(manager.get_active_effect_count(), initial + 32)
	await wait_seconds(1.0)
	assert_eq(manager.get_active_effect_count(), initial)

func test_real_special_hit_and_miss_keep_damage_and_contact_positions() -> void:
	var manager: Node = get_node("/root/VFXManager")
	await wait_seconds(0.9)
	var player: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	add_child_autoqfree(player)
	player.set_physics_process(false)
	player.global_position = Vector3(1000.0, 0.9, 1000.0)
	player.rotation = Vector3.ZERO
	var target: CharacterBody3D = ENEMY.instantiate() as CharacterBody3D
	add_child_autoqfree(target)
	target.set_physics_process(false)
	target.max_health = 1000.0
	target.current_health = 1000.0
	target.global_position = player.global_position + Vector3(0.7, 0.0, -1.7)
	await wait_physics_frames(3)
	player.perform_special_attack()
	assert_eq(player.combat.special_cooldown_timer, 4.0)
	await wait_seconds(0.22)
	assert_eq(target.current_health, 940.0, "Real special applies the original damage once")
	var contacts: Array[CleaveVFX] = _contacts(manager)
	assert_eq(contacts.size(), 1)
	if contacts.size() == 1:
		assert_lt(contacts[0].global_position.distance_to(target.global_position + Vector3.UP * 0.35), 0.001)
	await wait_seconds(0.9)
	target.global_position = player.global_position + Vector3(0.0, 0.0, 2.2)
	await wait_physics_frames(3)
	player.combat.special_cooldown_timer = 0.0
	player.perform_special_attack()
	await wait_seconds(0.22)
	assert_eq(target.current_health, 940.0, "A target behind the player must not be hit")
	assert_eq(_contacts(manager).size(), 0, "A miss has no target contact flash")
	await wait_seconds(0.9)

func test_windup_does_not_survive_owner_removal() -> void:
	var manager: Node = get_node("/root/VFXManager")
	var owner_node := Node3D.new()
	add_child(owner_node)
	var windup: Node3D = manager.spawn_cleave_charge(owner_node, 0.15)
	owner_node.queue_free()
	await wait_seconds(0.06)
	assert_false(is_instance_valid(windup))

func test_contact_budget_never_limits_gameplay_damage() -> void:
	var manager: Node = get_node("/root/VFXManager")
	await wait_seconds(0.9)
	var player: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	add_child_autoqfree(player)
	player.set_physics_process(false)
	player.global_position = Vector3(1000.0, 0.9, 1000.0)
	player.rotation = Vector3.ZERO
	var targets: Array[CharacterBody3D] = []
	for index in range(8):
		var target: CharacterBody3D = ENEMY.instantiate() as CharacterBody3D
		add_child_autoqfree(target)
		target.set_physics_process(false)
		target.max_health = 1000.0
		target.current_health = 1000.0
		target.global_position = player.global_position + Vector3(-1.05 + float(index % 4) * 0.7,
			0.0, -1.0 - float(index / 4) * 0.8)
		targets.append(target)
	await wait_physics_frames(3)
	player.perform_special_attack()
	await wait_seconds(0.22)
	for target: CharacterBody3D in targets:
		assert_eq(target.current_health, 940.0)
	assert_eq(_contacts(manager).size(), 6, "Only the decorative flashes are capped")
	await wait_seconds(0.9)

func test_class_change_during_windup_cancels_warrior_release() -> void:
	var manager: Node = get_node("/root/VFXManager")
	await wait_seconds(0.9)
	var player: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	add_child_autoqfree(player)
	player.set_physics_process(false)
	player.perform_special_attack()
	player.set_class(1, false)
	await wait_seconds(0.22)
	var releases: int = 0
	for effect: Node in manager._container.get_children():
		if effect is CleaveVFX and not effect._charge and not effect._contact:
			releases += 1
	assert_eq(releases, 0)

func test_camera_impulse_settles_without_changing_orientation_or_fov() -> void:
	var camera := CameraFollow.new()
	add_child_autoqfree(camera)
	var original_basis: Basis = camera.basis
	var original_fov: float = camera.fov
	camera.add_combat_impulse(Vector3.RIGHT, 0.075)
	camera._step_combat_impulse(0.01)
	assert_gt(absf(camera.h_offset), 0.0)
	assert_lt(absf(camera.h_offset), 0.09)
	camera._step_combat_impulse(0.25)
	assert_eq(camera.h_offset, 0.0)
	assert_eq(camera.v_offset, 0.0)
	assert_eq(camera.basis, original_basis)
	assert_eq(camera.fov, original_fov)

func _contacts(manager: Node) -> Array[CleaveVFX]:
	var result: Array[CleaveVFX] = []
	for child: Node in manager._container.get_children():
		if child is CleaveVFX and child._contact:
			result.append(child as CleaveVFX)
	return result

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
	await wait_seconds(0.35)
	assert_eq(target.current_health, 940.0, "Real special applies the original damage once")
	var contacts: Array[CleaveVFX] = _contacts(manager)
	assert_eq(contacts.size(), 1)
	if contacts.size() == 1:
		assert_lt(contacts[0].global_position.distance_to(target.global_position + Vector3.UP * 0.65), 0.001)
	await wait_seconds(0.9)
	target.global_position = player.global_position + Vector3(0.0, 0.0, 2.2)
	await wait_physics_frames(3)
	player.combat.special_cooldown_timer = 0.0
	player.perform_special_attack()
	await wait_seconds(0.35)
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

func test_windup_glint_tracks_weapon_tip_while_owner_moves() -> void:
	var manager: Node = get_node("/root/VFXManager")
	var owner_node := Node3D.new()
	add_child_autoqfree(owner_node)
	var weapon_tip := Node3D.new()
	owner_node.add_child(weapon_tip)
	weapon_tip.position = Vector3(0.3, 1.4, -0.8)
	var windup: CleaveVFX = manager.spawn_cleave_charge(owner_node, 0.25, weapon_tip) as CleaveVFX
	await wait_frames(2)
	owner_node.position += Vector3(2.0, 0.0, 1.0)
	weapon_tip.position += Vector3(-0.2, 0.4, 0.6)
	await wait_frames(2)
	assert_lt(windup._weapon_glint.global_position.distance_to(weapon_tip.global_position), 0.001)
	owner_node.queue_free()
	await wait_frames(2)
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
	await wait_seconds(0.35)
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
	await wait_seconds(0.35)
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

func test_cleave_has_wide_full_body_motion_and_basic_cannot_interrupt_windup() -> void:
	var player: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	add_child_autoqfree(player)
	player.set_physics_process(false)
	player.perform_special_attack()
	player.perform_attack()
	var animation_player: AnimationPlayer = player.presentation.anim_player
	assert_eq(animation_player.current_animation, "special")
	var torso: Node3D = player.get_node("Visuals/HeroWarrior/root/torso") as Node3D
	animation_player.seek(0.20, true)
	var windup_yaw: float = torso.rotation.y
	animation_player.seek(0.34, true)
	assert_gt(absf(torso.rotation.y - windup_yaw), deg_to_rad(120.0), "A deliberate full-body horizontal swing")
	assert_almost_eq(animation_player.get_animation("special").length, PlayerCombat.CLEAVE_SPEC.recovery, 0.001)
	var arm: Node3D = player.get_node("Visuals/HeroWarrior/root/torso/right_arm") as Node3D
	var sword: Node3D = arm.get_node("sword") as Node3D
	for time: float in [0.10, 0.20, 0.24, 0.28, 0.34, 0.40, 0.58]:
		animation_player.seek(time, true)
		assert_gt(torso.to_local(sword.global_position).z, 0.0,
			"Weapon hand stays in front of the torso in imported +Z-forward coordinates")
	for time: float in [0.28, 0.30, 0.34, 0.40]:
		animation_player.seek(time, true)
		assert_lt(player.to_local(player.presentation.blade_tip_anchor.global_position).z, 0.0,
			"Committed blade sweep occurs in front of the player, not behind the back")
	await wait_seconds(1.1)

func test_front_sector_edges_range_and_restored_basic_hitbox() -> void:
	var player: CharacterBody3D = PLAYER.instantiate() as CharacterBody3D
	add_child_autoqfree(player)
	player.set_physics_process(false)
	player.global_position = Vector3(1000.0, 0.9, 1000.0)
	var offsets: Array[Vector3] = [Vector3(3.0, 0.0, -0.8), Vector3(-3.0, 0.0, -0.8),
		Vector3(0.0, 0.0, -3.7), Vector3(0.0, 0.0, -4.05), Vector3(0.0, 0.0, 2.2)]
	var targets: Array[CharacterBody3D] = []
	for offset: Vector3 in offsets:
		var target: CharacterBody3D = ENEMY.instantiate() as CharacterBody3D
		add_child_autoqfree(target)
		target.set_physics_process(false)
		target.max_health = 1000.0
		target.current_health = 1000.0
		target.global_position = player.global_position + offset
		targets.append(target)
	await wait_physics_frames(3)
	player.perform_special_attack()
	await wait_seconds(0.36)
	for index in range(5):
		assert_eq(targets[index].current_health, 940.0 if index < 3 else 1000.0,
			"Only centers within the visible frontal sector take damage")
	await wait_seconds(0.8)
	player.combat.attack_cooldown_timer = 0.0
	player.perform_attack()
	await wait_seconds(0.15)
	assert_eq(targets[0].current_health, 940.0, "Basic attack must not inherit the expanded cleave hitbox")
	assert_eq(targets[2].current_health, 940.0)
	assert_eq(player.get_node("SlashHitbox").frontal_radius, 0.0)
	await wait_seconds(0.9)

func test_contact_follows_knockback_and_recoil_recovers() -> void:
	var target: CharacterBody3D = ENEMY.instantiate() as CharacterBody3D
	add_child_autoqfree(target)
	target.set_physics_process(false)
	var manager: Node = get_node("/root/VFXManager")
	var effect: CleaveVFX = manager.spawn_cleave_contact(target.global_position + Vector3.UP * 0.65,
		Vector3.FORWARD, target) as CleaveVFX
	var rest: Transform3D = target.presentation.model_root.transform
	target.presentation.play_cleave_recoil(Vector3.FORWARD)
	await wait_seconds(0.065)
	assert_false(target.presentation.model_root.transform.is_equal_approx(rest))
	target.global_position += Vector3(2.0, 0.0, -1.0)
	await wait_process_frames(2)
	assert_lt(effect.global_position.distance_to(target.global_position + Vector3.UP * 0.65), 0.001)
	await wait_seconds(0.6)
	assert_true(target.presentation.model_root.transform.is_equal_approx(rest))
	assert_false(is_instance_valid(effect))

func test_windup_samples_terrain_at_the_caster_before_first_frame() -> void:
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(12.0, 0.2, 12.0)
	collider.shape = shape
	floor_body.add_child(collider)
	add_child_autoqfree(floor_body)
	floor_body.global_position = Vector3(1000.0, -0.1, 1000.0)
	var owner_node := Node3D.new()
	add_child_autoqfree(owner_node)
	owner_node.global_position = Vector3(1000.0, 0.9, 1000.0)
	await wait_physics_frames(2)
	var manager: Node = get_node("/root/VFXManager")
	var charge: CleaveVFX = manager.spawn_cleave_charge(owner_node, 0.28) as CleaveVFX
	assert_lt(charge.global_position.distance_to(owner_node.global_position + Vector3.UP * 0.25), 0.001)
	var footprint: MeshInstance3D = charge.get_node_or_null("CleaveFootprint") as MeshInstance3D
	assert_not_null(footprint, "The windup must sample terrain under the caster, not at world origin")
	if footprint:
		assert_almost_eq(footprint.get_aabb().size.x, PlayerCombat.CLEAVE_SPEC.radius * 2.0, 0.001)
		assert_almost_eq(footprint.get_aabb().size.z, PlayerCombat.CLEAVE_SPEC.radius, 0.001)
	await wait_seconds(0.4)

func _contacts(manager: Node) -> Array[CleaveVFX]:
	var result: Array[CleaveVFX] = []
	for child: Node in manager._container.get_children():
		if child is CleaveVFX and child._contact:
			result.append(child as CleaveVFX)
	return result

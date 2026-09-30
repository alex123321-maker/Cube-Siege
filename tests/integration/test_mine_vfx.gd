extends GutTest

const MINE: PackedScene = preload("res://scenes/prefabs/remote_mine.tscn")
const ENEMY: PackedScene = preload("res://scenes/enemy_dummy.tscn")

func test_visual_replacement_preserves_immediate_damage_and_radius() -> void:
	var origin := Vector3(1000.0, 0.9, 1000.0)
	var inside: CharacterBody3D = _target(origin + Vector3(4.4, 0.0, 0.0))
	var boundary: CharacterBody3D = _target(origin + Vector3(0.0, 0.0, -4.5))
	var outside: CharacterBody3D = _target(origin + Vector3(-4.6, 0.0, 0.0))
	var mine: Node3D = MINE.instantiate() as Node3D
	add_child_autoqfree(mine)
	mine.global_position = origin
	mine.detonate()
	assert_eq(inside.current_health, 750.0, "Damage stays 250 in the detonation call")
	assert_eq(boundary.current_health, 750.0, "The existing inclusive 4.5 radius is preserved")
	assert_eq(outside.current_health, 1000.0, "Presentation must not expand damage reach")
	await wait_seconds(1.7)

func test_overlapping_bursts_release_all_registered_roots() -> void:
	var manager: Node = get_node("/root/VFXManager")
	await wait_seconds(1.7)
	var initial: int = manager.get_active_effect_count()
	for index in range(8):
		manager.spawn_mine_explosion(Vector3(float(index), 0.9, 0.0), 4.5)
	assert_eq(manager.get_active_effect_count(), initial + 8)
	await wait_seconds(1.8)
	assert_eq(manager.get_active_effect_count(), initial, "Overlapping explosions leave no registered roots")

func test_effect_cleanup_uses_delta_even_when_rendering_runs_slowly() -> void:
	var manager: Node = get_node("/root/VFXManager")
	var initial: int = manager.get_active_effect_count()
	manager.spawn_mine_explosion(Vector3.ZERO, 4.5)
	var effect: MineExplosionVFX = manager._container.get_child(manager._container.get_child_count() - 1) as MineExplosionVFX
	effect.set_process(false)
	await wait_seconds(0.1)
	assert_false(effect.is_queued_for_deletion(), "Wall-clock passage cannot shorten a paused effect")
	effect._process(0.5)
	assert_false(effect.is_queued_for_deletion(), "The tail survives the initial impulse")
	effect._process(2.0)
	await wait_process_frames(2)
	assert_eq(manager.get_active_effect_count(), initial, "Advancing simulation time fully releases the effect")

func test_volume_uses_supplied_radius_and_expires_on_simulation_time() -> void:
	var manager: Node = get_node("/root/VFXManager")
	for radius: float in [2.25, 4.5, 6.75]:
		var origin := Vector3(1000.0, 0.9, 1000.0)
		manager.spawn_mine_explosion(origin, radius)
		var effect: MineExplosionVFX = manager._container.get_child(manager._container.get_child_count() - 1) as MineExplosionVFX
		effect.set_process(false)
		var volume: MeshInstance3D = effect.get_node("BlastVolume") as MeshInstance3D
		var bounds: BoxMesh = volume.mesh as BoxMesh
		assert_eq(bounds.size.x, radius * 2.0, "3D footprint uses the actual blast diameter")
		assert_eq(bounds.size.z, radius * 2.0)
		assert_gt(bounds.size.y, 0.0, "The periphery has depth, not a camera-facing quad")
		var material: ShaderMaterial = volume.material_override
		assert_eq(material.get_shader_parameter("radius"), radius, "Shader clips density at the supplied radius")
		assert_eq(material.get_shader_parameter("burst_origin"), origin)
		assert_true(volume.visible, "Full reach is present on the detonation frame")
		effect._process(manager.mine_profile.wave_lifetime + 0.01)
		assert_false(volume.visible, "Ray marching ends with the impulse, before the smoke tail")
		assert_false(effect.is_queued_for_deletion())
		effect._process(3.0)
	await wait_process_frames(2)

func _target(at: Vector3) -> CharacterBody3D:
	var target: CharacterBody3D = ENEMY.instantiate() as CharacterBody3D
	add_child_autoqfree(target)
	target.set_physics_process(false)
	target.max_health = 1000.0
	target.current_health = 1000.0
	target.global_position = at
	return target

func test_ground_imprint_reuses_steps_and_releases_streamed_receivers() -> void:
	var origin := Vector3(1200.0, 0.9, 1200.0)
	var terrain := Node3D.new()
	add_child_autoqfree(terrain)
	terrain.add_to_group("terrain")
	terrain.global_position = origin - Vector3.UP * 0.9
	var surface := MeshInstance3D.new()
	var step := BoxMesh.new()
	step.size = Vector3(4.0, 1.0, 8.0)
	surface.mesh = step
	terrain.add_child(surface)
	surface.position = Vector3(-2.0, -0.5, 0.0)
	var upper := MeshInstance3D.new()
	upper.mesh = step
	terrain.add_child(upper)
	upper.position = Vector3(2.0, 0.5, 0.0)
	var manager: Node = get_node("/root/VFXManager")
	manager.spawn_mine_explosion(origin, 4.5)
	var effect: MineExplosionVFX = manager._container.get_child(manager._container.get_child_count() - 1) as MineExplosionVFX
	effect.set_process(false)
	var ground: Node3D = effect.get_node("GroundImprint") as Node3D
	assert_eq(ground.get_child_count(), 2, "Both step heights receive the imprint")
	var imprint: MeshInstance3D = ground.get_child(0) as MeshInstance3D
	assert_same(imprint.mesh, surface.mesh, "Reuse step tops and vertical faces")
	assert_eq(imprint.global_transform, surface.global_transform)
	assert_eq(ground.get_child(1).global_transform, upper.global_transform, "Preserve the one-unit height discontinuity")
	var material: ShaderMaterial = imprint.material_override
	assert_eq(material.get_shader_parameter("radius"), 4.5)
	effect._process(0.8)
	assert_true(ground.visible, "The ground remembers the radius after the fire has gone")
	assert_false(effect.get_node("BlastVolume").visible)
	surface.queue_free()
	await wait_process_frames(2)
	assert_eq(ground.get_child_count(), 1, "Streaming out one step preserves the other")
	upper.queue_free()
	await wait_process_frames(2)
	assert_eq(ground.get_child_count(), 0, "Streaming a receiver out removes its imprint")
	effect._process(2.0)
	await wait_process_frames(2)

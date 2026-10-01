extends GutTest

const CONTACT: PackedScene = preload("res://scenes/vfx/library/warm_contact.tscn")
const DUST: PackedScene = preload("res://scenes/vfx/library/soft_dust.tscn")

func test_two_stamps_share_profile_but_not_animated_material() -> void:
	var first: VFXStamp3D = CONTACT.instantiate() as VFXStamp3D
	var second: VFXStamp3D = CONTACT.instantiate() as VFXStamp3D
	add_child_autoqfree(first)
	add_child_autoqfree(second)
	first.set_process(false)
	second.set_process(false)
	assert_same(first.profile, second.profile)
	assert_ne(first._material, second._material)
	assert_true(first._material.billboard_keep_scale, "Billboard must retain the actual size/expansion, not discard node scale")
	first._step(0.05)
	assert_gt(first._material.albedo_color.a, 0.0)
	assert_eq(second._material.albedo_color.a, 0.0)
	assert_almost_eq(first.profile.tint.a, 0.85, 0.0001)

func test_bound_stamp_follows_target_and_removal_cleans_up() -> void:
	var target := Node3D.new()
	add_child_autoqfree(target)
	var effect: VFXStamp3D = DUST.instantiate() as VFXStamp3D
	add_child_autoqfree(effect)
	effect.set_process(false)
	effect.global_position = Vector3(1.0, 0.6, -0.3)
	effect.bind_target(target)
	target.global_position += Vector3(2.0, 0.0, 1.0)
	effect._step(0.04)
	assert_lt(effect.global_position.distance_to(target.global_position + Vector3(1.0, 0.6, -0.3)), 0.001)
	target.queue_free()
	await wait_process_frames(2)
	effect._step(0.01)
	assert_true(effect.is_queued_for_deletion())

func test_one_delta_clock_expires_without_wall_clock_timer() -> void:
	var effect: VFXStamp3D = DUST.instantiate() as VFXStamp3D
	add_child_autoqfree(effect)
	effect.set_process(false)
	effect._step(effect.profile.lifetime - 0.01)
	assert_false(effect.is_queued_for_deletion())
	effect._step(0.011)
	assert_true(effect.is_queued_for_deletion())

extends GutTest

func test_rapid_hits_preserve_material_and_restore_original_overlay() -> void:
	var actor := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "Body"
	mesh.mesh = BoxMesh.new()
	var original_override := StandardMaterial3D.new()
	var original_overlay := StandardMaterial3D.new()
	mesh.material_override = original_override
	mesh.material_overlay = original_overlay
	actor.add_child(mesh)
	var hurtbox := HurtboxArea.new()
	hurtbox.mesh_to_flash_path = NodePath("../Body")
	actor.add_child(hurtbox)
	add_child_autoqfree(actor)
	hurtbox.flash_hit()
	assert_eq(mesh.material_override, original_override, "A hit must preserve the actor's base material")
	assert_eq(mesh.material_overlay, hurtbox.flash_material)
	await wait_seconds(0.07)
	hurtbox.flash_hit()
	await wait_seconds(0.07)
	assert_eq(mesh.material_overlay, hurtbox.flash_material, "The first pulse must not clear the second hit")
	await wait_seconds(0.10)
	assert_eq(mesh.material_overlay, original_overlay, "Restore the pre-hit overlay after the latest pulse")
	assert_eq(mesh.material_override, original_override)

func test_removing_hurtbox_restores_surviving_mesh() -> void:
	var actor := Node3D.new()
	var mesh := MeshInstance3D.new()
	mesh.name = "Body"
	mesh.mesh = BoxMesh.new()
	actor.add_child(mesh)
	var hurtbox := HurtboxArea.new()
	hurtbox.mesh_to_flash_path = NodePath("../Body")
	actor.add_child(hurtbox)
	add_child_autoqfree(actor)
	hurtbox.flash_hit()
	hurtbox.queue_free()
	await wait_process_frames(2)
	assert_null(mesh.material_overlay, "Removing the presentation owner must not leave the mesh highlighted")

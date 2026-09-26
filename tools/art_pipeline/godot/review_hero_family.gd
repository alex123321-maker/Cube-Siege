extends "res://tools/art_pipeline/godot/review_heroes.gd"
## Same camera, floor and lighting for the three runtime hero scenes.

func _run() -> void:
	hero = "warrior"
	output = _arg("--output", "res://art/work/hero-polish/family")
	DirAccess.make_dir_recursive_absolute(output)
	_setup_studio()
	model.free()
	var heroes: Array[Node3D] = []
	var bounds: Dictionary = {}
	for i: int in 3:
		var name: String = ["warrior", "archer", "engineer"][i]
		var actor: Node3D = load("res://assets/models/characters/hero_%s.tscn" % name).instantiate()
		world.add_child(actor)
		actor.position.x = (i - 1) * 1.7
		var ap: AnimationPlayer = actor.get_node("AnimationPlayer")
		ap.play("idle")
		ap.seek(.1, true)
		ap.advance(0)
		ap.pause()
		heroes.append(actor)
		var minimum_y: float = INF
		for part: MeshInstance3D in actor.find_children("*", "MeshInstance3D", true, false):
			for corner: int in 8:
				minimum_y = minf(minimum_y, part.to_global(part.get_aabb().get_endpoint(corner)).y)
		bounds[name] = {"minimum_world_y": minimum_y}
	FileAccess.open(output.path_join("bounds.json"), FileAccess.WRITE).store_string(JSON.stringify(bounds, "  "))
	camera.size = 6.0
	camera.position = Vector3(0, 2.8, -9)
	camera.look_at(Vector3(0, 1, 0))
	await _capture("family.png")
	camera.position = Vector3(4, 7, -9)
	camera.look_at(Vector3(0, .8, 0))
	await _capture("family_isometric.png")
	var silhouette := StandardMaterial3D.new()
	silhouette.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	silhouette.albedo_color = Color(.025, .025, .03)
	for actor: Node3D in heroes:
		for mesh: MeshInstance3D in actor.find_children("*", "MeshInstance3D", true, false):
			mesh.material_override = silhouette
	camera.position = Vector3(0, 2.8, -9)
	camera.look_at(Vector3(0, 1, 0))
	await _capture("family_silhouettes.png")
	quit()

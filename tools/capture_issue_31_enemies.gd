extends SceneTree

const ZOMBIE_SCENE: PackedScene = preload("res://scenes/enemy_dummy.tscn")
const SKIRMISHER_SCENE: PackedScene = preload("res://scenes/enemies/ranged_skirmisher.tscn")
const SIEGE_SCENE: PackedScene = preload("res://scenes/enemies/siege_breaker.tscn")
const OUTPUT_DIR: String = "res://docs/screenshots/issue_31"

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Enemy screenshots require a rendering display.")
		quit(1)
		return

	var output: String = OUTPUT_DIR
	DirAccess.make_dir_recursive_absolute(output)

	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	var map: MapGenerator = main.get_node("MapGenerator")
	map.random_seed = false
	map.custom_seed = 1337
	root.add_child(main)
	current_scene = main

	main.process_mode = Node.PROCESS_MODE_DISABLED
	var player: Node3D = main.get_node("Player")
	player.visible = true
	var enemies_node: Node = main.get_node_or_null("Enemies")
	if enemies_node:
		enemies_node.process_mode = Node.PROCESS_MODE_DISABLED
		for c in enemies_node.get_children():
			c.queue_free()

	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	camera.fov = 42.0
	camera.far = 300.0
	camera.make_current()

	var p_pos: Vector3 = player.global_position

	var showcase: Node3D = Node3D.new()
	showcase.name = "EnemyCaptureShowcase"
	main.add_child(showcase)

	# 1. Zombie gameplay camera capture
	var zombie: CharacterBody3D = ZOMBIE_SCENE.instantiate() as CharacterBody3D
	showcase.add_child(zombie)
	zombie.global_position = p_pos + Vector3(0, 0, 3.5)
	zombie.look_at(p_pos, Vector3.UP)
	camera.position = p_pos + Vector3(0, 7.5, 11)
	camera.look_at(p_pos + Vector3(0, 0.5, 2.0), Vector3.UP)
	await _snap_shot(output.path_join("zombie_gameplay_camera.png"))
	zombie.queue_free()

	# 2. Skirmisher gameplay camera capture
	var skirmisher: CharacterBody3D = SKIRMISHER_SCENE.instantiate() as CharacterBody3D
	showcase.add_child(skirmisher)
	skirmisher.global_position = p_pos + Vector3(0, 0, 3.5)
	skirmisher.look_at(p_pos, Vector3.UP)
	await _snap_shot(output.path_join("skirmisher_gameplay_camera.png"))
	skirmisher.queue_free()

	# 3. Siege breaker gameplay camera capture
	var siege: CharacterBody3D = SIEGE_SCENE.instantiate() as CharacterBody3D
	showcase.add_child(siege)
	siege.global_position = p_pos + Vector3(0, 0, 4.0)
	siege.look_at(p_pos, Vector3.UP)
	await _snap_shot(output.path_join("siege_breaker_gameplay_camera.png"))
	siege.queue_free()

	# 4. Hit Flash Showcase
	var z: CharacterBody3D = ZOMBIE_SCENE.instantiate() as CharacterBody3D
	var s: CharacterBody3D = SKIRMISHER_SCENE.instantiate() as CharacterBody3D
	var b: CharacterBody3D = SIEGE_SCENE.instantiate() as CharacterBody3D
	showcase.add_child(z)
	showcase.add_child(s)
	showcase.add_child(b)
	z.global_position = p_pos + Vector3(-2.5, 0, 3.5)
	s.global_position = p_pos + Vector3(0, 0, 3.5)
	b.global_position = p_pos + Vector3(3.0, 0, 4.0)
	z.look_at(p_pos, Vector3.UP)
	s.look_at(p_pos, Vector3.UP)
	b.look_at(p_pos, Vector3.UP)

	var zh: HurtboxArea = z.get_node("Hurtbox")
	var sh: HurtboxArea = s.get_node("Hurtbox")
	var bh: HurtboxArea = b.get_node("Hurtbox")
	if zh and zh.mesh_to_flash: zh.mesh_to_flash.material_override = zh.flash_material
	if sh and sh.mesh_to_flash: sh.mesh_to_flash.material_override = sh.flash_material
	if bh and bh.mesh_to_flash: bh.mesh_to_flash.material_override = bh.flash_material
	await _snap_shot(output.path_join("enemy_hit_flash_showcase.png"))
	z.queue_free()
	s.queue_free()
	b.queue_free()

	# 5. Mixed Combat Scene with wave
	var spawn_configs: Array[Dictionary] = [
		{"type": ZOMBIE_SCENE, "offset": Vector3(-2.5, 0.0, 2.5)},
		{"type": ZOMBIE_SCENE, "offset": Vector3(-4.0, 0.0, 4.0)},
		{"type": ZOMBIE_SCENE, "offset": Vector3(1.5, 0.0, 2.8)},
		{"type": SKIRMISHER_SCENE, "offset": Vector3(-5.0, 0.0, 5.5)},
		{"type": SKIRMISHER_SCENE, "offset": Vector3(4.5, 0.0, 5.0)},
		{"type": SIEGE_SCENE, "offset": Vector3(-2.0, 0.0, 6.0)},
		{"type": SIEGE_SCENE, "offset": Vector3(2.5, 0.0, 5.5)},
	]
	for cfg in spawn_configs:
		var enemy: CharacterBody3D = cfg["type"].instantiate() as CharacterBody3D
		showcase.add_child(enemy)
		enemy.global_position = p_pos + cfg["offset"]
		enemy.look_at(p_pos, Vector3.UP)

	camera.position = p_pos + Vector3(0, 11, 16)
	camera.look_at(p_pos + Vector3(0, 0, 3.5), Vector3.UP)
	await _snap_shot(output.path_join("mixed_combat_scene.png"))

	print("[SUCCESS] All Issue #31 enemy screenshots captured!")
	quit(0)

func _snap_shot(filepath: String) -> void:
	for i in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	var img: Image = root.get_texture().get_image()
	if img and not img.is_empty():
		img.save_png(filepath)
		print("Saved capture: ", filepath)

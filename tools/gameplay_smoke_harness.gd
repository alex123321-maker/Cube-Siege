extends SceneTree

## Dedicated Gameplay Smoke Harness for Cube Siege (Issue #44 / F27).
## Validates real main.tscn initialization, player lifecycle for all 3 classes
## (Warrior, Archer, Engineer), real projectile/combat hits against targets,
## and procedural chunk streaming transitions under isolated test storage.

const MAIN_SCENE_PATH = "res://scenes/main.tscn"
const ENEMY_DUMMY_SCENE_PATH = "res://scenes/enemy_dummy.tscn"
const ARROW_SCENE_PATH = "res://scenes/prefabs/arrow_projectile.tscn"

var total_checks: int = 0
var passed_checks: int = 0
var failed_checks: int = 0

func _init() -> void:
	print("\n" + "=".repeat(70))
	print(" [GAMEPLAY SMOKE HARNESS] Validating 3 Classes, Combat & Streaming")
	print("=".repeat(70))
	call_deferred("_run_harness")

func _assert_check(cond: bool, check_name: String, detail: String = "") -> void:
	total_checks += 1
	if cond:
		passed_checks += 1
		print("  [PASS] | %-42s | %s" % [check_name, detail])
	else:
		failed_checks += 1
		printerr("  [FAIL] | %-42s | %s" % [check_name, detail])

func _run_harness() -> void:
	# Enforce test profile isolation
	var save_mgr = root.get_node_or_null("SaveManager")
	if save_mgr and save_mgr.has_method("set_storage_dir"):
		save_mgr.set_storage_dir("user://test_profile/")

	var classes_to_test = [
		{"id": 0, "name": "Warrior"},
		{"id": 1, "name": "Archer"},
		{"id": 2, "name": "Engineer"}
	]

	for cls in classes_to_test:
		print("\n--- Testing Gameplay Slice: %s (Class ID: %d) ---" % [cls["name"], cls["id"]])
		await _test_class_slice(cls["id"], cls["name"])

	print("\n" + "=".repeat(70))
	print(" [GAMEPLAY SMOKE HARNESS] Summary: %d/%d Passed, %d Failed" % [passed_checks, total_checks, failed_checks])
	print("=".repeat(70) + "\n")

	quit(0 if failed_checks == 0 else 1)

func _test_class_slice(class_id: int, cls_label: String) -> void:
	var main_scene = load(MAIN_SCENE_PATH)
	if not main_scene:
		_assert_check(false, "%s Scene Load" % cls_label, "Failed to load %s" % MAIN_SCENE_PATH)
		return

	var main_instance = main_scene.instantiate()
	root.add_child(main_instance)
	await process_frame
	# The production run now starts with a mandatory talent reward. Resolve it
	# through the real modal before exercising the legacy three-class kit.
	var hud: Node = main_instance.get_node("HUD")
	var run_player: PlayerPrototype = main_instance.get_node("Player") as PlayerPrototype
	if run_player.progression.run_build.active_reward_id >= 0:
		hud.build_panel._focus(run_player.progression.run_build.active_reward_id)

	# Settle physics and world generation
	for _i in range(12):
		await process_frame
		await physics_frame

	var player = main_instance.get_node_or_null("Player")
	_assert_check(player != null, "%s Player Present" % cls_label, "Player node found in main scene")
	if not player:
		main_instance.queue_free()
		return

	# Configure active class
	player.set_class(class_id, false)
	_assert_check(player.current_class == class_id, "%s Class Configured" % cls_label, "Player active class is %s" % cls_label)
	_assert_check(player.current_health > 0.0, "%s Health Valid" % cls_label, "Player current HP: %.1f / %.1f" % [player.current_health, player.max_health])

	# Spawn enemy dummy target
	var enemy_scene = load(ENEMY_DUMMY_SCENE_PATH)
	var target = enemy_scene.instantiate()
	main_instance.add_child(target)
	target.global_position = player.global_position + Vector3(0, 0, -1.5)

	for _i in range(4):
		await process_frame
		await physics_frame

	var initial_hp = target.current_health
	_assert_check(initial_hp > 0.0, "%s Target Spawned" % cls_label, "Target initial HP: %.1f" % initial_hp)

	# Perform class-specific combat delivery
	match class_id:
		0: # Warrior: melee slash
			player.combat.perform_attack(player, 0, false, false)
			# Wait for attack delay and slash execution
			for _i in range(12):
				await process_frame
				await physics_frame
			var final_hp = target.current_health
			_assert_check(final_hp < initial_hp, "Warrior Melee Hit", "Target HP reduced from %.1f to %.1f" % [initial_hp, final_hp])

		1: # Archer: real projectile launch and impact
			var arrow_scene = load(ARROW_SCENE_PATH)
			var arrow = arrow_scene.instantiate()
			main_instance.add_child(arrow)
			arrow.global_position = player.global_position + Vector3(0, 1.2, 0)
			var dir = (target.global_position + Vector3(0, 1.0, 0) - arrow.global_position).normalized()
			arrow.setup(dir, 25.0, player, 1)

			# Advance physics until projectile impacts target
			for _i in range(15):
				await process_frame
				await physics_frame

			var final_hp = target.current_health
			_assert_check(final_hp < initial_hp, "Archer Projectile Hit", "Arrow reduced target HP from %.1f to %.1f" % [initial_hp, final_hp])

		2: # Engineer: hammer smash
			player.combat.perform_attack(player, 2, false, false)
			for _i in range(15):
				await process_frame
				await physics_frame
			var final_hp = target.current_health
			_assert_check(final_hp < initial_hp, "Engineer Hammer Hit", "Target HP reduced from %.1f to %.1f" % [initial_hp, final_hp])

	# Test procedural chunk streaming transition (fail-closed check on MapGenerator)
	var map_gen: MapGenerator = main_instance.get_node_or_null("MapGenerator") as MapGenerator
	if not map_gen:
		_assert_check(false, "%s MapGenerator Present" % cls_label, "MapGenerator node missing in main scene")
		if is_instance_valid(target):
			target.queue_free()
		main_instance.queue_free()
		return

	var initial_chunk: Vector2i = map_gen.last_player_chunk
	var initial_active_count: int = map_gen.active_chunks.size()
	_assert_check(initial_active_count > 0, "%s Initial Active Chunks" % cls_label, "Active chunks populated: %d" % initial_active_count)

	# Calculate expected transition: move player 2 chunks East (+32 meters)
	var chunk_step_blocks: float = float(ChunkBuilder.CHUNK_SIZE)
	var target_chunk_x: int = initial_chunk.x + 2
	var expected_new_chunk: Vector2i = Vector2i(target_chunk_x, initial_chunk.y)
	var new_border_coord: Vector2i = Vector2i(target_chunk_x + map_gen.load_radius_chunks, initial_chunk.y)

	var border_initially_present: bool = map_gen.active_chunks.has(new_border_coord)
	_assert_check(not border_initially_present, "%s Border Chunk Invariant" % cls_label, "Chunk %s correctly outside initial load radius" % str(new_border_coord))

	# Move player across the chunk boundary
	player.global_position.x = float(target_chunk_x) * chunk_step_blocks + 4.0

	# Process frames to let MapGenerator detect position change and process chunk streaming
	for _i in range(30):
		await process_frame
		await physics_frame

	var final_player_chunk: Vector2i = map_gen.last_player_chunk
	var chunk_updated: bool = (final_player_chunk == expected_new_chunk)
	var border_loaded: bool = map_gen.active_chunks.has(new_border_coord)

	_assert_check(
		chunk_updated and border_loaded,
		"%s Streaming Transition" % cls_label,
		"Player chunk changed %s -> %s; new border chunk %s successfully loaded into active_chunks" % [
			str(initial_chunk), str(final_player_chunk), str(new_border_coord)
		]
	)

	# Clean up target and main scene
	if is_instance_valid(target):
		target.queue_free()
	main_instance.queue_free()

	for _i in range(3):
		await process_frame
		await physics_frame

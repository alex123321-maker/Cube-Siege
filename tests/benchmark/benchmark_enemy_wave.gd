extends SceneTree

## Performance benchmark for representative enemy wave simulation (Issue #31).
## Measures frametime and physics processing overhead with 50 active enemies
## (30 Zombies, 15 Ranged Skirmishers, 5 Siege Breakers) on forward+ renderer.

const ZOMBIE_SCENE = preload("res://scenes/enemy_dummy.tscn")
const SKIRMISHER_SCENE = preload("res://scenes/enemies/ranged_skirmisher.tscn")
const SIEGE_SCENE = preload("res://scenes/enemies/siege_breaker.tscn")

func _init() -> void:
	call_deferred("_run_benchmark")

func _run_benchmark() -> void:
	print("\n--- Running Representative Enemy Wave Benchmark (Issue #31) ---")
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world

	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(100.0, 1.0, 100.0)
	col.shape = box
	col.position.y = -0.5
	floor_body.add_child(col)
	world.add_child(floor_body)

	# Mock player target
	var player_body := CharacterBody3D.new()
	player_body.name = "Player"
	player_body.add_to_group("player")
	player_body.position = Vector3(0.0, 0.9, 0.0)
	world.add_child(player_body)

	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	# Active camera to render graphical pipeline
	var camera := Camera3D.new()
	camera.current = true
	camera.position = Vector3(0.0, 16.0, 20.0)
	world.add_child(camera)
	camera.look_at(Vector3.ZERO, Vector3.UP)

	# Spawn representative wave of 50 enemies
	var total_enemies: int = 50
	var enemies: Array[CharacterBody3D] = []
	for i in range(total_enemies):
		var enemy: CharacterBody3D
		if i < 30:
			enemy = ZOMBIE_SCENE.instantiate() as CharacterBody3D
		elif i < 45:
			enemy = SKIRMISHER_SCENE.instantiate() as CharacterBody3D
		else:
			enemy = SIEGE_SCENE.instantiate() as CharacterBody3D
		
		var angle: float = (float(i) / float(total_enemies)) * TAU
		var radius: float = randf_range(8.0, 24.0)
		enemy.position = Vector3(cos(angle) * radius, 0.9 if i < 45 else 1.2, sin(angle) * radius)
		world.add_child(enemy)
		enemies.append(enemy)

	# Warm up simulation
	for i in range(20):
		await process_frame

	# Profile 100 simulation frames
	var frame_times: Array[float] = []
	var start_ms: int = Time.get_ticks_msec()
	for i in range(100):
		var f_start: int = Time.get_ticks_usec()
		await process_frame
		var f_elapsed: float = float(Time.get_ticks_usec() - f_start) / 1000.0
		frame_times.append(f_elapsed)

	var total_elapsed_ms: int = Time.get_ticks_msec() - start_ms
	var sum_ft: float = 0.0
	var max_ft: float = 0.0
	for ft in frame_times:
		sum_ft += ft
		if ft > max_ft:
			max_ft = ft
	var avg_ft: float = sum_ft / float(frame_times.size())
	var fps_est: float = 1000.0 / max(0.001, avg_ft)

	print("Wave Composition: 30 Zombies, 15 Ranged Skirmishers, 5 Siege Breakers (50 enemies total)")
	print("Simulation Duration: 100 frames (%d ms elapsed)" % total_elapsed_ms)
	print("Average Frametime: %.2f ms (~%.1f FPS)" % [avg_ft, fps_est])
	print("Peak Frametime:    %.2f ms" % max_ft)
	var target_max_avg_ft: float = 16.66 # 60 FPS
	if avg_ft <= target_max_avg_ft:
		print("Performance Gate:  PASS (Average Frametime %.2f ms <= 16.66 ms for 60 FPS target)" % avg_ft)
		print("----------------------------------------------------------------\n")
		quit(0)
	else:
		printerr("Performance Gate:  FAIL (Average Frametime %.2f ms > 16.66 ms threshold)" % avg_ft)
		print("----------------------------------------------------------------\n")
		quit(1)

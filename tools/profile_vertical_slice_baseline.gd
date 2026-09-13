extends SceneTree

## Dedicated profiling tool collecting runtime baseline metrics for Issue #22:
## 1. Frame time breakdown (Process / Physics / Render)
## 2. _spawn_chunk_resources execution time per chunk
## 3. Physics Server 3D active objects and collision pairs on 49 active chunks
## 4. Mob scaling impact on frame time (0, 10, 20, 50, 100 mobs)

func _init() -> void:
	call_deferred("_run_profiling")

func _run_profiling() -> void:
	print("\n" + "=".repeat(70))
	print(" CUBE SIEGE - VERTICAL SLICE PROFILER BASELINE (ISSUE #22)")
	print("=".repeat(70))

	# 1. Profile Map & Chunk Streaming
	var map_gen_scene: PackedScene = load("res://scenes/map_generator.tscn")
	if not map_gen_scene:
		push_error("Failed to load map_generator.tscn")
		quit(1)
		return

	var map_gen: MapGenerator = map_gen_scene.instantiate() as MapGenerator
	map_gen.random_seed = false
	map_gen.custom_seed = 1337
	root.add_child(map_gen)

	# Simulate 30 frames for initial loading and physics settlement
	for f in range(30):
		await process_frame

	var active_chunk_count: int = map_gen.active_chunks.size()
	var active_res_count: int = 0
	for c_res in map_gen.chunk_resources.values():
		active_res_count += (c_res as Array).size()

	# Benchmark single chunk resource spawn time
	var spawn_times_usec: Array[int] = []
	for i in range(10):
		var test_coord: Vector2i = Vector2i(100 + i, 100 + i)
		var test_nodes: Array[Node] = []
		var t0: int = Time.get_ticks_usec()
		map_gen._spawn_chunk_resources(test_coord.x, test_coord.y, test_nodes)
		var elapsed_us: int = Time.get_ticks_usec() - t0
		spawn_times_usec.append(elapsed_us)
		# Clean up test resources
		for res in test_nodes:
			if is_instance_valid(res):
				res.queue_free()

	var avg_spawn_us: float = 0.0
	for t in spawn_times_usec:
		avg_spawn_us += float(t)
	avg_spawn_us /= float(spawn_times_usec.size())

	# 2. Physics Server 3D metrics on 49 chunks
	var phys_objects: int = int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))
	var phys_collision_pairs: int = int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS))
	var draw_calls: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var primitives: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))

	print("\n--- 1. CHUNK STREAMING & PHYSICS SERVER BASELINE (49 CHUNKS) ---")
	print("  Active Chunks:          %d" % active_chunk_count)
	print("  Active Resource Nodes:  %d" % active_res_count)
	print("  Avg _spawn_chunk_resources time: %.2f µs (%.3f ms)" % [avg_spawn_us, avg_spawn_us / 1000.0])
	print("  Physics 3D Active Objects:       %d" % phys_objects)
	print("  Physics 3D Collision Pairs:      %d" % phys_collision_pairs)
	print("  Draw Calls in Frame:             %d" % draw_calls)
	print("  Primitives in Frame:             %d" % primitives)

	# 3. Mob Scaling Benchmark (0, 10, 20, 50, 100 mobs)
	print("\n--- 2. MOB SCALING RUNTIME BASELINE ---")
	print("  | Mobs | Process Time (ms) | Physics Time (ms) | Total Frame Time (ms) | Est. FPS |")
	print("  |------|-------------------|-------------------|-----------------------|----------|")

	var mob_scene: PackedScene = load("res://scenes/enemy_dummy.tscn")
	var spawned_mobs: Array[Node] = []

	var mob_counts: Array[int] = [0, 10, 20, 50, 100]
	for target_count in mob_counts:
		# Adjust mob count
		while spawned_mobs.size() < target_count:
			if mob_scene:
				var m = mob_scene.instantiate()
				var angle = randf() * TAU
				var dist = randf_range(5.0, 25.0)
				(m as Node3D).position = Vector3(cos(angle) * dist, 1.0, sin(angle) * dist)
				root.add_child(m)
				spawned_mobs.append(m)

		# Warm up 10 frames
		for w in range(10):
			await process_frame

		# Sample 30 frames using wall-clock delta
		var sample_total_us: int = 0
		var samples: int = 30
		for s in range(samples):
			var t_before: int = Time.get_ticks_usec()
			await process_frame
			sample_total_us += (Time.get_ticks_usec() - t_before)

		var avg_frame_ms: float = (float(sample_total_us) / float(samples)) / 1000.0
		var p_time: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		var ph_time: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		var est_fps: float = 1000.0 / maxf(avg_frame_ms, 0.001)
		print("  | %4d | %17.3f | %17.3f | %21.3f | %8.1f |" % [target_count, p_time, ph_time, avg_frame_ms, est_fps])

	# Cleanup mobs and map
	for m in spawned_mobs:
		if is_instance_valid(m):
			m.queue_free()
	map_gen.queue_free()

	print("\n" + "=".repeat(70))
	print(" BASELINE PROFILING COMPLETE")
	print("=".repeat(70) + "\n")
	quit(0)

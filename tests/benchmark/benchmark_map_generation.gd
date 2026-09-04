extends SceneTree

func _init() -> void:
	call_deferred("_run_benchmark")

func _run_benchmark() -> void:
	print("\n--- Running MapGenerator Performance Benchmark ---")
	var map_gen_scene: PackedScene = load("res://scenes/map_generator.tscn")
	if not map_gen_scene:
		print("ERROR: Failed to load map_generator.tscn")
		quit(1)
		return

	var iterations: int = 5
	var total_time_ms: float = 0.0
	var total_nodes: int = 0
	var terrain_nodes: int = 0
	var resource_nodes: int = 0

	for i in range(iterations):
		var generator = map_gen_scene.instantiate()
		generator.random_seed = false
		generator.custom_seed = 1337 + i
		
		var start_time: int = Time.get_ticks_msec()
		root.add_child(generator)
		# Wait for ready
		var elapsed: int = Time.get_ticks_msec() - start_time
		total_time_ms += float(elapsed)

		var t_count: int = generator.get_node("Terrain").get_child_count()
		var r_count: int = generator.get_node("Resources").get_child_count()
		terrain_nodes = t_count
		resource_nodes = r_count
		total_nodes = t_count + r_count

		print("  Run %d: %d ms | Terrain: %d | Resources: %d | Total: %d nodes" % [i + 1, elapsed, t_count, r_count, total_nodes])
		generator.queue_free()

	var avg_time: float = total_time_ms / float(iterations)
	print("\nBenchmark Result: Average Time = %.2f ms | Terrain Cubes = %d | Resources = %d" % [avg_time, terrain_nodes, resource_nodes])
	print("--------------------------------------------------\n")
	quit(0)

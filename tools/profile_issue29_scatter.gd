extends SceneTree
## Profile issue #29's production-density scatter on the 7x7 starting chunk window.

const SAMPLE_FRAMES: int = 120

func _initialize() -> void:
	call_deferred("_profile")

func _profile() -> void:
	var is_headless: bool = DisplayServer.get_name() == "headless"
	var viewport: Viewport = root.get_viewport()
	if not is_headless:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	var main: Node3D = load("res://scenes/main.tscn").instantiate() as Node3D
	var map: MapGenerator = main.get_node("MapGenerator") as MapGenerator
	map.random_seed = false
	map.custom_seed = 1337
	var generation_start: int = Time.get_ticks_usec()
	root.add_child(main)
	var generation_ms: float = float(Time.get_ticks_usec() - generation_start) / 1000.0
	for _warmup: int in range(30):
		await process_frame

	var frame_wall_us: int = 0
	var process_ms: float = 0.0
	var render_cpu_ms: float = 0.0
	var render_gpu_ms: float = 0.0
	var draw_calls: int = 0
	for _sample: int in range(SAMPLE_FRAMES):
		var frame_start: int = Time.get_ticks_usec()
		await process_frame
		frame_wall_us += Time.get_ticks_usec() - frame_start
		process_ms += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		draw_calls += int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		if not is_headless:
			render_cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid())
			render_gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid())

	var scatter_nodes: int = 0
	var scatter_instances: int = 0
	var scatter_colliders: int = 0
	for node: Node in map.get_node("Resources").get_children():
		if EnvironmentScatter.is_scatter_node(node):
			scatter_nodes += 1
			scatter_instances += (node as MultiMeshInstance3D).multimesh.instance_count
			scatter_colliders += node.find_children("*", "CollisionObject3D", true, false).size()
			scatter_colliders += node.find_children("*", "CollisionShape3D", true, false).size()
	var frame_wall_avg_ms: float = float(frame_wall_us) / float(SAMPLE_FRAMES) / 1000.0
	var process_avg_ms: float = process_ms / float(SAMPLE_FRAMES)
	var render_cpu_avg_ms: float = render_cpu_ms / float(SAMPLE_FRAMES)
	var render_gpu_avg_ms: float = render_gpu_ms / float(SAMPLE_FRAMES)
	var draw_calls_avg: int = int(roundf(float(draw_calls) / float(SAMPLE_FRAMES)))
	var report: Array[String] = [
		"# Issue #29 Scatter Runtime Profile",
		"",
		"- Seed: `1337`; density: `Medium` production default; start window: 49 chunks (7×7).",
		"- Internal density multipliers: Low `0.55`, Medium `0.80`, High `1.00`; cluster grid: `8m`, active clusters: `42%`.",
		"- Per-biome prop rates and variants are authored in `assets/environment/scatter_profiles/{forest,plains,mountains}.tres`.",
		"- Runtime: Godot %s, %s, %s." % [Engine.get_version_info()["string"], OS.get_name(), "headless" if is_headless else RenderingServer.get_video_adapter_name()],
		"- Synchronous initial terrain + resource + scatter generation: **%.2f ms** (whole 49-chunk startup, not scatter-only)." % generation_ms,
		"- Active terrain chunks: **%d**; resource container nodes: **%d**." % [map.active_chunks.size(), map.get_node("Resources").get_child_count()],
		"- Batched scatter nodes: **%d**; MultiMesh instances: **%d**; scatter collision nodes: **%d**." % [scatter_nodes, scatter_instances, scatter_colliders],
		"- Mean wall-clock frame over %d samples: **%.2f ms**; Godot process monitor: **%.3f ms**; mean draw calls: **%d**." % [SAMPLE_FRAMES, frame_wall_avg_ms, process_avg_ms, draw_calls_avg],
	]
	if not is_headless:
		report.append("- Mean measured render CPU / GPU: **%.2f / %.2f ms**." % [render_cpu_avg_ms, render_gpu_avg_ms])
	else:
		report.append("- GPU render timing is unavailable in headless mode; frame timing above is not a GPU performance claim.")
	var report_file: FileAccess = FileAccess.open("res://docs/verification/issue29/metrics.md", FileAccess.WRITE)
	if report_file:
		report_file.store_string("\n".join(report) + "\n")
		report_file.close()
		print("\n".join(report))
	else:
		push_error("Cannot write issue #29 profile report")
	quit(0)

extends SceneTree

class Stairs extends RefCounted:
	var queries: int = 0
	func height(x: int, z: int) -> int:
		queries += 1
		return floori(float(x + z) / 5.0)

func _initialize() -> void:
	call_deferred("_measure")

func _measure() -> void:
	create_timer(20.0).timeout.connect(func() -> void: quit(1))
	for stage: int in range(3, 7):
		for spec: BossAttackSpec in BossEncounterCatalog.build(stage).attacks:
			if spec.kind not in [BossAttackSpec.Kind.LINE_BEAM, BossAttackSpec.Kind.RADIAL_BEAM]:
				continue
			var terrain: Stairs = Stairs.new()
			var visual: BossAttackVFX = BossAttackVFX.new()
			root.add_child(visual)
			visual.setup(spec, Vector3(1, 0, -0.6).normalized(), Color.CORAL, Callable(terrain, "height"))
			var total: int = 0
			var worst: int = 0
			var initial_queries: int = terrain.queries
			for frame: int in range(240):
				var start: int = Time.get_ticks_usec()
				visual.set_warning_progress(float(frame % 60) / 59.0)
				var elapsed: int = Time.get_ticks_usec() - start
				total += elapsed
				worst = maxi(worst, elapsed)
			print("BOSS_PROJECTION stage=%d kind=%d mean_us=%.1f worst_us=%d terrain_queries_initial=%d additional=%d shared_mesh=%s" % [stage, spec.kind, float(total) / 240.0, worst, initial_queries, terrain.queries - initial_queries, visual._progress_mesh.mesh == visual._ray_body.mesh])
			visual.free()
	print("BOSS_PROJECTION_BENCHMARK PASS: 1440 CPU updates, one shared mesh per beam")
	quit(0)

extends GutTest

const SCENES: PackedStringArray = [
	"res://scenes/bosses/boss_01_cairn.tscn", "res://scenes/bosses/boss_02_gorgon.tscn",
	"res://scenes/bosses/boss_03_ash_oracle.tscn", "res://scenes/bosses/boss_04_mortar.tscn",
	"res://scenes/bosses/boss_05_rift_warden.tscn", "res://scenes/bosses/boss_06_rift_harbinger.tscn"]

class Target extends Node3D:
	var damage: float = 0.0
	func receive(amount: float, _push: Vector3, _kind: String, _attacker: Node) -> void:
		damage += amount

class Steps extends RefCounted:
	func height(x: int, _z: int) -> int:
		return 1 if x >= 0 else 0

func _target(point: Vector3) -> Target:
	var target: Target = Target.new()
	var hurtbox: HurtboxArea = HurtboxArea.new()
	hurtbox.name = "Hurtbox"
	target.add_child(hurtbox)
	hurtbox.damaged.connect(target.receive)
	add_child_autoqfree(target)
	target.global_position = point
	return target

func _boss(stage: int, target: Node3D) -> SiegeBoss:
	var boss: SiegeBoss = (load(SCENES[stage - 1]) as PackedScene).instantiate() as SiegeBoss
	boss.configure(stage, target)
	add_child_autoqfree(boss)
	boss.set_physics_process(false)
	boss.global_position = Vector3(-2.0, 1.5, 2.0)
	return boss

func _hazard(stage: int, attack: int, facing: Vector3, height: Callable = Callable()) -> BossAttackHazard:
	var target: Target = _target(Vector3(3.0, 1.9, -3.0))
	var boss: SiegeBoss = _boss(stage, target)
	boss.look_at(boss.global_position + facing, Vector3.UP)
	var spec: BossAttackSpec = boss.profile.attacks[attack]
	var origin: Vector3 = target.global_position if spec.target_centered else boss.global_position
	origin.y = 0.0
	var hazard: BossAttackHazard = BossAttackHazard.new()
	boss.add_child(hazard)
	hazard.setup(spec, boss, target, origin, facing, boss.profile.color, height)
	hazard.set_physics_process(false)
	return hazard

func _world_vertices(mesh: MeshInstance3D) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	var vertices: PackedVector3Array = mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex: Vector3 in vertices:
		result.append(mesh.to_global(vertex))
	return result

func _covers(mesh: MeshInstance3D, point: Vector3) -> bool:
	var vertices: PackedVector3Array = _world_vertices(mesh)
	for index: int in range(0, vertices.size(), 3):
		var a: Vector2 = Vector2(vertices[index].x, vertices[index].z)
		var b: Vector2 = Vector2(vertices[index + 1].x, vertices[index + 1].z)
		var c: Vector2 = Vector2(vertices[index + 2].x, vertices[index + 2].z)
		if Geometry2D.is_point_in_polygon(Vector2(point.x, point.z), PackedVector2Array([a, b, c])):
			return true
	return false

func test_all_six_bosses_lock_warning_world_basis_and_mark_centres() -> void:
	var facing: Vector3 = Vector3(1.0, 0.0, -0.6).normalized()
	for stage: int in range(1, 7):
		for attack: int in range(BossEncounterCatalog.build(stage).attacks.size()):
			var hazard: BossAttackHazard = _hazard(stage, attack, facing)
			assert_true(hazard.global_basis.is_equal_approx(Basis.IDENTITY), "Threat geometry must not inherit %s yaw" % hazard.boss.display_name)
			if hazard.marks.is_empty():
				var sample: Vector3 = hazard.global_position + facing * hazard.spec.reach * 0.6
				assert_true(_covers(hazard._visual._fill, sample), "Visible %s must cover its authoritative inner footprint" % hazard.spec.title)
			else:
				hazard._physics_process(hazard.spec.mark_gap + 0.001)
				for mark: BossAttackMark in hazard.marks:
					assert_almost_eq(mark.visual.global_position, mark.centre, Vector3.ONE * 0.001, "A marked explosion must draw at its actual world centre")
			var original: Transform3D = hazard.global_transform
			hazard.boss.rotation.y += 0.7
			hazard.boss.get_node("Visuals").position.x += 0.3
			assert_eq(hazard.global_transform, original, "A committed threat stays locked while its actor moves")

func test_all_catalog_footprints_follow_horizontal_voxel_tops() -> void:
	var terrain: Steps = Steps.new()
	var facing: Vector3 = Vector3(1.0, 0.0, -0.6).normalized()
	var lower: bool = false
	var upper: bool = false
	for stage: int in range(1, 7):
		for attack: int in range(BossEncounterCatalog.build(stage).attacks.size()):
			var hazard: BossAttackHazard = _hazard(stage, attack, facing, Callable(terrain, "height"))
			var visual: BossAttackVFX = hazard._visual if hazard.marks.is_empty() else hazard.marks[0].visual
			var vertices: PackedVector3Array = _world_vertices(visual._fill)
			var valid: bool = true
			for index: int in range(0, vertices.size(), 3):
				var a: Vector3 = vertices[index]
				var b: Vector3 = vertices[index + 1]
				var c: Vector3 = vertices[index + 2]
				var centre: Vector3 = (a + b + c) / 3.0
				var ground: float = terrain.height(TerrainCombatRules.world_to_voxel(centre.x), TerrainCombatRules.world_to_voxel(centre.z)) + 0.06
				valid = valid and absf(a.y - ground) < 0.001 and absf(b.y - ground) < 0.001 and absf(c.y - ground) < 0.001
				lower = lower or absf(a.y - 0.06) < 0.001
				upper = upper or absf(a.y - 1.06) < 0.001
			assert_true(valid, "%s must project each triangle onto one voxel top, never slope through stairs" % hazard.spec.title)
	assert_true(lower and upper, "Regression geometry spans both stair levels")

func test_active_line_and_four_radial_routes_keep_the_preview_direction() -> void:
	var facing: Vector3 = Vector3(1.0, 0.0, -0.6).normalized()
	for stage: int in range(3, 7):
		for attack: int in range(BossEncounterCatalog.build(stage).attacks.size()):
			var hazard: BossAttackHazard = _hazard(stage, attack, facing)
			if hazard.spec.kind not in [BossAttackSpec.Kind.LINE_BEAM, BossAttackSpec.Kind.RADIAL_BEAM]:
				continue
			hazard._visual.set_impact_progress(0.37)
			var rays: PackedFloat32Array = hazard.spec.radial_angles(0.37) if hazard.spec.kind == BossAttackSpec.Kind.RADIAL_BEAM else PackedFloat32Array([0.0])
			for angle: float in rays:
				var length: float = hazard.spec.reach * (0.6 if hazard.spec.kind == BossAttackSpec.Kind.RADIAL_BEAM else 0.25)
				var point: Vector3 = hazard.global_position + facing.rotated(Vector3.UP, deg_to_rad(angle)) * length
				assert_true(_covers(hazard._visual._progress_mesh, point), "The active ray must follow the same angle/reach clock as damage")

func test_gorgon_body_sweep_cannot_damage_outside_locked_lane() -> void:
	for point: Vector3 in [Vector3(0.0, 0.9, 0.8), Vector3(0.0, 0.9, -12.8), Vector3(2.3, 0.9, -4.0)]:
		var target: Target = _target(point)
		var boss: SiegeBoss = _boss(2, target)
		boss.global_position = Vector3(0.0, 1.5, 0.0)
		var hazard: BossAttackHazard = BossAttackHazard.new()
		boss.add_child(hazard)
		hazard.setup(boss.profile.attacks[0], boss, target, Vector3.ZERO, Vector3.FORWARD, boss.profile.color, Callable())
		hazard.set_physics_process(false)
		boss.state = SiegeBoss.State.ACTIVE
		boss.global_position = Vector3(1.0 if point.x > 0.0 else 0.0, 1.5, -12.0)
		hazard._sweep_contact()
		assert_eq(target.damage, 0.0, "Behind-origin, beyond-end and slid-body contacts outside the warning must stay safe")

func test_impact_audio_follows_real_detonations_and_cancelled_warnings_stay_silent() -> void:
	var bus: Node = get_node("/root/EventBus")
	var target: Target = _target(Vector3(40, 0.9, 40))
	var boss: SiegeBoss = _boss(3, target)
	var spec: BossAttackSpec = boss.profile.attacks[2].duplicate() as BossAttackSpec
	spec.windup = 1.0
	spec.mark_gap = 0.4
	spec.mark_count = 2
	spec.synchronise_duration()
	var hazard: BossAttackHazard = BossAttackHazard.new()
	boss.add_child(hazard)
	hazard.setup(spec, boss, target, Vector3.ZERO, Vector3.FORWARD, boss.profile.color, Callable())
	hazard.set_physics_process(false)
	watch_signals(bus)
	hazard._physics_process(0.4)
	assert_signal_emit_count(bus, "audio_cue_requested", 0, "Preparation cannot play an explosion")
	hazard._physics_process(0.6)
	assert_signal_emit_count(bus, "audio_cue_requested", 1)
	hazard._physics_process(0.4)
	assert_signal_emit_count(bus, "audio_cue_requested", 2, "Every real mark explosion gets exactly one cue")
	assert_eq(target.damage, 0.0, "Impact feedback must not add damage")
	var cancelled: BossAttackHazard = BossAttackHazard.new()
	boss.add_child(cancelled)
	cancelled.setup(boss.profile.attacks[0], boss, target, Vector3.ZERO, Vector3.FORWARD, boss.profile.color, Callable())
	cancelled.set_physics_process(false)
	cancelled.cancel()
	cancelled._physics_process(10.0)
	assert_signal_emit_count(bus, "audio_cue_requested", 2, "A cancelled threat cannot play a delayed impact")

func after_each() -> void:
	for child: Node in get_children():
		if child.scene_file_path == "res://scenes/floating_text.tscn":
			autoqfree(child)

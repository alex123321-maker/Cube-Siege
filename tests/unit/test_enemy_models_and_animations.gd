extends GutTest

## Automated unit and integration test suite for Issue #31:
## Production core enemy models, animations, and presentation integration.

const ZOMBIE_MODEL_PATH = "res://assets/models/enemies/zombie.tscn"
const SKIRMISHER_MODEL_PATH = "res://assets/models/enemies/ranged_skirmisher.tscn"
const SIEGE_MODEL_PATH = "res://assets/models/enemies/siege_breaker.tscn"

const ENEMY_DUMMY_SCENE = "res://scenes/enemy_dummy.tscn"
const RANGED_SKIRMISHER_SCENE = "res://scenes/enemies/ranged_skirmisher.tscn"
const SIEGE_BREAKER_SCENE = "res://scenes/enemies/siege_breaker.tscn"

const REQUIRED_ANIMATIONS = ["idle", "move", "attack", "hit", "death"]

func test_enemy_model_scenes_exist_and_load() -> void:
	var models = [ZOMBIE_MODEL_PATH, SKIRMISHER_MODEL_PATH, SIEGE_MODEL_PATH]
	for path in models:
		assert_true(ResourceLoader.exists(path), "Model scene must exist on disk: " + path)
		var scn: PackedScene = load(path)
		assert_not_null(scn, "Must load PackedScene: " + path)
		var inst: Node3D = scn.instantiate() as Node3D
		assert_not_null(inst, "Must instantiate model: " + path)
		add_child_autoqfree(inst)

func test_enemy_glb_files_exist() -> void:
	var glbs = [
		"res://assets/models/enemies/zombie.glb",
		"res://assets/models/enemies/ranged_skirmisher.glb",
		"res://assets/models/enemies/siege_breaker.glb"
	]
	for path in glbs:
		assert_true(FileAccess.file_exists(path), "Enemy GLB file must exist: " + path)

func test_enemy_models_contain_required_animations() -> void:
	var models = [
		{"name": "Zombie", "path": ZOMBIE_MODEL_PATH},
		{"name": "Ranged Skirmisher", "path": SKIRMISHER_MODEL_PATH},
		{"name": "Siege Breaker", "path": SIEGE_MODEL_PATH}
	]
	for m in models:
		var inst: Node3D = load(m.path).instantiate()
		add_child_autoqfree(inst)
		var anim_player: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		assert_not_null(anim_player, m.name + " must contain AnimationPlayer")
		var anim_list: PackedStringArray = anim_player.get_animation_list()
		for req in REQUIRED_ANIMATIONS:
			assert_true(anim_list.has(req), m.name + " must contain animation clip: " + req)

func test_enemy_models_contain_body_mesh_and_skeleton() -> void:
	var models = [
		{"name": "Zombie", "path": ZOMBIE_MODEL_PATH},
		{"name": "Ranged Skirmisher", "path": SKIRMISHER_MODEL_PATH},
		{"name": "Siege Breaker", "path": SIEGE_MODEL_PATH}
	]
	for m in models:
		var inst: Node3D = load(m.path).instantiate()
		add_child_autoqfree(inst)
		var mesh: MeshInstance3D = inst.find_child("Body", true, false) as MeshInstance3D
		assert_not_null(mesh, m.name + " must contain MeshInstance3D named 'Body'")
		var skel: Skeleton3D = inst.find_child("Skeleton3D", true, false) as Skeleton3D
		assert_not_null(skel, m.name + " must contain Skeleton3D")
		assert_gt(skel.get_bone_count(), 10, m.name + " must have a functional bone rig")

func test_no_boxmesh_placeholders_in_enemy_scenes() -> void:
	var scenes = [
		{"name": "EnemyDummy", "path": ENEMY_DUMMY_SCENE},
		{"name": "RangedSkirmisher", "path": RANGED_SKIRMISHER_SCENE},
		{"name": "SiegeBreaker", "path": SIEGE_BREAKER_SCENE}
	]
	for s in scenes:
		var inst: Node = load(s.path).instantiate()
		add_child_autoqfree(inst)
		var visuals: Node3D = inst.get_node_or_null("Visuals") as Node3D
		assert_not_null(visuals, s.name + " must have Visuals node")
		var box_meshes = visuals.find_children("*", "BoxMesh", true, false)
		assert_eq(box_meshes.size(), 0, s.name + " must not have BoxMesh placeholders in Visuals")
		# Also check MeshInstance3D meshes are not BoxMesh
		var mesh_instances = visuals.find_children("*", "MeshInstance3D", true, false)
		for mi in mesh_instances:
			assert_false(mi.mesh is BoxMesh, s.name + " must not use BoxMesh: " + mi.name)

func test_enemy_scenes_instantiate_with_presentation() -> void:
	var scenes = [
		{"name": "EnemyDummy", "path": ENEMY_DUMMY_SCENE, "hp": 80.0, "speed": 3.2},
		{"name": "RangedSkirmisher", "path": RANGED_SKIRMISHER_SCENE, "hp": 60.0, "speed": 3.6},
		{"name": "SiegeBreaker", "path": SIEGE_BREAKER_SCENE, "hp": 220.0, "speed": 2.4}
	]
	for s in scenes:
		var enemy: CharacterBody3D = load(s.path).instantiate() as CharacterBody3D
		add_child_autoqfree(enemy)
		assert_not_null(enemy.presentation, s.name + " must have presentation component")
		assert_not_null(enemy.presentation.anim_player, s.name + " presentation must bind to AnimationPlayer")
		assert_not_null(enemy.presentation.body_mesh, s.name + " presentation must bind to body_mesh")
		assert_eq(enemy.max_health, s.hp, s.name + " max_health must remain unchanged")
		assert_eq(enemy.move_speed, s.speed, s.name + " move_speed must remain unchanged")

func test_hurtbox_and_damage_flash_resolution() -> void:
	var scenes = [
		{"name": "EnemyDummy", "path": ENEMY_DUMMY_SCENE},
		{"name": "RangedSkirmisher", "path": RANGED_SKIRMISHER_SCENE},
		{"name": "SiegeBreaker", "path": SIEGE_BREAKER_SCENE}
	]
	for s in scenes:
		var enemy: CharacterBody3D = load(s.path).instantiate() as CharacterBody3D
		add_child_autoqfree(enemy)
		var hurtbox: HurtboxArea = enemy.get_node_or_null("Hurtbox") as HurtboxArea
		assert_not_null(hurtbox, s.name + " must have HurtboxArea")
		assert_not_null(hurtbox.mesh_to_flash, s.name + " HurtboxArea must resolve mesh_to_flash")
		assert_eq(hurtbox.mesh_to_flash.name, "Body", s.name + " mesh_to_flash must be 'Body'")
		
		# Test triggering damage flash
		hurtbox.flash_hit()
		assert_not_null(hurtbox.mesh_to_flash.material_override, s.name + " flash_hit must apply material_override")

func test_enemy_animation_actions_do_not_block_gameplay() -> void:
	var dummy: CharacterBody3D = load(ENEMY_DUMMY_SCENE).instantiate() as CharacterBody3D
	add_child_autoqfree(dummy)
	
	# Attack presentation call
	dummy.perform_attack()
	assert_eq(dummy.presentation.current_action, &"attack", "Attack action must be recorded in presentation")
	assert_eq(dummy.attack_timer, dummy.attack_cooldown, "Gameplay attack timer must be set independently")
	
	# Hit presentation call
	dummy._on_damaged(10.0, Vector3.ZERO, "physical", null)
	assert_eq(dummy.current_health, 70.0, "Health must decrease immediately")

func test_enemy_death_lifecycle() -> void:
	var dummy: CharacterBody3D = load(ENEMY_DUMMY_SCENE).instantiate() as CharacterBody3D
	add_child_autoqfree(dummy)
	
	dummy._on_damaged(100.0, Vector3.ZERO, "physical", null)
	assert_lte(dummy.current_health, 0.0, "Dummy must be dead")
	assert_true(dummy.is_dying, "is_dying flag must be set")
	assert_true(dummy.presentation.is_dying, "presentation.is_dying must be set")
	assert_eq(dummy.presentation.current_action, &"death", "Death animation action must be active")
	
	# Hurtbox and collision must be disabled to prevent lingering interaction
	assert_false(dummy.hurtbox.monitoring, "Hurtbox monitoring must be disabled upon death")
	assert_false(dummy.hurtbox.monitorable, "Hurtbox monitorable must be disabled upon death")

func test_distinct_silhouettes_and_footprints() -> void:
	var dummy = load(ENEMY_DUMMY_SCENE).instantiate()
	var skirmisher = load(RANGED_SKIRMISHER_SCENE).instantiate()
	var siege = load(SIEGE_BREAKER_SCENE).instantiate()
	add_child_autoqfree(dummy)
	add_child_autoqfree(skirmisher)
	add_child_autoqfree(siege)
	
	var dummy_col = dummy.get_node("CollisionShape3D").shape as BoxShape3D
	var skirm_col = skirmisher.get_node("CollisionShape3D").shape as BoxShape3D
	var siege_col = siege.get_node("CollisionShape3D").shape as BoxShape3D
	
	assert_not_null(dummy_col)
	assert_not_null(skirm_col)
	assert_not_null(siege_col)
	
	# Footprint sizes preserved exactly
	assert_eq(dummy_col.size, Vector3(0.8, 1.8, 0.8), "Dummy collision footprint preserved")
	assert_eq(skirm_col.size, Vector3(0.6, 1.8, 0.6), "Skirmisher collision footprint preserved")
	assert_eq(siege_col.size, Vector3(1.4, 2.4, 1.4), "Siege Breaker collision footprint preserved")
	
	# Siege breaker is significantly wider and taller
	assert_gt(siege_col.size.x, dummy_col.size.x * 1.5, "Siege Breaker must be >= 1.5x wider than grunt")
	assert_gt(siege_col.size.y, dummy_col.size.y * 1.2, "Siege Breaker must be >= 1.2x taller than grunt")
	
	dummy.queue_free()
	skirmisher.queue_free()
	siege.queue_free()

func test_foot_sliding_prevention_speed_scaling() -> void:
	var dummy: CharacterBody3D = load(ENEMY_DUMMY_SCENE).instantiate() as CharacterBody3D
	add_child_autoqfree(dummy)
	
	# When stopped, idle animation with speed_scale 1.0
	dummy.presentation.update(0.016, Vector3.ZERO, dummy.move_speed)
	assert_eq(dummy.presentation.anim_player.current_animation, "idle")
	assert_eq(dummy.presentation.anim_player.speed_scale, 1.0)
	
	# When moving at normal speed, move animation scaled to gait
	dummy.presentation.update(0.016, Vector3(dummy.move_speed, 0, 0), dummy.move_speed)
	assert_eq(dummy.presentation.anim_player.current_animation, "move")
	assert_almost_eq(dummy.presentation.anim_player.speed_scale, 1.0, 0.05)
	
	# When moving at half speed (e.g. slowed), animation speed scales down
	dummy.presentation.update(0.016, Vector3(dummy.move_speed * 0.5, 0, 0), dummy.move_speed)
	assert_almost_eq(dummy.presentation.anim_player.speed_scale, 0.5, 0.05)

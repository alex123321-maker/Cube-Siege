extends GutTest

## Unit tests for MonsterAvoidance, EntityRegistry, and spatial crowd dynamics.

const MonsterAvoidanceScript = preload("res://scripts/movement/monster_avoidance.gd")
const EntityRegistryScript = preload("res://scripts/core/entity_registry.gd")
const BOSS_GORGON_SCENE = preload("res://scenes/enemies/boss_gorgon.tscn")
const RANGED_SKIRMISHER_SCENE = preload("res://scenes/enemies/ranged_skirmisher.tscn")

func test_right_hand_passing_rule_for_head_on_encounter() -> void:
	# Mob A at (0, 0, 0), moving East towards (+1, 0, 0)
	var mob_a: CharacterBody3D = CharacterBody3D.new()
	add_child_autoqfree(mob_a)
	mob_a.global_position = Vector3(0.0, 0.0, 0.0)
	mob_a.velocity = Vector3(3.0, 0.0, 0.0)
	mob_a.set("radius", 0.4)

	# Mob B at (1.0, 0, 0), moving West towards (-1, 0, 0) (head-on collision course)
	var mob_b: CharacterBody3D = CharacterBody3D.new()
	add_child_autoqfree(mob_b)
	mob_b.global_position = Vector3(1.0, 0.0, 0.0)
	mob_b.velocity = Vector3(-3.0, 0.0, 0.0)
	mob_b.set("radius", 0.4)

	var desired_a = Vector3(3.0, 0.0, 0.0)
	var neighbors: Array[Node3D] = [mob_b]

	var avoided_vel_a = MonsterAvoidance.compute_avoidance_velocity(
		mob_a,
		desired_a,
		3.0,
		0.4,
		neighbors
	)

	# In 3D space: facing +X (East), right hand is +Z (South)
	assert_ne(avoided_vel_a.z, 0.0, "Steering force must break symmetric deadlock by pushing sideways")
	assert_gt(avoided_vel_a.length(), 0.1, "Mob must keep moving while dodging")

func test_stationary_queue_deceleration() -> void:
	# Mob A behind Mob B
	var mob_a: CharacterBody3D = CharacterBody3D.new()
	add_child_autoqfree(mob_a)
	mob_a.global_position = Vector3(0.0, 0.0, 0.0)
	mob_a.velocity = Vector3(3.0, 0.0, 0.0)
	mob_a.set("radius", 0.4)

	# Mob B is stationary directly in front of Mob A
	var mob_b: CharacterBody3D = CharacterBody3D.new()
	add_child_autoqfree(mob_b)
	mob_b.global_position = Vector3(0.7, 0.0, 0.0)
	mob_b.velocity = Vector3.ZERO
	mob_b.set("radius", 0.4)

	var desired_a = Vector3(3.0, 0.0, 0.0)
	var avoided_vel = MonsterAvoidance.compute_avoidance_velocity(
		mob_a,
		desired_a,
		3.0,
		0.4,
		[mob_b]
	)

	# Forward velocity towards the stationary mob should be steered sideways
	assert_lt(avoided_vel.x, desired_a.x, "Forward speed directly into stationary mob must be redirected or reduced")
	assert_gt(avoided_vel.length(), 0.1, "Mob should steer around stationary obstacle")

func test_vertical_tier_separation_ignores_different_elevations() -> void:
	# Mob A at ground level (Y = 0)
	var mob_a: CharacterBody3D = CharacterBody3D.new()
	add_child_autoqfree(mob_a)
	mob_a.global_position = Vector3(0.0, 0.0, 0.0)
	mob_a.velocity = Vector3(3.0, 0.0, 0.0)
	mob_a.set("radius", 0.4)

	# Mob B directly above on a high cliff (Y = 5.0m, no vertical volume overlap)
	var mob_b: CharacterBody3D = CharacterBody3D.new()
	add_child_autoqfree(mob_b)
	mob_b.global_position = Vector3(0.3, 5.0, 0.0)
	mob_b.velocity = Vector3.ZERO
	mob_b.set("radius", 0.4)

	var desired_a = Vector3(3.0, 0.0, 0.0)
	var avoided_vel = MonsterAvoidance.compute_avoidance_velocity(
		mob_a,
		desired_a,
		3.0,
		0.4,
		[mob_b]
	)

	assert_almost_eq(avoided_vel.x, desired_a.x, 0.01, "Mob on high tier should not repel mob on lower tier")

func test_skirmisher_retreats_past_stationary_gorgon_without_deadlock() -> void:
	# Scenario from B7: Skirmisher at X=1.5 retreats from player at X=0 towards +X,
	# encountering stationary Boss Gorgon at X=3.0.
	var skirmisher = RANGED_SKIRMISHER_SCENE.instantiate()
	add_child_autoqfree(skirmisher)
	skirmisher.global_position = Vector3(1.5, 0.9, 0.0)
	skirmisher.velocity = Vector3(3.0, 0.0, 0.0)

	var gorgon = BOSS_GORGON_SCENE.instantiate()
	add_child_autoqfree(gorgon)
	gorgon.global_position = Vector3(3.0, 0.0, 0.0)
	gorgon.velocity = Vector3.ZERO

	var desired_retreat = Vector3(3.0, 0.0, 0.0)
	var registry = EntityRegistryScript.new()
	add_child_autoqfree(registry)
	registry.register_enemy(gorgon)

	var neighbors = registry.get_nearby_enemies(skirmisher.global_position, 0.3, skirmisher)
	assert_true(neighbors.has(gorgon), "Skirmisher query must detect large neighbor (Gorgon) before physical collision (B7)")

	var avoided_vel = MonsterAvoidance.compute_avoidance_velocity(
		skirmisher,
		desired_retreat,
		3.0,
		0.3,
		neighbors
	)

	assert_gt(avoided_vel.length(), 0.5, "Skirmisher must not freeze into zero-speed deadlock (B7)")
	assert_ne(avoided_vel.z, 0.0, "Skirmisher must steer sideways around the stationary boss")

func test_entity_registry_resource_and_building_flowfield_sync() -> void:
	var registry = EntityRegistryScript.new()
	add_child_autoqfree(registry)

	var wall: Node3D = Node3D.new()
	wall.add_to_group("walls")
	add_child_autoqfree(wall)
	wall.global_position = Vector3(5.5, 0.0, 5.5)

	registry.register_building(wall)
	assert_true(registry.monster_flowfield.blocked_cells.has(Vector2i(5, 5)), "Registered wall must block flowfield cell")

	registry.unregister_building(wall)
	assert_false(registry.monster_flowfield.blocked_cells.has(Vector2i(5, 5)), "Unregistered wall must unblock flowfield cell")

	var rock: Node3D = Node3D.new()
	rock.add_to_group("resource_nodes")
	add_child_autoqfree(rock)
	rock.global_position = Vector3(8.5, 0.0, 8.5)

	registry.register_resource(rock)
	assert_true(registry.monster_flowfield.blocked_cells.has(Vector2i(8, 8)), "Registered resource must block flowfield cell")

	registry.unregister_resource(rock)
	assert_false(registry.monster_flowfield.blocked_cells.has(Vector2i(8, 8)), "Unregistered resource must unblock flowfield cell")

	# Full clear
	registry.register_resource(rock)
	registry.clear()
	assert_eq(registry.monster_flowfield.blocked_cells.size(), 0, "EntityRegistry.clear() must completely wipe blocked_cells (B5)")

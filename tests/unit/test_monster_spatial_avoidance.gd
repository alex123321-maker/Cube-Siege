extends GutTest

## Unit tests for MonsterAvoidance and spatial indexing crowd dynamics.

const MonsterAvoidanceScript = preload("res://scripts/movement/monster_avoidance.gd")
const EntityRegistryScript = preload("res://scripts/core/entity_registry.gd")

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

	# Mob B is stationary (e.g. attacking or blocked at a gate) directly in front of Mob A
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

	# Forward velocity towards the stationary mob should be significantly reduced/steered
	assert_lt(avoided_vel.x, desired_a.x, "Forward speed directly into stationary mob must be reduced")

func test_vertical_tier_separation_ignores_different_elevations() -> void:
	# Mob A at ground level (Y = 0)
	var mob_a: CharacterBody3D = CharacterBody3D.new()
	add_child_autoqfree(mob_a)
	mob_a.global_position = Vector3(0.0, 0.0, 0.0)
	mob_a.velocity = Vector3(3.0, 0.0, 0.0)
	mob_a.set("radius", 0.4)

	# Mob B directly above on a cliff (Y = 3.0m, > 1.8m separation)
	var mob_b: CharacterBody3D = CharacterBody3D.new()
	add_child_autoqfree(mob_b)
	mob_b.global_position = Vector3(0.3, 3.0, 0.0)
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

	# Because Mob B is on a different tier (>1.8m vertical difference), Mob A should not be repelled
	assert_almost_eq(avoided_vel.x, desired_a.x, 0.01, "Mob on high tier should not repel mob on lower tier")

func test_spatial_hash_bucket_registration_and_query() -> void:
	var registry = EntityRegistryScript.new()
	add_child_autoqfree(registry)

	var e1: CharacterBody3D = CharacterBody3D.new()
	add_child_autoqfree(e1)
	e1.global_position = Vector3(2.0, 1.0, 2.0)

	var e2: CharacterBody3D = CharacterBody3D.new()
	add_child_autoqfree(e2)
	e2.global_position = Vector3(2.5, 1.0, 2.5)

	var e_far: CharacterBody3D = CharacterBody3D.new()
	add_child_autoqfree(e_far)
	e_far.global_position = Vector3(50.0, 1.0, 50.0)

	registry.register_enemy(e1)
	registry.register_enemy(e2)
	registry.register_enemy(e_far)

	# Query near e1 (radius 2.0)
	var nearby = registry.get_nearby_enemies(Vector3(2.0, 1.0, 2.0), 2.0, e1)
	assert_true(nearby.has(e2), "Nearby enemy within 2m must be returned")
	assert_false(nearby.has(e1), "Self must be excluded from nearby neighbors")
	assert_false(nearby.has(e_far), "Far enemy (50m away) must not be returned in local query")

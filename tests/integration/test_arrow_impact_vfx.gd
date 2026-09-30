extends GutTest

const ARROW: PackedScene = preload("res://scenes/prefabs/arrow_projectile.tscn")
const ENEMY: PackedScene = preload("res://scenes/enemy_dummy.tscn")

func test_real_basic_projectile_creates_one_contact_and_cleans_up() -> void:
	var manager: Node = get_node("/root/VFXManager")
	await wait_seconds(0.6)
	var owner := Node3D.new()
	add_child_autoqfree(owner)
	owner.add_to_group("player")
	var target: CharacterBody3D = ENEMY.instantiate() as CharacterBody3D
	add_child_autoqfree(target)
	target.set_physics_process(false)
	target.max_health = 1000.0
	target.current_health = 1000.0
	target.global_position = Vector3(1000.0, 0.9, 995.0)
	var arrow: Node3D = ARROW.instantiate() as Node3D
	add_child(arrow)
	arrow.global_position = Vector3(1000.0, 0.8, 1000.0)
	arrow.setup(Vector3.FORWARD, 25.0, owner, 1)
	await wait_seconds(0.20)
	assert_lt(target.current_health, 1000.0, "A real projectile reached the target")
	assert_eq(manager.get_active_effect_count(), 1, "One visual contact, independent of damage listeners")
	assert_false(is_instance_valid(arrow), "The basic arrow is still consumed on contact")
	await wait_seconds(0.5)
	assert_eq(manager.get_active_effect_count(), 0)

func test_rejected_targets_and_other_arrow_types_do_not_receive_new_style() -> void:
	var manager: Node = get_node("/root/VFXManager")
	await wait_seconds(0.6)
	var owner := Node3D.new()
	add_child_autoqfree(owner)
	owner.add_to_group("player")
	var friendly := Node3D.new()
	add_child_autoqfree(friendly)
	friendly.add_to_group("buildings")
	var hurtbox := HurtboxArea.new()
	friendly.add_child(hurtbox)
	var arrow: Node3D = ARROW.instantiate() as Node3D
	add_child_autoqfree(arrow)
	arrow.set_physics_process(false)
	arrow.setup(Vector3.FORWARD, 25.0, owner, 1)
	arrow._on_hitbox_area_entered(hurtbox)
	assert_eq(manager.get_active_effect_count(), 0, "Friendly building does not produce a contact")
	assert_eq(arrow.pierce_count, 1)
	assert_true(arrow.hit_targets.is_empty())
	var piercing: Node3D = ARROW.instantiate() as Node3D
	add_child_autoqfree(piercing)
	piercing.set_physics_process(false)
	piercing.setup(Vector3.FORWARD, 25.0, owner, 6)
	piercing.pierce_count = 1
	assert_false(piercing._uses_archer_impact, "Last pierce keeps the existing special-arrow presentation")
	var tower_arrow: Node3D = ARROW.instantiate() as Node3D
	add_child_autoqfree(tower_arrow)
	tower_arrow.set_physics_process(false)
	tower_arrow.setup(Vector3.FORWARD, 25.0, friendly, 1)
	assert_false(tower_arrow._uses_archer_impact, "Tower visuals stay outside the archer basic-attack task")

func test_overlaps_use_simulation_time_and_do_not_consume_gameplay_rng() -> void:
	var manager: Node = get_node("/root/VFXManager")
	await wait_seconds(0.6)
	seed(7861)
	var expected: float = randf()
	seed(7861)
	var effects: Array[ArrowImpactVFX] = []
	for index in range(12):
		var effect: ArrowImpactVFX = manager.spawn_arrow_impact(Vector3(float(index), 1.0, 0.0), Vector3.FORWARD) as ArrowImpactVFX
		effect.set_process(false)
		effects.append(effect)
	assert_eq(randf(), expected, "Art variation cannot alter gameplay random outcomes")
	await wait_seconds(0.5)
	assert_eq(manager.get_active_effect_count(), 12, "Wall clock cannot expire paused visual clocks")
	for effect: ArrowImpactVFX in effects:
		effect._process(1.0)
	await wait_process_frames(2)
	assert_eq(manager.get_active_effect_count(), 0, "All overlapping roots release on simulation time")

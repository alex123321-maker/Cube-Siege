extends SceneTree

class Target extends Node3D:
	func take_damage(_amount: float) -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func _height(_x: int, z: int) -> int:
	return 0 if z == 10 else 3

func _solid(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.position = pos
	body.collision_layer = 1
	body.collision_mask = 0
	var col: CollisionShape3D = CollisionShape3D.new()
	var box: BoxShape3D = BoxShape3D.new()
	box.size = size
	col.shape = box
	body.add_child(col)
	parent.add_child(body)

func _run() -> void:
	var ff: MonsterFlowfield = MonsterFlowfield.new(42, _height)
	ff.set_chunk_loaded_lookup(func(_x: int, _z: int) -> bool: return true)
	ff.set_cell_blocked(Vector2i(10, 10), true)
	var wall_queries: int = 0
	var positive_wall_queries: int = 0
	var wall_ready_step: int = -1
	var max_pending: int = 0
	for step in range(240):
		ff.advance(1.0 / 60.0)
		var player: Vector3 = Vector3(11.5 + 4.5 * float(step) / 60.0, 0.9, 10.5)
		var direction: Vector3 = ff.get_flow_direction(Vector3(7.5, 0.9, 10.5), player, 0.4, 1)
		if direction.length_squared() < 0.001 and not ff.is_query_pending(player, 0.4):
			wall_queries += 1
			var wall_direction: Vector3 = ff.get_flow_direction(Vector3(7.5, 0.9, 10.5), Vector3(10.5, 0, 10.5), 0.4, 2)
			if wall_direction.x > 0.0:
				positive_wall_queries += 1
		if wall_ready_step == -1 and not ff.is_query_pending(Vector3(10.5, 0, 10.5)):
			wall_ready_step = step + 1
		max_pending = maxi(max_pending, ff.get_pending_request_count())
	print("PUBLIC_CLOCK after-fix total_builds=", ff.get_rebuild_count(), " wall_queries=", wall_queries, " positive_wall_queries=", positive_wall_queries, " wall_ready_step=", wall_ready_step, " max_pending=", max_pending)
	var registry: Node = root.get_node("EntityRegistry")
	registry.clear()
	registry.monster_flowfield.set_height_lookup(_height)
	registry.monster_flowfield.set_chunk_loaded_lookup(func(_x: int, _z: int) -> bool: return true)
	var arena: Node3D = Node3D.new()
	root.add_child(arena)
	current_scene = arena
	_solid(arena, Vector3(20, -0.5, 10.5), Vector3(80, 1, 1))
	_solid(arena, Vector3(20, 1.5, 5), Vector3(80, 3, 10))
	_solid(arena, Vector3(20, 1.5, 16), Vector3(80, 3, 10))
	var target: Target = Target.new()
	target.position = Vector3(11.5, 0.9, 10.5)
	target.add_to_group("player")
	arena.add_child(target)
	registry.register_player(target)
	var wall: BuildingBase = (load("res://scenes/prefabs/wood_wall.tscn") as PackedScene).instantiate() as BuildingBase
	wall.position = Vector3(10.5, 0, 10.5)
	arena.add_child(wall)
	registry.register_building(wall)
	var grunt: CharacterBody3D = (load("res://scenes/enemy_dummy.tscn") as PackedScene).instantiate() as CharacterBody3D
	grunt.position = Vector3(7.5, 0.9, 10.5)
	arena.add_child(grunt)
	grunt.target_player = target
	for step in range(240):
		target.position.x = 11.5 + 4.5 * float(step) / 60.0
		await physics_frame
	await process_frame
	print("ACTUAL_ENEMY after-fix position=", grunt.global_position, " wall_hp=", wall.current_health, " rebuilds=", registry.monster_flowfield.get_rebuild_count())
	quit(0)

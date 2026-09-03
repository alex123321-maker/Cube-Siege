extends RefCounted
class_name TowerTargeting

## Finds the nearest enemy within range of a given position.
## Uses group lookup (consider Area3D in future for better performance).
static func find_nearest_enemy(tree: SceneTree, from_pos: Vector3, max_range: float) -> Node3D:
	var enemies: Array[Node] = tree.get_nodes_in_group("enemies")
	var nearest: Node3D = null
	var min_dist: float = max_range
	for e in enemies:
		if e is Node3D and is_instance_valid(e):
			var dist: float = from_pos.distance_to(e.global_position)
			if dist <= min_dist:
				min_dist = dist
				nearest = e
	return nearest

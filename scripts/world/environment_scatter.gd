extends RefCounted
class_name EnvironmentScatter

## Presentation-only biome dressing. Placement is derived from world coordinates
## and seed, then batched by authored prop into one MultiMesh per chunk.

enum DensityLevel { LOW, MEDIUM, HIGH }

const PRODUCTION_DENSITY: DensityLevel = DensityLevel.MEDIUM
const DENSITY_MULTIPLIERS: Dictionary = {
	DensityLevel.LOW: 0.55,
	DensityLevel.MEDIUM: 0.8,
	DensityLevel.HIGH: 1.0,
}
const CLUSTER_SIZE: int = 8
const CLUSTER_ACTIVE_CHANCE: float = 0.42
const SCATTER_CHOICE_SALT: int = 0x53434154

const PROP_PATHS: Dictionary = {
	"grass_tuft_small_01": "res://assets/environment/dressing_pack/grass_tuft_small_01.glb",
	"grass_tuft_small_02": "res://assets/environment/dressing_pack/grass_tuft_small_02.glb",
	"grass_tuft_small_03": "res://assets/environment/dressing_pack/grass_tuft_small_03.glb",
	"grass_tuft_med_01": "res://assets/environment/dressing_pack/grass_tuft_med_01.glb",
	"grass_tuft_med_02": "res://assets/environment/dressing_pack/grass_tuft_med_02.glb",
	"grass_tuft_tall_01": "res://assets/environment/dressing_pack/grass_tuft_tall_01.glb",
	"flower_white_cluster": "res://assets/environment/dressing_pack/flower_white_cluster.glb",
	"flower_yellow_cluster": "res://assets/environment/dressing_pack/flower_yellow_cluster.glb",
	"flower_red_cluster": "res://assets/environment/dressing_pack/flower_red_cluster.glb",
	"flower_mixed_accent": "res://assets/environment/dressing_pack/flower_mixed_accent.glb",
	"moss_tree_base": "res://assets/environment/dressing_pack/moss_tree_base.glb",
	"moss_rock_shelf": "res://assets/environment/dressing_pack/moss_rock_shelf.glb",
	"moss_cliff_ledge": "res://assets/environment/dressing_pack/moss_cliff_ledge.glb",
	"stone_debris_single": "res://assets/environment/dressing_pack/stone_debris_single.glb",
	"stone_debris_trio": "res://assets/environment/dressing_pack/stone_debris_trio.glb",
	"stone_debris_flat_patch": "res://assets/environment/dressing_pack/stone_debris_flat_patch.glb",
	"stone_debris_angular_chip": "res://assets/environment/dressing_pack/stone_debris_angular_chip.glb",
	"stone_debris_fine_scatter": "res://assets/environment/dressing_pack/stone_debris_fine_scatter.glb",
	"stone_debris_mountain_cluster": "res://assets/environment/dressing_pack/stone_debris_mountain_cluster.glb",
}

## Profile values are per-cell selection chances before cluster and density scaling.
## Editable in the Inspector; these are internal authoring controls, not gameplay settings.
const BIOME_PROFILES: Dictionary = {
	BiomeSystem.BiomeType.FOREST: preload("res://assets/environment/scatter_profiles/forest.tres"),
	BiomeSystem.BiomeType.PLAINS: preload("res://assets/environment/scatter_profiles/plains.tres"),
	BiomeSystem.BiomeType.MOUNTAINS: preload("res://assets/environment/scatter_profiles/mountains.tres"),
}

const SHARED_DRESSING_MATERIAL: Material = preload("res://assets/environment/dressing_pack/textures/material_dressing_atlas.tres")
static var _mesh_cache: Dictionary = {}

static func cluster_is_active(world_x: int, world_z: int, world_seed: int) -> bool:
	var cluster_x: int = floori(float(world_x) / float(CLUSTER_SIZE))
	var cluster_z: int = floori(float(world_z) / float(CLUSTER_SIZE))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _stable_seed(cluster_x, cluster_z, world_seed, 0x51A7)
	return rng.randf() < CLUSTER_ACTIVE_CHANCE

static func choose_prop(
	world_x: int,
	world_z: int,
	world_seed: int,
	_cell_seed: int,
	biome_weights: Dictionary,
	world_height: float,
	density_level: DensityLevel,
	is_mountain_trail: bool,
	is_cliff_ledge: bool = false
) -> StringName:
	if not cluster_is_active(world_x, world_z, world_seed):
		return &""

	var candidates: Array[Dictionary] = []
	var total_chance: float = 0.0
	for biome_value: int in BIOME_PROFILES:
		var biome_weight: float = float(biome_weights.get(biome_value, 0.0))
		if biome_weight <= 0.0:
			continue
		var profile: EnvironmentScatterProfile = BIOME_PROFILES[biome_value]
		var mountain_high_surface: bool = biome_value == BiomeSystem.BiomeType.MOUNTAINS and biome_weight >= 0.7 and world_height > 8.0 and not is_mountain_trail
		var grass_rate: float = profile.grass_rate
		if mountain_high_surface:
			grass_rate = 0.0
		var flower_rate: float = 0.0 if mountain_high_surface else profile.flower_rate
		for category: String in ["grass", "flower", "debris"]:
			var rate: float = grass_rate if category == "grass" else (flower_rate if category == "flower" else profile.debris_rate)
			var weighted_rate: float = biome_weight * rate
			if weighted_rate <= 0.0:
				continue
			var prop_ids: PackedStringArray = profile.grass_props if category == "grass" else (profile.flower_props if category == "flower" else profile.debris_props)
			for prop_id: String in prop_ids:
				candidates.append({"id": prop_id, "weight": weighted_rate / float(prop_ids.size())})
			total_chance += weighted_rate
		if biome_value == BiomeSystem.BiomeType.MOUNTAINS and is_cliff_ledge:
			var ledge_rate: float = biome_weight * 0.025
			candidates.append({"id": "moss_cliff_ledge", "weight": ledge_rate})
			total_chance += ledge_rate

	if candidates.is_empty():
		return &""

	var density_scale: float = float(DENSITY_MULTIPLIERS.get(density_level, DENSITY_MULTIPLIERS[PRODUCTION_DENSITY]))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	# Keep scatter selection independent from MapGenerator's existing resource RNG.
	rng.seed = _stable_seed(world_x, world_z, world_seed, SCATTER_CHOICE_SALT)
	if rng.randf() >= minf(total_chance * density_scale, 0.95):
		return &""

	var choice_roll: float = rng.randf() * total_chance
	for candidate: Dictionary in candidates:
		choice_roll -= float(candidate["weight"])
		if choice_roll <= 0.0:
			return StringName(candidate["id"])
	return StringName(candidates.back()["id"])

static func find_cliff_ledge_direction(world_x: int, world_z: int, world_seed: int) -> Vector2i:
	var top_height: int = BiomeSystem.get_voxel_height(world_x, world_z, world_seed)
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for direction: Vector2i in directions:
		var neighbor_height: int = BiomeSystem.get_voxel_height(world_x + direction.x, world_z + direction.y, world_seed)
		if top_height - neighbor_height >= 2:
			return direction
	return Vector2i.ZERO

static func choose_associated_moss(
	resource_type: ResourceDistribution.ResourceType,
	forest_weight: float,
	cell_seed: int,
	density_level: DensityLevel
) -> StringName:
	if resource_type != ResourceDistribution.ResourceType.WOOD and resource_type != ResourceDistribution.ResourceType.STONE:
		return &""
	var density_scale: float = float(DENSITY_MULTIPLIERS.get(density_level, 0.8))
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = cell_seed ^ 0x4D055
	var forest_factor: float = lerpf(0.35, 1.0, clampf(forest_weight, 0.0, 1.0))
	var base_chance: float = 0.34 if resource_type == ResourceDistribution.ResourceType.WOOD else 0.22
	if rng.randf() >= base_chance * forest_factor * density_scale:
		return &""
	return &"moss_tree_base" if resource_type == ResourceDistribution.ResourceType.WOOD else &"moss_rock_shelf"

static func make_instance_transform(
	prop_id: StringName,
	world_position: Vector3,
	cell_seed: int,
	rotation_offset: float = 0.0
) -> Transform3D:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _stable_seed(int(floorf(world_position.x)), int(floorf(world_position.z)), cell_seed, hash(prop_id))
	var position: Vector3 = world_position
	if prop_id == &"moss_rock_shelf":
		var angle: float = rng.randf() * TAU
		position += Vector3(cos(angle), 0.0, sin(angle)) * 0.42
	var scale: float = rng.randf_range(0.86, 1.14)
	var rotation: float = rotation_offset + rng.randf_range(-0.06, 0.06) if prop_id == &"moss_cliff_ledge" else rng.randf() * TAU + rotation_offset
	var basis: Basis = Basis(Vector3.UP, rotation).scaled(Vector3.ONE * scale)
	return Transform3D(basis, position)

static func append_instance(
	instances_by_prop: Dictionary,
	prop_id: StringName,
	transform: Transform3D,
	world_cell: Vector2i = Vector2i(-2147483648, -2147483648)
) -> void:
	if not instances_by_prop.has(prop_id):
		instances_by_prop[prop_id] = {"transforms": [], "cells": []}
	var entry: Dictionary = instances_by_prop[prop_id]
	(entry["transforms"] as Array).append(transform)
	(entry["cells"] as Array).append(world_cell)

static func create_multimesh_nodes(instances_by_prop: Dictionary) -> Array[Node]:
	var nodes: Array[Node] = []
	for prop_value: Variant in instances_by_prop:
		var prop_id: StringName = StringName(prop_value)
		var entry: Variant = instances_by_prop[prop_value]
		var transforms: Array = entry["transforms"] if entry is Dictionary else entry
		var cells: Array = entry["cells"] if entry is Dictionary else []
		if transforms.is_empty():
			continue
		var mesh: Mesh = _get_mesh(prop_id)
		if mesh == null:
			push_warning("Environment scatter prop could not be loaded: %s" % prop_id)
			continue
		var multimesh: MultiMesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = mesh
		multimesh.instance_count = transforms.size()
		for index: int in transforms.size():
			multimesh.set_instance_transform(index, transforms[index])
		var instance: MultiMeshInstance3D = MultiMeshInstance3D.new()
		instance.name = "Scatter_%s" % prop_id
		instance.multimesh = multimesh
		instance.material_override = SHARED_DRESSING_MATERIAL
		instance.set_meta("scatter_cells", cells)
		nodes.append(instance)
	return nodes

static func _get_mesh(prop_id: StringName) -> Mesh:
	if _mesh_cache.has(prop_id):
		return _mesh_cache[prop_id] as Mesh
	var scene: PackedScene = load(String(PROP_PATHS.get(String(prop_id), ""))) as PackedScene
	if scene == null:
		return null
	var root: Node = scene.instantiate()
	var mesh_instance: MeshInstance3D = _find_mesh_instance(root)
	var mesh: Mesh = mesh_instance.mesh if mesh_instance else null
	root.free()
	if mesh:
		_mesh_cache[prop_id] = mesh
	return mesh

static func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		return node as MeshInstance3D
	for child: Node in node.get_children():
		var result: MeshInstance3D = _find_mesh_instance(child)
		if result:
			return result
	return null

static func _stable_seed(x: int, z: int, seed_value: int, salt: int) -> int:
	return int((x * 73856093) ^ (z * 19349663) ^ (seed_value * 83492791) ^ salt)

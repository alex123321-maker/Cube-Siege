extends GutTest

const HeightSamples = preload("res://scripts/world/chunk_height_samples.gd")

class ObservedMap extends MapGenerator:
	var samples_seen: Array[WeakRef] = []
	var shared_samples_valid: bool = true

	func _spawn_chunk_resources(cx: int, cz: int, out_nodes: Array[Node], height_samples: HeightSamples = null) -> void:
		shared_samples_valid = shared_samples_valid and height_samples != null
		if height_samples != null:
			samples_seen.append(weakref(height_samples))
			shared_samples_valid = shared_samples_valid and height_samples.voxel_heights.size() == 324
			shared_samples_valid = shared_samples_valid and height_samples.get_voxel_height(cx * 16, cz * 16) == BiomeSystem.get_voxel_height(cx * 16, cz * 16, actual_seed)
		super._spawn_chunk_resources(cx, cz, out_nodes, height_samples)

func test_every_halo_sample_matches_authoritative_world_height() -> void:
	for seed_value: int in [999, 4242, -1337]:
		for coord: Vector2i in [Vector2i.ZERO, Vector2i(-3, -4), Vector2i(-7, 5), Vector2i(23, 0)]:
			var samples: HeightSamples = HeightSamples.new(coord.x, coord.y, seed_value)
			assert_eq(samples.continuous_heights.size(), 324, "One chunk owns only its 18x18 halo")
			assert_eq(samples.voxel_heights.size(), 324)
			var all_authoritative: bool = true
			for z in range(samples.origin_z, samples.origin_z + 18):
				for x in range(samples.origin_x, samples.origin_x + 18):
					all_authoritative = all_authoritative and samples.get_voxel_height(x, z) == BiomeSystem.get_voxel_height(x, z, seed_value)
					all_authoritative = all_authoritative and samples.get_continuous_height(x, z) == BiomeSystem.sample_height(float(x), float(z), seed_value)
			assert_true(all_authoritative, "Halo must preserve continuous height and exact voxel quantization at seed=%d, chunk=%s" % [seed_value, coord])

func test_adjacent_chunk_halos_share_exact_heights_across_negative_seams() -> void:
	for coord: Vector2i in [Vector2i(-1, -1), Vector2i(-4, 3), Vector2i(5, -6)]:
		var center: HeightSamples = HeightSamples.new(coord.x, coord.y, 4242)
		var east: HeightSamples = HeightSamples.new(coord.x + 1, coord.y, 4242)
		var north: HeightSamples = HeightSamples.new(coord.x, coord.y - 1, 4242)
		var seams_match: bool = true
		for index in range(18):
			var z: int = center.origin_z + index
			for x in [east.origin_x, east.origin_x + 1]:
				seams_match = seams_match and center.get_voxel_height(x, z) == east.get_voxel_height(x, z)
				seams_match = seams_match and center.get_continuous_height(x, z) == east.get_continuous_height(x, z)
			var x: int = center.origin_x + index
			for z_shared in [center.origin_z, center.origin_z + 1]:
				seams_match = seams_match and center.get_voxel_height(x, z_shared) == north.get_voxel_height(x, z_shared)
				seams_match = seams_match and center.get_continuous_height(x, z_shared) == north.get_continuous_height(x, z_shared)
		assert_true(seams_match, "Both sides of a streamed border must use identical authoritative samples")

func test_sampling_another_seed_does_not_mutate_an_existing_chunk() -> void:
	var first: HeightSamples = HeightSamples.new(-7, 5, 999)
	var saved_heights: PackedFloat64Array = first.continuous_heights.duplicate()
	var second: HeightSamples = HeightSamples.new(-7, 5, 4242)
	assert_ne(first.continuous_heights, second.continuous_heights, "Fixture must distinguish two world seeds")
	assert_eq(first.continuous_heights, saved_heights, "BiomeSystem's cached noise seed must not invalidate completed samples")

func test_real_chunk_load_shares_then_releases_its_temporary_samples() -> void:
	var map: ObservedMap = ObservedMap.new()
	map.random_seed = false
	map.custom_seed = 999
	map.load_radius_chunks = 0
	add_child_autoqfree(map)
	for cx in range(-4, 5):
		map.load_chunk(cx, -3)
	assert_true(map.shared_samples_valid, "Resources must receive the terrain load's authoritative halo")
	assert_eq(map.samples_seen.size(), 10, "Observe startup chunk and nine real streaming loads")
	for reference: WeakRef in map.samples_seen:
		assert_null(reference.get_ref(), "Loaded terrain/resources must not retain sampling caches as distance grows")
	assert_eq(map.active_chunks.size(), 10)

func test_legacy_baseline_does_not_use_the_modern_sampling_pass() -> void:
	var previous: bool = ChunkBuilder.use_legacy_presentation
	var material: StandardMaterial3D = StandardMaterial3D.new()
	ChunkBuilder.use_legacy_presentation = true
	var legacy: Dictionary = ChunkBuilder.build_chunk_terrain(-1, 0, 999, material, material, material, material)
	ChunkBuilder.use_legacy_presentation = false
	var modern: Dictionary = ChunkBuilder.build_chunk_terrain(-1, 0, 999, material, material, material, material)
	ChunkBuilder.use_legacy_presentation = previous
	assert_false(legacy.has("height_samples"), "Legacy verification algorithm stays untouched")
	assert_not_null(modern.get("height_samples"), "Production geometry exposes its temporary samples for resource generation")
	assert_not_null(legacy.get("shape"))
	assert_not_null(modern.get("shape"))

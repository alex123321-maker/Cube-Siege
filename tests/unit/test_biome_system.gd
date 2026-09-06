extends GutTest

const BiomeSystem = preload("res://scripts/world/biome_system.gd")

func test_biome_determinism() -> void:
	var seed_val: int = 12345
	var h1: int = BiomeSystem.get_voxel_height(40, 20, seed_val)
	var h2: int = BiomeSystem.get_voxel_height(40, 20, seed_val)
	assert_eq(h1, h2, "Same coordinates and seed must yield identical voxel height")

	var b1 = BiomeSystem.sample_biome_weights(40.0, 20.0, seed_val)
	var b2 = BiomeSystem.sample_biome_weights(40.0, 20.0, seed_val)
	assert_eq(b1["primary"], b2["primary"], "Same coordinates and seed must yield identical biome")

func test_portal_clear_zone_is_flat_zero() -> void:
	var seed_val: int = 42
	for x in range(-6, 7):
		for z in range(-6, 7):
			if Vector2(float(x), float(z)).length() <= 6.5:
				var h: int = BiomeSystem.get_voxel_height(x, z, seed_val)
				assert_eq(h, 0, "Portal area (dist <= 6.5) at (%d, %d) must be flat at height 0" % [x, z])

func test_forest_height_bounds() -> void:
	var seed_val: int = 101
	# Forest is in sector ANGLE_FOREST (~0 rad / +X)
	var dir: Vector2 = Vector2(cos(BiomeSystem.ANGLE_FOREST), sin(BiomeSystem.ANGLE_FOREST))
	for r in range(15, 100, 5):
		var pt: Vector2 = dir * float(r)
		var h: int = BiomeSystem.get_voxel_height(int(round(pt.x)), int(round(pt.y)), seed_val)
		assert_true(h >= 0 and h <= 10, "Forest height must stay in 0..10 range, got %d at r=%d" % [h, r])

func test_plains_height_bounds() -> void:
	var seed_val: int = 202
	# Plains is in sector ANGLE_PLAINS (~+120 deg)
	var dir: Vector2 = Vector2(cos(BiomeSystem.ANGLE_PLAINS), sin(BiomeSystem.ANGLE_PLAINS))
	for r in range(15, 100, 5):
		var pt: Vector2 = dir * float(r)
		var h: int = BiomeSystem.get_voxel_height(int(round(pt.x)), int(round(pt.y)), seed_val)
		assert_true(h >= 0 and h <= 4, "Plains height must stay in 0..4 range, got %d at r=%d" % [h, r])

func test_mountains_height_scaling() -> void:
	var seed_val: int = 303
	# Mountains is in sector ~240 degrees (-X, -Z)
	var dir: Vector2 = Vector2(-0.5, -0.866).normalized()

	var max_h_120: int = 0
	for r in range(110, 130, 2):
		var pt: Vector2 = dir * float(r)
		var h: int = BiomeSystem.get_voxel_height(int(round(pt.x)), int(round(pt.y)), seed_val)
		if h > max_h_120:
			max_h_120 = h

	var max_h_240: int = 0
	for r in range(230, 260, 2):
		var pt: Vector2 = dir * float(r)
		var h: int = BiomeSystem.get_voxel_height(int(round(pt.x)), int(round(pt.y)), seed_val)
		if h > max_h_240:
			max_h_240 = h

	assert_true(max_h_120 >= 50, "Mountains must scale without low cap, reaching 50+ at ~120m, got %d" % max_h_120)
	assert_true(max_h_240 >= 100, "Mountains must scale without low cap, reaching 100+ at ~240m, got %d" % max_h_240)

func test_step_walkability_contract() -> void:
	# |delta| <= 1 is passable
	assert_true(BiomeSystem.is_height_step_walkable(0, 0), "Equal height is walkable")
	assert_true(BiomeSystem.is_height_step_walkable(5, 6), "+1 step is walkable")
	assert_true(BiomeSystem.is_height_step_walkable(6, 5), "-1 step is walkable")

	# |delta| >= 2 is impassable
	assert_false(BiomeSystem.is_height_step_walkable(0, 2), "+2 step is impassable")
	assert_false(BiomeSystem.is_height_step_walkable(2, 0), "-2 step is impassable")
	assert_false(BiomeSystem.is_height_step_walkable(10, 15), "+5 step is impassable")

	# Coordinate-based step test
	var s: int = 123
	# Flat portal zone adjacent coords must be walkable
	assert_true(BiomeSystem.is_step_walkable(0, 0, 1, 0, s), "Portal adjacent step is walkable")

func test_mountain_border_smooth_attenuation_no_vertical_wall() -> void:
	var seed_val: int = 777
	var r: float = 60.0

	# 1. Deep mountain sector (-120 deg / 240 deg): high elevation
	var deep_x: int = int(round(cos(deg_to_rad(-120.0)) * r))
	var deep_z: int = int(round(sin(deg_to_rad(-120.0)) * r))
	var h_deep: int = BiomeSystem.get_voxel_height(deep_x, deep_z, seed_val)
	assert_true(h_deep >= 20, "Deep mountains at 60m should be elevated (got %d)" % h_deep)

	# 2. Border between Mountains and Plains (-60 deg): mountain height attenuates to Plains level
	var border_x: int = int(round(cos(deg_to_rad(-60.0)) * r))
	var border_z: int = int(round(sin(deg_to_rad(-60.0)) * r))
	var h_border: int = BiomeSystem.get_voxel_height(border_x, border_z, seed_val)
	assert_true(h_border <= 5, "At sector border, mountain height must smoothly attenuate to neighbor level (got %d)" % h_border)

	# 3. Inside Plains sector (-10 deg): height is Plains level
	var plains_x: int = int(round(cos(deg_to_rad(-10.0)) * r))
	var plains_z: int = int(round(sin(deg_to_rad(-10.0)) * r))
	var h_plains: int = BiomeSystem.get_voxel_height(plains_x, plains_z, seed_val)
	assert_true(h_plains <= 4, "Inside Plains sector, height must remain <= 4 (got %d)" % h_plains)

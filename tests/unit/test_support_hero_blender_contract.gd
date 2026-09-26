extends GutTest

const LENGTHS: Dictionary = {
	"archer": {"idle": 1.2, "walk": .8, "attack": .38, "special": .6, "utility": .4, "ultimate": .7},
	"engineer": {"idle": 1.2, "walk": .8, "attack": .48, "special": .4, "utility": .45, "ultimate": .75},
}

func test_blender_exports_preserve_action_clocks_and_rigid_ownership() -> void:
	for hero: String in LENGTHS:
		assert_true(FileAccess.file_exists("res://art/characters/%s/hero_%s.blend" % [hero, hero]))
		var model: Node3D = load("res://assets/models/characters/hero_%s.tscn" % hero).instantiate()
		add_child_autoqfree(model)
		var ap: AnimationPlayer = model.get_node("AnimationPlayer")
		for clip: String in LENGTHS[hero]:
			assert_true(ap.has_animation(clip), hero + " keeps " + clip)
			assert_almost_eq(ap.get_animation(clip).length, LENGTHS[hero][clip], .001, "Authored duration is unchanged")
		for clip: String in ["idle", "walk"]:
			assert_eq(ap.get_animation(clip).loop_mode, Animation.LOOP_LINEAR)
		var hooks: Array = ["root/torso/left_arm/bow", "root/torso/quiver"] if hero == "archer" else ["root/torso/right_arm/wrench", "root/torso/powerpack"]
		for path: String in hooks:
			var hook: Node = model.get_node(path)
			assert_gt(hook.find_children("*", "MeshInstance3D", true, false).size(), 0, "Actual geometry follows " + path)

func test_support_hero_textures_are_individual_and_decodable() -> void:
	var hashes: Array[String] = []
	for hero: String in ["warrior", "archer", "engineer"]:
		var path: String = "res://assets/models/textures/%s/hero_%s_material_atlas.png" % [hero, hero]
		var digest: String = FileAccess.get_sha256(path)
		assert_false(digest.is_empty())
		assert_false(digest in hashes, "Hero atlas must not be a shared binary copy")
		assert_not_null(load(path), "Runtime image must decode")
		hashes.append(digest)

func test_archer_bow_and_draw_hand_remain_attached_during_shots() -> void:
	var model: Node3D = load("res://assets/models/characters/hero_archer.tscn").instantiate()
	add_child_autoqfree(model)
	var ap: AnimationPlayer = model.get_node("AnimationPlayer")
	var bow: Node3D = model.get_node("root/torso/left_arm/bow")
	var hand: MeshInstance3D = model.get_node("root/torso/left_arm/left_elbow/left_glove")
	var arrow: Node3D = model.get_node("root/torso/right_arm/arrow_hand")
	for clip: String in ["idle", "walk", "attack", "special", "utility", "ultimate"]:
		ap.play(clip)
		for index: int in 21:
			ap.seek(ap.get_animation(clip).length * index / 20.0, true)
			ap.advance(0)
			assert_lt(bow.global_position.distance_to(hand.to_global(hand.get_aabb().get_center())), .08, "Bow grip stays in the hand through " + clip)
			assert_true(bow.global_transform.is_finite())
		ap.pause()
	for entry: Array in [["attack", .06], ["special", .25]]:
		ap.play(entry[0])
		ap.seek(entry[1], true)
		ap.advance(0)
		assert_gt((-arrow.global_basis.z.normalized()).dot(Vector3.FORWARD), .98, "Nocked shaft points along gameplay shot")
		assert_gt(arrow.global_position.z - bow.global_position.z, .2, "Drawing hand pulls the string back")
		ap.pause()

func test_elf_reference_features_are_part_of_the_rig() -> void:
	var model: Node3D = load("res://assets/models/characters/hero_archer.tscn").instantiate()
	add_child_autoqfree(model)
	var head: Node3D = model.get_node("root/torso/head")
	for fragment: String in ["emerald_iris", "upper_lash", "eye_catchlight", "pointed_ear", "ponytail_lock", "swept_fringe"]:
		assert_gt(head.find_children(fragment + "*", "MeshInstance3D", true, false).size(), 0, "User reference feature: " + fragment)

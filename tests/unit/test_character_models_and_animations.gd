extends GutTest

## Tests for production-ready character models, rigs, sources, and animations (Issue #6)

const WARRIOR_SCENE_PATH = "res://assets/models/characters/hero_warrior.tscn"
const ARCHER_SCENE_PATH = "res://assets/models/characters/hero_archer.tscn"
const ENGINEER_SCENE_PATH = "res://assets/models/characters/hero_engineer.tscn"

const DECOY_SCENE_PATH = "res://assets/models/props/decoy_dummy_model.tscn"
const TURRET_SCENE_PATH = "res://assets/models/props/temp_turret_model.tscn"
const MINE_SCENE_PATH = "res://assets/models/props/remote_mine_model.tscn"

func test_bbmodel_source_files_exist() -> void:
	var required_sources = [
		"res://assets/models/sources/hero_warrior.bbmodel",
		"res://assets/models/sources/hero_archer.bbmodel",
		"res://assets/models/sources/hero_engineer.bbmodel",
		"res://assets/models/sources/decoy_dummy.bbmodel",
		"res://assets/models/sources/temp_turret.bbmodel",
		"res://assets/models/sources/remote_mine.bbmodel"
	]
	for p in required_sources:
		assert_true(FileAccess.file_exists(p), "Source bbmodel must exist: " + p)

func test_character_scenes_instantiate() -> void:
	for path in [WARRIOR_SCENE_PATH, ARCHER_SCENE_PATH, ENGINEER_SCENE_PATH]:
		assert_true(ResourceLoader.exists(path), "Character scene must exist on disk: " + path)
		var scn: PackedScene = load(path)
		assert_not_null(scn, "Should load PackedScene: " + path)
		var inst = scn.instantiate()
		assert_not_null(inst, "Should instantiate character model: " + path)
		add_child_autoqfree(inst)

func test_character_bones_hierarchy() -> void:
	var scenes = [
		{"name": "Warrior", "path": WARRIOR_SCENE_PATH, "weapon": "sword"},
		{"name": "Archer", "path": ARCHER_SCENE_PATH, "weapon": "bow"},
		{"name": "Engineer", "path": ENGINEER_SCENE_PATH, "weapon": "wrench"}
	]

	for s in scenes:
		var inst: Node3D = load(s.path).instantiate()
		add_child_autoqfree(inst)

		assert_not_null(inst.find_child("root", true, false), s.name + " must have root bone")
		assert_not_null(inst.find_child("torso", true, false), s.name + " must have torso bone")
		assert_not_null(inst.find_child("head", true, false), s.name + " must have head bone")
		assert_not_null(inst.find_child("right_arm", true, false), s.name + " must have right_arm bone")
		assert_not_null(inst.find_child("left_arm", true, false), s.name + " must have left_arm bone")
		assert_not_null(inst.find_child("right_leg", true, false), s.name + " must have right_leg bone")
		assert_not_null(inst.find_child("left_leg", true, false), s.name + " must have left_leg bone")
		assert_not_null(inst.find_child(s.weapon, true, false), s.name + " must have weapon/tool bone: " + s.weapon)

func test_character_animations_present() -> void:
	var required_anims = ["idle", "walk", "attack", "special", "ultimate"]
	var scenes = [
		{"name": "Warrior", "path": WARRIOR_SCENE_PATH},
		{"name": "Archer", "path": ARCHER_SCENE_PATH},
		{"name": "Engineer", "path": ENGINEER_SCENE_PATH}
	]

	for s in scenes:
		var inst: Node3D = load(s.path).instantiate()
		add_child_autoqfree(inst)
		var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
		assert_not_null(ap, s.name + " must have AnimationPlayer")
		if ap:
			for a_name in required_anims:
				assert_true(ap.has_animation(a_name), "%s must have '%s' animation" % [s.name, a_name])
			# Utility or block
			var has_util = ap.has_animation("utility") or ap.has_animation("block")
			assert_true(has_util, s.name + " must have utility or block animation")

func test_prop_models_instantiate() -> void:
	for path in [DECOY_SCENE_PATH, TURRET_SCENE_PATH, MINE_SCENE_PATH]:
		assert_true(ResourceLoader.exists(path), "Prop scene must exist: " + path)
		var scn: PackedScene = load(path)
		var inst = scn.instantiate()
		assert_not_null(inst, "Prop instance should not be null: " + path)
		add_child_autoqfree(inst)

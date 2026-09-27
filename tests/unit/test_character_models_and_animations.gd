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

func test_warrior_art_source_texture_and_runtime_contract() -> void:
	assert_true(FileAccess.file_exists("res://art/characters/warrior/hero_warrior.blend"), "Warrior must have an editable Blender source")
	var warrior_texture := "res://assets/models/textures/warrior/hero_warrior_material_atlas.png"
	assert_true(FileAccess.file_exists(warrior_texture), "Warrior must have its own runtime texture")
	var warrior_hash: String = FileAccess.get_sha256(warrior_texture)
	for other_texture: String in [
		"res://assets/models/textures/hero_archer.png",
		"res://assets/models/textures/hero_engineer.png",
	]:
		assert_ne(warrior_hash, FileAccess.get_sha256(other_texture), "Warrior texture must be unique: " + other_texture)

	var warrior: Node3D = load(WARRIOR_SCENE_PATH).instantiate()
	add_child_autoqfree(warrior)
	var ap: AnimationPlayer = warrior.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert_not_null(ap, "Warrior runtime scene must expose AnimationPlayer")
	if ap:
		assert_almost_eq(ap.get_animation("idle").length, 1.2, 0.001, "Idle timing must remain unchanged")
		assert_almost_eq(ap.get_animation("walk").length, 0.8, 0.001, "Run/movement timing must remain unchanged")
		assert_almost_eq(ap.get_animation("attack").length, 0.35, 0.001, "LMB timing must remain unchanged")
		assert_eq(ap.get_animation("idle").loop_mode, Animation.LOOP_LINEAR, "Idle must loop")
		assert_eq(ap.get_animation("walk").loop_mode, Animation.LOOP_LINEAR, "Run/movement must loop")

func test_prop_models_instantiate() -> void:
	for path in [DECOY_SCENE_PATH, TURRET_SCENE_PATH, MINE_SCENE_PATH]:
		assert_true(ResourceLoader.exists(path), "Prop scene must exist: " + path)
		var scn: PackedScene = load(path)
		var inst = scn.instantiate()
		assert_not_null(inst, "Prop instance should not be null: " + path)
		add_child_autoqfree(inst)

func test_warrior_weapon_hooks_own_visible_geometry() -> void:
	var warrior: Node3D = load(WARRIOR_SCENE_PATH).instantiate()
	add_child_autoqfree(warrior)
	for path: String in ["root/torso/right_arm/sword", "root/torso/left_arm/shield"]:
		var hook: Node3D = warrior.get_node(path) as Node3D
		assert_gt(hook.find_children("*", "MeshInstance3D", true, false).size(), 0,
			"Weapon hook must own its rendered meshes, not be an empty compatibility marker: " + path)
	var front: Node3D = warrior.get_node("FrontMarker") as Node3D
	assert_lt(front.global_position.z, 0.0, "Warrior face must point toward gameplay -Z")

func _sample_warrior_pose(ap: AnimationPlayer, clip: String, time: float) -> void:
	ap.play(clip)
	ap.seek(time, true)
	ap.advance(0)
	ap.pause()

func test_warrior_export_retains_idle_pose_and_combat_contacts() -> void:
	var warrior: Node3D = load(WARRIOR_SCENE_PATH).instantiate()
	add_child_autoqfree(warrior)
	var ap: AnimationPlayer = warrior.get_node("AnimationPlayer")
	var tip: Node3D = warrior.find_child("SwordTip", true, false)
	_sample_warrior_pose(ap, "idle", 0.1)
	assert_gt(tip.global_position.x, 0.65, "Constant idle arm angle must survive NLA export; sword clears the leg")
	assert_lt(tip.global_position.z, -0.08, "Idle sword tilts slightly forward")
	for contact: Array in [["attack", 0.06], ["special", 0.15]]:
		_sample_warrior_pose(ap, contact[0], contact[1])
		assert_lt(tip.global_position.z, -0.8, "Blade reaches gameplay forward at damage start: " + contact[0])
		assert_gt(tip.global_position.y, 0.8, "Contact crosses torso height: " + contact[0])
	_sample_warrior_pose(ap, "idle", 0.1)
	assert_gt(tip.global_position.x, 0.65, "Returning from an attack restores the authored idle pose")

func test_warrior_grip_stays_in_hand_through_all_clips() -> void:
	var warrior: Node3D = load(WARRIOR_SCENE_PATH).instantiate()
	add_child_autoqfree(warrior)
	var ap: AnimationPlayer = warrior.get_node("AnimationPlayer")
	var grip: Node3D = warrior.find_child("SwordGrip", true, false)
	var hand: Node3D = warrior.find_child("R_Gauntlet", true, false)
	var distance: float = grip.global_position.distance_to(hand.global_position)
	assert_lt(distance, 0.12, "Grip is inside the gauntlet")
	for clip: StringName in ap.get_animation_list():
		for fraction: float in [0.0, 0.25, 0.5, 0.75, 0.99]:
			_sample_warrior_pose(ap, clip, ap.get_animation(clip).length * fraction)
			assert_almost_eq(grip.global_position.distance_to(hand.global_position), distance, 0.001,
				"Sword must not detach during " + clip)

func test_warrior_has_a_closed_fist_and_transverse_sword_grip() -> void:
	var warrior: Node3D = load(WARRIOR_SCENE_PATH).instantiate()
	add_child_autoqfree(warrior)
	var ap: AnimationPlayer = warrior.get_node("AnimationPlayer")
	var sword: Node3D = warrior.get_node("root/torso/right_arm/sword")
	var socket: Node3D = warrior.find_child("SwordPalmSocket", true, false)
	assert_not_null(socket, "The shaped palm needs a physical grip centre")
	assert_eq(sword.find_children("R_GripFinger*_Curl", "MeshInstance3D", true, false).size(), 4, "Four fingers close around the hilt")
	assert_not_null(sword.find_child("R_GripThumbTip", true, false), "The thumb closes the opposing side")
	for clip: StringName in ap.get_animation_list():
		for index: int in 41:
			_sample_warrior_pose(ap, clip, ap.get_animation(clip).length * index / 40.0)
			if socket:
				assert_lt(socket.global_position.distance_to(sword.global_position), .002, "Palm cannot drift off the hilt: " + clip)
			assert_lt(absf(sword.basis.y.normalized().dot(Vector3.UP)), .65, "Blade must cross the fist instead of extending the forearm: " + clip)

func test_warrior_run_articulates_legs_and_has_no_root_motion() -> void:
	var warrior: Node3D = load(WARRIOR_SCENE_PATH).instantiate()
	add_child_autoqfree(warrior)
	var ap: AnimationPlayer = warrior.get_node("AnimationPlayer")
	var leg: Node3D = warrior.get_node("root/right_leg")
	var knee: Node3D = warrior.get_node("root/right_leg/right_knee")
	_sample_warrior_pose(ap, "walk", 0.0)
	var start: Quaternion = leg.quaternion
	_sample_warrior_pose(ap, "walk", 0.4)
	assert_gt(start.angle_to(leg.quaternion), 0.7, "Run must swing legs, not be a renamed idle clip")
	assert_gt(knee.quaternion.angle_to(Quaternion.IDENTITY), 0.4, "Run bends the trailing knee")
	_sample_warrior_pose(ap, "walk", 0.7999)
	assert_lt(start.angle_to(leg.quaternion), 0.01, "Loop boundary must be continuous")
	var motion_root: Node3D = warrior.get_node("root")
	assert_almost_eq(motion_root.position.x, 0.0, 0.001, "Movement remains owned by the gameplay controller")
	assert_almost_eq(motion_root.position.z, 0.0, 0.001, "No baked forward root motion")

func test_warrior_shield_board_clears_hand_and_forearm() -> void:
	var warrior: Node3D = load(WARRIOR_SCENE_PATH).instantiate()
	add_child_autoqfree(warrior)
	var ap: AnimationPlayer = warrior.get_node("AnimationPlayer")
	var board: MeshInstance3D = warrior.find_child("ShieldCore", true, false)
	var grip: Node3D = warrior.find_child("ShieldGrip", true, false)
	var hand: Node3D = warrior.find_child("L_Gauntlet", true, false)
	assert_not_null(grip, "Shield needs an actual rear grip, not a board embedded in the fist")
	for clip: StringName in ap.get_animation_list():
		for fraction: float in [0.0, 0.25, 0.5, 0.75, 0.99]:
			_sample_warrior_pose(ap, clip, ap.get_animation(clip).length * fraction)
			if grip:
				assert_lt(grip.global_position.distance_to(hand.global_position), 0.03, "Shield grip remains inside the fist: " + clip)
			# In board mesh coordinates, the rear surface is minimum Z.
			# Every gauntlet/forearm corner must stay behind it, with a visible gap.
			for part: String in ["L_Gauntlet", "L_Knuckle", "L_Vambrace"]:
				var armor: MeshInstance3D = warrior.find_child(part, true, false)
				var nearest_z: float = -INF
				for i: int in range(8):
					nearest_z = maxf(nearest_z, board.to_local(armor.to_global(armor.get_aabb().get_endpoint(i))).z)
				assert_lt(nearest_z, board.get_aabb().position.z - 0.025, "Shield board must not intersect " + part + " during " + clip)

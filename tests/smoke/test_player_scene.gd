extends GutTest

func test_player_scene_can_load_and_instantiate() -> void:
	var path: String = "res://scenes/player.tscn"
	assert_true(ResourceLoader.exists(path), "player.tscn should exist on disk")
	
	var scene_res: PackedScene = load(path)
	assert_not_null(scene_res, "player.tscn should be loadable as PackedScene")
	
	var instance: Node = scene_res.instantiate()
	assert_not_null(instance, "player instance should not be null")
	assert_true(instance is CharacterBody3D, "player instance should be a CharacterBody3D")
	
	add_child_autoqfree(instance)
	assert_true(instance.is_inside_tree(), "player should enter scene tree without errors")

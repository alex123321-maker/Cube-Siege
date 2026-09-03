extends GutTest

func test_main_game_scene_can_load_and_instantiate() -> void:
	var path: String = "res://scenes/main.tscn"
	assert_true(ResourceLoader.exists(path), "main.tscn should exist on disk")
	
	var scene_res: PackedScene = load(path)
	assert_not_null(scene_res, "main.tscn should be loadable as PackedScene")
	
	var instance: Node = scene_res.instantiate()
	assert_not_null(instance, "main.tscn instance should not be null")
	
	add_child_autoqfree(instance)
	assert_true(instance.is_inside_tree(), "main.tscn should enter scene tree successfully")

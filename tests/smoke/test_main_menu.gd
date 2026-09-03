extends GutTest

func test_main_menu_can_load_and_instantiate() -> void:
	var path: String = "res://scenes/main_menu.tscn"
	assert_true(ResourceLoader.exists(path), "main_menu.tscn should exist on disk")
	
	var scene_res: PackedScene = load(path)
	assert_not_null(scene_res, "main_menu.tscn should be loadable as PackedScene")
	
	var instance: Node = scene_res.instantiate()
	assert_not_null(instance, "main_menu instance should not be null")
	
	add_child_autoqfree(instance)
	assert_true(instance.is_inside_tree(), "main_menu should enter the scene tree without errors")

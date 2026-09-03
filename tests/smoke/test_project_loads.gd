extends GutTest

func test_required_autoloads_exist() -> void:
	# Check EventBus
	var event_bus = get_node_or_null("/root/EventBus")
	assert_not_null(event_bus, "EventBus autoload singleton should exist")
	
	# Check MasteryManager
	var mastery_mgr = get_node_or_null("/root/MasteryManager")
	assert_not_null(mastery_mgr, "MasteryManager autoload singleton should exist")
	
	# Check RosterManager
	var roster_mgr = get_node_or_null("/root/RosterManager")
	assert_not_null(roster_mgr, "RosterManager autoload singleton should exist")

func test_project_settings_valid() -> void:
	var app_name: String = ProjectSettings.get_setting("application/config/name", "")
	assert_eq(app_name, "Cube Siege", "Project name should be 'Cube Siege'")
	
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	assert_eq(main_scene, "res://scenes/main_menu.tscn", "Main scene should point to main_menu.tscn")

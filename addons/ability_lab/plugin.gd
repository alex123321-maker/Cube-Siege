@tool
extends EditorPlugin

func _enter_tree() -> void:
	add_tool_menu_item("Лаборатория способностей", _open_lab)

func _exit_tree() -> void:
	remove_tool_menu_item("Лаборатория способностей")

func _open_lab() -> void:
	EditorInterface.play_custom_scene("res://scenes/tools/ability_lab.tscn")

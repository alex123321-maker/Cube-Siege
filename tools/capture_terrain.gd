#!/usr/bin/env python3
## tools/capture_terrain.gd — запускается как: godot -s tools/capture_terrain.gd
## Примечание: этот файл должен быть в формате GDScript с shebang-комментарием
## Реальный capture выполняется через gen_terrain_comparison.py (Pillow)
## и через ручной запуск игры с фиксированным seed=1337.
extends SceneTree

## Capture script для terrain comparison screenshots.
## Запуск: godot --path . -s tools/capture_terrain.gd
##
## Генерирует PNG-файлы в docs/terrain_capture/:
##   runtime_forest_close.png
##   runtime_forest_gameplay.png
##   runtime_plains.png
##   runtime_mountain_top.png
##   runtime_cliff.png
##   runtime_forest_plains_boundary.png
##   runtime_plains_mountain_boundary.png

const SEED_VALUE: int = 1337
const OUTPUT_DIR: String = "res://docs/terrain_capture/"

# Camera positions для каждого биома при seed=1337
# Forest: ~(+X direction от Portal), Plains: ~(+120°), Mountains: ~(-120°)
const CAPTURE_POINTS: Array = [
	{"name": "runtime_forest_close",          "pos": Vector3(12, 20, 0),   "look": Vector3(12, 0, 0)},
	{"name": "runtime_forest_gameplay",       "pos": Vector3(30, 28, 0),   "look": Vector3(30, 0, 0)},
	{"name": "runtime_plains",               "pos": Vector3(-15, 20, 26),  "look": Vector3(-15, 0, 26)},
	{"name": "runtime_mountain_top",         "pos": Vector3(-15, 28, -26), "look": Vector3(-15, 0, -26)},
	{"name": "runtime_cliff",               "pos": Vector3(-20, 22, -30),  "look": Vector3(-20, 0, -30)},
	{"name": "runtime_forest_plains_boundary", "pos": Vector3(5, 24, 15),  "look": Vector3(5, 0, 15)},
	{"name": "runtime_plains_mountain_boundary","pos": Vector3(-10, 24, 0),"look": Vector3(-10, 0, 0)},
]

var _map_gen: Node = null
var _camera: Camera3D = null
var _capture_idx: int = 0
var _frames_waited: int = 0
const FRAMES_PER_CAPTURE: int = 5

func _initialize() -> void:
	var root: Window = get_root()

	# Ensure output dir exists
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(OUTPUT_DIR)
	)

	# Load and add MapGenerator
	var mg_scene: PackedScene = load("res://scenes/main.tscn")
	if not mg_scene:
		push_error("Cannot load main.tscn")
		quit(1)
		return
	var main_node: Node = mg_scene.instantiate()
	root.add_child(main_node)

	# Set fixed seed
	var map_gen: Node = main_node.find_child("MapGenerator", true, false)
	if map_gen:
		map_gen.random_seed = false
		map_gen.custom_seed = SEED_VALUE
		map_gen.generate_world()
		_map_gen = map_gen

	# Add isometric-style camera
	_camera = Camera3D.new()
	_camera.fov = 60.0
	root.add_child(_camera)
	_camera.make_current()

	print("[Capture] Initialized. Will capture %d views." % CAPTURE_POINTS.size())

func _process(_delta: float) -> bool:
	_frames_waited += 1
	if _frames_waited < FRAMES_PER_CAPTURE:
		return false
	_frames_waited = 0

	if _capture_idx >= CAPTURE_POINTS.size():
		print("[Capture] All captures done. Exiting.")
		quit(0)
		return false

	var cp: Dictionary = CAPTURE_POINTS[_capture_idx]
	var cam_pos: Vector3 = cp["pos"]
	var look_at: Vector3  = cp["look"]

	_camera.global_position = cam_pos
	_camera.look_at(look_at, Vector3.UP)

	# Take screenshot
	var img: Image = get_root().get_texture().get_image()
	if img and not img.is_empty():
		var path: String = OUTPUT_DIR + cp["name"] + ".png"
		var err: Error = img.save_png(ProjectSettings.globalize_path(path))
		if err == OK:
			print("[Capture] Saved: " + path)
		else:
			push_warning("[Capture] Failed to save: " + path)
	else:
		push_warning("[Capture] Empty image at view: " + cp["name"])

	_capture_idx += 1
	return false


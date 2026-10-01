extends SceneTree

## Isolated component preview, explicitly not a production ability validation.
const PRESETS: Array[PackedScene] = [preload("res://scenes/vfx/library/warm_contact.tscn"),
	preload("res://scenes/vfx/library/soft_dust.tscn")]
var _output: String = "res://screenshots_debug/vfx_workbench/stamps/frames/"

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=").trim_suffix("/") + "/"
	call_deferred("_capture")

func _capture() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	var scene := Node3D.new()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 1.5, 3.0)
	camera.look_at(Vector3(0, 0.8, 0))
	camera.current = true
	var world_environment := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.16, 0.19, 0.23)
	world_environment.environment = environment
	scene.add_child(world_environment)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var title := Label.new()
	title.text = "UTILITY COMPONENTS / WARM CONTACT + SOFT DUST / NOT A FULL ABILITY"
	title.position = Vector2(28, 24)
	title.add_theme_font_size_override("font_size", 22)
	layer.add_child(title)
	DirAccess.make_dir_recursive_absolute(_output)
	var effects: Array[VFXStamp3D] = []
	for frame in range(90):
		if frame == 6:
			for index in range(PRESETS.size()):
				var effect: VFXStamp3D = PRESETS[index].instantiate() as VFXStamp3D
				scene.add_child(effect)
				effect.position = Vector3(-1.2 + float(index) * 2.4, 1.0, 0)
				effects.append(effect)
		if frame in [6, 9, 12, 18, 25, 40, 65]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(_output + "stamps_0_%03d.png" % frame)
		await process_frame
	var remaining: int = 0
	for effect: VFXStamp3D in effects:
		if is_instance_valid(effect):
			remaining += 1
	print("VFX_STAMP_PREVIEW active_effects=", remaining)
	quit(0 if remaining == 0 else 2)

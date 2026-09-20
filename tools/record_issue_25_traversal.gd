extends SceneTree

## Tool for Issue #25: Records a traversal video along the mountain trail
## demonstrating terrain massing, cliff clusters, and terrace presentation in motion.

const MAIN_SCENE_PATH = "res://scenes/main.tscn"
const FIXED_SEED: int = 1337
const TOTAL_FRAMES: int = 240 # 8 seconds at 30 fps
const FPS: int = 30
const FRAMES_DIR = "docs/screenshots/issue_25/frames"
const OUTPUT_VIDEO = "docs/screenshots/issue_25/traversal_demo.mp4"

var watchdog_elapsed: float = 0.0
const MAX_WATCHDOG_TIME: float = 90.0

func _init() -> void:
	print("[TRAVERSAL-RECORD] Initializing traversal recorder...")
	call_deferred("_run")

func _wait_frames(count: int = 5) -> void:
	for i in range(count):
		await process_frame
		watchdog_elapsed += 0.016
		if watchdog_elapsed > MAX_WATCHDOG_TIME:
			printerr("[WATCHDOG-TIMEOUT] Exceeded %d seconds. Quitting." % MAX_WATCHDOG_TIME)
			quit(1)

func _run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	DirAccess.make_dir_recursive_absolute(FRAMES_DIR)

	var main_scene = load(MAIN_SCENE_PATH)
	if not main_scene:
		printerr("Cannot load main.tscn")
		quit(1)
		return

	var main = main_scene.instantiate()
	root.add_child(main)

	var camera: CameraFollow = main.get_node_or_null("Camera3D") as CameraFollow
	var player: CharacterBody3D = main.get_node_or_null("Player") as CharacterBody3D
	var map_gen: MapGenerator = main.get_node_or_null("MapGenerator") as MapGenerator

	if not camera or not player or not map_gen:
		printerr("Required nodes missing in main.tscn")
		quit(1)
		return

	root.size = Vector2i(1280, 720)
	player.set_physics_process(false)

	# Fixed seed for strictly deterministic terrain
	map_gen.random_seed = false
	map_gen.custom_seed = FIXED_SEED
	map_gen.actual_seed = FIXED_SEED
	map_gen.generate_world()

	# Start near portal clear radius on trail
	var start_r: float = 16.0
	var start_ang: float = BiomeSystem.get_trail_angle(start_r, FIXED_SEED)
	var start_x: float = start_r * cos(start_ang)
	var start_z: float = start_r * sin(start_ang)
	var start_h: float = float(map_gen.get_voxel_height(int(floorf(start_x)), int(floorf(start_z))))
	player.global_position = Vector3(start_x, start_h + 0.9, start_z)

	map_gen.update_player_chunks(Vector2i(int(floorf(start_x / 16.0)), int(floorf(start_z / 16.0))), true)
	camera.target = player
	camera._init_camera_transform()

	print("[TRAVERSAL-RECORD] Warming up chunks...")
	await _wait_frames(30)

	print("[TRAVERSAL-RECORD] Recording %d frames along mountain trail..." % TOTAL_FRAMES)
	var vp = root.get_viewport()

	for frame_idx in range(TOTAL_FRAMES):
		var t: float = float(frame_idx) / float(TOTAL_FRAMES - 1)
		# Smooth acceleration and progress from r=16 to r=125 (high elevation)
		var r: float = lerpf(16.0, 125.0, t)
		var ang: float = BiomeSystem.get_trail_angle(r, FIXED_SEED)
		var x: float = r * cos(ang)
		var z: float = r * sin(ang)
		var h: float = float(map_gen.get_voxel_height(int(floorf(x)), int(floorf(z))))
		player.global_position = Vector3(x, h + 0.9, z)

		var chunk_c := Vector2i(int(floorf(x / 16.0)), int(floorf(z / 16.0)))
		map_gen.update_player_chunks(chunk_c, false)

		camera.step_camera(1.0 / float(FPS))

		await process_frame
		await RenderingServer.frame_post_draw

		if vp:
			var tex = vp.get_texture()
			if tex:
				var img: Image = tex.get_image()
				if img and not img.is_empty():
					var frame_path = "%s/frame_%04d.png" % [FRAMES_DIR, frame_idx]
					img.save_png(frame_path)

		if frame_idx % 30 == 0:
			print("  [RECORD] Frame %d/%d (r=%.1f, h=%.0f)" % [frame_idx, TOTAL_FRAMES, r, h])

	print("[TRAVERSAL-RECORD] Finished recording frames. Encoding video with ffmpeg...")
	
	var ffmpeg_args = [
		"-framerate", str(FPS),
		"-i", "%s/frame_%%04d.png" % FRAMES_DIR,
		"-c:v", "libx264",
		"-pix_fmt", "yuv420p",
		"-crf", "22",
		"-y", OUTPUT_VIDEO
	]
	
	var exit_code = OS.execute("ffmpeg", ffmpeg_args, [], true)
	print("[TRAVERSAL-RECORD] ffmpeg exited with code: %d" % exit_code)

	if exit_code == 0:
		print("[TRAVERSAL-RECORD] Successfully encoded %s" % OUTPUT_VIDEO)
		# Clean up frames
		var dir = DirAccess.open(FRAMES_DIR)
		if dir:
			dir.list_dir_begin()
			var fn = dir.get_next()
			while fn != "":
				if fn.ends_with(".png"):
					dir.remove(fn)
				fn = dir.get_next()
			dir.list_dir_end()
			DirAccess.remove_absolute(FRAMES_DIR)
			print("[TRAVERSAL-RECORD] Cleaned up temporary frame images.")
	else:
		printerr("[TRAVERSAL-RECORD] ffmpeg encoding failed.")

	quit(0)

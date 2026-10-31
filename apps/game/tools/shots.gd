extends SceneTree
## Fixed-viewpoint screenshot set of the running game (windowed, not headless):
##   godot --path apps/game --resolution 1920x1080 --script res://tools/shots.gd -- --out=DIR [--at=8] [--only=a,b] [--weather=rain]
## Loads main.tscn (mock racers, weather), lets it run for --at seconds, then captures each
## viewpoint in world/viewpoints.gd (placed from the course data) with the overlay hidden.

const Course = preload("res://sim/course.gd")
const Viewpoints = preload("res://world/viewpoints.gd")

var out := ""
var at := 8.0
var only: PackedStringArray = []


func _initialize() -> void:
	var pass_args: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"out":
				out = kv[1]
			"at":
				at = float(kv[1])
			"only":
				only = kv[1].split(",")
	if out == "":
		push_error("shots: --out=DIR is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _run() -> void:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	var t := 0.0
	while t < at:
		await process_frame
		t += 1.0 / 60.0
	var cam: Camera3D = main.get("camera")
	cam.set_process(false)
	var overlay: Control = main.get("overlay")
	if overlay != null:
		overlay.get_parent().visible = false
	for v in Viewpoints.all(Course.new()):
		if not only.is_empty() and not (v[0] in only):
			continue
		cam.global_position = v[1]
		cam.look_at(v[2], Vector3.UP)
		cam.fov = float(v[3]) if v.size() > 3 else 60.0
		for i in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		var path := out.path_join("%s.png" % v[0])
		img.save_png(path)
		print("shot ", path)
	quit(0)

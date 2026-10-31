extends SceneTree
## Fixed-viewpoint screenshot set of the running game (windowed, not headless):
##   godot --path apps/game --resolution 1920x1080 --script res://tools/shots.gd -- --out=DIR [--at=8] [--only=a,b] [--weather=rain]
## Loads main.tscn (mock racers, weather), lets it run for --at seconds, then captures each
## viewpoint below with the overlay hidden. Viewpoints are placed from the course data so they
## follow route edits.

const Course = preload("res://sim/course.gd")
const Route = preload("res://sim/route.gd")

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
	for v in viewpoints(Course.new()):
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


## [name, camera position, look-at point, fov?]
static func viewpoints(c: Course) -> Array:
	var s0: Route = c.segments["start"]["route"]
	var jr: Route = c.segments["ramp_jump"]["route"]
	var pw: Route = c.segments["pond_water"]["route"]
	var pb: Route = c.segments["pond_bridge"]["route"]
	var ce: Route = c.segments["cross_exposed"]["route"]
	var bn: Route = c.segments["bends"]["route"]
	var j1 := jr.pos_at(0.0)
	var j2 := jr.pos_at(jr.length)
	var j3 := pw.pos_at(0.0)
	var j4 := ce.pos_at(0.0)
	var hump := pb.pos_at(pb.length * 0.5)
	var fin := bn.pos_at(bn.length)
	var mid := ce.pos_at(ce.length * 0.5)
	return [
		["start", s0.pos_at(0.0) + Vector3(9, 4.5, -12), s0.pos_at(15.0) + Vector3(0, 1, 0)],
		["ramp_split", j1 + Vector3(-9, 7, -14), j1 + Vector3(6, 0, 22)],
		["ramp_side", j1 + Vector3(-24, 9, 30), j1 + Vector3(6, 0, 30)],
		["ramp_merge", j2 + Vector3(16, 8, 14), j2 + Vector3(2, 0, -14)],
		["pond_split", j3 + Vector3(10, 9, -12), j3 + Vector3(-12, 0, 30)],
		["pond_bridge", hump + Vector3(-22, 6, -16), hump + Vector3(0, 1, 0)],
		["ford", pw.pos_at(30.0) + Vector3(9, 4, -10), pw.pos_at(55.0)],
		["cross_split", j4 + Vector3(-12, 8, -10), j4 + Vector3(8, 0, 28)],
		["causeway", mid + Vector3(-34, 5, -8), mid + Vector3(0, 0, 0)],
		["bends", bn.pos_at(45.0) + Vector3(-30, 16, -6), bn.pos_at(55.0)],
		["finish", fin + Vector3(10, 4, -24), fin + Vector3(0, 2, 0)],
		["overview", Vector3(70, 110, 120), Vector3(0, 0, 230), 55.0],
	]

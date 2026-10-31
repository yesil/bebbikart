extends SceneTree
## Fixed-viewpoint screenshots of the village loop in the running game (windowed, not headless):
##   godot --path apps/game --resolution 1920x1080 --script res://tools/village_shots.gd -- --track=village --out=DIR [--at=8] [--only=a,b]
## Loads main.tscn (it reads --track=village from the same arguments), lets the mock racers run
## for --at seconds, then captures each viewpoint with the overlay hidden. Viewpoints are placed
## from the course and plan data so they follow edits.

const VillageCourse = preload("res://sim/village_course.gd")
const VillagePlan = preload("res://world/village/village_plan.gd")
const Route = preload("res://sim/route.gd")

var out := ""
var at := 8.0
var only: PackedStringArray = []


func _initialize() -> void:
	var track := ""
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		match kv[0]:
			"out":
				out = kv[1]
			"at":
				at = float(kv[1])
			"only":
				only = kv[1].split(",")
			"track":
				track = kv[1]
	if out == "" or track != "village":
		push_error("village_shots: --out=DIR and --track=village are required")
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
	if cam == null:
		push_error("village_shots: the game did not start (see errors above)")
		quit(1)
		return
	cam.set_process(false)
	var overlay: Control = main.get("overlay")
	if overlay != null:
		overlay.get_parent().visible = false
	var c := VillageCourse.new()
	for v in viewpoints(c, VillagePlan.new(c)):
		if not only.is_empty() and not (v[0] in only):
			continue
		cam.global_position = v[1]
		cam.look_at(v[2], Vector3.UP)
		cam.fov = float(v[3]) if v.size() > 3 else 60.0
		for i in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := get_root().get_texture().get_image()
		var path := out.path_join("%s.png" % v[0])
		img.save_png(path)
		print("shot ", path)
	quit(0)


## [name, camera position, look-at point, fov?]
static func viewpoints(c: VillageCourse, plan: VillagePlan) -> Array:
	var r := func(id: String) -> Route: return c.segments[id]["route"]
	var s0: Route = r.call("start")
	var h1: Route = r.call("hills1")
	var jr: Route = r.call("ramp_jump")
	var ar: Route = r.call("ramp_around")
	var pw: Route = r.call("pond_water")
	var pb: Route = r.call("pond_bridge")
	var ce: Route = r.call("cross_exposed")
	var cs: Route = r.call("cross_sheltered")
	var bn: Route = r.call("bends")
	var up := Vector3.UP
	var church := Vector3.ZERO
	for b in plan.buildings:
		if b["kind"] == "church":
			church = Vector3(b["pos"].x, 0, b["pos"].y)
	var f := Vector3(plan.fountain.x, 0, plan.fountain.y)
	var hump := plan.bridge_mid
	var mid := ce.pos_at(ce.length * 0.5)
	var centre := (s0.pos_at(0) + pw.pos_at(pw.length * 0.5)) * 0.5
	return [
		["start", s0.pos_at(0.0) + s0.normal_at(0.0) * -8.0 + Vector3(0, 4, -14), s0.pos_at(14.0) + up],
		["main_street", h1.pos_at(4.0) + up * 3.0, h1.pos_at(30.0) + up * 2.0],
		["church", ar.pos_at(ar.length * 0.5) + (church - ar.pos_at(ar.length * 0.5)) * -1.4 + up * 6.0, church + up * 8.0],
		["ski_jump", jr.pos_at(0.0) + jr.normal_at(0.0) * 10.0 + up * 5.0, jr.pos_at(20.0)],
		["pond", pw.pos_at(0.0) + pw.normal_at(0.0) * 9.0 + up * 9.0, pw.pos_at(pw.length * 0.6) + pw.normal_at(0.0) * -6.0],
		["covered_bridge", hump + pb.normal_at(c.segments["pond_bridge"]["route"].length * 0.5) * 16.0 + up * 4.0, hump + up],
		["brook", hump + Vector3(0, 14, 0) + pb.normal_at(c.segments["pond_bridge"]["route"].length * 0.5) * -20.0, hump, 60.0],
		["laubengasse", cs.pos_at(8.0) + up * 3.0, cs.pos_at(30.0) + up * 2.0],
		["causeway", mid + ce.normal_at(ce.length * 0.5) * 24.0 + up * 4.0, mid + ce.normal_at(ce.length * 0.5) * -60.0 + up * 15.0],
		["signpost", r.call("hills2").pos_at(r.call("hills2").length - 16.0) + up * 3.0, pw.pos_at(10.0) + up * 1.5],
		["fountain", f + Vector3(10, 5, -10), f + up],
		["overview", centre + Vector3(-60, 70, -110), centre, 55.0],
		["mountains", centre + Vector3(0, 30, 60), centre + Vector3(0, 20, -300), 60.0],
	]

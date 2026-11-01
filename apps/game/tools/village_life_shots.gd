extends SceneTree
## Close-up screenshots of the village life (world/village_life.gd) in the running game (windowed):
##   godot --path apps/game --resolution 1280x720 --script res://tools/village_life_shots.gd -- --kit --out=DIR
## Loads main.tscn (mock mode with the kit's racers; main.gd reads the same arguments), waits until
## the village life is placed, freezes the race and shoots: a few crowd groups from the road, the
## bunting over the main street, the pigeons on the roundabout's island before and after they take
## off (as a kart coming round sends them up), and a balloon.

const Route = preload("res://sim/route.gd")

var out := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0] == "out":
			out = kv[1]
	if out == "":
		push_error("village_life_shots: --out=DIR is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	_run.call_deferred()


func _run() -> void:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	var life = null
	var waited := 0
	while waited < 900:
		await process_frame
		waited += 1
		life = main.get("village_life")
		if life != null and life.placed:
			break
	if life == null or not life.placed:
		push_error("village_life_shots: the village life was never placed (see errors above)")
		quit(1)
		return
	for i in 20:
		await process_frame
	main.set_physics_process(false)
	main.call("_set_split", false)
	main.set_process(false)
	main.get("duel_hud").visible = false
	var cam: Camera3D = main.get("camera")
	cam.set_process(false)
	var course = main.get("course")
	# Crowd groups, from the middle of the road a little way off.
	for gi in mini(4, life.groups.size()):
		var g: Vector3 = life.groups[gi]["pos"]
		await _shot(cam, g + Vector3(0, 2.2, 0) + (_road_dir(course, g) * 7.0), g + Vector3.UP * 0.8, "crowd_%d" % gi)
	# The bunting over the main street.
	var h1: Route = course.segments["hills1"]["route"]
	await _shot(cam, h1.pos_at(2.0) + Vector3.UP * 2.5, h1.pos_at(24.0) + Vector3.UP * 4.5, "bunting")
	# Pigeons on the island, then up and round the fountain (a stand-in kart drives over).
	var pc: Vector3 = life.pigeon_centre
	await _shot(cam, pc + Vector3(9, 3, 9), pc, "pigeons_ground")
	# Send them up as a kart coming round would.
	for bird in life._pigeons:
		bird["state"] = "fly"
		bird["t"] = 0.0
		bird["fly_s"] = 30.0
	for i in 90:
		await process_frame
	await _shot(cam, pc + Vector3(12, 4, 12), pc + Vector3.UP * 5.0, "pigeons_flying")
	# A balloon.
	var b: Node3D = life.balloons[0]["node"]
	await _shot(cam, b.global_position + Vector3(40, -25, 40), b.global_position, "balloon")
	main.free()
	await create_timer(0.3).timeout
	quit(0)


## Along the road nearest to p, pointing at p's side of it (the camera stands on the road).
func _road_dir(course, p: Vector3) -> Vector3:
	var best := INF
	var best_q := p
	for id in ["start", "hills1", "hills2", "mill", "cobbles", "bends"]:
		var r: Route = course.segments[id]["route"]
		var s := 0.0
		while s <= r.length:
			var q := r.pos_at(s)
			var dd := Vector2(q.x - p.x, q.z - p.z).length()
			if dd < best:
				best = dd
				best_q = q
			s += 1.0
	var v := best_q - p
	v.y = 0.0
	return v.normalized()


func _shot(cam: Camera3D, from: Vector3, at: Vector3, name_: String) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	cam.fov = 60.0
	for i in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := out.path_join(name_ + ".png")
	get_root().get_texture().get_image().save_png(path)
	print("shot ", path)

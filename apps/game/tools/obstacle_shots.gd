extends SceneTree
## Screenshots of each village surprise (sim/obstacles.gd) on its road, from a race camera's height
## behind it (windowed, not headless):
##   godot --path apps/game --resolution 1280x720 --script res://tools/obstacle_shots.gd -- --track=village --out=DIR [--no-obstacles]
## Loads main.tscn (mock mode, with its own surprises off: --no-obstacles is passed on by the same
## arguments, so only the ones placed here show), freezes the race, then for each kind places a
## group at a fixed spot, lets it walk, roll or drop in, and shoots it at a few moments.
## --hit: instead, lets the mock race run and drops a grazing cow (then sheep, cheese, hay) in the
## lane of the first racer to reach a surprise spot, holds its thumb there so it can't dodge, and
## shoots the race camera every 0.15 s round the hit (hit_<kind>_<n>.png).
## --close: instead, a cow and a flock of sheep up close: front three-quarter and side while
## grazing or crossing (close_<kind>_front.png, close_<kind>_side.png), then knocked by a kart
## that isn't there, shot from the front as they react and run off (close_<kind>_hit_<n>.png).

const VillageCourse = preload("res://sim/village_course.gd")
const Obstacles = preload("res://sim/obstacles.gd")
const ObstacleViews = preload("res://world/obstacle_views.gd")
const Route = preload("res://sim/route.gd")
const Tuning = preload("res://sim/tuning.gd")

## [name, spot index, kind, s on the spot's segment, side, seconds to shoot at]
const SHOTS := [
	["cow", 1, "cow", 20.0, 1.0, [1.0, 4.0, 9.0]],
	["sheep", 3, "sheep", 30.0, -1.0, [1.5, 4.0, 7.0]],
	["cheese", 0, "cheese", 70.0, 1.0, [1.2, 2.5, 4.0]],
	["hay", 0, "hay", 80.0, -1.0, [0.3, 1.5]],
]
## --close: [kind, spot index, s, side, seconds walked in before the shots, camera distance (m)]
const CLOSE := [
	["cow", 1, 20.0, 1.0, 6.0, 4.6],
	["sheep", 3, 30.0, -1.0, 2.6, 3.4],
]
const CLOSE_HIT_AT := [0.1, 0.25, 0.45, 0.7, 1.0, 1.4]   # seconds after the knock

var out := ""
var hit_mode := false
var close_mode := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0] == "out":
			out = kv[1]
		if kv[0] == "hit":
			hit_mode = true
		if kv[0] == "close":
			close_mode = true
	if out == "" or not OS.get_cmdline_user_args().has("--no-obstacles"):
		push_error("obstacle_shots: --out=DIR, --track=village and --no-obstacles are required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	_run.call_deferred()


func _run() -> void:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	get_root().add_child(main)
	for i in 30:
		await process_frame
	var sim = main.get("sim")
	var cam: Camera3D = main.get("camera")
	if sim == null or cam == null:
		push_error("obstacle_shots: the game did not start (see errors above)")
		quit(1)
		return
	if hit_mode:
		await _hits(main, sim)
		main.free()
		await create_timer(0.3).timeout
		quit(0)
		return
	main.set_physics_process(false)
	main.call("_set_split", false)
	main.get("duel_hud").visible = false
	main.set_process(false)
	cam.set_process(false)
	# The game's own surprises are off: give it some, with their views.
	sim.obstacles = Obstacles.new(sim.course, 1)
	var views := ObstacleViews.new()
	main.add_child(views)
	var err := views.setup(sim)
	if err != "":
		push_error("obstacle_shots: " + err)
		quit(1)
		return
	if close_mode:
		await _close(sim, cam, views)
		main.free()
		await create_timer(0.3).timeout
		quit(0)
		return
	for shot in SHOTS:
		sim.obstacles.items.clear()
		sim.obstacles.groups.clear()
		var spot: Dictionary = sim.course.obstacle_spots[shot[1]]
		var r: Route = sim.course.segments[spot["seg"]]["route"]
		var s: float = shot[3]
		sim.obstacles.place_group(sim, shot[1], shot[2], s, shot[4])
		var back := maxf(0.0, s - 13.0)
		cam.global_position = r.pos_at(back) + Vector3.UP * 3.0
		cam.look_at(r.pos_at(minf(r.length, s + 3.0)) + Vector3.UP * 0.6, Vector3.UP)
		cam.fov = 62.0
		var t := 0.0
		for at: float in shot[5]:
			while t < at:
				sim.obstacles.step(sim)
				t += Tuning.DT
				if int(t / Tuning.DT) % 2 == 0:
					await process_frame
			for i in 3:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := out.path_join("%s_%04.1f.png" % [shot[0], at])
			get_root().get_texture().get_image().save_png(path)
			print("shot ", path)
	# Free the game and let its audio streams go before quitting (they leak otherwise).
	main.free()
	await create_timer(0.3).timeout
	quit(0)


## The mock race runs on; each kind in turn is dropped in front of a racer in its own lane.
func _hits(main: Node, sim) -> void:
	sim.obstacles = Obstacles.new(sim.course, 2)
	sim.obstacles.enabled = false  # only the ones placed here
	var views := ObstacleViews.new()
	main.add_child(views)
	main.set("obstacle_views", views)
	var err := views.setup(sim)
	if err != "":
		push_error("obstacle_shots: " + err)
		return
	for kind in ["cow", "sheep", "cheese", "hay"]:
		var placed := false
		var waited := 0.0
		var hit_at := -1.0
		var n := 0
		var held := ""          # the racer whose thumb is held in its lane
		var held_x := 0.0
		var gid := -1
		while waited < 90.0:
			await process_frame
			waited += main.get_process_delta_time()
			if not placed:
				for r in sim.racers:
					var spot_i := -1
					for i in sim.course.obstacle_spots.size():
						var sp: Dictionary = sim.course.obstacle_spots[i]
						if sp["seg"] == r.seg_id and r.ls < float(sp["b"]) - 25.0 and (kind in sp["kinds"] or kind == "hay"):
							spot_i = i
					if spot_i < 0:
						continue
					gid = sim.obstacles.place_group(sim, spot_i, kind, r.ls + 25.0, 1.0)
					var first := true
					for it in sim.obstacles.items:
						if int(it["group"]) == gid:
							# Right in its lane: a cow already grazing there, the first bale lying
							# there; sheep and cheese about to cross it.
							if kind == "cow" or (kind == "hay" and first):
								it["d"] = r.d
								it["target"] = r.d
								it["state"] = "stay"
								it["stay"] = 8.0
								it["t"] = 0.0
							first = false
					held = r.run_id
					held_x = r.lane_x()
					placed = true
					print("placed %s ahead of %s" % [kind, r.run_id])
					break
				continue
			if hit_at < 0.0 and held != "":
				sim.steer(held, held_x)  # over the mock player's own thumb
			if hit_at < 0.0:
				for it in sim.obstacles.items:
					if int(it["group"]) == gid and it["hit"]:
						hit_at = waited
				if hit_at < 0.0 and waited > 60.0:
					break
				if hit_at < 0.0:
					continue
			if n < 14:
				await RenderingServer.frame_post_draw
				var path := out.path_join("hit_%s_%02d.png" % [kind, n])
				get_root().get_texture().get_image().save_png(path)
				print("shot ", path)
				n += 1
				var t0 := waited
				while waited - t0 < 0.15:
					await process_frame
					waited += main.get_process_delta_time()
			else:
				break
		for r in sim.racers:
			sim.steer(r.run_id, null)
		if hit_at < 0.0:
			push_error("obstacle_shots: no racer hit the %s" % kind)


## Each animal up close: it walks in (the sim stepping), then the sim holds it still while its view
## goes on moving, shot from the front three-quarter and the side; then it is knocked as if a kart
## passed just beside it and shot from the front as it reacts and runs off.
func _close(sim, cam: Camera3D, views: Node) -> void:
	cam.fov = 40.0
	for c in CLOSE:
		var kind: String = c[0]
		sim.obstacles.items.clear()
		sim.obstacles.groups.clear()
		var gid: int = sim.obstacles.place_group(sim, c[1], kind, c[2], c[3])
		await _run_sim(sim, float(c[4]))
		var it: Dictionary = {}
		for o in sim.obstacles.items:
			if int(o["group"]) == gid:
				it = o
				break
		var seg: Dictionary = sim.course.segments[it["seg"]]
		var r: Route = seg["route"]
		var s := float(it["s"])
		var rel := float(it["rel"])
		var fwd: Vector3 = r.tangent_at(s) * cos(rel) + r.normal_at(s) * sin(rel)
		var at: Vector3 = r.world_at(s, float(it["d"]))
		at.y = sim.course.surface_y(seg, s)
		var dist: float = c[5]
		var front: Vector3 = at + fwd.rotated(Vector3.UP, 0.7) * dist + Vector3.UP * 1.1
		cam.global_position = front
		cam.look_at(at + Vector3.UP * 0.7, Vector3.UP)
		await _save("close_%s_front" % kind)
		cam.global_position = at + fwd.rotated(Vector3.UP, PI * 0.5) * dist * 1.15 + Vector3.UP * 0.8
		cam.look_at(at + Vector3.UP * 0.6, Vector3.UP)
		await _save("close_%s_side" % kind)
		# The knock: a kart passing just to one side (as Obstacles.collide does it).
		var kart_d := float(it["d"]) + 0.6
		for o in sim.obstacles.items:
			if int(o["group"]) == gid and (o == it or kind == "sheep"):
				sim.obstacles._scare(o, signf(float(o["d"]) - kart_d))
		views.call("on_hit", {"kind": kind, "pos": at, "runId": ""})
		cam.global_position = front
		cam.look_at(at + Vector3.UP * 0.7, Vector3.UP)
		var t0 := 0.0
		for i in CLOSE_HIT_AT.size():
			await _run_sim(sim, float(CLOSE_HIT_AT[i]) - t0)
			t0 = float(CLOSE_HIT_AT[i])
			await _save("close_%s_hit_%d" % [kind, i])


## Steps the surprises for `secs` of sim time, in step with the frames (their views animate on the
## frames' time).
func _run_sim(sim, secs: float) -> void:
	var acc := 0.0
	var done := 0.0
	while done < secs:
		await process_frame
		acc += get_root().get_process_delta_time()
		while acc >= Tuning.DT and done < secs:
			sim.obstacles.step(sim)
			acc -= Tuning.DT
			done += Tuning.DT


func _save(name: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var path := out.path_join(name + ".png")
	get_root().get_texture().get_image().save_png(path)
	print("shot ", path)

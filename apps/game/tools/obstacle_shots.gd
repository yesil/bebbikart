extends SceneTree
## Screenshots of each village surprise (sim/obstacles.gd) on its road, from a race camera's height
## behind it (windowed, not headless):
##   godot --path apps/game --resolution 1280x720 --script res://tools/obstacle_shots.gd -- --track=village --out=DIR [--no-obstacles]
## Loads main.tscn (mock mode, with its own surprises off: --no-obstacles is passed on by the same
## arguments, so only the ones placed here show), freezes the race, then for each kind places a
## group at a fixed spot, lets it walk, roll or drop in, and shoots it at a few moments.

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

var out := ""


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		if kv[0] == "out":
			out = kv[1]
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

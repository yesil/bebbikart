extends SceneTree
## Renders the race HUD's harder-to-reach states from test data and saves screenshots: the
## podium at the end of a session, the standings with a full house of 20 racers (compact rows),
## and the race board with 16 racers on the track (compact rows, "+6 more"). Must run windowed (the dummy renderer saves blank images):
##   godot --path apps/game --resolution 1920x1080 --script res://tools/hud_check.gd -- --out=DIR [--language=de]
## Exits 1 if the standings would run into the camera's name tag at the bottom left, the race
## board into its picture-in-picture at the bottom right, or the board shows a loop run's laps from
## anywhere but the run itself (a 2-lap run with config.lapsPerRun 3 must read "Lap 1/2").

const RaceHud = preload("res://ui/race_hud.gd")
const I18n = preload("res://ui/i18n.gd")
const NAMES := ["Mia", "Noah", "Lina", "Ben", "Ella", "Finn", "Zoe", "Leo", "Ava", "Max",
	"Nora", "Tim", "Ida", "Kai", "Yara", "Oli", "Rosa", "Sam", "Lou", "Jan"]
const CAMERA_TAG_TOP := 930.0   # ui/camera_hud.gd: the on-camera tag's top edge at 1080 p
const INSET_TOP := 716.0        # ui/camera_hud.gd: the picture-in-picture's top edge (1080 - 24 - 340)
const Course = preload("res://sim/course.gd")
const VillageCourse = preload("res://sim/village_course.gd")
const Sim = preload("res://sim/sim.gd")
const Builds = preload("res://sim/builds.gd")
const Messages = preload("res://net/messages.gd")

## Just enough of sim/sim.gd for the HUD: nobody on the track.
class FakeSim:
	var racers: Array = []
	var queue: Array = []
	var by_run := {}
	var go_tick := {}
	var grid_go := -1
	var tick := 0
	func on_grid(_id: String) -> bool:
		return false


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out := String(args.get("out", "user://hud_check"))
	DirAccess.make_dir_recursive_absolute(out)
	var err := I18n.set_language(String(args.get("language", "en")))
	if err != "":
		push_error(err)
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		push_error("hud_check: run it windowed, the headless renderer saves blank images")
		quit(1)
		return
	var bg := ColorRect.new()
	bg.color = Color(0.32, 0.5, 0.36)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var hud := RaceHud.new()
	root.add_child(hud)
	await process_frame  # _ready builds the panels
	var roster: Array = []
	var board: Array = []
	for i in NAMES.size():
		roster.append({"playerId": "p%d" % i, "nickname": NAMES[i], "status": "ready" if i < 17 else "processing",
			"stage": "designing" if i >= 17 else "", "connected": i != 9})
		if i < 14:
			board.append({"playerId": "p%d" % i, "rank": i + 1, "bestTimeMs": 29800 + i * 730})
	hud.set_roster(roster)
	hud.set_leaderboard(board)
	var sim := FakeSim.new()
	for f in 3:
		hud.update(0.1, sim, {})
		await process_frame
	await _shot(out.path_join("standings_20.png"))
	var panel: Control = hud.get("_paddock_panel")
	var bottom := panel.get_global_rect().end.y
	print("standings bottom at %.0f px (camera tag starts at %.0f)" % [bottom, CAMERA_TAG_TOP])
	hud.set_session("running")
	hud.set_session("ended")
	for f in 3:
		hud.update(0.1, sim, {})
		await process_frame
	await _shot(out.path_join("podium.png"))
	# 16 racers on the countryside, all released (no countdown), a few seconds in.
	var cfg: Dictionary = Messages.default_config()
	cfg["startCountdownMs"] = 0
	var race := Sim.new(Course.new(), cfg, 3)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 16:
		race.add_run("r%d" % i, "p%d" % i, Builds.random_build(rng))
	for t in 60 * 6:
		race.step()
		race.outbox.clear()
	for f in 3:
		hud.update(0.1, race, {})
		await process_frame
	await _shot(out.path_join("board_16.png"))
	var board_panel: Control = hud.get("_board_panel")
	var board_bottom := board_panel.get_global_rect().end.y
	print("race board bottom at %.0f px with %d racers (inset starts at %.0f)" % [board_bottom, race.racers.size(), INSET_TOP])
	# Village runs that race 2 laps (the server's lapsPerRun, sent with each run) while this
	# game's config still says 3: the board must show the run's laps.
	var vcfg: Dictionary = Messages.default_config()
	vcfg["startCountdownMs"] = 0
	vcfg["lapsPerRun"] = 3
	var loop := Sim.new(VillageCourse.new(), vcfg, 4)
	for i in 3:
		loop.add_run("v%d" % i, "p%d" % i, Builds.random_build(rng), 2)
	for t in 60 * 4:
		loop.step()
		loop.outbox.clear()
	for f in 3:
		hud.update(0.1, loop, {})
		await process_frame
	var lap_text := String(hud.get("_board_rows")[0]["info"].text)
	var want := I18n.f("hud.lap", [1, 2])
	print("village 2-lap run on the board: \"%s\" (want \"%s\")" % [lap_text, want])
	if lap_text != want:
		print("HUD CHECK FAILED: the board doesn't show the run's own lap count")
		quit(1)
		return
	if bottom > CAMERA_TAG_TOP:
		print("HUD CHECK FAILED: the standings run into the camera's name tag")
		quit(1)
		return
	if board_bottom > INSET_TOP:
		print("HUD CHECK FAILED: the race board runs into the camera's picture-in-picture")
		quit(1)
		return
	print("HUD CHECK PASSED")
	quit(0)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved ", path)

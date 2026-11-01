extends SceneTree
## Duel mode check (contracts §2i), headless: the mock players' line, the two halves and the
## champion, raced in the solo sim (own start lights, no collisions), with Push driven by the mock
## players (§2g). Then the duel screen and HUD are built and driven for a few frames, split and
## full screen, so a script error there shows up here and not first on the big screen.
##   godot --headless --path apps/game --script res://tools/duel_check.gd [-- --players=6 --secs=420 --track=village]
## Exits 1 if a rule is broken:
##  - never more than one run per half, never more than two on the track;
##  - with both halves free the left one goes first;
##  - a half waits duelResultMs after a lap before its next run;
##  - the champion never launches while someone else waits;
##  - a duel run on a loop races one lap; nobody is bumped (karts pass through each other);
##  - the two halves race at the same time, started at different moments;
##  - Push reaches the racers, and the champion is the best lap.

const Course = preload("res://sim/course.gd")
const VillageCourse = preload("res://sim/village_course.gd")
const Sim = preload("res://sim/sim.gd")
const Racer = preload("res://sim/racer.gd")
const Tuning = preload("res://sim/tuning.gd")
const Messages = preload("res://net/messages.gd")
const MockNet = preload("res://net/mock_net.gd")
const I18n = preload("res://ui/i18n.gd")
const CameraRig = preload("res://world/camera_rig.gd")
const DuelScreen = preload("res://world/duel_screen.gd")
const DuelHud = preload("res://ui/duel_hud.gd")

var problems: PackedStringArray = []
var _ui_frames := 0
var _ui := {}


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var tracks := ["countryside", "village"]
	if args.has("track"):
		tracks = [String(args["track"])]
	for t in tracks:
		_race(t, int(args.get("players", "6")), float(args.get("secs", "420")), int(args.get("seed", "3")))
	# The screen and HUD need the tree running: built on the first frame (_process).


func _course(track: String):
	return VillageCourse.new() if track == "village" else Course.new()


func _race(track: String, n_players: int, secs: float, seed_: int) -> void:
	var course = _course(track)
	var config := Messages.default_config()
	config["track"] = track
	config["mode"] = "duel"
	var sim := Sim.new(course, config, seed_)
	sim.solo = true
	sim.emit_messages = true
	var net := MockNet.new(config, n_players, seed_)
	net.course = course
	net.sim = sim
	net.duel = true
	net.log_mode = "none"
	var hold := float(config["duelResultMs"]) / 1000.0
	var loop: bool = course.get("loop") == true
	var side_of := {}            # runId -> side
	var on_side := {"left": "", "right": ""}
	var freed_at := {"left": -INF, "right": -INF}
	var start_t := {}            # runId -> sim seconds it went green
	var runs := 0
	var finished := 0
	var failed := 0
	var laps_ms: Array = []
	var pushes := 0
	var overlap_s := 0.0
	var staggered := 0           # second-half starts while the other half was already racing
	var last_queue := {}
	var t := 0.0
	var dt := 1.0 / float(Protocol.SIM_TICK_HZ)
	while t < secs:
		t += dt
		var champ_before: Dictionary = net._champion()
		var line_before: Array = net.line.duplicate()
		for msg in net.poll(dt, 0):
			var pl = msg["payload"]
			match msg["type"]:
				Messages.RUN_START:
					runs += 1
					var side := String(pl.get("side", ""))
					var rid: String = pl["runId"]
					if side == "":
						problems.append("%s: run.start without a side" % track)
						continue
					if on_side[side] != "":
						problems.append("%s: %s started on the %s half while %s still races there" % [track, rid, side, on_side[side]])
					if side == "right" and on_side["left"] == "" and t - freed_at["left"] >= hold:
						problems.append("%s: the right half went first while the left one was free" % track)
					if t - freed_at[side] < hold - dt * 2.0:
						problems.append("%s: the %s half took its next run %.2f s after a lap (hold %.1f s)" % [track, side, t - freed_at[side], hold])
					if not champ_before.is_empty() and pl["playerId"] == champ_before["playerId"] and line_before.size() > 1:
						problems.append("%s: the champion launched while %d others waited" % [track, line_before.size() - 1])
					var laps := int(pl.get("lapsPerRun", 0))
					if loop and laps != 1:
						problems.append("%s: a duel run on the loop races %d laps" % [track, laps])
					var r: Racer = sim.add_run(rid, pl["playerId"], pl["build"], Tuning.DEFAULT_SIZE, laps)
					if r == null:
						problems.append("%s: sim refused %s" % [track, rid])
						continue
					side_of[rid] = side
					on_side[side] = rid
				Messages.RUN_BOOST:
					sim.boost(pl["runId"])
				Messages.RUN_PUSH:
					pushes += 1
					sim.push(pl["runId"], bool(pl["on"]))
				Messages.QUEUE_UPDATED:
					last_queue = pl
		sim.step()
		if sim.racers.size() == 2:
			overlap_s += dt
		if sim.active_count() > 2:
			problems.append("%s: %d runs on the track" % [track, sim.active_count()])
		for m in sim.outbox:
			var type: String = m["type"]
			var p: Dictionary = m["payload"]
			match type:
				Messages.GAME_RUN_STARTED:
					start_t[p["runId"]] = t
					var other := String(on_side["left" if side_of.get(p["runId"]) == "right" else "right"])
					if other != "" and start_t.has(other) and t - float(start_t[other]) > 0.5:
						staggered += 1
				Messages.GAME_RUN_FINISHED, Messages.GAME_RUN_FAILED:
					for e in p.get("events", []):
						if String(e["kind"]).begins_with("bumped"):
							problems.append("%s: %s was bumped in a duel" % [track, p["runId"]])
					if type == Messages.GAME_RUN_FINISHED:
						finished += 1
						if loop:
							if (p["laps"] as Array).size() != 1:
								problems.append("%s: %s finished %d laps" % [track, p["runId"], (p["laps"] as Array).size()])
							laps_ms.append(int(p["bestLapMs"]))
						else:
							laps_ms.append(int(p["elapsedMs"]))
					else:
						failed += 1
					var side: String = side_of.get(p["runId"], "")
					if side != "":
						on_side[side] = ""
						freed_at[side] = t
					net.send(type, p)
				"sim.removed":
					if p["outcome"] == "aborted":
						net.run_gone(p["runId"])
		sim.outbox.clear()
	# The champion is the best time anyone set.
	var best := 0
	for ms in laps_ms:
		best = ms if best == 0 else mini(best, ms)
	var champ: Dictionary = last_queue.get("champion", {})
	if finished > 0 and (champ.is_empty() or int(champ["timeMs"]) != best):
		problems.append("%s: champion %s, but the best lap was %d ms" % [track, JSON.stringify(champ), best])
	if pushes == 0:
		problems.append("%s: no Push from the mock players" % track)
	if overlap_s < secs * 0.2:
		problems.append("%s: the two halves raced together only %.0f s of %.0f s" % [track, overlap_s, secs])
	if staggered == 0:
		problems.append("%s: the halves never started at different times" % track)
	laps_ms.sort()
	print("%-11s %d players, %.0f s: %d runs (%d finished, %d failed), lap median %.2f s, best %.2f s · both halves racing %.0f%% of the time, %d staggered starts · %.1f push changes per run · champion %s with %d tries" % [
		track, n_players, secs, runs, finished, failed,
		(laps_ms[laps_ms.size() / 2] / 1000.0) if not laps_ms.is_empty() else 0.0, best / 1000.0,
		100.0 * overlap_s / secs, staggered, float(pushes) / maxf(1.0, runs),
		champ.get("nickname", "-"), int(champ.get("tries", 0))])


# ---------------------------------------------------------------- the duel screen and HUD

func _start_ui() -> void:
	var err := I18n.set_language("en")
	if err != "":
		problems.append("i18n: " + err)
		_finish()
		return
	var course = _course("village")
	var config := Messages.default_config()
	config["mode"] = "duel"
	var sim := Sim.new(course, config, 1)
	sim.solo = true
	var main := Node3D.new()
	root.add_child(main)
	var cam := CameraRig.new()
	main.add_child(cam)
	var screen := DuelScreen.new()
	main.add_child(screen)
	screen.setup(cam, [[Vector3(0, 20, -30), Vector3.ZERO], [Vector3(30, 20, 0), Vector3.ZERO]])
	var hud := DuelHud.new()
	main.add_child(hud)
	var views := {}
	for side in ["left", "right"]:
		var rid: String = "run_ui_" + side
		var r: Racer = sim.add_run(rid, "ply_" + side, {"stars": {}, "routes": {"ramp": "around", "pond": "bridge", "crossing": "sheltered"}}, Tuning.DEFAULT_SIZE, 1)
		if r == null:
			problems.append("ui: sim refused a run")
			_finish()
			return
		var v := Node3D.new()
		v.add_child(Node3D.new())  # the camera reads the body's yaw from the first child
		main.add_child(v)
		views[side] = v
		hud.set_side(rid, side)
	hud.set_queue({"line": [{"playerId": "ply_x", "nickname": "Noah"}], "racing": [], "split": true, "skipped": [],
		"champion": {"playerId": "ply_c", "nickname": "Mia", "timeMs": 52300, "tries": 3}})
	_ui = {"sim": sim, "screen": screen, "hud": hud, "views": views, "cam": cam}


func _process(delta: float) -> bool:
	if _ui.is_empty():
		_start_ui()
		return false
	var sim: Sim = _ui["sim"]
	var screen: DuelScreen = _ui["screen"]
	var hud: DuelHud = _ui["hud"]
	var views: Dictionary = _ui["views"]
	_ui_frames += 1
	# 40 frames split, 20 full screen, then split again; one lap's verdict on the way.
	var split := _ui_frames <= 40 or _ui_frames > 60
	screen.set_split(split)
	for i in 3:
		sim.step()
	for side in views:
		var r: Racer = sim.by_run.get("run_ui_" + side)
		if r != null:
			views[side].position = r.world_pos()
	if _ui_frames == 10:
		sim.push("run_ui_left", true)
	if _ui_frames == 30:
		hud.result("right", I18n.t("duel.new_champion"), "51.20 s", true)
	var on_side := {"left": views["left"], "right": views["right"]} if split else {"left": views["left"]}
	var cams: Array = screen.update(delta, on_side, views.values())
	if cams.size() != (2 if split else 1):
		problems.append("ui: %d cameras for a %s screen" % [cams.size(), "split" if split else "full"])
	var rects := {"left": screen.rect_of("left")}
	if split:
		rects["right"] = screen.rect_of("right")
		if rects["left"].size.x <= 0.0 or rects["left"].end.x > rects["right"].position.x:
			problems.append("ui: halves %s and %s overlap or are empty" % [rects["left"], rects["right"]])
	var runs := {}
	for side in rects:
		runs[side] = sim.by_run.get("run_ui_" + side)
	hud.update(delta, sim, rects, runs, func(pid: String) -> String: return pid.trim_prefix("ply_"))
	if split and get_root().disable_3d != true:
		problems.append("ui: the main viewport still draws 3D under the split screen")
	if not split and get_root().disable_3d:
		problems.append("ui: the full screen has 3D off")
	if _ui_frames >= 80:
		_finish()
		return true
	return false


func _finish() -> void:
	if problems.is_empty():
		print("DUEL CHECK PASSED")
		quit(0)
	else:
		for p in problems:
			print("FAIL ", p)
		print("DUEL CHECK FAILED (%d problems)" % problems.size())
		quit(1)

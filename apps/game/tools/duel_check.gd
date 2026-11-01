extends SceneTree
## Line check (contracts §2i), headless: the mock players' line, the two halves and the
## champion, raced in the solo sim (own start lights, no collisions), steered by the mock players'
## thumbs (§2g). Each track is raced by one player alone, then by --players who stop coming
## after --secs. Then the split screen and HUD are built and driven for a few frames, split and
## full screen, so a script error there shows up here and not first on the big screen.
##   godot --headless --path apps/game --script res://tools/duel_check.gd [-- --players=6 --secs=420 --track=village]
## Exits 1 if a rule is broken:
##  - never more than one run per half, never more than two on the track;
##  - one player alone races full screen on the left; the screen splits only once two play, and
##    goes whole again only splitHoldMs after the last lap, with nobody waiting;
##  - with both halves free the left one goes first;
##  - a half waits duelResultMs after a lap before its next run;
##  - the champion never launches while someone else waits;
##  - a duel run on a loop races one lap; nobody is bumped (karts pass through each other);
##  - the two halves race at the same time, started at different moments;
##  - two racers waiting for green at once wait in different grid slots (not inside each other);
##  - steering reaches the racers: some forks are picked by the thumb, some boost arrows caught;
##  - nobody leaves the road (the one off_track left is the causeway's low wall, in the wind);
##  - the champion is the best lap;
##  - on screen: a camera per half, and an empty half says who is next across the half (not one
##    letter per line).

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
		_race(t, 1, 150.0, int(args.get("seed", "3")))
		_race(t, int(args.get("players", "6")), float(args.get("secs", "420")), int(args.get("seed", "3")))
	# The screen and HUD need the tree running: built on the first frame (_process).


func _course(track: String):
	return VillageCourse.new() if track == "village" else Course.new()


func _race(track: String, n_players: int, secs: float, seed_: int) -> void:
	var course = _course(track)
	var config := Messages.default_config()
	config["track"] = track
	var sim := Sim.new(course, config, seed_)
	sim.solo = true
	sim.emit_messages = true
	var net := MockNet.new(config, n_players, seed_)
	net.course = course
	net.sim = sim
	net.log_mode = "none"
	var hold := float(config["duelResultMs"]) / 1000.0
	var split_hold := maxf(float(config["splitHoldMs"]), float(config["duelResultMs"])) / 1000.0
	var tail_max := 600.0  # after secs nobody comes back: the line empties, then the hold
	var loop: bool = course.get("loop") == true
	var side_of := {}            # runId -> side
	var on_side := {"left": "", "right": ""}
	var freed_at := {"left": -INF, "right": -INF}
	var start_t := {}            # runId -> sim seconds it went green
	var runs := 0
	var finished := 0
	var failed := 0
	var laps_ms: Array = []
	var steers := 0
	var steered_forks := 0
	var forks := 0
	var arrows := 0
	var overlap_s := 0.0
	var staggered := 0           # second-half starts while the other half was already racing
	var both_parked := 0         # ticks two racers waited on the grid at once
	var shared_slot := false
	var last_queue := {}
	var was_split := false
	var split_on_at := -1.0
	var split_off_at := -1.0
	var last_lap_at := -INF
	var t := 0.0
	var dt := 1.0 / float(Protocol.SIM_TICK_HZ)
	while t < secs + tail_max:
		if t >= secs and net.line.is_empty() and sim.active_count() == 0 and t - last_lap_at > split_hold + 5.0:
			break
		t += dt
		if t >= secs:  # everyone goes home: whoever is in the line still races
			for p in net.players:
				if p["status"] != "racing":
					p["wait"] = INF
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
					if side == "right" and not net.split:
						problems.append("%s: a run on the right half while the screen is whole" % track)
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
				Messages.RUN_STEER:
					steers += 1
					sim.steer(pl["runId"], pl["x"])
				Messages.QUEUE_UPDATED:
					last_queue = pl
					var now_split := bool(pl["split"])
					if now_split and not was_split:
						if net._playing() < 2:
							problems.append("%s: the screen split with %d playing" % [track, net._playing()])
						if split_on_at < 0.0:
							split_on_at = t
					if was_split and not now_split:
						if net._playing() > 0:
							problems.append("%s: the screen went whole with %d still playing" % [track, net._playing()])
						if t - last_lap_at < split_hold - dt * 2.0:
							problems.append("%s: the screen went whole %.1f s after the last lap (hold %.0f s)" % [track, t - last_lap_at, split_hold])
						split_off_at = t
					was_split = now_split
		sim.step()
		if sim.grid_slot.size() >= 2:
			both_parked += 1
			var lanes := {}
			for id in sim.grid_slot:
				if lanes.has(sim.grid_slot[id]) and not shared_slot:
					shared_slot = true
					problems.append("%s: two racers wait in the same grid slot" % track)
				lanes[sim.grid_slot[id]] = true
		if sim.racers.size() == 2 and t < secs:
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
				"sim.fork":
					forks += 1
					if bool(p["steered"]):
						steered_forks += 1
				"sim.boost":
					arrows += 1
				Messages.GAME_RUN_FINISHED, Messages.GAME_RUN_FAILED:
					if type == Messages.GAME_RUN_FAILED and p["reason"] == "off_track" and not String(p["stretch"]) in ["causeway"]:
						problems.append("%s: %s left the road on %s" % [track, p["runId"], p["stretch"]])
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
					last_lap_at = t
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
	if steers == 0:
		problems.append("%s: no steering from the mock players" % track)
	if steered_forks == 0:
		problems.append("%s: no fork was picked by steering (%d forks)" % [track, forks])
	if steered_forks == forks:
		problems.append("%s: every fork was picked by steering: hands off never took the stars' way" % track)
	if arrows == 0:
		problems.append("%s: nobody caught a boost arrow" % track)
	if was_split or not net.line.is_empty() or sim.active_count() > 0:
		problems.append("%s: %.0f s after everyone left the screen is still %s (%d in line, %d racing)" % [
			track, t - secs, "split" if was_split else "whole", net.line.size(), sim.active_count()])
	if n_players == 1:
		if split_on_at >= 0.0:
			problems.append("%s: one player alone, but the screen split" % track)
		if finished + failed < 2:
			problems.append("%s: one player alone raced only %d laps" % [track, finished + failed])
	else:
		if split_on_at < 0.0:
			problems.append("%s: %d players, but the screen never split" % [track, n_players])
		if overlap_s < secs * 0.2:
			problems.append("%s: the two halves raced together only %.0f s of %.0f s" % [track, overlap_s, secs])
		if staggered == 0:
			problems.append("%s: the halves never started at different times" % track)
		if both_parked == 0:
			problems.append("%s: the two halves never waited on the grid at the same time" % track)
	laps_ms.sort()
	print("%-11s %d player%s, %.0f s + %.0f s going home: %d runs (%d finished, %d failed), lap median %.2f s, best %.2f s · split %s · both halves racing %.0f%% of the time, %d staggered starts · %.1f steering changes per run, %d of %d forks steered, %.1f boost arrows per run · champion %s with %d tries" % [
		track, n_players, "" if n_players == 1 else "s", secs, t - secs, runs, finished, failed,
		(laps_ms[laps_ms.size() / 2] / 1000.0) if not laps_ms.is_empty() else 0.0, best / 1000.0,
		("%.0f s to %.0f s" % [split_on_at, split_off_at]) if split_on_at >= 0.0 else "never",
		100.0 * overlap_s / secs, staggered, float(steers) / maxf(1.0, runs), steered_forks, forks, float(arrows) / maxf(1.0, runs),
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
		sim.steer("run_ui_left", 0.8)
	if _ui_frames == 25:
		sim.steer("run_ui_left", null)
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
	if _ui_frames >= 70:  # both halves empty, someone waiting: "Next: Noah" in each, on one line
		runs = {}
	hud.update(delta, sim, rects, runs, func(pid: String) -> String: return pid.trim_prefix("ply_"))
	if _ui_frames >= 72:
		for side in rects:
			var idle: Label = hud._halves[side]["idle"]
			if hud._halves[side]["verdict"].visible:
				continue  # the last lap's verdict has the half
			if not idle.visible:
				problems.append("ui: the empty %s half doesn't say who is next" % side)
			elif idle.size.x < rects[side].size.x * 0.5 or idle.get_line_count() > 2:
				problems.append("ui: the empty %s half's text is %.0f px wide on %d lines" % [side, idle.size.x, idle.get_line_count()])
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

extends SceneTree
## Group start check: a group of racers press Go together (the multiplayer case: 4, 6, 8 phones),
## many trials on both tracks in calm weather. Reports the runs that end early (off the road,
## flipped, stuck in the first EARLY_S seconds), how many of those were bumped just before, and
## how long the last racer of the group waits to be released. The same builds also drive alone,
## so a bad build is not blamed on the crowd.
##   godot --headless --path apps/game --script res://tools/start_crowd_check.gd [-- --trials=40 --sizes=4,6,8 --boost=early|zones|none]
## --boost=early (default): every racer taps its 3 boosts in the first seconds, like excited kids
## (and the sim-players harness); zones: taps on the boost zones; none: no taps.
## Exits 1 if crowd-caused early fails (bumped off, beyond what the same builds do alone) exceed
## MAX_CROWD_FAILS of all runs.
## --boost=onetap: a separate regression check. Random builds drive alone and tap Boost once, off a
## boost zone, at each of --tap-at seconds (default 3,6), in calm and in rain; counts the runs that
## end within EARLY_S and the time the tap costs against the same build not tapping.
##   ... -- --boost=onetap [--builds=200 --tap-at=3,6 --track=village]
## Exits 1 if the fails exceed MAX_ONETAP_FAILS for that weather.

const Course = preload("res://sim/course.gd")
const VillageCourse = preload("res://sim/village_course.gd")
const Sim = preload("res://sim/sim.gd")
const Racer = preload("res://sim/racer.gd")
const Builds = preload("res://sim/builds.gd")
const Messages = preload("res://net/messages.gd")
const Tuning = preload("res://sim/tuning.gd")

const EARLY_S := 15.0
const START_S := 4.0            # "start bumps": contacts this soon after Go
const MAX_CROWD_FAILS := 0.02
const MAX_ONETAP_FAILS := {"calm": 0.02, "rain": 0.10}
const ONETAP_WEATHER := {"calm": 0.0, "rain": 1.0}

var boost_mode := "early"


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var trials := int(args.get("trials", "40"))
	boost_mode = String(args.get("boost", "early"))
	var sizes: Array = Array(String(args.get("sizes", "4,6,8")).split(",")).map(func(s): return int(s))
	var village := VillageCourse.new()
	if not village.errors.is_empty():
		print("FAIL village course: ", "; ".join(village.errors))
		quit(1)
		return
	var worst := 0.0
	var tracks := [["countryside", Course.new()], ["village", village]]
	if args.has("track"):
		tracks = tracks.filter(func(t): return t[0] == args["track"])
	if boost_mode == "onetap":
		var taps_at: Array = Array(String(args.get("tap-at", "3,6")).split(",")).map(func(s): return float(s))
		var ok := true
		for track in tracks:
			for at in taps_at:
				for w in ONETAP_WEATHER:
					ok = _one_tap(track[0], track[1], int(args.get("builds", "200")), at, w) and ok
		print("ONE-TAP CHECK PASSED" if ok else "ONE-TAP CHECK FAILED")
		quit(0 if ok else 1)
		return
	for track in tracks:
		for n in sizes:
			var r := _group(track[0], track[1], n, trials)
			worst = maxf(worst, r)
	if worst > MAX_CROWD_FAILS:
		print("START CROWD CHECK FAILED: %.1f%% of runs bumped off early (max %.1f%%)" % [worst * 100.0, MAX_CROWD_FAILS * 100.0])
		quit(1)
		return
	print("START CROWD CHECK PASSED")
	quit(0)


## Returns the share of runs that fail early because of the crowd.
func _group(track: String, course, n: int, trials: int) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + n
	var runs := 0
	var early := 0
	var early_bumped := 0
	var solo_early := 0
	var reasons := {}
	var release_last := 0.0
	var bumps := 0
	var start_bumps := 0
	var start_loss := 0
	for t in trials:
		var builds: Array = []
		for i in n:
			builds.append(Builds.random_build(rng))
		var out := _drive(course, builds, 500 + t, true)
		runs += n
		early += out["early"]
		early_bumped += out["early_bumped"]
		bumps += out["bumps"]
		start_bumps += out["start_bumps"]
		start_loss += out["start_loss"]
		release_last += out["release_last"]
		for k in out["reasons"]:
			reasons[k] = int(reasons.get(k, 0)) + int(out["reasons"][k])
		for b in builds:
			solo_early += _drive(course, [b], 500 + t, false)["early"]
	var crowd := maxf(0.0, float(early_bumped) - float(solo_early)) / float(runs)
	print("%-11s %d at once: %3d runs · early fails %d (%.1f%%), %d right after a bump · same builds alone %d · bumps/run %.1f, in the first %.0f s %.2f (%.2f s lost/run) · last released after %.2f s · %s" % [
		track, n, runs, early, 100.0 * early / runs, early_bumped, solo_early, float(bumps) / runs, START_S,
		float(start_bumps) / runs, start_loss / 1000.0 / runs, release_last / trials, reasons])
	return crowd


func _drive(course, builds: Array, seed_: int, crowd: bool) -> Dictionary:
	var cfg: Dictionary = Messages.default_config()
	cfg["lapsPerRun"] = 1
	var sim := Sim.new(course, cfg, seed_)
	sim.emit_messages = false
	sim.weather.force(0.0, 0.0, 600.0)
	var mine := {}
	var taps := {}  # runId -> ticks after its release at which it taps Boost
	var trng := RandomNumberGenerator.new()
	trng.seed = seed_ * 31 + builds.size()
	for i in builds.size():
		mine["r%d" % i] = sim.add_run("r%d" % i, "p%d" % i, builds[i], Tuning.DEFAULT_SIZE)
		taps["r%d" % i] = [int((1.5 + trng.randf() * 2.0) * Tuning.HZ), int((8.0 + trng.randf() * 2.0) * Tuning.HZ), int((14.0 + trng.randf() * 2.0) * Tuning.HZ)]
	var out := {"early": 0, "early_bumped": 0, "bumps": 0, "start_bumps": 0, "start_loss": 0, "release_last": 0.0, "reasons": {}}
	var released := 0
	# The start countdown (config.startCountdownMs) holds the group on the grid first: the early
	# and start windows count from the first release (green), the last release from Go.
	var go := -1
	var countdown_s := float(cfg.get("startCountdownMs", 0)) / 1000.0
	for t in int((EARLY_S + countdown_s + 2.0) * Tuning.HZ):
		if go >= 0 and t - go >= int(EARLY_S * Tuning.HZ):
			break
		for o in sim.racers:
			var r: Racer = o
			if boost_mode == "early" and (taps[r.run_id] as Array).has(r.ticks):
				r.boost(sim)
			elif boost_mode == "zones" and r.boosts_left > 0 and r.boost_t <= 0.0 and not r.airborne and Course.in_ranges(r.seg["boosts"], r.ls):
				r.boost(sim)
		sim.step()
		for m in sim.outbox:
			var p: Dictionary = m["payload"]
			match m["type"]:
				"game.run.started":
					if go < 0:
						go = t
					released += 1
					if released == builds.size():
						out["release_last"] = t / float(Tuning.HZ)
				"sim.bump":
					out["bumps"] += 1
					if go >= 0 and t - go < START_S * Tuning.HZ:
						out["start_bumps"] += 1
				"game.run.failed":
					out["early"] += 1
					var r: Racer = mine[p["runId"]]
					var k := "%s@%s" % [p["reason"], p["section"]]
					out["reasons"][k] = int(out["reasons"].get(k, 0)) + 1
					if r.bumped_t > 0.0:
						out["early_bumped"] += 1
		sim.outbox.clear()
		if sim.active_count() == 0:
			break
	# Time the bumps at the start cost (the racers' own "bumped" events in the first START_S).
	for id in mine:
		for e in (mine[id] as Racer).events:
			if e["kind"] == "bumped" and int(e["atMs"]) < START_S * 1000.0:
				out["start_loss"] += int(e.get("timeLostMs", 0))
	if not crowd:
		out["early_bumped"] = out["early"]
	return out


## One off-zone Boost tap per build, alone. Returns false if too many runs end early.
func _one_tap(track: String, course, n: int, at: float, weather: String) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7000
	var fails := 0
	var fails_no_tap := 0
	var reasons := {}
	var styles := {}
	var lost: Array = []
	var slips := 0
	for i in n:
		var b := Builds.random_build(rng)
		var base := _drive_one(course, b, 900 + i, weather, -1.0)
		var tap := _drive_one(course, b, 900 + i, weather, at)
		fails_no_tap += 1 if base["failed"] != "" else 0
		if tap["failed"] != "":
			fails += 1
			reasons[tap["failed"]] = int(reasons.get(tap["failed"], 0)) + 1
			styles[b["style"]] = int(styles.get(b["style"], 0)) + 1
		elif base["failed"] == "" and tap["tapped"]:
			# Distance short of the untapped run at EARLY_S, in seconds at the untapped speed.
			lost.append((base["gs"] - tap["gs"]) / maxf(1.0, base["v"]))
		slips += 1 if tap["slipped"] else 0
	lost.sort()
	var share := float(fails) / n
	var ok := share <= float(MAX_ONETAP_FAILS[weather])
	var med: float = lost[lost.size() / 2] if not lost.is_empty() else NAN
	var p90: float = lost[int(lost.size() * 0.9)] if not lost.is_empty() else NAN
	print("%-11s one tap at %.0f s, %-4s: fails %3d/%d (%.1f%%, max %.0f%%) · no tap %d · %s %s · time vs no tap: median %+.2f s, p90 %+.2f s · slipped %d%s" % [
		track, at, weather, fails, n, 100.0 * share, 100.0 * float(MAX_ONETAP_FAILS[weather]), fails_no_tap,
		reasons, styles, med, p90, slips, "" if ok else "  <-- FAIL"])
	return ok


## Drives one build alone for EARLY_S. tap_at < 0: no tap; otherwise taps Boost at the first
## tick from tap_at seconds after its release that is off every boost zone and on the ground.
func _drive_one(course, build: Dictionary, seed_: int, weather: String, tap_at: float) -> Dictionary:
	var cfg: Dictionary = Messages.default_config()
	cfg["lapsPerRun"] = 1
	cfg["startCountdownMs"] = 0  # released at once: EARLY_S and tap_at count from Go
	var sim := Sim.new(course, cfg, seed_)
	sim.emit_messages = false
	sim.weather.force(float(ONETAP_WEATHER[weather]), 0.0, 600.0)
	var r: Racer = sim.add_run("r0", "p0", build, Tuning.DEFAULT_SIZE)
	var out := {"failed": "", "tapped": false, "slipped": false, "gs": 0.0, "v": 0.0}
	for t in int(EARLY_S * Tuning.HZ):
		if tap_at >= 0.0 and not out["tapped"] and r.is_active() and r.ticks >= int(tap_at * Tuning.HZ) \
				and not r.airborne and not Course.in_ranges(r.seg["boosts"], r.ls):
			r.boost(sim)
			out["tapped"] = true
		sim.step()
		if out["tapped"] and r.slipping:
			out["slipped"] = true
		for m in sim.outbox:
			if m["type"] == "game.run.failed":
				out["failed"] = "%s@%s" % [m["payload"]["reason"], m["payload"]["section"]]
		sim.outbox.clear()
		if sim.active_count() == 0:
			break
	out["gs"] = r.gs()
	out["v"] = r.v
	return out

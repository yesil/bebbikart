extends SceneTree
## Headless lap test for the village loop (sim/village_course.gd):
##   godot --headless --path apps/game --script res://tools/village_laps.gd [-- --laps=3 --builds=40]
## Prints lap times per route and weather, random-build fail rates and a crowd run, and exits 1
## when the loop is broken: a default build fails in calm weather, a run's laps or payloads are
## inconsistent (stretch times that don't add up to the lap within a tick, contracts §2d), or the
## crowd run jams. Countryside runs get the same stretch checks (_countryside).

const VillageCourse = preload("res://sim/village_course.gd")
const Course = preload("res://sim/course.gd")
const Tuning = preload("res://sim/tuning.gd")
const Sim = preload("res://sim/sim.gd")
const Racer = preload("res://sim/racer.gd")
const Builds = preload("res://sim/builds.gd")
const Messages = preload("res://net/messages.gd")

const WEATHERS := {"calm": [0.0, 0.0], "rain": [1.0, 0.0], "wind": [0.0, 0.8], "storm": [1.0, 0.8]}

var course: VillageCourse
var cfg: Dictionary
var fails: PackedStringArray = []


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	course = VillageCourse.new()
	if not course.errors.is_empty():
		for e in course.errors:
			print("FAIL course: ", e)
		quit(1)
		return
	cfg = Messages.default_config()
	cfg["lapsPerRun"] = int(args.get("laps", "3"))
	_routes()
	_random(int(args.get("builds", "40")))
	_crowd()
	_countryside()
	if fails.is_empty():
		print("LAP CHECKS PASSED")
		quit(0)
	else:
		for f in fails:
			print("  FAIL ", f)
		print("LAP CHECKS FAILED: %d" % fails.size())
		quit(1)


## Runs builds in one world, perfect boosts. Returns per run {laps, best, reason, finished}.
func run_group(builds: Array, weather: String, seed_: int, collisions: bool, launch_gap_ticks := 0) -> Array:
	var sim := Sim.new(course, cfg, seed_)
	sim.collisions_enabled = collisions
	var w: Array = WEATHERS[weather]
	sim.weather.force(w[0], w[1], float(seed_ * 37 % 360))
	var ids: Array[String] = []
	for i in builds.size():
		ids.append("r%d" % i)
	var results := {}
	var lap_msgs := {}
	var added := 0
	var guard := 0
	while results.size() < ids.size() and guard < 60 * 600:
		if added < ids.size() and guard >= added * launch_gap_ticks:
			sim.add_run(ids[added], "p%d" % added, builds[added])
			added += 1
		guard += 1
		for r in sim.racers:
			var rc: Racer = r
			if rc.boosts_left > 0 and rc.boost_t <= 0.0 and not rc.airborne and Course.in_ranges(rc.seg["boosts"], rc.ls):
				rc.boost(sim)
		sim.step()
		for m in sim.outbox:
			var p: Dictionary = m["payload"]
			_check_stretches("village", m["type"], p)
			match m["type"]:
				"game.run.lap":
					lap_msgs[p["runId"]] = int(lap_msgs.get(p["runId"], 0)) + 1
				"game.run.finished":
					results[p["runId"]] = {"finished": true, "laps": p["laps"], "best": int(p["bestLapMs"]), "reason": "",
						"trace": (p["trace"]["samples"] as Array).size(), "splits": p["splits"]}
				"game.run.failed":
					results[p["runId"]] = {"finished": false, "laps": p["laps"], "best": int(p.get("bestLapMs", -1)),
						"reason": "%s@%s" % [p["reason"], p["section"]]}
		sim.outbox.clear()
	var out: Array = []
	for id in ids:
		if not results.has(id):
			fails.append("%s never ended (jam?)" % id)
			out.append({"finished": false, "laps": [], "best": -1, "reason": "guard"})
			continue
		var res: Dictionary = results[id]
		if (res["laps"] as Array).size() != int(lap_msgs.get(id, 0)):
			fails.append("%s: %d lap messages but %d laps in the result" % [id, lap_msgs.get(id, 0), res["laps"].size()])
		if res["finished"]:
			if (res["laps"] as Array).size() != int(cfg["lapsPerRun"]):
				fails.append("%s finished after %d laps, expected %d" % [id, res["laps"].size(), cfg["lapsPerRun"]])
			if int(res["trace"]) == 0 or (res["splits"] as Dictionary).size() != 4:
				fails.append("%s: best-lap trace or splits missing" % id)
		out.append(res)
	return out


func _routes() -> void:
	print("== Default stars, balanced, solo: best lap / all laps (s) ==")
	var lens := course.all_route_lengths()
	for key in lens:
		var parts: PackedStringArray = key.split("/")
		var b := Builds.default_build()
		b["routes"] = {"ramp": parts[0], "pond": parts[1], "crossing": parts[2]}
		var line := "%-24s %5.0f m " % [key, lens[key]]
		for wname in WEATHERS:
			var res: Dictionary = run_group([b], wname, 11, false)[0]
			if res["finished"]:
				line += " %s %5.2f" % [wname, res["best"] / 1000.0]
			else:
				line += " %s FAIL(%s)" % [wname, res["reason"]]
				if wname == "calm":
					fails.append("default build %s fails in calm: %s" % [key, res["reason"]])
		print(line)


func _random(n: int) -> void:
	print("== Random builds, solo (best lap median, fail rate) ==")
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var builds: Array = []
	for i in n:
		builds.append(Builds.random_build(rng))
	for wname in WEATHERS:
		var times: Array[float] = []
		var failed := 0
		var reasons := {}
		for i in n:
			var res: Dictionary = run_group([builds[i]], wname, 100 + i, false)[0]
			if res["finished"]:
				times.append(res["best"] / 1000.0)
			else:
				failed += 1
				reasons[res["reason"]] = int(reasons.get(res["reason"], 0)) + 1
		times.sort()
		var med: float = times[times.size() / 2] if not times.is_empty() else -1.0
		print("%-6s median best lap %5.2f s  range %5.2f..%5.2f  fails %d/%d %s" % [wname, med,
			times[0] if not times.is_empty() else -1.0, times[-1] if not times.is_empty() else -1.0, failed, n,
			JSON.stringify(reasons)])


func _crowd() -> void:
	print("== Crowd: 20 random builds, one every 1.5 s, collisions on, calm ==")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var builds: Array = []
	for i in 20:
		builds.append(Builds.random_build(rng))
	var res := run_group(builds, "calm", 7, true, 90)
	var done := 0
	var reasons := {}
	for r in res:
		if r["finished"]:
			done += 1
		else:
			reasons[r["reason"]] = int(reasons.get(r["reason"], 0)) + 1
	print("finished %d/20, fails %s" % [done, JSON.stringify(reasons)])


## Stretch payloads (contracts §2d): known ids of the track, the times of a lap (or a finished
## point-to-point run) add up to it within a tick, a fail names its stretch, every event has one.
func _check_stretches(track: String, type: String, p: Dictionary) -> void:
	if type not in ["game.run.lap", "game.run.finished", "game.run.failed"]:
		return
	var known := {}
	for st in Protocol.TRACK_STRETCHES[track]:
		known[st["id"]] = true
	var tag := "%s %s %s" % [track, type, p["runId"]]
	if not p.has("stretches"):
		fails.append("%s: no stretches" % tag)
		return
	var sum := 0
	for st in p["stretches"]:
		if not known.has(st["id"]):
			fails.append("%s: unknown stretch %s" % [tag, st["id"]])
		sum += int(st["ms"])
	var whole := -1
	if type == "game.run.lap":
		whole = int(p["lapMs"])
	elif type == "game.run.finished":
		whole = int(p["bestLapMs"]) if p.has("bestLapMs") else int(p["elapsedMs"])
	if whole >= 0 and absi(sum - whole) > int(ceil(1000.0 / Tuning.HZ)):
		fails.append("%s: stretches add up to %d ms, the lap is %d ms" % [tag, sum, whole])
	if type == "game.run.failed" and not known.has(p.get("stretch", "")):
		fails.append("%s: fail without a known stretch (%s)" % [tag, p.get("stretch", "none")])
	if type != "game.run.lap":
		for e in p["events"]:
			if not known.has(e.get("stretch", "")):
				fails.append("%s: event %s without a known stretch" % [tag, e["kind"]])


## The countryside (point to point) reports stretches the same way: random builds, all weathers.
func _countryside() -> void:
	var c := Course.new()
	if not c.errors.is_empty():
		fails.append("countryside course: %s" % "; ".join(c.errors))
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var n := 0
	for i in 12:
		var b := Builds.random_build(rng)
		for wname in WEATHERS:
			var w: Array = WEATHERS[wname]
			var sim := Sim.new(c, cfg, 300 + i)
			sim.weather.force(w[0], w[1], 45.0)
			sim.add_run("c%d" % i, "p0", b)
			for t in 60 * 120:
				sim.step()
				for m in sim.outbox:
					_check_stretches("countryside", m["type"], m["payload"])
					if m["type"] in ["game.run.finished", "game.run.failed"]:
						n += 1
				sim.outbox.clear()
				if sim.active_count() == 0:
					break
	print("== Countryside stretches: %d runs checked ==" % n)

extends SceneTree
## Chocolate coins check (sim/coins.gd): two karts at a time race laps of the village like the
## duel (solo), in calm weather, with the same builds and seeds, each driver without coins (its
## baseline lap) and with them:
##   hands  hands off: the autopilot doesn't go for them;
##   kid    Racer.bot_steer: onto the boost arrows and the coins, the stars' ways.
## Reports per lap: time and what the coins change, coins and whole lines taken. Also lays 500
## laps of coins and checks each: the full number of lines, every coin inside the rails, none in
## the run-in to a fork or on a boost strip.
##   godot --headless --path apps/game --script res://tools/coin_check.gd [-- --trials=20 --laps=3]
## Exits 1 on a bad layout, if a kid collecting them isn't faster than without them, or if hands
## off takes more than MAX_HANDS_SHARE of the coins.

const VillageCourse = preload("res://sim/village_course.gd")
const Course = preload("res://sim/course.gd")
const Sim = preload("res://sim/sim.gd")
const Builds = preload("res://sim/builds.gd")
const Messages = preload("res://net/messages.gd")
const Coins = preload("res://sim/coins.gd")
const Tuning = preload("res://sim/tuning.gd")

const MODES := ["hands", "kid"]
const MAX_HANDS_SHARE := 0.35
const FORK_CLEAR_M := 44.0
const SECOND_KART_S := 9.0


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var trials := int(args.get("trials", "20"))
	var laps := int(args.get("laps", "3"))
	var course := VillageCourse.new()
	if not course.errors.is_empty():
		print("FAIL village course: ", "; ".join(course.errors))
		quit(1)
		return
	var problems: PackedStringArray = []
	var layout := Coins.new(course)
	var bad := layout.check()
	if bad != "":
		problems.append(bad)
	problems.append_array(_check_layouts(course, layout))
	var res := {}
	for mode in MODES:
		res[mode + "_off"] = _run_mode(course, mode, false, trials, laps)
		res[mode] = _run_mode(course, mode, true, trials, laps)
	print("")
	print("driver     laps   lap s  +s/lap  coins/lap  lines/lap  fails")
	for mode in MODES:
		for key in [mode + "_off", mode]:
			var r: Dictionary = res[key]
			print("%-9s  %4d  %6.2f  %+6.2f  %9.1f  %9.2f  %s" % [key, r["laps"], _lap_s(r), _lap_s(r) - _lap_s(res[mode + "_off"]),
				_per_lap(r, "coins"), _per_lap(r, "lines"), JSON.stringify(r["fails"])])
	var per_lap := Coins.LINES * Coins.PER_LINE
	if _lap_s(res["kid"]) >= _lap_s(res["kid_off"]):
		problems.append("a kid collecting coins is no faster (%.2f s) than without them (%.2f s)" % [_lap_s(res["kid"]), _lap_s(res["kid_off"])])
	if _per_lap(res["hands"], "coins") > MAX_HANDS_SHARE * per_lap:
		problems.append("hands off takes %.1f of %d coins a lap" % [_per_lap(res["hands"], "coins"), per_lap])
	for mode in MODES:
		var base: Dictionary = res[mode + "_off"]["fails"]
		for reason in res[mode]["fails"]:
			if int(res[mode]["fails"][reason]) > int(base.get(reason, 0)):
				problems.append("%s: %d %s fails (%d without coins)" % [mode, res[mode]["fails"][reason], reason, base.get(reason, 0)])
	if not problems.is_empty():
		print("COIN CHECK FAILED: ", "; ".join(problems))
		quit(1)
		return
	print("COIN CHECK PASSED")
	quit(0)


func _check_layouts(course, layout) -> PackedStringArray:
	var out: PackedStringArray = []
	var path: Array = course.path_for({})
	for i in 500:
		var coins: Array = layout.lay(i * 31 + 7, path)
		var lines := {}
		for c in coins:
			lines[int(c["line"])] = true
			var seg: Dictionary = course.segments[c["seg"]]
			if absf(float(c["d"])) > Course.rail_lim(seg):
				out.append("lap %d: a coin outside the rails on %s (d %.2f)" % [i, c["seg"], c["d"]])
			for b in seg["boosts"]:
				if float(c["s"]) >= float(b[0]) - 2.0 and float(c["s"]) <= float(b[1]) + 2.0:
					out.append("lap %d: a coin on the boost strip of %s" % [i, c["seg"]])
			var k := path.find(c["seg"])
			if k < path.size() - 1 and String(course.segments[path[k + 1]]["fork"]) != "" \
					and (seg["route"].length - float(c["s"])) < FORK_CLEAR_M:
				out.append("lap %d: a coin %.1f m before a fork on %s" % [i, seg["route"].length - float(c["s"]), c["seg"]])
		if lines.size() != Coins.LINES:
			out.append("lap %d: %d lines, not %d" % [i, lines.size(), Coins.LINES])
		if not out.is_empty():
			break
	return out


func _lap_s(r: Dictionary) -> float:
	return float(r["lap_ms"]) / maxi(1, int(r["laps"])) / 1000.0


func _per_lap(r: Dictionary, key: String) -> float:
	return float(r[key]) / maxi(1, int(r["laps"]))


func _run_mode(course, mode: String, coins_on: bool, trials: int, laps: int) -> Dictionary:
	var out := {"laps": 0, "lap_ms": 0, "coins": 0, "lines": 0, "fails": {}}
	for t in trials:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7000 + t
		var cfg := Messages.default_config()
		cfg["startCountdownMs"] = 0
		cfg["lapsPerRun"] = laps
		var sim := Sim.new(course, cfg, 500 + t)
		sim.solo = true
		sim.emit_messages = false
		sim.weather.force(0.0, 0.0, 100000.0)
		if coins_on:
			sim.coins = Coins.new(course)
		var racers: Array = [null, null]
		var tick := 0
		var limit := int((laps * 75.0 + SECOND_KART_S + 10.0) * Tuning.HZ)
		while tick < limit:
			tick += 1
			if tick == 1 or tick == int(SECOND_KART_S * Tuning.HZ):
				var k := 0 if tick == 1 else 1
				racers[k] = sim.add_run("r%d" % k, "p%d" % k, Builds.random_build(rng), Tuning.DEFAULT_SIZE)
			for r in racers:
				if r != null and r.state == "racing" and mode == "kid":
					r.bot_steer()
			sim.step()
			for m in sim.outbox:
				if m["type"] == "sim.coin" and m["payload"]["lineDone"]:
					out["lines"] += 1
			sim.outbox.clear()
			var busy := false
			for r in racers:
				if r == null or r.state == "racing" or r.state == "queued":
					busy = true
			if not busy:
				break
		for r in racers:
			if r == null:
				continue
			out["laps"] += r.laps.size()
			for ms in r.laps:
				out["lap_ms"] += ms
			out["coins"] += r.coins_run
			if r.state == "failed":
				out["fails"][r.fail_reason] = int(out["fails"].get(r.fail_reason, 0)) + 1
			elif r.state == "racing":
				out["fails"]["unfinished"] = int(out["fails"].get("unfinished", 0)) + 1
	return out

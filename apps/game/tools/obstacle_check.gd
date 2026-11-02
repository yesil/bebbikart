extends SceneTree
## Village surprises check (sim/obstacles.gd): two karts at a time race laps of the village like
## the duel (solo: they pass through each other), in calm weather, with the same builds and seeds
## for three drivers, each without the surprises (its baseline lap) and with them:
##   hands  hands off: the autopilot slows and steers round them;
##   kid    Racer.bot_steer: onto the boost arrows, the stars' ways, round the surprises;
##   wild   a thumb swiping to random lanes and holding them (never looks out for them).
## Reports per lap: time and what the surprises add to it, surprises met, hits (by kind), the time
## the `obstacle` events say they cost; and the run fails.
##   godot --headless --path apps/game --script res://tools/obstacle_check.gd [-- --trials=30 --laps=3]
## Exits 1 if a surprise leaves no way past (a hands-off or kid hit rate above MAX_CAREFUL_HITS of
## the surprises met), if surprises make runs fail that don't without them, if a wild thumb never
## hits one (then they aren't in the way at all), if a hit costs less than the autopilot's careful
## pass (then nobody needs to steer), or if fewer than one is met per lap.

const VillageCourse = preload("res://sim/village_course.gd")
const Sim = preload("res://sim/sim.gd")
const Racer = preload("res://sim/racer.gd")
const Builds = preload("res://sim/builds.gd")
const Messages = preload("res://net/messages.gd")
const Obstacles = preload("res://sim/obstacles.gd")
const Tuning = preload("res://sim/tuning.gd")

const MODES := ["hands", "kid", "wild"]
const MAX_CAREFUL_HITS := 0.05
const SWIPE_S := Vector2(0.6, 2.0)
const SECOND_KART_S := 9.0       # the other half's kart leaves this much later


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var trials := int(args.get("trials", "30"))
	var laps := int(args.get("laps", "3"))
	debug = args.has("debug")
	var course := VillageCourse.new()
	if not course.errors.is_empty():
		print("FAIL village course: ", "; ".join(course.errors))
		quit(1)
		return
	var bad := Obstacles.new(course, 1).check()
	if bad != "":
		print("FAIL obstacle spots: ", bad)
		quit(1)
		return
	var res := {}
	for mode in MODES:
		res[mode + "_off"] = _run_mode(course, mode, false, trials, laps)
		res[mode] = _run_mode(course, mode, true, trials, laps)
	print("")
	print("driver     laps   lap s  +s/lap  met/lap  hits/lap  hit%  lost s/lap  fails  hits by kind")
	for mode in MODES:
		for key in [mode + "_off", mode]:
			var r: Dictionary = res[key]
			print("%-9s  %4d  %6.2f  %+6.2f  %7.2f  %8.2f  %3.0f%%  %10.2f  %s  %s" % [key, r["laps"], _lap_s(r),
				_lap_s(r) - _lap_s(res[mode + "_off"]), _per_lap(r, "met"), _per_lap(r, "hits"),
				100.0 * float(r["hits"]) / maxf(1.0, float(r["met"])), _per_lap(r, "lost_ms") / 1000.0,
				JSON.stringify(r["fails"]), JSON.stringify(r["by_kind"])])
	# From the `obstacle` events (what the coach sees): the lap times of random thumbs are too
	# noisy to price one hit.
	var per_hit := float(res["wild"]["lost_ms"]) / 1000.0 / maxf(1.0, float(res["wild"]["hits"]))
	var per_care := float(res["hands"]["lost_ms"]) / 1000.0 / maxf(1.0, float(res["hands"]["met"]))
	print("a hit costs about %.2f s, the autopilot's careful pass %.2f s" % [per_hit, per_care])
	var problems: PackedStringArray = []
	for mode in ["hands", "kid"]:
		var rate := float(res[mode]["hits"]) / maxf(1.0, float(res[mode]["met"]))
		if rate > MAX_CAREFUL_HITS:
			problems.append("%s: %.0f%% of the surprises met were hit (max %.0f%%)" % [mode, rate * 100.0, MAX_CAREFUL_HITS * 100.0])
	for mode in MODES:
		var base: Dictionary = res[mode + "_off"]["fails"]
		for reason in res[mode]["fails"]:
			if int(res[mode]["fails"][reason]) > int(base.get(reason, 0)):
				problems.append("%s: %d %s fails (%d without surprises)" % [mode, res[mode]["fails"][reason], reason, base.get(reason, 0)])
	if int(res["wild"]["hits"]) == 0:
		problems.append("wild thumbs never hit a surprise: they are not in the way")
	elif per_hit <= per_care:
		problems.append("a hit (%.2f s) costs no more than the autopilot's careful pass (%.2f s)" % [per_hit, per_care])
	if _per_lap(res["hands"], "met") < 1.0:
		problems.append("fewer than one surprise met per lap")
	if not problems.is_empty():
		print("OBSTACLE CHECK FAILED: ", "; ".join(problems))
		quit(1)
		return
	print("OBSTACLE CHECK PASSED")
	quit(0)


func _lap_s(r: Dictionary) -> float:
	return float(r["lap_ms"]) / maxi(1, int(r["laps"])) / 1000.0


func _per_lap(r: Dictionary, key: String) -> float:
	return float(r[key]) / maxi(1, int(r["laps"]))


var debug := false


func _run_mode(course, mode: String, surprises: bool, trials: int, laps: int) -> Dictionary:
	var out := {"laps": 0, "lap_ms": 0, "met": 0, "hits": 0, "lost_ms": 0, "fails": {}, "by_kind": {}}
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
		if surprises:
			sim.obstacles = Obstacles.new(course, 900 + t)
		var racers: Array = [null, null]
		var swipe := {}
		var seen := {}
		var tick := 0
		var limit := int((laps * 75.0 + SECOND_KART_S + 10.0) * Tuning.HZ)
		while tick < limit:
			tick += 1
			if tick == 1 or tick == int(SECOND_KART_S * Tuning.HZ):
				var k := 0 if tick == 1 else 1
				racers[k] = sim.add_run("r%d" % k, "p%d" % k, Builds.random_build(rng), Tuning.DEFAULT_SIZE)
			for r in racers:
				if r == null or r.state != "racing":
					continue
				match mode:
					"kid":
						r.bot_steer()
					"wild":
						var left := float(swipe.get(r.run_id, 0.0)) - Tuning.DT
						if left <= 0.0:
							left = rng.randf_range(SWIPE_S.x, SWIPE_S.y)
							r.set_steer(rng.randf_range(-1.0, 1.0))
						swipe[r.run_id] = left
				if sim.obstacles != null:
					for it in sim.obstacles.items:
						if it["seg"] == r.seg_id and absf(r.ls - float(it["s"])) < 2.0 and sim.obstacles.hittable(it):
							seen["%s:%d" % [r.run_id, int(it["group"])]] = true
			sim.step()
			for m in sim.outbox:
				if m["type"] == "sim.obstacle":
					var kind: String = m["payload"]["kind"]
					out["by_kind"][kind] = int(out["by_kind"].get(kind, 0)) + 1
					if debug and mode != "wild":
						var hr = sim.by_run.get(m["payload"]["runId"])
						var it: Dictionary = {}
						for o in sim.obstacles.items:
							if int(o["id"]) == int(m["payload"]["item"]):
								it = o
						print("HIT %s trial %d %s on %s s=%.1f d=%.2f target=%.2f v=%.1f steer=%s | item s=%.1f d=%.2f rel=%.2f hd=%.2f hs=%.2f" % [
							mode, t, kind, hr.seg_id, hr.ls, hr.d, hr.d_target, hr.v, hr.kid_steering(), float(it.get("s", 0)), float(it.get("d", 0)),
							float(it.get("rel", 0)), Obstacles.half_d(it) if not it.is_empty() else 0.0, Obstacles.half_s(it) if not it.is_empty() else 0.0])
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
			out["hits"] += r.obstacles_hit
			for e in r.events:
				if e["kind"] == "obstacle":
					out["lost_ms"] += int(e.get("timeLostMs", 0))
			if r.state == "failed":
				out["fails"][r.fail_reason] = int(out["fails"].get(r.fail_reason, 0)) + 1
			elif r.state == "racing":
				out["fails"]["unfinished"] = int(out["fails"].get("unfinished", 0)) + 1
		out["met"] += seen.size()
	return out

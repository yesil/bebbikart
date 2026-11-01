extends SceneTree
## Group start check: a group of racers press Go together (the multiplayer case: 4, 6, 8 phones),
## many trials on both tracks in calm weather. Reports the runs that end early (off the road,
## flipped, stuck in the first EARLY_S seconds), how many of those were bumped just before, and
## how long the last racer of the group waits to be released. The same builds also drive alone,
## so a bad build is not blamed on the crowd.
##   godot --headless --path apps/game --script res://tools/start_crowd_check.gd [-- --trials=40 --sizes=4,6,8 --steer=wild|kid|off]
## --steer=wild (default): every racer's thumb swipes to random lanes three times in the first
## seconds, like excited kids; kid: Racer.bot_steer (onto the boost arrows, the stars' ways); off:
## hands off.
## Exits 1 if crowd-caused early fails (bumped off, beyond what the same builds do alone) exceed
## MAX_CROWD_FAILS of all runs.

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
const STEER_MODES := ["wild", "kid", "off"]
const SWIPE_S := 1.0            # a wild swipe holds its lane this long, then lets go

var steer_mode := "wild"


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var trials := int(args.get("trials", "40"))
	steer_mode = String(args.get("steer", "wild"))
	if not steer_mode in STEER_MODES:
		push_error("start_crowd_check: --steer must be one of %s" % [STEER_MODES])
		quit(1)
		return
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
	var swipes := {}  # runId -> [[tick after its release, lane], ...]: wild thumbs
	var trng := RandomNumberGenerator.new()
	trng.seed = seed_ * 31 + builds.size()
	for i in builds.size():
		mine["r%d" % i] = sim.add_run("r%d" % i, "p%d" % i, builds[i], Tuning.DEFAULT_SIZE)
		var sw: Array = []
		for at in [1.5, 8.0, 14.0]:
			var tick := int((at + trng.randf() * 2.0) * Tuning.HZ)
			sw.append([tick, trng.randf_range(-1.0, 1.0)])
			sw.append([tick + int(SWIPE_S * Tuning.HZ), null])
		swipes["r%d" % i] = sw
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
			if steer_mode == "kid":
				r.bot_steer()
			elif steer_mode == "wild":
				for sw in swipes[r.run_id]:
					if int(sw[0]) == r.ticks:
						r.set_steer(sw[1])
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

extends SceneTree
## Headless balance sweep (game.md task #5).
##   godot --headless --path apps/game --script res://tools/sweep.gd -- --builds=200 --seeds=3
## Options: --builds=N random builds (default 200), --seeds=N repeats per measurement (default 3),
##          --boost=perfect|none, --quick (smaller run), --json=path (dump raw results)
##          --trace=jump:3,ramp:jump[,weather:rain]  run one build and print its splits + events
## Village loop balance (lap 2 of 2, solo, boosts on the zones), a few minutes:
##   godot --headless --path apps/game --script res://tools/sweep.gd -- --track=village [--builds=300 --seeds=3]
## Builds are ranked by their expected lap: the mean over the seeds of the clean lap 2 (slips
## included, a missed exit's extra circle taken out) plus the missed-exit risk priced exactly (the
## racer's chance at the exit x the time of one more circle), a fail counting as a lap of
## runTimeCapMs. Best build per weather (random
## screen + hill-climb: move stars, flip a route, change style), a cross table of those builds in
## every weather, the best build held to each fork choice and to each style with its gap to the
## best, each stretch's 0-vs-10-star gain for the ability it tests, the fork-by-stars tables, fail
## rates and how much slower than calm each weather is.

const Course = preload("res://sim/course.gd")
const Sim = preload("res://sim/sim.gd")
const Racer = preload("res://sim/racer.gd")
const Builds = preload("res://sim/builds.gd")
const Messages = preload("res://net/messages.gd")
const VillageCourse = preload("res://sim/village_course.gd")
const Tuning = preload("res://sim/tuning.gd")
const Route = preload("res://sim/route.gd")

const WEATHERS := {
	"calm": [0.0, 0.0],
	"rain": [1.0, 0.0],
	"wind": [0.0, 0.8],
	"storm": [1.0, 0.8],
}

var course: Course
var cfg: Dictionary
var boost_mode := "perfect"
var seeds := 3
var n_builds := 200
var raw: Array = []


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	n_builds = int(args.get("builds", "200"))
	seeds = int(args.get("seeds", "3"))
	boost_mode = String(args.get("boost", "perfect"))
	if args.has("quick"):
		n_builds = 40
		seeds = 2
	course = Course.new()
	cfg = Messages.default_config()
	var t0 := Time.get_ticks_msec()
	if args.get("track", "countryside") == "village":
		n_builds = int(args.get("builds", "300"))
		seeds = int(args.get("seeds", "3"))
		if not _village():
			quit(1)
			return
		print("\nvillage sweep done in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
		quit()
		return
	if args.has("trace"):
		_trace_one(String(args["trace"]))
		quit()
		return

	_section_routes()
	_section_default()
	_section_styles()
	_section_random()
	_section_forks()
	_section_crowd()

	print("\nsweep done in %.1f s" % ((Time.get_ticks_msec() - t0) / 1000.0))
	if args.has("json"):
		var f := FileAccess.open(String(args["json"]), FileAccess.WRITE)
		f.store_string(JSON.stringify(raw))
	quit()


# ---------------------------------------------------------------- running

## Runs builds simultaneously in one world. Returns [{ms, reason, events, build}].
func run_group(builds: Array, weather: String, seed_: int, collisions: bool) -> Array:
	var sim := Sim.new(course, cfg, seed_)
	sim.collisions_enabled = collisions
	sim.emit_messages = false
	var w: Array = WEATHERS[weather]
	var wrng := RandomNumberGenerator.new()
	wrng.seed = seed_ * 31 + 5
	sim.weather.force(w[0], w[1], wrng.randf_range(0.0, 360.0))
	var ids: Array[String] = []
	for i in builds.size():
		var id := "r%d" % i
		ids.append(id)
		sim.add_run(id, "p%d" % i, builds[i])
	var results := {}
	var racers := {}
	for id in ids:
		racers[id] = sim.by_run[id]
	var guard := 0
	while results.size() < ids.size() and guard < 60 * 120:
		guard += 1
		if boost_mode == "perfect":
			for r in sim.racers:
				var rc: Racer = r
				if rc.boosts_left > 0 and rc.boost_t <= 0.0 and not rc.airborne and Course.in_ranges(rc.seg["boosts"], rc.ls):
					rc.boost(sim)
		sim.step()
		for m in sim.outbox:
			var p: Dictionary = m["payload"]
			if m["type"] == "game.run.finished":
				results[p["runId"]] = {"ms": int(p["elapsedMs"]), "reason": "", "events": p["events"]}
			elif m["type"] == "game.run.failed":
				results[p["runId"]] = {"ms": -1, "reason": p["reason"], "section": p["section"], "events": p["events"]}
		sim.outbox.clear()
	var out: Array = []
	for i in ids.size():
		var res: Dictionary = results.get(ids[i], {"ms": -1, "reason": "guard", "events": []})
		res["build"] = builds[i]
		res["weather"] = weather
		out.append(res)
	return out


## Mean finish time over seeds (solo), plus fail count.
func measure(build: Dictionary, weather: String) -> Dictionary:
	var times: Array[float] = []
	var fails := 0
	var reasons := {}
	for k in seeds:
		var res: Dictionary = run_group([build], weather, 1000 + k * 17, false)[0]
		raw.append({"w": weather, "b": Builds.describe(build), "ms": res["ms"], "reason": res["reason"]})
		if int(res["ms"]) > 0:
			times.append(float(res["ms"]))
		else:
			fails += 1
			var rk := "%s@%s" % [res["reason"], res.get("section", "?")]
			reasons[rk] = int(reasons.get(rk, 0)) + 1
	var mean := -1.0
	if not times.is_empty():
		mean = 0.0
		for t in times:
			mean += t
		mean /= times.size()
	return {"mean": mean, "fails": fails, "n": seeds, "reasons": reasons}


func fmt(m: Dictionary) -> String:
	var s := "  --  " if float(m["mean"]) < 0 else "%6.2f" % (float(m["mean"]) / 1000.0)
	if int(m["fails"]) > 0:
		s += " (%d/%d fail %s)" % [m["fails"], m["n"], ",".join(PackedStringArray(m["reasons"].keys()))]
	return s


# ---------------------------------------------------------------- sections

func _section_routes() -> void:
	print("== Route lengths (m) ==")
	var lens := course.all_route_lengths()
	for k in lens:
		print("  %-26s %6.1f" % [k, lens[k]])
	for id in course.ordered_ids:
		var r = course.segments[id]["route"]
		print("  seg %-16s %6.1f m" % [id, r.length])


func _section_default() -> void:
	print("\n== Default build (%s), solo, boost=%s ==" % [Builds.describe(Builds.default_build()), boost_mode])
	for w in WEATHERS:
		print("  %-6s %s" % [w, fmt(measure(Builds.default_build(), w))])


func _section_styles() -> void:
	print("\n== Driving style (default stars/routes) ==")
	var line := "  %-9s" % ""
	for w in WEATHERS:
		line += "%-24s" % w
	print(line)
	for style in Protocol.DRIVING_STYLES:
		var b := Builds.default_build()
		b["style"] = style
		line = "  %-9s" % style
		for w in WEATHERS:
			line += "%-24s" % fmt(measure(b, w))
		print(line)


func _section_random() -> void:
	print("\n== %d random builds x %d seeds, solo ==" % [n_builds, seeds])
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var builds: Array = []
	for i in n_builds:
		builds.append(Builds.random_build(rng))
	for w in WEATHERS:
		var rows: Array = []
		var fails := 0
		var total := 0
		var reasons := {}
		for b in builds:
			var m := measure(b, w)
			fails += int(m["fails"])
			total += int(m["n"])
			for k in m["reasons"]:
				reasons[k] = int(reasons.get(k, 0)) + int(m["reasons"][k])
			if float(m["mean"]) > 0:
				rows.append([float(m["mean"]), b])
		rows.sort_custom(func(a, b2): return a[0] < b2[0])
		var times: Array = rows.map(func(r): return r[0])
		var med: float = times[times.size() / 2] if not times.is_empty() else -1.0
		print("  [%s] median %.2f s  best %.2f  worst %.2f  fail %.1f%% %s" % [
			w, med / 1000.0, (times[0] if not times.is_empty() else -1.0) / 1000.0,
			(times[times.size() - 1] if not times.is_empty() else -1.0) / 1000.0,
			100.0 * fails / maxi(1, total), reasons])
		for i in mini(5, rows.size()):
			print("      #%d %.2f  %s" % [i + 1, rows[i][0] / 1000.0, Builds.describe(rows[i][1])])


## Build with `stat` = x and the remaining stars spread like the default build.
## `order`: which abilities give or take the difference first.
func _build_with(stat: String, x: int, order: Array = ["speed", "grip", "stability", "jump", "water", "bounce"]) -> Dictionary:
	var b := Builds.default_build()
	var stars: Dictionary = b["stars"]
	stars[stat] = x
	order = order.duplicate()
	order.erase(stat)
	var total := 0
	for a in stars:
		total += int(stars[a])
	var want := int(cfg["starsTotal"])
	var i := 0
	var guard := 0
	while total != want and guard < 400:
		guard += 1
		var a: String = order[i % order.size()]
		if total > want and int(stars[a]) > 0:
			stars[a] = int(stars[a]) - 1
			total -= 1
		elif total < want and int(stars[a]) < int(cfg["starsMaxPerAbility"]):
			stars[a] = int(stars[a]) + 1
			total += 1
		i += 1
	return b


func _section_forks() -> void:
	var forks := [["ramp", "jump", ["jump", "around"]], ["pond", "water", ["water", "bridge"]], ["crossing", "stability", ["exposed", "sheltered"]]]
	for f in forks:
		var fork: String = f[0]
		var stat: String = f[1]
		var choices: Array = f[2]
		print("\n== Fork %s: %s stars 0..%d step 2 (rest default-ish); time %s vs %s, Δ = first - second ==" % [fork, stat, int(cfg["starsMaxPerAbility"]), choices[0], choices[1]])
		for w in WEATHERS:
			var line := "  %-6s" % w
			for x in range(0, int(cfg["starsMaxPerAbility"]) + 1, 2):
				var b := _build_with(stat, x)
				var ma := measure(_with_route(b, fork, choices[0]), w)
				var mb := measure(_with_route(b, fork, choices[1]), w)
				var delta := ""
				if float(ma["mean"]) > 0 and float(mb["mean"]) > 0:
					delta = "%+.2f" % ((float(ma["mean"]) - float(mb["mean"])) / 1000.0)
				else:
					delta = "F%d/%d" % [ma["fails"], mb["fails"]]
				if int(ma["fails"]) > 0 and float(ma["mean"]) > 0:
					delta += "*"
				line += "  %d:%-8s" % [x, delta]
			print(line)


func _with_route(b: Dictionary, fork: String, choice: String) -> Dictionary:
	var c := b.duplicate(true)
	c["routes"][fork] = choice
	return c


func _section_crowd() -> void:
	print("\n== Crowds (random builds released together, calm + storm) ==")
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for size in [1, 6, 16]:
		for w in ["calm", "storm"]:
			var times: Array[float] = []
			var fails := 0
			var bumps := 0
			var n := 0
			for rep in maxi(1, 48 / size):
				var builds: Array = []
				for i in size:
					builds.append(Builds.random_build(rng))
				for res in run_group(builds, w, 7000 + rep, true):
					n += 1
					for e in res["events"]:
						if e["kind"] == "bumped":
							bumps += 1
					if int(res["ms"]) > 0:
						times.append(float(res["ms"]))
					else:
						fails += 1
			times.sort()
			var med: float = times[times.size() / 2] if not times.is_empty() else -1.0
			print("  group %2d %-6s racers %3d  median %.2f s  fail %.1f%%  bumped events/racer %.2f" % [
				size, w, n, med / 1000.0, 100.0 * fails / maxi(1, n), float(bumps) / maxi(1, n)])


func _trace_one(spec: String) -> void:
	var b := Builds.default_build()
	var weather := "calm"
	for part in spec.split(","):
		var kv := part.split(":")
		if kv.size() != 2:
			continue
		if kv[0] == "weather":
			weather = kv[1]
		elif kv[0] == "style":
			b["style"] = kv[1]
		elif b["routes"].has(kv[0]):
			b["routes"][kv[0]] = kv[1]
		else:
			b = _build_with(kv[0], int(kv[1])) if b["stars"].has(kv[0]) else b
	var sim := Sim.new(course, cfg, 1017)
	var w: Array = WEATHERS[weather]
	sim.weather.force(w[0], w[1], 90.0)
	sim.add_run("r0", "p0", b)
	print(Builds.describe(b), "  weather ", weather)
	for i in 60 * 120:
		for r in sim.racers:
			var rc: Racer = r
			if rc.boosts_left > 0 and rc.boost_t <= 0.0 and not rc.airborne and Course.in_ranges(rc.seg["boosts"], rc.ls):
				rc.boost(sim)
		sim.step()
		for m in sim.outbox:
			if m["type"] in ["game.run.section", "game.run.finished", "game.run.failed"]:
				var p: Dictionary = m["payload"].duplicate()
				p.erase("trace")
				print(m["type"], " ", JSON.stringify(p))
		sim.outbox.clear()
		if sim.active_count() == 0 and i > 10:
			break



# ---------------------------------------------------------------- village loop

## Stretches that each test one ability (sim/village_course.gd).
const STRETCHES := [["farm", "grip"], ["cobbles", "bounce"], ["ridge", "stability"], ["alpbach", "water"]]
const FORK_STAT := {"ramp": "jump", "pond": "water", "crossing": "stability"}
const MIN_GAIN_MS := 20.0          # hill-climb: smaller gains are noise

var village
var vcfg: Dictionary
var vcache := {}                   # "weather|build" -> measurement
var vbroken := false               # the sim failed to load: stop, print nothing more


## One solo run of two laps; times the second lap (and each segment in it).
func vrun(build: Dictionary, weather: String, k: int) -> Dictionary:
	var sim := Sim.new(village, vcfg, 1000 + k * 17)
	sim.collisions_enabled = false
	sim.emit_messages = false
	var w: Array = WEATHERS[weather]
	# Wind from evenly spread directions over the seeds, so every build meets the same gusts.
	sim.weather.force(w[0], w[1], fposmod(40.0 + 360.0 * k / maxf(1.0, seeds), 360.0))
	var r: Racer = sim.add_run("r0", "p0", build)
	if r == null:
		push_error("sweep: the sim did not create a racer (script error above?)")
		vbroken = true
		return {"ms": -1.0, "seg": {}, "reason": "no_racer", "missed": false}
	var seg_ms := {}
	var cur := ""
	var cur_t := 0
	var detour_ticks := 0
	var risk_ms := 0.0
	var loop_len: float = (village.segments["roundabout_loop"]["route"] as Route).length
	for i in 60 * 400:
		if r.boosts_left > 0 and r.boost_t <= 0.0 and not r.airborne and Course.in_ranges(r.seg["boosts"], r.ls):
			r.boost(sim)
		sim.step()
		if r.lap == 1 and not r.detour.is_empty():
			detour_ticks += 1
		if r.miss_chance >= 0.0:
			# One more circle at the speed it reaches the exit (the autopilot drives it at 0.85).
			if r.lap == 1:
				risk_ms += r.miss_chance * loop_len / maxf(1.0, 0.85 * r.v) * 1000.0
			r.miss_chance = -1.0
		if r.lap == 1 and r.seg_id != cur:
			if cur != "":
				seg_ms[cur] = float(seg_ms.get(cur, 0.0)) + (r.ticks - cur_t) * 1000.0 / Tuning.HZ
			cur = r.seg_id
			cur_t = r.ticks
		for m in sim.outbox:
			var p: Dictionary = m["payload"]
			if m["type"] == "game.run.finished":
				# "clean": a missed roundabout exit's extra circle taken out.
				var dms := detour_ticks * 1000.0 / Tuning.HZ
				return {"ms": float(p["laps"][1]) - dms + risk_ms, "clean": float(p["laps"][1]) - dms, "seg": seg_ms, "reason": "", "missed": detour_ticks > 0}
			if m["type"] == "game.run.failed":
				return {"ms": -1.0, "seg": {}, "reason": "%s@%s" % [p["reason"], r.seg_id], "missed": false}
		sim.outbox.clear()
	return {"ms": -1.0, "seg": {}, "reason": "guard", "missed": false}


## Expected lap 2 over n seeds (a fail counts as a lap of runTimeCapMs), plus the clean mean.
func vmeasure(build: Dictionary, weather: String, n: int = -1) -> Dictionary:
	n = seeds if n < 0 else n
	var key := "%s|%d|%s" % [weather, n, JSON.stringify(build)]
	if vcache.has(key):
		return vcache[key]
	if vbroken:
		return {"mean": -1.0, "clean": -1.0, "fails": n, "n": n, "reasons": {"broken": n}, "seg": {}, "missed": 0}
	var sum := 0.0
	var clean := 0.0
	var ok := 0
	var reasons := {}
	var seg := {}
	var missed := 0
	for k in n:
		var res := vrun(build, weather, k)
		if float(res["ms"]) > 0.0:
			sum += float(res["ms"])
			clean += float(res["clean"])
			ok += 1
			missed += 1 if res["missed"] else 0
			for id in res["seg"]:
				seg[id] = float(seg.get(id, 0.0)) + float(res["seg"][id])
		else:
			sum += float(vcfg["runTimeCapMs"])
			reasons[res["reason"]] = int(reasons.get(res["reason"], 0)) + 1
	for id in seg:
		seg[id] = float(seg[id]) / ok
	var m := {"mean": sum / n, "clean": clean / ok if ok > 0 else -1.0, "fails": n - ok, "n": n, "reasons": reasons, "seg": seg, "missed": missed}
	vcache[key] = m
	return m


## Expected lap time for ranking (fails already priced in).
func vscore(m: Dictionary) -> float:
	return INF if float(m["mean"]) < 0.0 else float(m["mean"])


func vfmt(m: Dictionary) -> String:
	if float(m["mean"]) < 0.0:
		return "  fail"
	return "%6.2f%s" % [float(m["mean"]) / 1000.0, "*" if int(m["fails"]) > 0 else ("~" if int(m["missed"]) > 0 else " ")]


## Short form of a build: stars s/j/g/w/st/b, style, routes.
func vdesc(b: Dictionary) -> String:
	var st: Dictionary = b["stars"]
	var r: Dictionary = b["routes"]
	return "spd%d jmp%d grp%d wat%d stb%d bnc%d %-8s %s/%s/%s" % [int(st["speed"]), int(st["jump"]), int(st["grip"]),
		int(st["water"]), int(st["stability"]), int(st["bounce"]), b["style"], r["ramp"], r["pond"], r["crossing"]]


## Builds one move away: `step` stars from one ability to another, one route flipped, or another style.
func neighbours(b: Dictionary, step: int, lock_fork: String = "", lock_style := false) -> Array:
	var out: Array = []
	var mx := int(cfg["starsMaxPerAbility"])
	for a in Protocol.ABILITIES:
		for c in Protocol.ABILITIES:
			if a == c or int(b["stars"][a]) < step or int(b["stars"][c]) + step > mx:
				continue
			var nb: Dictionary = b.duplicate(true)
			nb["stars"][a] = int(nb["stars"][a]) - step
			nb["stars"][c] = int(nb["stars"][c]) + step
			out.append(nb)
	for f in Protocol.FORK_IDS:
		if f == lock_fork:
			continue
		var nb: Dictionary = b.duplicate(true)
		var ch: Array = Protocol.FORK_CHOICES[f]
		nb["routes"][f] = ch[1] if nb["routes"][f] == ch[0] else ch[0]
		out.append(nb)
	for style in Protocol.DRIVING_STYLES:
		if style != b["style"] and not lock_style:
			var nb: Dictionary = b.duplicate(true)
			nb["style"] = style
			out.append(nb)
	return out


## Steepest-descent hill-climb on the expected lap time, at most max_steps moves:
## 2-star moves first, 1-star moves once those stop paying.
func climb(start: Dictionary, weather: String, max_steps: int, lock_fork: String = "", lock_style := false) -> Dictionary:
	var best := start
	var best_s := vscore(vmeasure(best, weather))
	var step := 2
	for i in max_steps:
		var cand := {}
		var cand_s := best_s - MIN_GAIN_MS
		for nb in neighbours(best, step, lock_fork, lock_style):
			var sc := vscore(vmeasure(nb, weather))
			if sc < cand_s:
				cand = nb
				cand_s = sc
		if cand.is_empty():
			if step == 1:
				break
			step = 1
			continue
		best = cand
		best_s = cand_s
	return best


func _village() -> bool:
	village = VillageCourse.new()
	if not village.errors.is_empty():
		print("FAIL village course: ", "; ".join(village.errors))
		return false
	vcfg = Messages.default_config()
	vcfg["lapsPerRun"] = 2
	vcfg["startCountdownMs"] = 0
	print("== Village loop: expected lap 2 of 2 (missed-exit risk priced in; * = a fail in it, priced as a %.0f s lap; ~ = a missed exit happened), solo, boosts on the zones, %d seeds, wind %.1f from spread directions ==" % [float(vcfg["runTimeCapMs"]) / 1000.0, seeds, WEATHERS["wind"][1]])
	var weathers: Array = WEATHERS.keys()
	var line := ""
	# Single-ability tables keep speed and grip at default and trade the other abilities first.
	var order := ["jump", "water", "bounce", "stability", "grip", "speed"]

	# Default build.
	line = "  default (%s)  " % vdesc(Builds.default_build())
	for w in weathers:
		line += "%s %s  " % [w, vfmt(vmeasure(Builds.default_build(), w))]
	if vbroken:
		print("FAIL: the sim did not run (see the script errors above)")
		return false
	print(line)

	# Random screen: one seed each.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var pool: Array = []
	for i in n_builds:
		pool.append(Builds.random_build(rng))
	var screen := {}
	print("\n== %d random builds, 1 seed: fails per run ==" % n_builds)
	for w in weathers:
		var rows: Array = []
		var fails := 0
		var reasons := {}
		var by_style := {}
		var missed := {}
		for b in pool:
			var m := vmeasure(b, w, 1)
			if int(m["missed"]) > 0:
				missed[b["style"]] = int(missed.get(b["style"], 0)) + 1
			if int(m["fails"]) > 0:
				fails += 1
				by_style[b["style"]] = int(by_style.get(b["style"], 0)) + 1
				for k in m["reasons"]:
					reasons[k] = int(reasons.get(k, 0)) + 1
			else:
				rows.append([float(m["mean"]), b])
		rows.sort_custom(func(a, c): return a[0] < c[0])
		screen[w] = rows
		var med: float = rows[rows.size() / 2][0] if not rows.is_empty() else -1.0
		print("  %-6s fails %3d/%d (%4.1f%%)  median lap %.2f s  by style %s  %s  missed exit by style %s" % [w, fails, n_builds, 100.0 * fails / n_builds, med / 1000.0, by_style, reasons, missed])

	# Best build per weather: the screen's top 4 re-measured, then a hill-climb from the best 2.
	var best := {}
	for w in weathers:
		var tops: Array = (screen[w] as Array).slice(0, 4).map(func(r): return r[1])
		tops.sort_custom(func(a, c): return vscore(vmeasure(a, w)) < vscore(vmeasure(c, w)))
		best[w] = climb(tops[0], w, 8)
	print("\n== Best build per weather (hill-climbed) ==")
	for w in weathers:
		print("  %-6s %s  %s" % [w, vfmt(vmeasure(best[w], w)), vdesc(best[w])])

	# Cross table: each weather's best build in every weather, more seeds.
	var n_cross := seeds * 2
	print("\n== Cross table: best build of <row> driven in <column>, lap s (%d seeds; * = fails) ==" % n_cross)
	line = "  %-11s" % "best for"
	for w in weathers:
		line += "%10s" % w
	print(line)
	for bw in weathers:
		line = "  %-11s" % bw
		for w in weathers:
			var m := vmeasure(best[bw], w, n_cross)
			line += "%9s%s" % [vfmt(m).strip_edges(), "!" if bw == w else " "]
		print(line)
	line = "  %-11s" % "calm-best loses"
	for w in weathers:
		var own := vmeasure(best[w], w, n_cross)
		var calm := vmeasure(best["calm"], w, n_cross)
		line += "%+10.2f" % ((float(calm["mean"]) - float(own["mean"])) / 1000.0) if float(calm["mean"]) > 0 and float(own["mean"]) > 0 else "%10s" % "fail"
	print(line)

	# Forks: the best build held to each choice, per weather, and its gap to the weather's best. The
	# choice the best build doesn't take starts from it with the route flipped and is re-climbed
	# with the route locked.
	print("\n== Forks: best build held to each choice, gap to the weather's best (s) ==")
	for f in Protocol.FORK_IDS:
		var ch: Array = Protocol.FORK_CHOICES[f]
		for c in ch:
			line = "  %-9s %-9s" % [f, c]
			var builds := ""
			for w in weathers:
				var held: Dictionary = best[w] if best[w]["routes"][f] == c else climb(_with_route(best[w], f, c), w, 6, f)
				var gap := (vscore(vmeasure(held, w)) - vscore(vmeasure(best[w], w))) / 1000.0
				line += "  %s %6.2f (%+.2f)" % [w, vscore(vmeasure(held, w)) / 1000.0, gap]
				if gap > 0.0:
					builds += "\n      %-6s %s" % [w, vdesc(held)]
			print(line + builds)

	# Styles: the best build held to each style (stars and routes re-climbed).
	print("\n== Styles: best build held to each style, gap to the weather's best (s) ==")
	for style in Protocol.DRIVING_STYLES:
		line = "  %-9s" % style
		var builds := ""
		for w in weathers:
			var held: Dictionary = best[w]
			if best[w]["style"] != style:
				held = best[w].duplicate(true)
				held["style"] = style
				held = climb(held, w, 6, "", true)
			var gap := (vscore(vmeasure(held, w)) - vscore(vmeasure(best[w], w))) / 1000.0
			line += "  %s %6.2f (%+.2f)" % [w, vscore(vmeasure(held, w)) / 1000.0, gap]
			if gap > 0.0:
				builds += "\n      %-6s %s" % [w, vdesc(held)]
		print(line + builds)

	# Fork by stars: default-ish build with the fork's ability at 0..10, each choice.
	print("\n== Fork by stars: default build with <ability> at x stars; clean lap Δ = first choice - second (* = fails) ==")
	for f in FORK_STAT:
		var ch: Array = Protocol.FORK_CHOICES[f]
		print("  %s (%s - %s, by %s stars)" % [f, ch[0], ch[1], FORK_STAT[f]])
		for w in weathers:
			line = "    %-6s" % w
			for x in range(0, int(cfg["starsMaxPerAbility"]) + 1, 2):
				var b := _build_with(FORK_STAT[f], x, order)
				var ma := vmeasure(_with_route(b, f, ch[0]), w)
				var mb := vmeasure(_with_route(b, f, ch[1]), w)
				# Clean laps here: a missed exit is luck, not the fork.
				var dl := "%+.2f%s" % [(float(ma["clean"]) - float(mb["clean"])) / 1000.0, "*" if int(ma["fails"]) + int(mb["fails"]) > 0 else ""]
				line += "  %2d:%-7s" % [x, dl]
			print(line)

	# Stretches: time in the stretch with its ability at 0 vs 10 stars (rest default-ish).
	print("\n== Stretches: time in the stretch, ability 0 -> 10 stars (s saved); default build, speed kept ==")
	for sp in STRETCHES:
		line = "  %-8s %-9s" % [sp[0], sp[1]]
		for w in weathers:
			var m0 := vmeasure(_build_with(sp[1], 0, order), w)
			var m10 := vmeasure(_build_with(sp[1], 10, order), w)
			if int(m0["fails"]) == int(m0["n"]) or int(m10["fails"]) == int(m10["n"]):
				line += "  %s fail %d/%d" % [w, m0["fails"], m10["fails"]]
				continue
			var t0 := float(m0["seg"].get(sp[0], 0.0))
			var t10 := float(m10["seg"].get(sp[0], 0.0))
			line += "  %s %.2f->%.2f (%+.2f)" % [w, t0 / 1000.0, t10 / 1000.0, (t0 - t10) / 1000.0]
		print(line)

	# How much slower each weather is than calm, per random build (both finished), by style.
	print("\n== Weather / calm lap ratio over the random builds (median, p90, max), by style ==")
	for w in weathers.slice(1):
		line = "  %-6s" % w
		for style in Protocol.DRIVING_STYLES:
			var ratios: Array = []
			for b in pool:
				if b["style"] != style:
					continue
				var mc := vmeasure(b, "calm", 1)
				var mw := vmeasure(b, w, 1)
				if int(mc["fails"]) == 0 and int(mw["fails"]) == 0:
					ratios.append(float(mw["mean"]) / float(mc["mean"]))
			ratios.sort()
			if ratios.is_empty():
				continue
			line += "  %s %.2f / %.2f / %.2f" % [style, ratios[ratios.size() / 2], ratios[int(ratios.size() * 0.9)], ratios[ratios.size() - 1]]
		print(line)

	# Fails of the best builds (cross-table seeds) and of random builds (screen).
	print("\n== Fails: best builds over the cross-table seeds ==")
	for bw in weathers:
		line = "  best for %-6s" % bw
		for w in weathers:
			var m := vmeasure(best[bw], w, n_cross)
			line += "  %s %d/%d %s" % [w, m["fails"], m["n"], m["reasons"] if int(m["fails"]) > 0 else ""]
		print(line)
	return true

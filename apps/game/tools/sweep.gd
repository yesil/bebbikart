extends SceneTree
## Headless balance sweep (game.md task #5).
##   godot --headless --path apps/game --script res://tools/sweep.gd -- --builds=200 --seeds=3
## Options: --builds=N random builds (default 200), --seeds=N repeats per measurement (default 3),
##          --boost=perfect|none, --quick (smaller run), --json=path (dump raw results)
##          --trace=jump:3,ramp:jump[,weather:rain]  run one build and print its splits + events

const Course = preload("res://sim/course.gd")
const Sim = preload("res://sim/sim.gd")
const Racer = preload("res://sim/racer.gd")
const Builds = preload("res://sim/builds.gd")
const Messages = preload("res://net/messages.gd")

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
func _build_with(stat: String, x: int) -> Dictionary:
	var b := Builds.default_build()
	var stars: Dictionary = b["stars"]
	stars[stat] = x
	var order := ["speed", "grip", "stability", "jump", "water", "bounce"]
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

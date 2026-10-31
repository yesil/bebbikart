extends SceneTree
## Regression check: no two karts may sit inside each other, on either track, including where
## they are on different road pieces (fork splits and merges, the loop's start line):
##   godot --headless --path apps/game --script res://tools/kart_overlap_check.gd [-- --seconds=240]
## Drives a 20-kart crowd with random builds in calm weather and in the storm. Every kart is one of
## the bundled sample racers (res://racer_kit/samples, built and measured like the game does:
## world/toy_footprint.gd), so wide karts and long rides mix. Exits 1 if any two bodies (their
## footprint rectangles along each kart's yaw, world ground plane) overlap by more than OVERLAP_TOL.

const Course = preload("res://sim/course.gd")
const VillageCourse = preload("res://sim/village_course.gd")
const Sim = preload("res://sim/sim.gd")
const Racer = preload("res://sim/racer.gd")
const Builds = preload("res://sim/builds.gd")
const Messages = preload("res://net/messages.gd")
const Tuning = preload("res://sim/tuning.gd")
const ToyFootprint = preload("res://world/toy_footprint.gd")

## A push solves one pair at a time, so a third kart can leave a little overlap for a tick.
const OVERLAP_TOL := 0.25
const RACERS := 20

var fails: PackedStringArray = []
var samples: Array = []  # [name, Vector2 half width/length]


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var seconds := float(args.get("seconds", "240"))
	for f in DirAccess.get_files_at("res://racer_kit/samples"):
		if not f.ends_with(".json"):
			continue
		var fp := ToyFootprint.of_spec(JSON.parse_string(FileAccess.get_file_as_string("res://racer_kit/samples/" + f)))
		if fp.has("error"):
			print("FAIL sample %s: %s" % [f, fp["error"]])
			quit(1)
			return
		samples.append([f.get_basename(), fp["size"]])
		print("  %-14s half width %.2f m, half length %.2f m" % [f.get_basename(), fp["size"].x, fp["size"].y])
	if samples.is_empty():
		print("FAIL: no sample racers in res://racer_kit/samples")
		quit(1)
		return
	var village := VillageCourse.new()
	if not village.errors.is_empty():
		print("FAIL village course: ", "; ".join(village.errors))
		quit(1)
		return
	for track in [["countryside", Course.new()], ["village", village]]:
		for w in [["calm", 0.0, 0.0], ["storm", 1.0, 0.8]]:
			_run(track[0], track[1], w, seconds)
	if fails.is_empty():
		print("KART OVERLAP CHECK PASSED")
		quit(0)
		return
	for f in fails.slice(0, 30):
		print("  FAIL ", f)
	print("KART OVERLAP CHECK FAILED: %d overlaps" % fails.size())
	quit(1)


func _run(track: String, course, weather: Array, seconds: float) -> void:
	var cfg: Dictionary = Messages.default_config()
	cfg["lapsPerRun"] = 2
	var sim := Sim.new(course, cfg, 7)
	sim.emit_messages = false
	var reasons := {}
	sim.weather.force(weather[1], weather[2], 40.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var launched := 0
	var pairs := 0
	var worst := 0.0
	var body := {}  # runId -> [sample name, half size]
	for t in int(seconds * Tuning.HZ):
		if sim.active_count() < RACERS and t % 30 == 0:
			var smp: Array = samples[launched % samples.size()]
			var id := "r%d" % launched
			sim.add_run(id, "p%d" % launched, Builds.random_build(rng), smp[1])
			body[id] = smp
			launched += 1
		for o in sim.racers:
			var r: Racer = o
			if r.boosts_left > 0 and r.boost_t <= 0.0 and not r.airborne and Course.in_ranges(r.seg["boosts"], r.ls):
				r.boost(sim)
		sim.step()
		for m in sim.outbox:
			if m["type"] == "game.run.failed":
				var k := "%s@%s" % [m["payload"]["reason"], m["payload"]["section"]]
				reasons[k] = int(reasons.get(k, 0)) + 1
		sim.outbox.clear()
		var list: Array = sim.racers
		for i in list.size():
			var a: Racer = list[i]
			var pa := a.world_pos()
			for j in range(i + 1, list.size()):
				var b: Racer = list[j]
				var pb := b.world_pos()
				if absf(pa.y - pb.y) > 1.2:
					continue
				pairs += 1
				var depth := _overlap(pa, a.yaw(), body[a.run_id][1], pb, b.yaw(), body[b.run_id][1])
				worst = maxf(worst, depth)
				if depth > OVERLAP_TOL:
					fails.append("%s %s t=%.1fs: %s (%s) on %s s=%.1f and %s (%s) on %s s=%.1f overlap %.2f m" % [
						track, weather[0], t / float(Tuning.HZ), a.run_id, body[a.run_id][0], a.seg_id, a.ls,
						b.run_id, body[b.run_id][0], b.seg_id, b.ls, depth])
	print("%-11s %-5s %d karts, %d pairs checked, worst overlap %.2f m, fails %s" % [track, weather[0], launched, pairs, worst, reasons])


## How deep two footprint rectangles (centre, yaw from +Z towards +X, half size x across / y
## along) overlap on the ground plane: the smallest overlap of their projections (separating
## axes), 0 when apart.
func _overlap(pa: Vector3, ya: float, ha: Vector2, pb: Vector3, yb: float, hb: Vector2) -> float:
	var fa := Vector2(sin(ya), cos(ya))
	var fb := Vector2(sin(yb), cos(yb))
	var axes := [fa, Vector2(fa.y, -fa.x), fb, Vector2(fb.y, -fb.x)]
	var d := Vector2(pb.x - pa.x, pb.z - pa.z)
	var depth := INF
	for ax in axes:
		var a: Vector2 = ax
		var ra := ha.y * absf(fa.dot(a)) + ha.x * absf(Vector2(fa.y, -fa.x).dot(a))
		var rb := hb.y * absf(fb.dot(a)) + hb.x * absf(Vector2(fb.y, -fb.x).dot(a))
		var o := ra + rb - absf(d.dot(a))
		if o <= 0.0:
			return 0.0
		depth = minf(depth, o)
	return depth

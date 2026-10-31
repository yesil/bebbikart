extends SceneTree
## Regression check: no two karts may sit inside each other, on either track, including where
## they are on different road pieces (fork splits and merges, the loop's start line):
##   godot --headless --path apps/game --script res://tools/kart_overlap_check.gd [-- --seconds=240]
## Drives a 20-kart crowd with random builds in calm weather and in the storm, and exits 1 if
## any pair ends a tick closer than OVERLAP_TOL inside the collision radius (world ground plane).

const Course = preload("res://sim/course.gd")
const VillageCourse = preload("res://sim/village_course.gd")
const Sim = preload("res://sim/sim.gd")
const Racer = preload("res://sim/racer.gd")
const Builds = preload("res://sim/builds.gd")
const Messages = preload("res://net/messages.gd")
const Tuning = preload("res://sim/tuning.gd")

## A push solves one pair at a time, so a third kart can leave a little overlap for a tick.
const OVERLAP_TOL := 0.25
const RACERS := 20

var fails: PackedStringArray = []


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var seconds := float(args.get("seconds", "240"))
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
	var limit := Tuning.RADIUS * 2.0 - OVERLAP_TOL
	for t in int(seconds * Tuning.HZ):
		if sim.active_count() < RACERS and t % 30 == 0:
			sim.add_run("r%d" % launched, "p%d" % launched, Builds.random_build(rng))
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
				var dist := Vector2(pa.x - pb.x, pa.z - pb.z).length()
				if dist < limit:
					worst = maxf(worst, limit - dist)
					fails.append("%s %s t=%.1fs: %s on %s s=%.1f and %s on %s s=%.1f are %.2f m apart" % [
						track, weather[0], t / float(Tuning.HZ), a.run_id, a.seg_id, a.ls, b.run_id, b.seg_id, b.ls, dist])
	print("%-11s %-5s %d karts, %d pairs checked, worst overlap %.2f m, fails %s" % [track, weather[0], launched, pairs, worst, reasons])

extends RefCounted
## The racing world: fixed 60 Hz step, start queue + lanes, racer collisions, weather.
## Pure RefCounted; scene nodes only read from it. Messages for the server go to `outbox`
## as {type, payload} using contracts §7 Game->Server types; "sim.*" entries are local-only.

const Tuning = preload("res://sim/tuning.gd")
const Course = preload("res://sim/course.gd")
const Racer = preload("res://sim/racer.gd")
const Weather = preload("res://sim/weather.gd")

var course: Course
var config: Dictionary
var weather: Weather
var rng := RandomNumberGenerator.new()
var tick := 0

var racers: Array = []          # racing, in release order
var queue: Array = []           # waiting at the start
var by_run := {}
var outbox: Array = []
var pair_cool := {}             # "runA|runB" -> tick until which bumps are not logged
var collisions_enabled := true
var emit_messages := true       # sweep turns progress chatter off


func _init(p_course: Course, p_config: Dictionary, seed_: int) -> void:
	course = p_course
	config = p_config
	rng.seed = seed_
	weather = Weather.new(config.get("weather", {}), seed_ * 7 + 1)


func emit(type: String, payload: Dictionary) -> void:
	if not emit_messages and (type == "game.run.progress" or type == "game.run.section"):
		return
	outbox.append({"type": type, "payload": payload})


func add_run(run_id: String, player_id: String, build: Dictionary) -> Racer:
	var r := Racer.new()
	r.setup(run_id, player_id, build, course, config, rng.randi())
	by_run[run_id] = r
	queue.append(r)
	return r


func boost(run_id: String) -> void:
	var r: Racer = by_run.get(run_id)
	if r != null:
		r.boost(self)


func abort(run_id: String) -> void:
	var r: Racer = by_run.get(run_id)
	if r == null:
		return
	r.abort()
	queue.erase(r)
	racers.erase(r)
	by_run.erase(run_id)
	emit("sim.removed", {"runId": run_id, "outcome": "aborted"})


func active_count() -> int:
	return racers.size() + queue.size()


func step() -> void:
	tick += 1
	weather.step()
	if weather.changed:
		emit("game.weather", weather.state())
	_release_from_queue()
	for r in racers:
		(r as Racer).step(self)
	if collisions_enabled:
		_collide()
	var keep: Array = []
	for r in racers:
		if (r as Racer).state == "racing":
			keep.append(r)
		else:
			by_run.erase(r.run_id)
			emit("sim.removed", {"runId": r.run_id, "outcome": r.state})
	racers = keep


# ---------------------------------------------------------------- start

func _release_from_queue() -> void:
	while not queue.is_empty():
		var best_lane := 0.0
		var best_gap := -INF
		for lane in Tuning.START_LANES:
			var gap := 1000.0
			for o in racers:
				var r: Racer = o
				if r.seg_idx == 0 and absf(r.d - lane) < Tuning.RADIUS * 2.0:
					gap = minf(gap, r.ls)
			if gap > best_gap:
				best_gap = gap
				best_lane = lane
		if best_gap < Tuning.START_GAP + Tuning.RADIUS * 2.0:
			return
		var q: Racer = queue.pop_front()
		q.state = "racing"
		q.d = best_lane
		q.lane = best_lane
		q.d_target = best_lane
		q.y = course.surface_y(q.seg, 0.0)
		racers.append(q)
		emit("game.run.started", {"runId": q.run_id})


# ---------------------------------------------------------------- traffic queries

## Nearest racer ahead on the same segment within `dist` metres and |dd| < lat.
func racer_ahead(me: Racer, dist: float, lat: float):
	var best = null
	var best_ds := dist
	for o in racers:
		var r: Racer = o
		if r == me or r.seg_id != me.seg_id:
			continue
		var ds := r.ls - me.ls
		if ds > 0.0 and ds < best_ds and absf(r.d - me.d_target) < lat + 0.5 and absf(r.d - me.d) < lat + 1.0:
			best = r
			best_ds = ds
	return best


## Metres of free road ahead in a lateral line `d`.
func lane_free(me: Racer, d: float, dist: float) -> float:
	var free := dist
	for o in racers:
		var r: Racer = o
		if r == me or r.seg_id != me.seg_id:
			continue
		var ds := r.ls - me.ls
		if ds > -1.5 and absf(r.d - d) < Tuning.RADIUS * 2.2:
			free = minf(free, maxf(0.0, ds))
	return free


# ---------------------------------------------------------------- collisions

func _collide() -> void:
	var by_seg := {}
	for o in racers:
		var r: Racer = o
		var id: String = r.seg_id
		if not by_seg.has(id):
			by_seg[id] = []
		by_seg[id].append(r)
	var min_d := Tuning.RADIUS * 2.0
	for id in by_seg:
		var list: Array = by_seg[id]
		for i in list.size():
			for j in range(i + 1, list.size()):
				var a: Racer = list[i]
				var b: Racer = list[j]
				var ds := b.ls - a.ls
				var dd := b.d - a.d
				if absf(ds) >= min_d or absf(dd) >= min_d or absf(a.y - b.y) > 1.2:
					continue
				var dist := sqrt(ds * ds + dd * dd)
				if dist >= min_d:
					continue
				var nx := 1.0
				var ny := 0.0
				if dist > 0.0001:
					nx = ds / dist
					ny = dd / dist
				var ima := 1.0 / a.mass
				var imb := 1.0 / b.mass
				var overlap := min_d - dist
				var share_a := ima / (ima + imb)
				a.ls -= nx * overlap * share_a
				a.d -= ny * overlap * share_a
				b.ls += nx * overlap * (1.0 - share_a)
				b.d += ny * overlap * (1.0 - share_a)
				# Approaching speed along the normal (a -> b).
				var vrel := (a.v - b.v) * nx + (a.vd - b.vd) * ny
				if vrel <= 0.0:
					continue
				var jimp := (1.0 + Tuning.RESTITUTION) * vrel / (ima + imb)
				a.v = maxf(0.0, a.v - jimp * nx * ima)
				a.vd -= jimp * ny * ima
				b.v = maxf(0.0, b.v + jimp * nx * imb)
				b.vd += jimp * ny * imb
				if vrel < Tuning.BUMP_LOG_IMPULSE:
					continue
				var key: String = a.run_id + "|" + b.run_id if a.run_id < b.run_id else b.run_id + "|" + a.run_id
				if int(pair_cool.get(key, -1)) > tick:
					continue
				pair_cool[key] = tick + Tuning.HZ
				# Hitter = whoever moves faster towards the other.
				var a_toward := a.v * nx + a.vd * ny
				var b_toward := -(b.v * nx + b.vd * ny)
				var hitter: Racer = a if a_toward >= b_toward else b
				var victim: Racer = b if hitter == a else a
				victim.got_bumped(hitter.player_id)
				hitter.bumped_other(victim.player_id)
				emit("sim.bump", {"hitter": hitter.run_id, "victim": victim.run_id, "pos": victim.world_pos()})


# ---------------------------------------------------------------- render helpers

func all_visible() -> Array:
	return racers.duplicate()

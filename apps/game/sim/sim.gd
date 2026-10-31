extends RefCounted
## The racing world: fixed 60 Hz step, start queue + lanes, racer collisions, weather.
## Pure RefCounted; scene nodes only read from it. Messages for the server go to `outbox`
## as {type, payload} using contracts §7 Game->Server types; "sim.*" entries are local-only.

const Tuning = preload("res://sim/tuning.gd")
const Course = preload("res://sim/course.gd")
const Racer = preload("res://sim/racer.gd")
const Weather = preload("res://sim/weather.gd")

var course  # sim/course.gd or sim/village_course.gd (loop track)
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
## Race start countdown (contracts §2c, config.startCountdownMs): runs that arrive while it is
## open wait on the grid and leave together when it goes green.
var grid_go := -1               # tick the open countdown goes green; -1 = none since start
var go_tick := {}               # runId -> tick its countdown goes green (queued runs only)
var grid_slot := {}             # runId -> front-row start lane it waits in, visible on the grid


func _init(p_course, p_config: Dictionary, seed_: int) -> void:
	course = p_course
	# A broken course (e.g. a segment without a stretch) is never raced: add_run refuses.
	for e in course.errors:
		push_error("sim: course %s: %s" % [course.NAME, e])
	config = p_config
	rng.seed = seed_
	weather = Weather.new(config.get("weather", {}), seed_ * 7 + 1)


func emit(type: String, payload: Dictionary) -> void:
	if not emit_messages and (type == "game.run.progress" or type == "game.run.section"):
		return
	outbox.append({"type": type, "payload": payload})


func add_run(run_id: String, player_id: String, build: Dictionary) -> Racer:
	if not course.errors.is_empty():
		push_error("sim: refusing run %s, course %s is broken: %s" % [run_id, course.NAME, "; ".join(course.errors)])
		return null
	var r := Racer.new()
	r.setup(run_id, player_id, build, course, config, rng.randi())
	by_run[run_id] = r
	queue.append(r)
	var countdown_ms := int(config.get("startCountdownMs", 0))
	if countdown_ms > 0:
		if grid_go <= tick:
			grid_go = tick + int(ceil(countdown_ms * Tuning.HZ / 1000.0))
		go_tick[run_id] = grid_go
		_park_on_grid(r)
		emit("game.run.grid", {"runId": run_id, "goInMs": int(round((grid_go - tick) * 1000.0 / Tuning.HZ))})
	return r


## The run waits for green in a free front-row slot near its own line, if one is left (the second
## row waits out of sight and leaves as soon as the front row has pulled away).
func _park_on_grid(r: Racer) -> void:
	var home := r.lane_home * (r.half_width() - 0.7)
	var taken := {}
	for id in grid_slot:
		taken[grid_slot[id]] = true
	var best := INF
	for lane in Tuning.START_LANES:
		if taken.has(lane) or _start_gap(lane) < Tuning.START_GAP + Tuning.RADIUS * 2.0:
			continue
		if absf(lane - home) < absf(best - home):
			best = lane
	if best == INF:
		return
	grid_slot[r.run_id] = best
	r.d = best
	r.lane = best
	r.d_target = best
	r.y = course.surface_y(r.seg, 0.0)


## Waiting on the grid, in a front-row slot (racer views show it parked there).
func on_grid(run_id: String) -> bool:
	return grid_slot.has(run_id)


func boost(run_id: String) -> void:
	var r: Racer = by_run.get(run_id)
	if r != null:
		r.boost(self)


## Loop tracks: finish the run when the racer next crosses the line ("pit in").
func stop(run_id: String) -> void:
	var r: Racer = by_run.get(run_id)
	if r != null:
		r.pit_requested = true


func abort(run_id: String) -> void:
	var r: Racer = by_run.get(run_id)
	if r == null:
		return
	r.abort()
	queue.erase(r)
	racers.erase(r)
	by_run.erase(run_id)
	go_tick.erase(run_id)
	grid_slot.erase(run_id)
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
	# A group pressing Go together leaves side by side: each racer takes the free slot nearest
	# the line it likes to drive (lane_home), so nobody has to cut across another kart's nose.
	# A racer parked on the grid leaves from its own slot.
	while not queue.is_empty():
		var q: Racer = queue[0]
		if int(go_tick.get(q.run_id, 0)) > tick:
			return  # the countdown hasn't gone green yet
		var home: float = grid_slot.get(q.run_id, q.lane_home * (q.half_width() - 0.7))
		var best_lane := 0.0
		var best_miss := INF
		for lane in Tuning.START_LANES:
			if _start_gap(lane) < Tuning.START_GAP + Tuning.RADIUS * 2.0:
				continue
			if absf(lane - home) < best_miss:
				best_miss = absf(lane - home)
				best_lane = lane
		if best_miss == INF:
			return
		queue.pop_front()
		go_tick.erase(q.run_id)
		grid_slot.erase(q.run_id)
		q.state = "racing"
		q.d = best_lane
		q.lane = best_lane
		q.d_target = best_lane
		q.y = course.surface_y(q.seg, 0.0)
		racers.append(q)
		emit("game.run.started", {"runId": q.run_id})


## Free metres ahead of a start slot (1000 when nobody is near it).
func _start_gap(lane: float) -> float:
	var gap := 1000.0
	for o in racers:
		var r: Racer = o
		if absf(r.d - lane) >= Tuning.RADIUS * 2.0:
			continue
		if r.seg_idx == 0:
			gap = minf(gap, r.ls)
		elif r.looping and r.seg_idx == r.segs.size() - 1:
			# A lapping racer about to cross the line counts as close too.
			gap = minf(gap, r.route().length - r.ls)
	return gap


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

## Racers are circles in the world's ground plane, not per road piece: where a fork splits or
## merges, or the loop wraps, karts on different pieces are side by side and must not pass
## through each other. Each push and impulse is split back into the racer's own (s, d) frame.
func _collide() -> void:
	var n := racers.size()
	var pos := PackedVector3Array()
	var tan := PackedVector3Array()
	var nor := PackedVector3Array()
	pos.resize(n)
	tan.resize(n)
	nor.resize(n)
	for i in n:
		var r: Racer = racers[i]
		var rt := r.route()
		pos[i] = r.world_pos()
		tan[i] = rt.tangent_at(r.ls)
		nor[i] = rt.normal_at(r.ls)
	var min_d := Tuning.RADIUS * 2.0
	for i in n:
		for j in range(i + 1, n):
			var a: Racer = racers[i]
			var b: Racer = racers[j]
			var dx := pos[j].x - pos[i].x
			var dz := pos[j].z - pos[i].z
			if absf(dx) >= min_d or absf(dz) >= min_d or absf(a.y - b.y) > 1.2:
				continue
			var dist := sqrt(dx * dx + dz * dz)
			if dist >= min_d:
				continue
			# World normal a -> b (along a's heading if they sit exactly on top of each other).
			var nw := tan[i]
			if dist > 0.0001:
				nw = Vector3(dx / dist, 0.0, dz / dist)
			var ima := 1.0 / a.mass
			var imb := 1.0 / b.mass
			var overlap := min_d - dist
			var share_a := ima / (ima + imb)
			var push_a := -nw * overlap * share_a
			var push_b := nw * overlap * (1.0 - share_a)
			a.ls = maxf(0.0, a.ls + push_a.dot(tan[i]))
			b.ls = maxf(0.0, b.ls + push_b.dot(tan[j]))
			if a.seg_id != b.seg_id:
				# Two branches of a fork where they still overlap (split, merge, the loop's line):
				# their lines converge, so the karts touch tick after tick. They only rub, and are
				# never shoved off their own road by a kart driving another one.
				a.d = _shove(a, push_a.dot(nor[i]))
				b.d = _shove(b, push_b.dot(nor[j]))
				continue
			a.d += push_a.dot(nor[i])
			b.d += push_b.dot(nor[j])
			# Approaching speed along the normal (a -> b).
			var va := tan[i] * a.v + nor[i] * a.vd
			var vb := tan[j] * b.v + nor[j] * b.vd
			var vrel := (va - vb).dot(nw)
			if vrel <= 0.0:
				continue
			var jimp := (1.0 + Tuning.RESTITUTION) * vrel / (ima + imb)
			var ja := -nw * jimp * ima
			var jb := nw * jimp * imb
			a.v = maxf(0.0, a.v + ja.dot(tan[i]))
			a.vd += ja.dot(nor[i])
			b.v = maxf(0.0, b.v + jb.dot(tan[j]))
			b.vd += jb.dot(nor[j])
			if vrel < Tuning.BUMP_LOG_IMPULSE:
				continue
			var key: String = a.run_id + "|" + b.run_id if a.run_id < b.run_id else b.run_id + "|" + a.run_id
			if int(pair_cool.get(key, -1)) > tick:
				continue
			pair_cool[key] = tick + Tuning.HZ
			# Hitter = whoever moves faster towards the other.
			var a_toward := va.dot(nw)
			var b_toward := -vb.dot(nw)
			var hitter: Racer = a if a_toward >= b_toward else b
			var victim: Racer = b if hitter == a else a
			victim.got_bumped(hitter.player_id)
			hitter.bumped_other(victim.player_id)
			emit("sim.bump", {"hitter": hitter.run_id, "victim": victim.run_id, "pos": victim.world_pos()})


## Racer r's lateral position after a sideways push of dd, kept on the road (inside where a
## rail would stop it) unless it was already further out.
func _shove(r: Racer, dd: float) -> float:
	var lim := maxf(r.half_width() - 0.45, absf(r.d))
	return clampf(r.d + dd, -lim, lim)


# ---------------------------------------------------------------- render helpers

func all_visible() -> Array:
	return racers.duplicate()

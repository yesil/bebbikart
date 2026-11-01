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
## Duel mode (contracts §2i): every run is alone against the clock. Each gets its own start
## lights, the karts pass through each other (no collisions, no bumps) and the autopilot drives
## as if the road were empty (no overtaking, no blocked start slots).
var solo := false
## Race start countdown (contracts §2c, config.startCountdownMs): runs that arrive while it is
## open wait on the grid and leave together when it goes green.
var grid_go := -1               # tick the open countdown goes green; -1 = none since start
var go_tick := {}               # runId -> tick its countdown goes green (queued runs only)
var grid_slot := {}             # runId -> front-row start lane it waits in, visible on the grid
## Village surprises (sim/obstacles.gd): cows, sheep, cheese wheels and hay bales on the road.
## The game turns them on (main.gd); null in the tools, so their baselines stay the same.
var obstacles = null


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


## size: the racer's half width and half length from its built toy (Tuning.DEFAULT_SIZE for
## headless and mock racers); a missing size is a bug, so the run is refused.
## laps: the laps this run races, from the server (run.start lapsPerRun); tools without a server
## pass none and the racer takes config.lapsPerRun.
func add_run(run_id: String, player_id: String, build: Dictionary, size: Vector2, laps := 0) -> Racer:
	if not course.errors.is_empty():
		push_error("sim: refusing run %s, course %s is broken: %s" % [run_id, course.NAME, "; ".join(course.errors)])
		return null
	if size.x <= 0.0 or size.y <= 0.0:
		push_error("sim: refusing run %s: no footprint size (%s)" % [run_id, size])
		return null
	var r := Racer.new()
	r.setup(run_id, player_id, build, course, config, rng.randi(), size)
	r.obstacles = obstacles
	if laps > 0:
		r.laps_max = laps
	by_run[run_id] = r
	queue.append(r)
	var countdown_ms := int(config.get("startCountdownMs", 0))
	if countdown_ms > 0:
		var go := tick + int(ceil(countdown_ms * Tuning.HZ / 1000.0))
		if solo:
			go_tick[run_id] = go  # its own lights: never joins another run's countdown
		else:
			if grid_go <= tick:
				grid_go = go
			go_tick[run_id] = grid_go
		_park_on_grid(r)
		emit("game.run.grid", {"runId": run_id, "goInMs": int(round((int(go_tick[run_id]) - tick) * 1000.0 / Tuning.HZ))})
	return r


## The run waits for green in a free front-row slot near its own line, if one is left (the second
## row waits out of sight and leaves as soon as the front row has pulled away). Solo runs pass
## through each other on the track but still wait in slots of their own; with more of them
## waiting than slots, the extra ones share the nearest (they pass through).
func _park_on_grid(r: Racer) -> void:
	var home := r.lane_home * (r.half_width() - 0.7)
	var taken := {}
	for id in grid_slot:
		taken[grid_slot[id]] = true
	var best := INF
	for lane in Tuning.START_LANES:
		if taken.has(lane) or _start_gap(lane, r) < Tuning.START_GAP:
			continue
		if absf(lane - home) < absf(best - home):
			best = lane
	if best == INF and solo:
		for lane in Tuning.START_LANES:
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


## The kid's thumb on the phone's steering pad (run.steer, contracts §2g): a lane x in [-1, 1]
## across the road (+ right), or null when it lets go. A run that has just ended may still get one.
func steer(run_id: String, x) -> void:
	var r: Racer = by_run.get(run_id)
	if r != null:
		r.set_steer(x)


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
	if obstacles != null:
		obstacles.step(self)
	for r in racers:
		(r as Racer).step(self)
	if obstacles != null:
		for r in racers:
			if (r as Racer).state == "racing":
				obstacles.collide(self, r)
	if collisions_enabled and not solo:
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
	# A racer parked on the grid leaves from its own slot. Solo runs (duel) each have their own
	# lights: one still counting down doesn't hold back one behind it that is green.
	var i := 0
	while i < queue.size():
		var q: Racer = queue[i]
		if int(go_tick.get(q.run_id, 0)) > tick:
			if solo:
				i += 1
				continue
			return  # the countdown hasn't gone green yet
		var home: float = grid_slot.get(q.run_id, q.lane_home * (q.half_width() - 0.7))
		var best_lane := 0.0
		var best_miss := INF
		for lane in Tuning.START_LANES:
			if _start_gap(lane, q) < Tuning.START_GAP:
				continue
			if absf(lane - home) < best_miss:
				best_miss = absf(lane - home)
				best_lane = lane
		if best_miss == INF:
			return
		queue.remove_at(i)
		go_tick.erase(q.run_id)
		grid_slot.erase(q.run_id)
		q.state = "racing"
		q.d = best_lane
		q.lane = best_lane
		q.d_target = best_lane
		q.y = course.surface_y(q.seg, 0.0)
		racers.append(q)
		emit("game.run.started", {"runId": q.run_id})


## Free metres between racer q's nose in a start slot and the nearest kart there (1000 when
## nobody is near it), each counted at its own size.
func _start_gap(lane: float, q: Racer) -> float:
	var gap := 1000.0
	if solo:
		return gap
	for o in racers:
		var r: Racer = o
		if absf(r.d - lane) >= r.radius + q.radius:
			continue
		if r.seg_idx == 0:
			gap = minf(gap, r.ls - r.half_len - q.half_len)
		elif r.looping and r.seg_idx == r.segs.size() - 1:
			# A lapping racer about to cross the line counts as close too.
			gap = minf(gap, r.route().length - r.ls - r.half_len - q.half_len)
	return gap


# ---------------------------------------------------------------- traffic queries

## Nearest racer ahead on the same segment within `dist` metres and |dd| < lat.
func racer_ahead(me: Racer, dist: float, lat: float):
	var best = null
	if solo:
		return best
	var best_ds := dist
	for o in racers:
		var r: Racer = o
		if r == me or r.seg_id != me.seg_id:
			continue
		# Gaps nose to tail and side by side at each racer's own size (default karts: as before).
		var ds := r.ls - me.ls - r.extra_len() - me.extra_len()
		var wide := r.radius + me.radius - Tuning.RADIUS * 2.0
		if ds > 0.0 and ds < best_ds and absf(r.d - me.d_target) < lat + 0.5 + wide and absf(r.d - me.d) < lat + 1.0 + wide:
			best = r
			best_ds = ds
	return best


## Metres of free road ahead in a lateral line `d`.
func lane_free(me: Racer, d: float, dist: float) -> float:
	var free := dist
	if solo:
		return free
	for o in racers:
		var r: Racer = o
		if r == me or r.seg_id != me.seg_id:
			continue
		var ds := r.ls - me.ls - r.extra_len() - me.extra_len()
		if ds > -1.5 and absf(r.d - d) < (r.radius + me.radius) * 1.1:
			free = minf(free, maxf(0.0, ds))
	return free


# ---------------------------------------------------------------- collisions

## Racers are their footprint rectangles in the world's ground plane (the built toy's half width
## and half length, along its yaw), not per road piece: where a fork splits or merges, or the loop
## wraps, karts on different pieces are side by side and must not pass through each other. An
## overlapping pair is pushed apart along the axis it overlaps least on (separating axes); each
## push and impulse is split back into the racer's own (s, d) frame.
func _collide() -> void:
	var n := racers.size()
	var pos := PackedVector3Array()
	var tan := PackedVector3Array()
	var nor := PackedVector3Array()
	var fwd := PackedVector2Array()  # where the body points on the ground plane (its yaw)
	pos.resize(n)
	tan.resize(n)
	nor.resize(n)
	fwd.resize(n)
	for i in n:
		var r: Racer = racers[i]
		var rt := r.route()
		pos[i] = r.world_pos()
		tan[i] = rt.tangent_at(r.ls)
		nor[i] = rt.normal_at(r.ls)
		fwd[i] = Vector2(sin(r.yaw()), cos(r.yaw()))
	for i in n:
		for j in range(i + 1, n):
			var a: Racer = racers[i]
			var b: Racer = racers[j]
			var dx := pos[j].x - pos[i].x
			var dz := pos[j].z - pos[i].z
			var reach := a.half_len + a.radius + b.half_len + b.radius  # beyond any corner
			if absf(dx) >= reach or absf(dz) >= reach or absf(a.y - b.y) > 1.2:
				continue
			var contact := _box_contact(Vector2(dx, dz), fwd[i], Vector2(a.radius, a.half_len), fwd[j], Vector2(b.radius, b.half_len))
			if contact.is_empty():
				continue
			var overlap: float = contact[0]
			var nw: Vector3 = contact[1]  # world normal a -> b
			var ima := 1.0 / a.mass
			var imb := 1.0 / b.mass
			var share_a := ima / (ima + imb)
			var push_a := -nw * overlap * share_a
			var push_b := nw * overlap * (1.0 - share_a)
			a.ls = maxf(0.0, a.ls + push_a.dot(tan[i]))
			b.ls = maxf(0.0, b.ls + push_b.dot(tan[j]))
			if a.seg_id != b.seg_id:
				# Two branches of a fork where they still overlap (split, merge, the loop's line):
				# their lines converge, so the karts touch tick after tick. They only rub, and are
				# never shoved off their own road by a kart driving another one. What the road's edge
				# keeps them from sliding apart sideways, they settle along the road: the one behind
				# waits (two wide karts can't fit side by side where the lanes split).
				var da := _shove(a, push_a.dot(nor[i]))
				var db := _shove(b, push_b.dot(nor[j]))
				var rest := overlap - absf(da - a.d) - absf(db - b.d)
				a.d = da
				b.d = db
				if rest > 0.0:
					var behind: Racer = a if Vector2(dx, dz).dot(Vector2(tan[i].x, tan[i].z)) >= 0.0 else b
					var front: Racer = b if behind == a else a
					behind.ls = maxf(0.0, behind.ls - rest)
					behind.v = minf(behind.v, front.v)
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


## Two footprint rectangles, b's centre `d` from a's, each with its forward direction and half
## size (x across, y along): [depth, world normal a -> b] along the axis they overlap least on,
## or [] when apart.
static func _box_contact(d: Vector2, fa: Vector2, ha: Vector2, fb: Vector2, hb: Vector2) -> Array:
	var sa := Vector2(fa.y, -fa.x)
	var sb := Vector2(fb.y, -fb.x)
	var depth := INF
	var axis := Vector2.ZERO
	for ax in [fa, sa, fb, sb]:
		var a: Vector2 = ax
		var ra := ha.y * absf(fa.dot(a)) + ha.x * absf(sa.dot(a))
		var rb := hb.y * absf(fb.dot(a)) + hb.x * absf(sb.dot(a))
		var along := d.dot(a)
		var o := ra + rb - absf(along)
		if o <= 0.0:
			return []
		if o < depth:
			depth = o
			axis = a if along >= 0.0 else -a
	return [depth, Vector3(axis.x, 0.0, axis.y)]


## Racer r's lateral position after a sideways push of dd, kept inside the rails.
func _shove(r: Racer, dd: float) -> float:
	var lim := maxf(r.rail_lim(), absf(r.d))
	return clampf(r.d + dd, -lim, lim)


# ---------------------------------------------------------------- render helpers

func all_visible() -> Array:
	return racers.duplicate()

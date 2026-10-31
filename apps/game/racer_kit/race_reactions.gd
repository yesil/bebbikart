extends Node
## Race-wide reactions of the kit racers (main.gd adds one as a child): overtakes (the passer
## pumps a fist, waves or taunts and glances back, the passed racer's head follows them, a grumpy
## one shakes its head), a brace just before two racers bump, a wave or a cheeky taunt to a rival
## driving alongside, an "eek" flinch when a racer close by crashes, both cheering when two cross
## the line within FINISH_TOGETHER_S, and the weather (rain, wind) for every driver. Each driver
## remembers being passed (grumpier) and passing (cockier): RacerGestures.mood_mem.
## On the start grid (sim countdown): fidgets, looks at the neighbours, a wave to the crowd or the
## signature gesture, leaning in on 3-2-1, a whoop on green (the ride crouches and leaps too).
## Runs after main.gd has synced the views each frame. Placeholder views (no toy) are skipped.
## Finish and crash reactions themselves are the views' own (KitRacerView.leave()).

const Gestures = preload("res://racer_kit/racer_gestures.gd")
const Tuning = preload("res://sim/tuning.gd")
const PASS_NEAR := 7.0       # m: only racers this close can overtake each other
const PASS_LANE := 4.0       # m sideways: further apart is not a pass (other road, fork)
const PASS_GAP := 0.6        # m along the road either side before an order flip counts
const PASS_FASTER := 0.4     # m/s: the passer must be this much faster (not two side by side jostling)
const COOL := 3.0            # s between overtake reactions of one racer
const BRACE_DIST := 1.8      # m between racers
const BRACE_CLOSING := 2.5   # m/s closing speed
const BRACE_COOL := 1.0
const SIDE_ALONG := 1.3      # m: alongside = this close along the road …
const SIDE_LANE := Vector2(0.9, 3.5)  # … this far apart sideways …
const SIDE_SPEED := 1.2      # … at about the same speed (m/s) …
const SIDE_S := 1.0          # … for this long, then one of them waves or taunts
const SIDE_COOL := 10.0      # s before the same pair does it again
const SIDE_AFTER_S := 5.0    # s after leaving the grid: a group pulling away together is no rivalry
const CRASH_NEAR := 14.0     # m: racers this close to a crash flinch
const FINISH_TOGETHER_S := 1.0
const TOGETHER_NEAR := 10.0  # m: and close enough to see each other; each finisher cheers together once
const PASSED_MOOD := -0.35   # mood memory per pass (RacerGestures.remember)
const PASSING_MOOD := 0.3
const GRID_LEAN_S := 2.4     # s before green the drivers start leaning in
const GRID_CALM_S := 1.3     # s before green the hands go back to the handle

var main                     # main.gd: reads views, leaving views and sim
## This frame's events, for tools: {"type": "overtake" | "alongside" | "flinch" | "finish_together"
## | "go", "passer"/"passed" | "by"/"to" | "view" | "views": ...}.
var events: Array = []

var _order := {}             # pair key -> 1 / -1: which of the two was ahead along the road
var _side_t := {}            # pair key -> seconds alongside
var _side_cool := {}         # pair key -> seconds until it may happen again
var _kits: Array = []        # racing kit views this frame (reused)
var _next_id := 0
var _sweep := 0.0
var _clock := 0.0
var _seen_left := {}         # instance id of a view that left (finished / crashed) -> true
var _finishers: Array = []   # [[clock, view], ...] recent finishers
var _rng := RandomNumberGenerator.new()


func _init(p_main) -> void:
	main = p_main
	name = "RaceReactions"


func _process(delta: float) -> void:
	if main.sim == null or delta <= 0.0:
		return
	_clock += delta
	events.clear()
	var w = main.sim.weather
	var rain: float = w.rain_intensity()
	var wind: Vector3 = w.wind_vec()
	_kits.clear()
	for k in main.views:
		var v = main.views[k]
		if v.get("toy") == null or v.racer == null:
			continue
		if v.parked:
			v.toy.rain = rain
			v.toy.wind = wind
			_grid(v, delta)
			continue
		if v.racer.state != "racing":
			continue
		if v.grid_t >= 0.0:
			_go(v)
		v.toy.rain = rain
		v.toy.wind = wind
		if v.react_id < 0:
			v.react_id = _next_id
			_next_id += 1
		v.react_cool = maxf(0.0, v.react_cool - delta)
		v.brace_cool = maxf(0.0, v.brace_cool - delta)
		v.race_t += delta
		_kits.append(v)
	for i in _kits.size():
		for j in range(i + 1, _kits.size()):
			_pair(_kits[i], _kits[j], delta)
	for v in _kits:
		v.react_prev = v.global_position
	_left_course()
	# Forget pairs of racers that left now and then.
	_sweep -= delta
	if _sweep <= 0.0:
		_sweep = 5.0
		var live := {}
		for v in _kits:
			live[v.react_id] = true
		for d in [_order, _side_t, _side_cool]:
			for key in d.keys():
				if not live.has(key >> 16) or not live.has(key & 0xffff):
					d.erase(key)
		for id in _seen_left.keys():
			if not is_instance_id_valid(id):
				_seen_left.erase(id)


func _pair(a, b, delta: float) -> void:
	var lo = a if a.react_id < b.react_id else b
	var hi = b if lo == a else a
	var key: int = (lo.react_id << 16) | hi.react_id
	if _side_cool.has(key):
		_side_cool[key] = maxf(0.0, _side_cool[key] - delta)
	var d: Vector3 = hi.global_position - lo.global_position
	var dist2 := d.length_squared()
	if dist2 > PASS_NEAR * PASS_NEAR:
		_order.erase(key)
		_side_t.erase(key)
		return
	# Brace just before a bump: close and closing fast.
	if dist2 < BRACE_DIST * BRACE_DIST and lo.react_prev != Vector3.ZERO and hi.react_prev != Vector3.ZERO:
		var closing := -d.normalized().dot((hi.global_position - hi.react_prev) - (lo.global_position - lo.react_prev)) / delta
		if closing > BRACE_CLOSING:
			for v in [lo, hi]:
				if v.brace_cool <= 0.0:
					v.brace_cool = BRACE_COOL
					v.toy.gesture("brace")
	var fwd: Vector3 = lo.forward() + hi.forward()
	if fwd.length_squared() < 0.5:
		return  # facing apart (crossing roads): not an overtake
	fwd = fwd.normalized()
	var along := d.dot(fwd)
	var lat2 := dist2 - along * along
	_alongside(lo, hi, key, along, lat2, delta)
	if lat2 > PASS_LANE * PASS_LANE:
		return
	var sgn := 1 if along > PASS_GAP else (-1 if along < -PASS_GAP else 0)
	if sgn == 0:
		return
	var before: int = _order.get(key, 0)
	_order[key] = sgn
	if before != 0 and before != sgn:
		# hi was ahead (+1) and now lo is (-1): lo passed hi, and the other way round.
		var passer = lo if sgn < 0 else hi
		var passed = hi if sgn < 0 else lo
		if passer.racer.v - passed.racer.v > PASS_FASTER:
			_overtake(passer, passed)


func _overtake(passer, passed) -> void:
	events.append({"type": "overtake", "passer": passer, "passed": passed})
	var g: Gestures = passer.toy.gestures
	var gp: Gestures = passed.toy.gestures
	g.remember(PASSING_MOOD)
	gp.remember(PASSED_MOOD)
	if passer.react_cool <= 0.0:
		passer.react_cool = COOL
		var toward := _side_of(passer, passed)
		# Cheer (or taunt, when cocky) with the arm away from the racer just passed, glance back.
		var pose := g.pass_gesture()
		g.play(pose, -toward if pose != Gestures.G.TAUNT else toward)
		g.play(Gestures.G.GLANCE_BACK, toward, 1.1, 0.25)
		passer.toy.look_at_node(passed.toy.head_pivot, 1.3)
	if passed.react_cool <= 0.0:
		passed.react_cool = COOL
		passed.toy.look_at_node(passer.toy.head_pivot, 1.5)
		var sulk := gp.passed_gesture()
		if sulk >= 0:
			gp.play(sulk, 0, 0.0, 0.35)


## -1 / 1: which side of `v` (its left / right arm) the other racer is on.
func _side_of(v, other) -> int:
	var local: Vector3 = v.toy.global_transform.affine_inverse() * other.global_position
	return 1 if local.x > 0.0 else -1


## Two racers side by side at the same speed for SIDE_S: the cockier one waves or taunts at the
## other, they look at each other, and a friendly rival may wave back.
func _alongside(lo, hi, key: int, along: float, lat2: float, delta: float) -> void:
	var beside: bool = absf(along) < SIDE_ALONG and lat2 > SIDE_LANE.x * SIDE_LANE.x and lat2 < SIDE_LANE.y * SIDE_LANE.y \
		and absf(lo.racer.v - hi.racer.v) < SIDE_SPEED and lo.racer.v > 4.0 and hi.racer.v > 4.0 \
		and lo.race_t > SIDE_AFTER_S and hi.race_t > SIDE_AFTER_S
	if not beside:
		_side_t.erase(key)
		return
	_side_t[key] = float(_side_t.get(key, 0.0)) + delta
	if _side_t[key] < SIDE_S or float(_side_cool.get(key, 0.0)) > 0.0 or lo.react_cool > 0.0 or hi.react_cool > 0.0:
		return
	_side_cool[key] = SIDE_COOL
	var gl: Gestures = lo.toy.gestures
	var gh: Gestures = hi.toy.gestures
	var by = lo if gl.mood_mem > gh.mood_mem or (gl.mood_mem == gh.mood_mem and _rng.randf() < 0.5) else hi
	var to = hi if by == lo else lo
	by.react_cool = COOL
	to.react_cool = COOL
	var g: Gestures = by.toy.gestures
	var pose := g.rival_gesture()
	by.toy.look_at_node(to.toy.head_pivot, 1.6)
	to.toy.look_at_node(by.toy.head_pivot, 1.4)
	if pose >= 0:
		g.play(pose, _side_of(by, to), 1.2)
		var back := (to.toy.gestures as Gestures).rival_gesture()
		if pose == Gestures.G.WAVE and back == Gestures.G.WAVE and _rng.randf() < 0.6:
			to.toy.gestures.play(Gestures.G.WAVE, _side_of(to, by), 1.0, 0.45)
	events.append({"type": "alongside", "by": by, "to": to, "gesture": pose})


## Racers that just finished or crashed (main.gd keeps them on screen in `leaving`): racers close
## to a crash flinch and look; two finishing within FINISH_TOGETHER_S cheer together.
func _left_course() -> void:
	var left: Dictionary = main.leaving
	for id in left:
		var v = left[id]
		if not is_instance_valid(v) or v.toy == null or _seen_left.has(v.get_instance_id()):
			continue
		_seen_left[v.get_instance_id()] = true
		if v.leaving == "failed":
			for o in _kits:
				if o.global_position.distance_squared_to(v.global_position) < CRASH_NEAR * CRASH_NEAR:
					o.toy.gestures.play(Gestures.G.FLINCH, 0, 0.0, _rng.randf_range(0.0, 0.15))
					o.toy.look_at_node(v.toy.head_pivot, 1.4)
					o.react_cool = maxf(o.react_cool, 1.5)
					events.append({"type": "flinch", "view": o, "crash": v})
		elif v.leaving == "finished":
			for f in _finishers:
				var o = f[1]
				if not v.cheered and _clock - float(f[0]) <= FINISH_TOGETHER_S and is_instance_valid(o) \
						and o.leaving == "finished" and not o.cheered \
						and o.global_position.distance_squared_to(v.global_position) < TOGETHER_NEAR * TOGETHER_NEAR:
					_cheer_together(v, o)
			_finishers.append([_clock, v])
	while not _finishers.is_empty() and _clock - float(_finishers[0][0]) > FINISH_TOGETHER_S:
		_finishers.pop_front()


func _cheer_together(a, b) -> void:
	a.cheered = true
	b.cheered = true
	for p in [[a, b], [b, a]]:
		var g: Gestures = p[0].toy.gestures
		g.stop(g.sig_pose)
		g.stop(Gestures.G.WAVE)
		g.play(Gestures.G.CHEER, 0, 1.5)
		p[0].toy.look_at_node(p[1].toy.head_pivot, 1.5)
	events.append({"type": "finish_together", "views": [a, b]})


# ---------------------------------------------------------------- start grid

## Waiting on the grid for green: look at the neighbours, a fidget, a wave to the crowd or the
## signature gesture while there is time; lean in (and the ride crouches) for the last
## GRID_LEAN_S, with a nod on each second of the lights.
func _grid(v, delta: float) -> void:
	var sim = main.sim
	var id: String = v.racer.run_id
	var go_in := float(int(sim.go_tick.get(id, sim.tick)) - sim.tick) / Tuning.HZ
	var toy: ToyRacer = v.toy
	var g: Gestures = toy.gestures
	if v.grid_t < 0.0:
		v.grid_t = 0.0
		v.grid_next = _rng.randf_range(0.35, 0.7)
		v.grid_beat = ceili(go_in)
		v.grid_ready = false
		_look_around(v, 1.0)
	v.grid_t += delta
	if v.grid_t >= v.grid_next and go_in > GRID_CALM_S + 0.5:
		v.grid_next = v.grid_t + _rng.randf_range(1.2, 2.0)
		var pose := g.fidget_gesture()
		if pose == Gestures.G.WAVE:
			g.look_at_camera(1.4)  # a wave to the crowd and the big screen
			g.play(pose, 1, 1.2)
		else:
			g.play(pose)
		if _rng.randf() < 0.6:
			toy.ride.fidget()
		elif _rng.randf() < 0.5:
			_look_around(v, 0.9)
	if go_in < GRID_LEAN_S:
		toy.ride.crouch(1.0 - go_in / GRID_LEAN_S)
		if not v.grid_ready:
			v.grid_ready = true
			g.hold(Gestures.G.READY, true)
	if go_in < GRID_CALM_S:
		for f in [Gestures.G.SCRATCH, Gestures.G.TAP, Gestures.G.STRETCH, Gestures.G.WAVE, g.sig_pose]:
			g.stop(f)
	var beat := ceili(go_in)
	if beat < v.grid_beat and beat >= 1:
		g.kick(Vector3(0.0, -2.0, 0.0))  # a nod on each light
		toy.ride.fidget()
	v.grid_beat = beat


## Green: hands up and a whoop, the ride leaps off.
func _go(v) -> void:
	v.grid_t = -1.0
	var g: Gestures = v.toy.gestures
	g.hold(Gestures.G.READY, false)
	for f in [Gestures.G.SCRATCH, Gestures.G.TAP, Gestures.G.STRETCH, Gestures.G.WAVE, g.sig_pose]:
		g.stop(f)
	g.play(Gestures.G.WHOOP, 0, 0.9)
	v.toy.ride.go()
	events.append({"type": "go", "view": v})


## Look at the nearest other racer waiting on the grid, or at the camera when alone.
func _look_around(v, secs: float) -> void:
	var best = null
	var best_d := 64.0
	for k in main.views:
		var o = main.views[k]
		if o == v or o.get("toy") == null or not o.parked:
			continue
		var d2: float = o.global_position.distance_squared_to(v.global_position)
		if d2 < best_d:
			best_d = d2
			best = o
	if best != null:
		v.toy.look_at_node(best.toy.head_pivot, secs)
	else:
		v.toy.gestures.look_at_camera(secs)

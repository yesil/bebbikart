extends Node
## Race-wide reactions of the kit racers (main.gd adds one as a child): overtakes (the passer
## pumps a fist or waves and glances back, the passed racer's head follows them), a brace just
## before two racers bump, and the weather (rain, wind) for every driver. Runs after main.gd
## has synced the views each frame. Placeholder views (no toy) are skipped. Finish and crash
## reactions are the views' own (KitRacerView.leave()).

const Gestures = preload("res://racer_kit/racer_gestures.gd")
const PASS_NEAR := 7.0       # m: only racers this close can overtake each other
const PASS_LANE := 4.0       # m sideways: further apart is not a pass (other road, fork)
const PASS_GAP := 0.6        # m along the road either side before an order flip counts
const COOL := 3.0            # s between overtake reactions of one racer
const BRACE_DIST := 1.8      # m between racers
const BRACE_CLOSING := 2.5   # m/s closing speed
const BRACE_COOL := 1.0

var main                     # main.gd: reads views and sim
## This frame's events, for tools: {"type": "overtake", "passer": view, "passed": view}.
var events: Array = []

var _order := {}             # pair key -> 1 / -1: which of the two was ahead along the road
var _kits: Array = []        # racing kit views this frame (reused)
var _next_id := 0
var _sweep := 0.0


func _init(p_main) -> void:
	main = p_main
	name = "RaceReactions"


func _process(delta: float) -> void:
	if main.sim == null or delta <= 0.0:
		return
	events.clear()
	var w = main.sim.weather
	var rain: float = w.rain_intensity()
	var wind: Vector3 = w.wind_vec()
	_kits.clear()
	for k in main.views:
		var v = main.views[k]
		if v.get("toy") == null or v.racer == null or v.racer.state != "racing":
			continue
		v.toy.rain = rain
		v.toy.wind = wind
		if v.react_id < 0:
			v.react_id = _next_id
			_next_id += 1
		v.react_cool = maxf(0.0, v.react_cool - delta)
		v.brace_cool = maxf(0.0, v.brace_cool - delta)
		_kits.append(v)
	for i in _kits.size():
		for j in range(i + 1, _kits.size()):
			_pair(_kits[i], _kits[j], delta)
	for v in _kits:
		v.react_prev = v.global_position
	# Forget pairs of racers that left now and then.
	_sweep -= delta
	if _sweep <= 0.0:
		_sweep = 5.0
		var live := {}
		for v in _kits:
			live[v.react_id] = true
		for key in _order.keys():
			if not live.has(key >> 16) or not live.has(key & 0xffff):
				_order.erase(key)


func _pair(a, b, delta: float) -> void:
	var lo = a if a.react_id < b.react_id else b
	var hi = b if lo == a else a
	var key: int = (lo.react_id << 16) | hi.react_id
	var d: Vector3 = hi.global_position - lo.global_position
	var dist2 := d.length_squared()
	if dist2 > PASS_NEAR * PASS_NEAR:
		_order.erase(key)
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
	if dist2 - along * along > PASS_LANE * PASS_LANE:
		return
	var sgn := 1 if along > PASS_GAP else (-1 if along < -PASS_GAP else 0)
	if sgn == 0:
		return
	var before: int = _order.get(key, 0)
	_order[key] = sgn
	if before != 0 and before != sgn:
		# hi was ahead (+1) and now lo is (-1): lo passed hi, and the other way round.
		_overtake(lo if sgn < 0 else hi, hi if sgn < 0 else lo)


func _overtake(passer, passed) -> void:
	events.append({"type": "overtake", "passer": passer, "passed": passed})
	if passer.react_cool <= 0.0:
		passer.react_cool = COOL
		var g: Gestures = passer.toy.gestures
		var local: Vector3 = passer.toy.global_transform.affine_inverse() * passed.global_position
		var toward := 1 if local.x > 0.0 else -1
		# Cheer with the arm away from the racer just passed, glance back at them.
		g.play(g.pass_pose, -toward)
		g.play(Gestures.G.GLANCE_BACK, toward, 1.1, 0.25)
		passer.toy.look_at_node(passed.toy.head_pivot, 1.3)
	if passed.react_cool <= 0.0:
		passed.react_cool = COOL
		passed.toy.look_at_node(passer.toy.head_pivot, 1.5)

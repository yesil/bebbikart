extends Node
## Race-wide reactions of the kit racers (main.gd adds one as a child): overtakes (the passer
## pumps a fist, waves or taunts and glances back, the passed racer's head follows them, a grumpy
## one shakes its head), a brace just before two racers bump, a wave or a cheeky taunt to a rival
## driving alongside, an "eek" flinch when a racer close by crashes, both cheering when two cross
## the line within FINISH_TOGETHER_S (two friends side by side high-five, hands meeting), and the
## weather (rain, wind) for every driver. Each driver remembers being passed (grumpier) and
## passing (cockier): RacerGestures.mood_mem. Each pair of players remembers who passed whom and
## who waved at whom (`_rivals`, for the whole game session): passing back someone who passed you
## earns them a revenge fist shake, and friends (more waves than passes) high-five at the line.
## On the start grid (sim countdown): fidgets, looks at the neighbours, a fist bump with a
## neighbour in reach, a wave to the crowd or the signature gesture, leaning in on 3-2-1 with the
## eyes on the start lights (the gantry's lamps where the track has a start gantry, the road
## ahead where it has none), a whoop on green (the ride crouches and leaps too).
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
const BUMP_LANE := 2.3       # m sideways: grid neighbours this close may fist-bump (lanes are 2 m apart)
const BUMP_AFTER_S := 0.4    # s on the grid before a fist bump
const LIGHTS_PATH := "StartGrid/StartGantry"  # the countryside's start gantry with its lamps (seed_decor.gd)
const LINGER_GAP := 0.25     # m kept between finishers standing after their run, and from racers going by
const NUDGE_SPEED := 10.0    # m/s they slide apart at
const OLD_S := 1.2           # s after its run a finisher has had its moment (cheer done)
const SQUEEZE_S := 0.25      # s two finishers may stay pressed together in a crowd before one pops
const HF_SIDE := Vector2(3.0, 3.5)  # m along / sideways: two finishers this close can high-five
const HF_S := 2.0            # s the high five may take (roll level within reach, then slap hands)
const HF_LINE_UP_S := 0.7    # s at most to roll level before the slap starts anyway
const HF_GAP := 0.045        # m each hand stops short of the meeting point (flat palms touching)

var main                     # main.gd: reads views, leaving views and sim
## This frame's events, for tools: {"type": "overtake" | "alongside" | "flinch" | "finish_together"
## | "go", "passer"/"passed" | "by"/"to" | "view" | "views": ...}.
var events: Array = []

var _order := {}             # pair key -> 1 / -1: which of the two was ahead along the road
var _side_t := {}            # pair key -> seconds alongside
var _side_cool := {}         # pair key -> seconds until it may happen again
var _kits: Array = []        # racing kit views this frame (reused)
var _lingering: Array = []   # finishers / crashed racers still on screen (reused)
var _squeezed := {}          # "id-id" -> seconds two finishers have been pressed together
var _next_id := 0
var _sweep := 0.0
var _clock := 0.0
var _seen_left := {}         # instance id of a view that left (finished / crashed) -> true
var _finishers: Array = []   # [[clock, view], ...] recent finishers
var _rng := RandomNumberGenerator.new()
## "playerA|playerB" (sorted) -> {playerA: times A passed B, playerB: times B passed A, "bond":
## waves minus passes}. Kept for the whole game session, across runs.
var _rivals := {}
var _lamps: Array = []       # the start gantry's lamps, looked up once; empty on a track without one
var _lamps_looked := false


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
	_high_fives(delta)
	_keep_apart(delta)
	if _lingering.is_empty():
		_squeezed.clear()
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
	var rec := _rivalry(passer, passed)
	var me: String = passer.racer.player_id
	var them: String = passed.racer.player_id
	var revenge := int(rec.get(them, 0)) > int(rec.get(me, 0))  # they had passed me more often
	rec[me] = int(rec.get(me, 0)) + 1
	rec.bond = int(rec.bond) - 1
	if passer.react_cool <= 0.0:
		passer.react_cool = COOL
		var toward := _side_of(passer, passed)
		if revenge:
			# Got them back: a fist shaken at them over the shoulder.
			g.play(Gestures.G.SHAKE_FIST, toward)
			passer.toy.look_at_node(passed.toy.head_pivot, 1.4)
			events.append({"type": "revenge", "passer": passer, "passed": passed})
		else:
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


## The two players' shared memory (see `_rivals`).
func _rivalry(a, b) -> Dictionary:
	var pa: String = a.racer.player_id
	var pb: String = b.racer.player_id
	var key := pa + "|" + pb if pa < pb else pb + "|" + pa
	if not _rivals.has(key):
		_rivals[key] = {pa: 0, pb: 0, "bond": 0}
	return _rivals[key]


## Friends: no more passes than waves between them, and neither in a grump.
func _friends(a, b) -> bool:
	return int(_rivalry(a, b).bond) >= 0 and a.toy.gestures.mood_mem > -0.45 and b.toy.gestures.mood_mem > -0.45


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
	if pose == Gestures.G.WAVE:
		_rivalry(by, to).bond = int(_rivalry(by, to).bond) + 1
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
					if _friends(v, o) and _can_high_five(v, o):
						_high_five(v, o)
					else:
						_cheer_together(v, o)
			_finishers.append([_clock, v])
	while not _finishers.is_empty() and _clock - float(_finishers[0][0]) > FINISH_TOGETHER_S:
		_finishers.pop_front()


## Finishers coasting and standing after their run (main.leaving) slide apart sideways, and the
## one behind stops behind, so two never sit inside each other (and none inside a racer going by).
func _keep_apart(delta: float) -> void:
	_lingering.clear()
	for id in main.leaving:
		var v = main.leaving[id]
		if is_instance_valid(v) and v.toy != null and v.leaving != "":
			_lingering.append(v)
	for i in _lingering.size():
		var a = _lingering[i]
		for j in range(i + 1, _lingering.size()):
			if a.hf_with != _lingering[j] or not _slapping(a):  # mid-slap, a pair keeps its own distance
				_apart(a, _lingering[j], true, delta)
		for b in _kits:
			_apart(a, b, false, delta)


func _apart(a, b, both: bool, delta: float) -> void:
	var fwd: Vector3 = a.forward()
	fwd.y = 0.0
	fwd = fwd.normalized()
	var n := Vector3(-fwd.z, 0.0, fwd.x)  # the road's +d side (Route.normal_at)
	var d: Vector3 = b.global_position - a.global_position
	var along := d.dot(fwd)
	var lat := d.dot(n)
	var ha: Vector2 = a.half_size()
	var hb: Vector2 = b.half_size()
	var gap_lat := absf(lat) - (ha.x + hb.x + LINGER_GAP)
	var gap_along := absf(along) - (ha.y + hb.y + LINGER_GAP)
	if gap_lat >= 0.0:
		return  # side by side with room
	# Away from the other one; when right in line, toward the road edge it is already nearer.
	var away := -signf(lat) if absf(lat) > 0.05 else (1.0 if float(a._leave_d) >= 0.0 else -1.0)
	var step := NUDGE_SPEED * delta
	var lock_a := _slapping(a)
	if not both:
		# A racer going by: overlapping, or coming up behind within 8 m: get out of its way (not
		# in the middle of a high five).
		if not lock_a and (gap_along < 0.0 or (along < 0.0 and gap_along < 8.0)):
			a.nudge(away * minf(step * 1.5, -gap_lat), 0.0)
		return
	var lock_b := _slapping(b)
	if lock_a and lock_b:
		return  # two pairs mid-slap side by side: a moment, then they move again
	if lock_a != lock_b:
		# One of them is mid high five and stays put: the other moves the whole way, sideways and
		# back off along the road, and pops away if it stays pressed against them.
		var mover = b if lock_a else a
		var dir := -away if lock_a else away
		if gap_along < 0.0:
			var behind: bool = (along < 0.0) if mover == b else (along > 0.0)
			mover.nudge(dir * minf(step, -gap_lat), minf(step, -gap_along) * (1.0 if behind else -1.0))
			mover._leave_v = 0.0
			if _squeeze(a, b, delta) > SQUEEZE_S and mover._leave_t > mover.POP:
				mover._leave_t = mover.POP
		return
	var back = a if along > 0.0 else b
	var front = b if back == a else a
	if gap_along < 0.0:
		# A crowd at the line: one that has had its moment pops away now instead of standing inside
		# the newcomer.
		var older = a if a._leave_t < b._leave_t else b
		var stay: float = older.FINISH_STAY if older.leaving == "finished" else older.FAIL_STAY
		# Squeezed together in a crowd for a moment, or one has had its cheer already: it pops.
		var had: float = stay - older._leave_t
		if (had > OLD_S or (_squeeze(a, b, delta) > SQUEEZE_S and had > 0.6)) and older._leave_t > older.POP:
			older._leave_t = older.POP
			return
		a.nudge(away * minf(step, -gap_lat) * 0.5, 0.0)
		b.nudge(-away * minf(step, -gap_lat) * 0.5, 0.0)
		back._leave_v = minf(back._leave_v, front._leave_v)
		back.nudge(0.0, minf(step, -gap_along))
	elif back._leave_v > front._leave_v and gap_along < (back._leave_v - front._leave_v) * 0.5:
		back._leave_v = front._leave_v + gap_along / 0.5  # ease in behind it


## Side by side (HF_SIDE) and their arms can bridge the gap they must keep (LINGER_GAP).
func _can_high_five(a, b) -> bool:
	var fwd: Vector3 = a.forward()
	fwd.y = 0.0
	fwd = fwd.normalized()
	var d: Vector3 = b.global_position - a.global_position
	if absf(d.dot(fwd)) > HF_SIDE.x or absf(d.dot(Vector3(-fwd.z, 0.0, fwd.x))) > HF_SIDE.y:
		return false
	var need: float = a.half_size().x + b.half_size().x + LINGER_GAP
	var reach: float = a.toy.gestures.high_five_reach(_side_of(a, b)) + b.toy.gestures.high_five_reach(_side_of(b, a))
	return reach * 0.88 >= need


func _high_five(a, b) -> void:
	a.cheered = true
	b.cheered = true
	a.hf_with = b
	b.hf_with = a
	a.hf_t = 0.0
	b.hf_t = 0.0
	a.hf_go = -1.0
	b.hf_go = -1.0
	for p in [[a, b], [b, a]]:
		var g: Gestures = p[0].toy.gestures
		g.stop(g.sig_pose)
		g.stop(Gestures.G.WAVE)
		g.stop(Gestures.G.CHEER)
		p[0].toy.look_at_node(p[1].toy.head_pivot, HF_S)


## Both lined up: the slap.
func _slap(a, b) -> void:
	events.append({"type": "high_five", "views": [a, b]})
	a.hf_go = a.hf_t
	b.hf_go = b.hf_t
	for v in [a, b]:
		v._leave_t = maxf(v._leave_t, Gestures.HF_PART + 0.6)  # both stay until the hands have parted
	for p in [[a, b], [b, a]]:
		var g: Gestures = p[0].toy.gestures
		g.high_five(_meet(p[0], p[1]), _side_of(p[0], p[1]))
		g.play(Gestures.G.CHEER, 0, 0.9, Gestures.HF_PART + 0.15)


## Where a's hand slaps b's: between their shoulders (nearer the shorter arm's), a little above
## them, a palm's thickness short of the meeting point.
func _meet(a, b, up := 0.15) -> Vector3:
	var ga: Gestures = a.toy.gestures
	var gb: Gestures = b.toy.gestures
	var sa: Vector3 = ga.character.global_transform * ga._shoulder[0 if _side_of(a, b) < 0 else 1]
	var sb: Vector3 = gb.character.global_transform * gb._shoulder[0 if _side_of(b, a) < 0 else 1]
	var ra := ga.high_five_reach(_side_of(a, b))
	var rb := gb.high_five_reach(_side_of(b, a))
	var mid := sa.lerp(sb, ra / maxf(ra + rb, 0.01)) + Vector3.UP * up
	var dir := sb - sa
	dir.y = 0.0
	return mid - dir.normalized() * HF_GAP


## High-fiving pairs: they roll to a stop side by side, just within reach of each other, and their
## hands keep aiming at the moving meeting point.
func _high_fives(delta: float) -> void:
	for id in main.leaving:
		var a = main.leaving[id]
		if not is_instance_valid(a) or a.hf_with == null:
			continue
		var b = a.hf_with
		if not is_instance_valid(b) or a.hf_t > HF_S:
			a.hf_with = null
			continue
		a.hf_t += delta
		if a.get_instance_id() > b.get_instance_id():
			continue  # each pair once
		var v := minf(a._leave_v, b._leave_v)
		a._leave_v = v
		b._leave_v = v
		var fwd: Vector3 = a.forward()
		fwd.y = 0.0
		fwd = fwd.normalized()
		var n := Vector3(-fwd.z, 0.0, fwd.x)
		var d: Vector3 = b.global_position - a.global_position
		var lat := d.dot(n)
		var reach: float = a.toy.gestures.high_five_reach(_side_of(a, b)) + b.toy.gestures.high_five_reach(_side_of(b, a))
		var want := maxf(a.half_size().x + b.half_size().x + LINGER_GAP, reach * 0.78)
		var move := clampf(absf(lat) - want, -6.0 * delta, 6.0 * delta) * 0.5 * signf(lat)
		a.nudge(move, 0.0)
		b.nudge(-move, 0.0)
		var along := d.dot(fwd)
		var need: float = a.half_size().y + b.half_size().y + LINGER_GAP
		if absf(lat) >= a.half_size().x + b.half_size().x + LINGER_GAP - 0.02 or absf(along) >= need:
			var back = a if along > 0.0 else b
			back.nudge(0.0, clampf(-absf(along), -6.0 * delta, 0.0))  # draw level (only where they cannot touch)
		if a.hf_go < 0.0:
			if absf(absf(lat) - want) < 0.12 and absf(along) < 0.35:
				_slap(a, b)
			elif a.hf_t > HF_LINE_UP_S:
				# The crowd at the line kept them apart: they cheer together instead.
				a.hf_with = null
				b.hf_with = null
				_cheer_together(a, b)
				continue
		a.toy.gestures.high_five_point(_meet(a, b))
		b.toy.gestures.high_five_point(_meet(b, a))


## Seconds two finishers have been pressed together (counts this frame's delta).
func _squeeze(a, b, delta: float) -> float:
	var key := "%d-%d" % [mini(a.get_instance_id(), b.get_instance_id()), maxi(a.get_instance_id(), b.get_instance_id())]
	_squeezed[key] = float(_squeezed.get(key, 0.0)) + delta
	return _squeezed[key]


## Mid-slap (lined up, until the hands part): the pair is not pushed around by the others.
func _slapping(v) -> bool:
	return v.hf_with != null and v.hf_go >= 0.0 and v.hf_t - v.hf_go < Gestures.HF_PART + 0.15


## A high five needs the two to roll level within reach (HF_LINE_UP_S); a pair the crowd keeps
## apart cheers together instead.
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
		v.grid_bumped = false
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
	if not v.grid_bumped and v.grid_t > BUMP_AFTER_S and go_in > GRID_CALM_S + 0.5:
		_fist_bump(v)
	if go_in < GRID_LEAN_S:
		toy.ride.crouch(1.0 - go_in / GRID_LEAN_S)
		if not v.grid_ready:
			v.grid_ready = true
			g.hold(Gestures.G.READY, true)
			_watch_lights(v, go_in + 0.3)
	if go_in < GRID_CALM_S:
		for f in [Gestures.G.SCRATCH, Gestures.G.TAP, Gestures.G.STRETCH, Gestures.G.WAVE, g.sig_pose]:
			g.stop(f)
	var beat := ceili(go_in)
	if beat < v.grid_beat and beat >= 1:
		g.kick(Vector3(0.0, -2.0, 0.0))  # a nod on each light
		toy.ride.fidget()
	v.grid_beat = beat


## Eyes on the start lights: the nearest lamp of the start gantry, or up the road ahead on a track
## without one.
func _watch_lights(v, secs: float) -> void:
	if not _lamps_looked:
		_lamps_looked = true
		for c in main.get_children():
			var gantry: Node = c.get_node_or_null(LIGHTS_PATH)
			if gantry != null:
				for l in gantry.get_children():
					if String(l.name).begins_with("Lamp") and not String(l.name).begins_with("LampHousing"):
						_lamps.append(l)
	if _lamps.is_empty():
		v.toy.look_at_point(v.global_position + v.forward() * 8.0 + Vector3.UP * 3.0, secs)
		return
	var best: Node3D = _lamps[0]
	for l in _lamps:
		if (l as Node3D).global_position.distance_squared_to(v.global_position) < best.global_position.distance_squared_to(v.global_position):
			best = l
	v.toy.look_at_node(best, secs)


## A fist bump with the nearest grid neighbour (both waiting a moment, neither bumped yet) whose
## fist it can reach; they look at each other first.
func _fist_bump(v) -> void:
	for k in main.views:
		var o = main.views[k]
		if o == v or o.get("toy") == null or not o.parked or o.grid_bumped or o.grid_t < 0.1:
			continue
		var d: Vector3 = o.global_position - v.global_position
		var fwd: Vector3 = v.forward()
		if absf(d.dot(fwd)) > 0.8 or Vector2(d.x, d.z).length() > BUMP_LANE:
			continue
		var reach: float = v.toy.gestures.high_five_reach(_side_of(v, o), Gestures.FB_REACH) \
			+ o.toy.gestures.high_five_reach(_side_of(o, v), Gestures.FB_REACH)
		if reach * 0.97 < Vector2(d.x, d.z).length():
			continue
		v.grid_bumped = true
		o.grid_bumped = true
		for p in [[v, o], [o, v]]:
			p[0].toy.look_at_node(p[1].toy.head_pivot, 0.9)
			p[0].toy.gestures.fist_bump(_meet(p[0], p[1], -0.05), _side_of(p[0], p[1]))
		events.append({"type": "fist_bump", "views": [v, o]})
		return


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

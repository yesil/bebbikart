extends RefCounted
## Village surprises: cows that wander onto the road and graze there, little flocks of sheep
## crossing it, cheese wheels rolling across from the dairy, hay bales a cart has lost. They turn
## up at random times at random places of the course's `obstacle_spots` ({seg, a, b, kinds}),
## never right in front of a kart, and always leave room to pass. Steering round them is free; a
## kart that hits one is knocked about and loses time (sim/racer.gd hit_obstacle, the `obstacle`
## run event). Hands off, the autopilot slows down and steers round them, so a kid who steers past
## early is faster. Pure data, like the rest of the sim: world/obstacle_views.gd draws them.
## main.gd turns them on for the game; the balance tools build their sims without them, so their
## baselines mean the same.
##
## An item is one animal, wheel or bale, in its segment's road frame: {id, group, kind, seg, s, d,
## rel (body yaw against the road: 0 faces the way karts drive, ±PI/2 across), vd (m/s across),
## state, t (seconds in it), wait (seconds before it sets off), target, hit}. States:
##   in      walking or rolling onto the road (sheep and cheese keep going right across);
##   stay    grazing (a cow) or lying there (hay);
##   out     leaving the road;
##   scared  hit by a kart: running, rolling or tumbling off, never hit again;
##   gone    off the road for good (dropped next tick).

const Tuning = preload("res://sim/tuning.gd")
const Course = preload("res://sim/course.gd")

## Per kind: body half size (x across its body, y nose to tail, metres), how many in a group,
## speed (m/s) going in and out, fleeing once hit, and how long it stays on the road [min, max] s
## (0: it doesn't stop, it crosses).
const KINDS := {
	"cow": {"half": Vector2(0.5, 1.3), "count": [1, 1], "move": 1.2, "flee": 3.5, "stay": [7.0, 13.0]},
	"sheep": {"half": Vector2(0.35, 0.75), "count": [3, 4], "move": 1.1, "flee": 3.5, "stay": [0.0, 0.0]},
	"cheese": {"half": Vector2(0.21, 0.62), "count": [2, 3], "move": 2.4, "flee": 5.0, "stay": [0.0, 0.0]},
	"hay": {"half": Vector2(0.55, 0.6), "count": [2, 3], "move": 0.0, "flee": 3.0, "stay": [9.0, 15.0]},
}
const MAX_GROUPS := 3
const FIRST_S := 3.0              # the first surprise this long after the start
const GAP_S := Vector2(2.0, 7.0)  # between surprises
const RETRY_S := 0.5              # no spot free of karts: look again this soon
const CLEAR_M := 40.0             # never turns up closer than this ahead of a kart
const VERGE := 1.4                # metres beyond the rail limit animals walk in from and off to
const HAY_DROP_S := 0.6           # a bale falls off the cart: hit only once it has landed
const HAY_PICK_S := 0.8           # a bale being picked up shrinks away this long (not in the way)
const SHEEP_SPREAD := Vector2(1.2, 1.6)  # a flock's spread across and along the road (metres)
const CHEESE_EVERY := 5.0         # metres between wheels along the road
const CHEESE_DELAY := 0.8         # seconds between wheels setting off
const PASS_S := 0.7               # seconds a kart takes to get past one (where a mover is meanwhile)

var course
var rng := RandomNumberGenerator.new()
var items: Array = []             # every item on or by the road
var groups := {}                  # group id -> {kind, spot, seg, s, until}
var _next_id := 1
var _next_tick := 0
var _tick := 0
var _by_seg := {}                 # segment id -> its items, rebuilt every step
## False: no new surprises turn up (the ones on the road still leave in their own time).
var enabled := true
var spawned := 0                  # groups so far (tools/obstacle_check.gd)


func _init(p_course, seed_: int) -> void:
	course = p_course
	rng.seed = seed_
	_next_tick = int(FIRST_S * Tuning.HZ)
	for sp in course.obstacle_spots:
		var seg: Dictionary = course.segments.get(sp["seg"], {})
		if seg.is_empty() or String(seg["fork"]) != "":
			push_error("obstacles: spot on %s is not a plain segment of %s" % [sp["seg"], course.NAME])
		for k in sp["kinds"]:
			if not KINDS.has(k):
				push_error("obstacles: spot on %s has an unknown kind \"%s\"" % [sp["seg"], k])


## Problems with the course's spots ("" when they are fine): main.gd refuses to start them.
func check() -> String:
	for sp in course.obstacle_spots:
		var seg: Dictionary = course.segments.get(sp["seg"], {})
		if seg.is_empty():
			return "spot on unknown segment %s" % sp["seg"]
		if String(seg["fork"]) != "":
			return "spot on fork way %s" % sp["seg"]
		var len_: float = seg["route"].length
		if float(sp["a"]) < 4.0 or float(sp["b"]) > len_ - 4.0 or float(sp["a"]) >= float(sp["b"]):
			return "spot on %s runs %.0f..%.0f m of %.0f m" % [sp["seg"], sp["a"], sp["b"], len_]
		for k in sp["kinds"]:
			if not KINDS.has(k):
				return "spot on %s has an unknown kind \"%s\"" % [sp["seg"], k]
	return ""


func step(sim) -> void:
	_tick += 1
	var dt := Tuning.DT
	if enabled and _tick >= _next_tick and groups.size() < MAX_GROUPS:
		if _spawn(sim):
			_next_tick = _tick + int(rng.randf_range(GAP_S.x, GAP_S.y) * Tuning.HZ)
		else:
			_next_tick = _tick + int(RETRY_S * Tuning.HZ)
	var keep: Array = []
	_by_seg = {}
	for it: Dictionary in items:
		_move(it, dt)
		if it["state"] == "gone":
			continue
		keep.append(it)
		if not _by_seg.has(it["seg"]):
			_by_seg[it["seg"]] = []
		_by_seg[it["seg"]].append(it)
	items = keep
	for gid in groups.keys():
		var left := false
		for it in items:
			if int(it["group"]) == int(gid):
				left = true
				break
		if not left:
			groups.erase(gid)


# ---------------------------------------------------------------- turning up

func _spawn(sim) -> bool:
	var free: Array = []
	var taken := {}
	for gid in groups:
		taken[int(groups[gid]["spot"])] = true
	for i in course.obstacle_spots.size():
		if not taken.has(i):
			free.append(i)
	if free.is_empty():
		return false
	var spot_i: int = free[rng.randi() % free.size()]
	var sp: Dictionary = course.obstacle_spots[spot_i]
	var s := rng.randf_range(float(sp["a"]), float(sp["b"]))
	if not _clear_of_karts(sim, sp["seg"], s):
		return false
	var kinds: Array = sp["kinds"]
	place_group(sim, spot_i, kinds[rng.randi() % kinds.size()], s, -1.0 if rng.randf() < 0.5 else 1.0)
	return true


## A group of `kind` at spot spot_i, `s` metres along its segment, coming from `side` (-1, 1).
## Returns its id. _spawn picks these at random; tools/obstacle_shots.gd places them by hand.
func place_group(sim, spot_i: int, kind: String, s: float, side: float) -> int:
	var sp: Dictionary = course.obstacle_spots[spot_i]
	var seg: Dictionary = course.segments[sp["seg"]]
	var lim := Course.rail_lim(seg)
	var k: Dictionary = KINDS[kind]
	var n := rng.randi_range(int(k["count"][0]), int(k["count"][1]))
	var gid := _next_id
	_next_id += 1
	groups[gid] = {"kind": kind, "spot": spot_i, "seg": sp["seg"], "s": s, "side": side}
	spawned += 1
	match kind:
		"cow":
			# Wanders in from the verge to graze somewhere on the road, never quite at its edge.
			var target := rng.randf_range(-0.55, 0.55) * lim
			_add(gid, kind, sp["seg"], s, side * (lim + VERGE), {"target": target,
				"stay": rng.randf_range(k["stay"][0], k["stay"][1])})
		"sheep":
			# A little flock crossing together, from one verge to the other.
			for i in n:
				_add(gid, kind, sp["seg"], s + rng.randf_range(-SHEEP_SPREAD.y, SHEEP_SPREAD.y),
					side * (lim + VERGE + rng.randf_range(0.0, SHEEP_SPREAD.x)), {"target": -side * (lim + VERGE + 1.0),
					"speed": float(k["move"]) * rng.randf_range(0.9, 1.1)})
		"cheese":
			# Wheels from the dairy rolling right across, one after the other, each on its own line.
			for i in n:
				_add(gid, kind, sp["seg"], s + i * CHEESE_EVERY + rng.randf_range(-1.0, 1.0), side * (lim + VERGE),
					{"target": -side * (lim + VERGE + 1.0), "speed": float(k["move"]) * rng.randf_range(0.9, 1.1),
					"wait": i * CHEESE_DELAY * rng.randf_range(0.8, 1.3)})
		"hay":
			# Bales a cart has lost, side by side from the verge inwards (the other side stays free).
			for i in n:
				var it := _add(gid, kind, sp["seg"], s + rng.randf_range(-1.5, 1.5), side * (lim - 0.3 - i * 1.25),
					{"target": side * (lim - 0.3 - i * 1.25), "stay": rng.randf_range(k["stay"][0], k["stay"][1])})
				it["rel"] = rng.randf_range(-PI, PI)
				it["state"] = "stay"
				it["t"] = -HAY_DROP_S
	sim.emit("sim.obstacle_spawned", {"kind": kind, "seg": sp["seg"], "s": s})
	return gid


func _add(gid: int, kind: String, seg_id: String, s: float, d: float, extra: Dictionary) -> Dictionary:
	var it := {"id": _next_id, "group": gid, "kind": kind, "seg": seg_id, "s": s, "d": d,
		"rel": 0.0, "vd": 0.0, "state": "in", "t": 0.0, "wait": 0.0, "target": d, "speed": 0.0,
		"stay": 0.0, "hit": false}
	_next_id += 1
	it.merge(extra, true)
	if float(it["speed"]) <= 0.0:
		it["speed"] = float(KINDS[kind]["move"])
	items.append(it)
	return it


## No kart racing within CLEAR_M before the spot (nor right on it): a surprise never pops up
## under a kart's nose.
func _clear_of_karts(sim, seg_id: String, s: float) -> bool:
	for o in sim.racers:
		var i: int = o.path.find(seg_id)
		if i < 0:
			continue
		var ahead: float = o.offsets[i] + s - o.gs()
		if ahead < -10.0 and o.looping:
			ahead += o.total_len
		if ahead > -10.0 and ahead < CLEAR_M:
			return false
	return true


# ---------------------------------------------------------------- moving

func _move(it: Dictionary, dt: float) -> void:
	if float(it["wait"]) > 0.0:
		it["wait"] = float(it["wait"]) - dt
		return
	it["t"] = float(it["t"]) + dt
	var seg: Dictionary = course.segments[it["seg"]]
	var off_road := Course.rail_lim(seg) + VERGE + 0.8
	match String(it["state"]):
		"in":
			var to: float = float(it["target"]) - float(it["d"])
			var step_ := signf(to) * minf(absf(to), float(it["speed"]) * dt)
			it["vd"] = step_ / dt
			it["d"] = float(it["d"]) + step_
			it["rel"] = signf(to) * PI * 0.5 if absf(to) > 0.01 else float(it["rel"])
			if absf(to) <= 0.01:
				if float(it["stay"]) > 0.0:
					it["state"] = "stay"
					it["t"] = 0.0
					it["vd"] = 0.0
					# Grazing, it turns a little away from straight across.
					it["turn_to"] = float(it["rel"]) + rng.randf_range(-0.8, 0.8)
				else:
					it["state"] = "gone"
		"stay":
			it["vd"] = 0.0
			if it.has("turn_to"):
				it["rel"] = move_toward(float(it["rel"]), float(it["turn_to"]), 0.4 * dt)
			if float(it["t"]) >= float(it["stay"]):
				it["state"] = "out"
				it["t"] = 0.0
				# Back to the nearer verge (a bale is picked up where it lies).
				it["target"] = float(it["d"]) if it["kind"] == "hay" else signf(float(it["d"]) if absf(float(it["d"])) > 0.01 else 1.0) * off_road
		"out" when it["kind"] == "hay":
			# The farmer picks it up: it shrinks away (world/obstacle_views.gd), no longer in the way.
			if float(it["t"]) >= HAY_PICK_S:
				it["state"] = "gone"
		"out", "scared":
			var to: float = float(it["target"]) - float(it["d"])
			var speed: float = float(KINDS[it["kind"]]["flee"]) if it["state"] == "scared" else float(it["speed"])
			var step_ := signf(to) * minf(absf(to), speed * dt)
			it["vd"] = step_ / dt
			it["d"] = float(it["d"]) + step_
			if it["kind"] != "hay" and absf(to) > 0.01:
				it["rel"] = signf(to) * PI * 0.5
			if absf(to) <= 0.01:
				it["state"] = "gone"


# ---------------------------------------------------------------- queries

## Half the item's footprint across the road and along it (its body turned by rel).
static func half_d(it: Dictionary) -> float:
	var h: Vector2 = KINDS[it["kind"]]["half"]
	var rel := float(it["rel"])
	return absf(sin(rel)) * h.y + absf(cos(rel)) * h.x


static func half_s(it: Dictionary) -> float:
	var h: Vector2 = KINDS[it["kind"]]["half"]
	var rel := float(it["rel"])
	return absf(cos(rel)) * h.y + absf(sin(rel)) * h.x


## Whether a kart can still hit it: on (or overhanging) the road, not fleeing, landed.
func hittable(it: Dictionary) -> bool:
	if it["hit"] or float(it["wait"]) > 0.0 or float(it["t"]) < 0.0:
		return false
	if it["state"] != "in" and it["state"] != "stay" and (it["state"] != "out" or it["kind"] == "hay"):
		return false
	var seg: Dictionary = course.segments[it["seg"]]
	return absf(float(it["d"])) - half_d(it) < Course.rail_lim(seg) + Tuning.SIZE_HALF_WIDTH.y


## What racer r would hit ahead within `reach` metres on its segment and the next one, nearest
## first: [ds (metres from the kart's nose to the item's near edge), the lanes the item's middle
## sweeps across from now until the kart has passed it (Vector2 lo, hi), half its footprint
## across the road]. Items the kart is alongside count (ds < 0) until it is past them.
func ahead(r, reach: float) -> Array:
	var out: Array = []
	if not r.detour.is_empty():
		return out
	var base: float = -r.ls
	for j in range(r.seg_idx, mini(r.seg_idx + 2, r.segs.size())):
		var sg: Dictionary = r.segs[j]
		for it: Dictionary in _by_seg.get(sg["id"], []):
			if not hittable(it):
				continue
			var hs := half_s(it)
			var ds: float = base + float(it["s"]) - hs - r.half_len
			if ds > reach or ds < -(2.0 * hs + 2.0 * r.half_len):
				continue
			var eta := clampf(maxf(ds, 0.0) / maxf(r.v, 4.0), 0.0, 3.0)
			# From where it is now (never cut across in front of it) to where it is as the kart passes.
			var now := float(it["d"])
			var b := d_at(it, eta + PASS_S)
			out.append([ds, Vector2(minf(now, b), maxf(now, b)), half_d(it)])
		base += float(sg["route"].length)
	out.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	return out


## Where the item will be across the road in `t` seconds: on its way to its target (a grazing cow
## or a bale stays put).
static func d_at(it: Dictionary, t: float) -> float:
	var go := maxf(0.0, t - maxf(0.0, float(it["wait"])))
	var speed := absf(float(it["vd"]))
	if it["state"] == "in" and speed == 0.0:
		speed = float(it["speed"])
	return move_toward(float(it["d"]), float(it["target"]), speed * go)


## The kind of the nearest surprise on racer r's road within `reach` metres ahead (any segment of
## its lap), or "" (the HUD's warning).
func kind_ahead(r, reach: float) -> String:
	var best := reach
	var kind := ""
	for gid in groups:
		var g: Dictionary = groups[gid]
		var i: int = r.path.find(g["seg"])
		if i < 0:
			continue
		var any := false
		for it: Dictionary in _by_seg.get(g["seg"], []):
			if int(it["group"]) == int(gid) and hittable(it):
				any = true
				break
		if not any:
			continue
		var ahead_m: float = r.offsets[i] + float(g["s"]) - r.gs()
		if ahead_m > -6.0 and ahead_m < best:
			best = ahead_m
			kind = g["kind"]
	return kind


## Racer r hits an item: the item flees (the whole flock with a sheep) and the racer is knocked
## about. Called by Sim.step after the racers moved.
func collide(sim, r) -> void:
	if not r.detour.is_empty() or r.y - sim.course.surface_y(r.seg, r.ls) > 1.0:
		return
	for it: Dictionary in _by_seg.get(r.seg_id, []):
		if not hittable(it):
			continue
		if absf(r.ls - float(it["s"])) >= r.half_len + half_s(it) or absf(r.d - float(it["d"])) >= r.radius + half_d(it):
			continue
		var away := signf(r.d - float(it["d"]))
		if away == 0.0:
			away = 1.0
		_scare(it, -away)
		if it["kind"] == "sheep":
			for o: Dictionary in items:
				if int(o["group"]) == int(it["group"]) and not o["hit"] and float(o["wait"]) <= 0.0:
					_scare(o, signf(float(o["d"]) - r.d) if absf(float(o["d"]) - r.d) > 0.01 else -away)
		r.hit_obstacle(sim, it["kind"], away)
		sim.emit("sim.obstacle", {"runId": r.run_id, "kind": it["kind"], "item": it["id"], "pos": r.world_pos()})
		return


## Off the road, fast, away from the kart (dir: -1 or 1 across the road).
func _scare(it: Dictionary, dir: float) -> void:
	var seg: Dictionary = course.segments[it["seg"]]
	it["hit"] = true
	it["state"] = "scared"
	it["t"] = 0.0
	it["target"] = dir * (Course.rail_lim(seg) + VERGE + 2.0)

extends RefCounted
## The Swiss village circuit: a closed loop, driven clockwise lap after lap. Same segment format
## and the same sections and forks as sim/course.gd (hills/pond/crossing/bends; ramp, pond,
## crossing), so builds, splits and coach tips mean the same on both tracks:
##   start      Dorfplatz in front of the inn, start/finish line at s = 0, heading north.
##   hills      Up the main street between chalets to the church hill. Ramp fork: `jump` takes
##              the wooden ski-jump kicker over the hay meadow, `around` loops round the churchyard.
##   pond       Down to the village brook. Pond fork: `water` fords the duck pond, `bridge` swings
##              east over the inflow brook on a covered wooden bridge.
##   crossing   Along the south edge. Crossing fork: `exposed` is the open causeway over the
##              meadow (mountain view, wind), `sheltered` the arcade lane between the chalets.
##   bends      Round the fountain and the lime tree on the square, then the line again.
## Routes are drawn turtle style (see sim/course.gd `_draw`). Headings add up to one full turn
## and two free straights (east on the church hill, north on the square) are solved so the loop
## closes exactly. tools/village_map.gd draws and checks the result.

const Route = preload("res://sim/route.gd")
const Tuning = preload("res://sim/tuning.gd")
const Course = preload("res://sim/course.gd")
const Forks = preload("res://sim/forks.gd")

const LOOP := true
const NAME := "village"
const MIN_FREE := 6.0              # shortest allowed solved straight
## Headings (degrees, clockwise from north) of the four legs between the corners.
const LEG_CHURCH := 76.0           # up the church hill (ramp fork)
const LEG_BROOK := 178.0           # down to the brook (pond fork)
const LEG_SOUTH := 262.0           # along the south edge (crossing fork)
## Roundabout on the Dorfplatz (fountain on the island). Swiss traffic circulates
## anticlockwise, so the right turn north is a right-hand entry, ROUNDABOUT_TURN degrees of
## left-hand circulation round the island, and a right-hand exit.
const ROUNDABOUT_R := 14.0         # racing line radius round the island
const ROUNDABOUT_LANE_R := 12.5    # entry and exit curves
const ROUNDABOUT_TURN := 120.0
## Racers sometimes miss the exit and go round once more (sim/racer.gd "miss"): base chance per
## pass, scaled by driving style, boosting and rain there.
const MISS_EXIT_CHANCE := 0.07
const MISS_BEFORE_EXIT := 3.0
const RIDGE_R := 24.0              # hairpin round the alp top      # metres before the exit where the racer commits or not
## The alp pass (the ridge stretch): a long climb with a kink up to the hairpin and the same kink on
## the way down. Each kink moves the road sideways and back, and the two cancel, so the pass ends
## where a bare hairpin would: nothing else on the loop moves.
const PASS_EXTRA := 25.0           # straight added to the way up and to the way down
const PASS_KINK_R := 30.0
const PASS_KINK_DEG := 22.0
const PASS_TOP := 8.5              # road height at the hairpin

var segments := {}
var ordered_ids: Array[String] = []
var loop := LOOP
## Geometry problems found while building (the loop not closing). tools/village_map.gd fails on
## any; the game refuses to start the track.
var errors: PackedStringArray = []
## Solved free straights: over the church hill (heading LEG_CHURCH) and the last run north
## into the start line.
var free_hill := 0.0
var free_north := 0.0
## {centre: Vector2, radius: float (racing line), s0, s1 (circulating stretch on "bends")}
var roundabout := {}
## The forks' ways and the side each leaves on (sim/forks.gd ways()).
var forks := {}
## Village surprises (sim/obstacles.gd): where cows, sheep, cheese wheels and hay bales may turn
## up, {seg, a, b (metres along it), kinds}. Plain stretches only, clear of the start, the boost
## arrows and the run-in to each fork.
var obstacle_spots: Array = []
## Chocolate coins (sim/coins.gd): where their lines may lie, {seg, a, b (metres along it)}.
## Plain stretches only: clear of the start, the boost arrows, the roundabout, the forks and
## the run-in to each (a kid steering for a fork's side needs that road free).
var coin_ranges: Array = []


func _init() -> void:
	# The end point moves linearly with the two free straights, so one probe build solves them.
	_build(0.0, 0.0)
	var gap := Vector3.ZERO - _end("bends")
	if absf(gap.y) > 0.001:
		_error("loop heights do not close (%.3f m)" % gap.y)
	var dh := Vector2(sin(deg_to_rad(LEG_CHURCH)), cos(deg_to_rad(LEG_CHURCH)))
	free_hill = gap.x / dh.x
	free_north = gap.z - free_hill * dh.y
	if free_hill < MIN_FREE or free_north < MIN_FREE:
		_error("loop cannot close, free straights hill %.1f m, north %.1f m (need >= %.1f m)"
			% [free_hill, free_north, MIN_FREE])
	segments.clear()
	ordered_ids.clear()
	_build(free_hill, free_north)
	var miss := _end("bends").distance_to(Vector3.ZERO)
	if miss > 0.05:
		_error("loop misses the start line by %.2f m" % miss)
	for e in Course.stretch_errors(segments, NAME):
		_error(e)
	# Over the church hill past the boost arrows, the farm track, the cobbles by the dairy, the
	# alp ridge, past the mountain stream (a cheese wheel group runs up to 11 m past its own spot).
	var hill_end: float = (segments["hills2"]["route"] as Route).length - Tuning.FORK_APPROACH_M - 5.0
	obstacle_spots = [
		{"seg": "hills2", "a": 48.0, "b": hill_end, "kinds": ["cow", "hay", "cheese"]},
		{"seg": "farm", "a": 8.0, "b": 32.0, "kinds": ["cow", "sheep"]},
		{"seg": "cobbles", "a": 5.0, "b": 12.0, "kinds": ["sheep", "cheese"]},
		{"seg": "ridge", "a": 12.0, "b": 170.0, "kinds": ["cow", "sheep"]},
		{"seg": "alpbach", "a": 24.0, "b": 40.0, "kinds": ["cow", "sheep"]},
	]
	var seg_len := func(id: String) -> float: return (segments[id]["route"] as Route).length
	coin_ranges = [
		{"seg": "hills2", "a": 36.0, "b": seg_len.call("hills2") - Tuning.FORK_APPROACH_M * 0.75},
		{"seg": "farm", "a": 3.0, "b": seg_len.call("farm") - 3.0},
		{"seg": "cobbles", "a": 2.0, "b": seg_len.call("cobbles") - 2.0},
		{"seg": "ridge", "a": 4.0, "b": seg_len.call("ridge") - 4.0},
		{"seg": "alpbach", "a": 2.0, "b": seg_len.call("alpbach") - Tuning.FORK_APPROACH_M * 0.75},
		{"seg": "bends", "a": 3.0, "b": float(roundabout["s0"]) - 4.0},
	]
	forks = Forks.ways(self)
	for e in Forks.errors(forks):
		_error(e)


func _error(msg: String) -> void:
	errors.append(msg)
	push_error("village_course: " + msg)


func _build(hill: float, north: float) -> void:
	# Dorfplatz: the start/finish straight in front of the inn.
	var p := _draw_ops(Vector3.ZERO, 0.0, [["S", 14.0]], [[0.0, 0.0]])
	_add("start", "hills", "", "", p, 5.0, {"stretch": "main_street"})
	# Main street: a gentle S between the chalets, then right up the church hill.
	var ops := [["S", 3.0], ["A", 22.0, 16.0], ["A", 22.0, -16.0], ["S", 2.0], ["A", 18.0, LEG_CHURCH], ["S", 4.0]]
	var l1 := 3.0 + deg_to_rad(32.0) * 22.0 + 2.0 + deg_to_rad(LEG_CHURCH) * 18.0 + 4.0
	p = _draw_ops(_end("start"), _heading("start"), ops, [[0.0, 0.0], [8.0, 0.3], [l1 - 6.0, 2.9], [l1, 3.0]])
	_add("hills1", "hills", "", "", p, 4.0, {"bumps": [16.0], "stretch": "main_street"})
	# Ramp fork. Around: a lane peeling off round the churchyard wall (to the right as the big
	# screen shows it: sim/forks.gd measures every fork's sides). Jump: straight over the wooden
	# ski-jump kicker into the hay meadow.
	var j1 := _end("hills1")
	var h1 := _heading("hills1")
	var around_ops := [["S", 3.0], ["A", 20.0, -48.4], ["A", 20.0, 48.4], ["S", 2.0], ["A", 20.0, 48.4], ["A", 20.0, -48.4], ["S", 3.0]]
	var around_pts := _draw_ops(j1, h1, around_ops, [[0.0, 3.0]])
	var jump_len := _along(around_pts, h1)
	_add("ramp_jump", "hills", "ramp", "jump", _draw_ops(j1, h1, [["S", jump_len]], [[0.0, 3.0]]), 3.0, {
		"ramp": {"kick_a": 22.0, "lip_s": 28.0, "lip_h": 2.0, "land_s": 46.0, "pit_depth": 0.4},
		"stretch": "kicker",
	})
	_add("ramp_around", "hills", "ramp", "around", around_pts, 3.5, {"stretch": "churchyard"})
	# Over the hill top, then right and down to the brook.
	# Two easier half-turns with a breather between: one long 100-degree arc downhill threw
	# daring racers off in the rain.
	var half := (LEG_BROOK - LEG_CHURCH) * 0.5
	ops = [["S", hill], ["A", 24.0, half], ["S", 5.0], ["A", 24.0, half], ["S", 8.0]]
	var l2 := hill + deg_to_rad(half * 2.0) * 24.0 + 13.0
	p = _draw_ops(_end("ramp_jump"), _heading("ramp_jump"), ops, [[0.0, 3.0], [hill, 3.0], [l2, 0.4]])
	# Boost arrows on the left over the hill top, well before the downhill turns (no arrows on
	# the start: a kart leaving from an outer slot would drive over them without steering).
	_add("hills2", "hills", "", "", p, 4.0, {"boosts": [[20.0, 32.0, -1]], "stretch": "church_hill"})
	# Pond fork. Bridge: the lane swings off to the right over the inflow brook on a covered
	# wooden bridge. Water: a stone ford straight through the duck pond.
	var j3 := _end("hills2")
	var h3 := _heading("hills2")
	var bridge_ops := [["S", 3.0], ["A", 11.0, -75.0], ["A", 20.0, 75.0], ["S", 8.0], ["A", 20.0, 75.0], ["A", 11.0, -75.0], ["S", 3.0]]
	var bridge_pts := _draw_ops(j3, h3, bridge_ops, [[0.0, 0.4]])
	var bl := Course._length(bridge_pts["pts"])
	bridge_pts = _draw_ops(j3, h3, bridge_ops, [[0.0, 0.4], [bl * 0.5 - 11.0, 0.4], [bl * 0.5, 1.5], [bl * 0.5 + 11.0, 0.4], [bl, 0.4]])
	var ford_len := _along(bridge_pts, h3)
	_add("pond_water", "pond", "pond", "water", _draw_ops(j3, h3, [["S", ford_len]],
		[[0.0, 0.4], [12.0, 0.4], [20.0, -0.2], [ford_len - 20.0, -0.2], [ford_len - 12.0, 0.4], [ford_len, 0.4]]), 4.0,
		{"water": [[13.0, ford_len - 13.0]], "stretch": "ford"})
	# Wooden deck: slick in the rain (the ford doesn't care).
	_add("pond_bridge", "pond", "pond", "bridge", bridge_pts, 2.8, {"rails": true, "rain_slick": 1.6, "stretch": "covered_bridge"})
	# Past the mill and out of the village to the south, onto the alp: each stretch tests one
	# ability (a sign at its start says which).
	p = _draw_ops(_end("pond_water"), _heading("pond_water"), [["S", 14.0]], [[0.0, 0.4]])
	_add("mill", "pond", "", "", p, 4.0, {"stretch": "farm"})
	# Farm track (grip): a muddy S through the fields, climbing gently.
	p = _draw_ops(_end("mill"), _heading("mill"), [["S", 4.0], ["A", 16.0, 30.0], ["A", 16.0, -60.0], ["A", 16.0, 30.0], ["S", 4.0]],
		[[0.0, 0.4], [44.0, 2.2]])
	_add("farm", "crossing", "", "", p, 3.5, {"exposure": 0.3, "grip": 0.85, "stretch": "farm"})
	# Cobbled lane (bounce): straight on over cobbles and humps, still climbing.
	p = _draw_ops(_end("farm"), _heading("farm"), [["S", 28.0]], [[0.0, 2.2], [28.0, 4.0]])
	_add("cobbles", "crossing", "", "", p, 3.5, {"exposure": 0.3, "bumps": [5.0, 11.0, 17.0, 23.0], "stretch": "cobbles"})
	# Ridge (stability): up the alp pass, a wide hairpin round the top and back down, open to the
	# wind (PASS_*: the kinks up and down cancel, so it ends where a bare hairpin would).
	var kink := [["A", PASS_KINK_R, PASS_KINK_DEG], ["A", PASS_KINK_R, -PASS_KINK_DEG]]
	var kink_l := deg_to_rad(PASS_KINK_DEG * 2.0) * PASS_KINK_R
	var climb := PASS_EXTRA + kink_l
	var hairpin := deg_to_rad(180.0) * RIDGE_R
	var ridge_l := climb + hairpin + kink_l + PASS_EXTRA + 16.0
	p = _draw_ops(_end("cobbles"), _heading("cobbles"), [["S", PASS_EXTRA]] + kink + [["A", RIDGE_R, 180.0]] + kink + [["S", PASS_EXTRA + 16.0]],
		[[0.0, 4.0], [climb + hairpin * 0.5, PASS_TOP], [ridge_l, 3.4]])
	# Mandatory for everyone, so open but not as wild as the optional causeway.
	_add("ridge", "crossing", "", "", p, 3.8, {"exposure": 0.7, "stretch": "ridge"})
	# Alpbach (water): down through a stream, then left back into the village.
	var turn_in := LEG_SOUTH - LEG_BROOK - 180.0
	p = _draw_ops(_end("ridge"), _heading("ridge"), [["S", 30.0], ["A", 16.0, turn_in], ["S", 14.0]],
		[[0.0, 3.4], [11.0, 2.3], [13.5, 2.0], [20.0, 2.0], [26.0, 1.6], [30.0 + deg_to_rad(absf(turn_in)) * 16.0, 0.4]])
	_add("alpbach", "crossing", "", "", p, 3.5, {"exposure": 0.4, "water": [[12.5, 19.5]], "stretch": "alpbach"})
	# Crossing fork. Sheltered: the arcade lane loops off to the left in among the houses.
	# Exposed: a low causeway straight over the open meadow, facing the mountains.
	var j4 := _end("alpbach")
	var h4 := _heading("alpbach")
	var shelter_ops := [["S", 3.0], ["A", 14.0, 62.0], ["A", 14.0, -62.0], ["S", 6.0], ["A", 14.0, -62.0], ["A", 14.0, 62.0], ["S", 3.0]]
	var shelter_pts := _draw_ops(j4, h4, shelter_ops, [[0.0, 0.4]])
	var xl := _along(shelter_pts, h4)
	_add("cross_exposed", "crossing", "crossing", "exposed", _draw_ops(j4, h4, [["S", xl]],
		[[0.0, 0.4], [18.0, 0.4], [28.0, 1.4], [xl - 28.0, 1.4], [xl - 18.0, 0.4], [xl, 0.4]]), 2.6,
		{"exposure": 1.0, "low_rails": true, "stretch": "causeway"})
	_add("cross_sheltered", "crossing", "crossing", "sheltered", shelter_pts, 3.5, {"exposure": 0.0, "stretch": "arcades"})
	# Square: a chicane past the bakery, then the roundabout round the fountain turns the
	# course north to the line.
	var lane := (360.0 - LEG_SOUTH + ROUNDABOUT_TURN) * 0.5
	var chicane := [["S", 4.0], ["A", 12.0, -25.0], ["A", 12.0, 50.0], ["A", 12.0, -25.0], ["S", 12.0]]
	ops = chicane + [["A", ROUNDABOUT_LANE_R, lane], ["A", ROUNDABOUT_R, -ROUNDABOUT_TURN], ["A", ROUNDABOUT_LANE_R, lane], ["S", north]]
	p = _draw_ops(_end("cross_exposed"), _heading("cross_exposed"), ops, [[0.0, 0.4], [25.0, 0.0]])
	_add("bends", "bends", "", "", p, 3.5, {"stretch": "square"})
	var b: Dictionary = segments["bends"]
	var blen: float = (b["route"] as Route).length
	var rs0 := 16.0 + deg_to_rad(100.0) * 12.0 + deg_to_rad(lane) * ROUNDABOUT_LANE_R
	var rs1 := rs0 + deg_to_rad(ROUNDABOUT_TURN) * ROUNDABOUT_R
	var br: Route = b["route"]
	var mid := br.world_at((rs0 + rs1) * 0.5, ROUNDABOUT_R)
	roundabout = {"centre": Vector2(mid.x, mid.z), "radius": ROUNDABOUT_R, "s0": rs0, "s1": rs1}
	# One full extra circle, from just before the exit back to the same point. Not part of any
	# path: a racer that misses the exit drives it and rejoins "bends" where it left.
	var at := rs1 - MISS_BEFORE_EXIT
	var from := br.pos_at(at)
	var circle := _draw_ops(from, br.heading_at(at), [["A", ROUNDABOUT_R, -360.0]], [[0.0, from.y]])
	var lr := Route.new()
	lr.build(circle["pts"])
	segments["roundabout_loop"] = {
		"id": "roundabout_loop", "section": "bends", "fork": "", "choice": "", "route": lr,
		"half_width": 3.5, "edge": Tuning.OFF_TRACK_MARGIN, "rails": false, "exposure": 0.4,
		"water": [], "boosts": [], "bumps": [], "ramp": {}, "end_heading": br.heading_at(at),
		"stretch": "square",
	}
	b["miss"] = {"at": at, "seg": "roundabout_loop", "chance": MISS_EXIT_CHANCE}
	b["boosts"] = [[blen - clampf(north, 4.0, 12.0), blen - 1.0, 1]]


func _end(id: String) -> Vector3:
	var r: Route = segments[id]["route"]
	return r.pos_at(r.length)


## Heading at the end of a segment, snapped to the drawn heading (turtle ops are exact).
func _heading(id: String) -> float:
	return float(segments[id]["end_heading"])


## Distance covered along heading h by a route that peels off and rejoins the same line.
static func _along(drawn: Dictionary, h: float) -> float:
	var pts: Array = drawn["pts"]
	var a: Vector3 = pts[0]
	var b: Vector3 = pts[pts.size() - 1]
	return Vector2(b.x - a.x, b.z - a.z).dot(Vector2(sin(h), cos(h)))


func _add(id: String, section: String, fork: String, choice: String, drawn: Dictionary, half_width: float, extra: Dictionary) -> void:
	var r := Route.new()
	r.build(drawn["pts"])
	var seg := {
		"id": id, "section": section, "fork": fork, "choice": choice, "route": r,
		"half_width": half_width, "edge": Tuning.OFF_TRACK_MARGIN, "rails": false,
		"exposure": 0.4, "water": [], "boosts": [], "bumps": [], "ramp": {},
		"end_heading": drawn["heading"],
	}
	for k in extra:
		seg[k] = extra[k]
	segments[id] = seg
	ordered_ids.append(id)


## Segment ids in driving order for one lap with a build's route choices.
func path_for(routes: Dictionary) -> Array[String]:
	var ramp := "ramp_jump" if routes.get("ramp", "around") == "jump" else "ramp_around"
	var pond := "pond_water" if routes.get("pond", "bridge") == "water" else "pond_bridge"
	var cross := "cross_exposed" if routes.get("crossing", "sheltered") == "exposed" else "cross_sheltered"
	var p: Array[String] = ["start", "hills1", ramp, "hills2", pond, "mill", "farm", "cobbles", "ridge", "alpbach", cross, "bends"]
	return p


func path_length(path: Array[String]) -> float:
	var total := 0.0
	for id in path:
		total += (segments[id]["route"] as Route).length
	return total


func surface_y(seg: Dictionary, s: float) -> float:
	return (seg["route"] as Route).pos_at(s).y + Course.surface_offset(seg, s)


func all_route_lengths() -> Dictionary:
	var out := {}
	for ramp in ["jump", "around"]:
		for pond in ["water", "bridge"]:
			for cross in ["exposed", "sheltered"]:
				var p := path_for({"ramp": ramp, "pond": pond, "crossing": cross})
				out["%s/%s/%s" % [ramp, pond, cross]] = path_length(p)
	return out


## Like sim/course.gd `_draw` (straights ("S", length) and arcs ("A", radius, degrees; positive
## turns right), heights by smoothstep between (s, y) keys), but from any start heading. Returns
## {pts, heading} with the exact heading at the end.
static func _draw_ops(from: Vector3, h0: float, ops: Array, ykeys: Array) -> Dictionary:
	var pos := Vector2(from.x, from.z)
	var h := h0
	var pts2: Array[Vector2] = [pos]
	for op in ops:
		if op[0] == "S":
			var n := maxi(1, int(ceil(float(op[1]))))
			for i in n:
				pos += Vector2(sin(h), cos(h)) * float(op[1]) / n
				pts2.append(pos)
		else:
			var r := float(op[1])
			var ang := deg_to_rad(float(op[2]))
			var n := maxi(2, int(ceil(absf(ang) * r)))
			for i in n:
				var dh := ang / n
				var chord := 2.0 * r * sin(absf(dh) * 0.5)
				pos += Vector2(sin(h + dh * 0.5), cos(h + dh * 0.5)) * chord
				h += dh
				pts2.append(pos)
	var out: Array = []
	var acc := 0.0
	for i in pts2.size():
		if i > 0:
			acc += pts2[i].distance_to(pts2[i - 1])
		out.append(Vector3(pts2[i].x, Course._key_y(ykeys, acc), pts2[i].y))
	return {"pts": out, "heading": h}

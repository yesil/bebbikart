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

const LOOP := true
const NAME := "village"
const MIN_FREE := 6.0              # shortest allowed solved straight
## Headings (degrees, clockwise from north) of the four legs between the corners.
const LEG_CHURCH := 76.0           # up the church hill (ramp fork)
const LEG_BROOK := 178.0           # down to the brook (pond fork)
const LEG_SOUTH := 262.0           # along the south edge (crossing fork)

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


func _error(msg: String) -> void:
	errors.append(msg)
	push_error("village_course: " + msg)


func _build(hill: float, north: float) -> void:
	# Dorfplatz: the start/finish straight in front of the inn.
	var p := _draw_ops(Vector3.ZERO, 0.0, [["S", 14.0]], [[0.0, 0.0]])
	# Boost out of the square: a boost before the downhill corners after the church sent
	# racers off the road.
	_add("start", "hills", "", "", p, 5.0, {"boosts": [[3.0, 12.0]]})
	# Main street: a gentle S between the chalets, then right up the church hill.
	var ops := [["S", 3.0], ["A", 22.0, 16.0], ["A", 22.0, -16.0], ["S", 2.0], ["A", 18.0, LEG_CHURCH], ["S", 4.0]]
	var l1 := 3.0 + deg_to_rad(32.0) * 22.0 + 2.0 + deg_to_rad(LEG_CHURCH) * 18.0 + 4.0
	p = _draw_ops(_end("start"), _heading("start"), ops, [[0.0, 0.0], [8.0, 0.3], [l1 - 6.0, 2.9], [l1, 3.0]])
	_add("hills1", "hills", "", "", p, 4.0, {"bumps": [16.0]})
	# Ramp fork. Around: a lane peeling left round the churchyard wall. Jump: straight over the
	# wooden ski-jump kicker into the hay meadow.
	var j1 := _end("hills1")
	var h1 := _heading("hills1")
	var around_ops := [["S", 3.0], ["A", 20.0, -48.4], ["A", 20.0, 48.4], ["S", 2.0], ["A", 20.0, 48.4], ["A", 20.0, -48.4], ["S", 3.0]]
	var around_pts := _draw_ops(j1, h1, around_ops, [[0.0, 3.0]])
	var jump_len := _along(around_pts, h1)
	_add("ramp_jump", "hills", "ramp", "jump", _draw_ops(j1, h1, [["S", jump_len]], [[0.0, 3.0]]), 3.0, {
		"ramp": {"kick_a": 9.0, "lip_s": 15.0, "lip_h": 2.0, "land_s": 33.0, "pit_depth": 0.4},
	})
	_add("ramp_around", "hills", "ramp", "around", around_pts, 3.5, {})
	# Over the hill top, then right and down to the brook.
	# Two easier half-turns with a breather between: one long 100-degree arc downhill threw
	# daring racers off in the rain.
	var half := (LEG_BROOK - LEG_CHURCH) * 0.5
	ops = [["S", hill], ["A", 24.0, half], ["S", 5.0], ["A", 24.0, half], ["S", 8.0]]
	var l2 := hill + deg_to_rad(half * 2.0) * 24.0 + 13.0
	p = _draw_ops(_end("ramp_jump"), _heading("ramp_jump"), ops, [[0.0, 3.0], [hill, 3.0], [l2, 0.4]])
	_add("hills2", "hills", "", "", p, 4.0, {})
	# Pond fork. Bridge: the lane swings left over the inflow brook on a covered wooden bridge.
	# Water: a stone ford straight through the duck pond.
	var j3 := _end("hills2")
	var h3 := _heading("hills2")
	var bridge_ops := [["S", 3.0], ["A", 11.0, -75.0], ["A", 20.0, 75.0], ["S", 8.0], ["A", 20.0, 75.0], ["A", 11.0, -75.0], ["S", 3.0]]
	var bridge_pts := _draw_ops(j3, h3, bridge_ops, [[0.0, 0.4]])
	var bl := Course._length(bridge_pts["pts"])
	bridge_pts = _draw_ops(j3, h3, bridge_ops, [[0.0, 0.4], [bl * 0.5 - 11.0, 0.4], [bl * 0.5, 1.5], [bl * 0.5 + 11.0, 0.4], [bl, 0.4]])
	var ford_len := _along(bridge_pts, h3)
	_add("pond_water", "pond", "pond", "water", _draw_ops(j3, h3, [["S", ford_len]],
		[[0.0, 0.4], [8.0, 0.4], [16.0, -0.2], [ford_len - 16.0, -0.2], [ford_len - 8.0, 0.4], [ford_len, 0.4]]), 4.0,
		{"water": [[9.0, ford_len - 9.0]]})
	_add("pond_bridge", "pond", "pond", "bridge", bridge_pts, 2.8, {"rails": true})
	# Past the mill and right onto the south edge.
	p = _draw_ops(_end("pond_water"), _heading("pond_water"), [["S", 5.0], ["A", 16.0, LEG_SOUTH - LEG_BROOK], ["S", 5.0]], [[0.0, 0.4]])
	_add("mill", "pond", "", "", p, 4.0, {})
	# Crossing fork. Sheltered: the arcade lane loops right in among the houses. Exposed: a low
	# causeway straight over the open meadow, facing the mountains.
	var j4 := _end("mill")
	var h4 := _heading("mill")
	var shelter_ops := [["S", 3.0], ["A", 14.0, 62.0], ["A", 14.0, -62.0], ["S", 6.0], ["A", 14.0, -62.0], ["A", 14.0, 62.0], ["S", 3.0]]
	var shelter_pts := _draw_ops(j4, h4, shelter_ops, [[0.0, 0.4]])
	var xl := _along(shelter_pts, h4)
	_add("cross_exposed", "crossing", "crossing", "exposed", _draw_ops(j4, h4, [["S", xl]],
		[[0.0, 0.4], [3.0, 0.4], [13.0, 1.4], [xl - 13.0, 1.4], [xl - 3.0, 0.4], [xl, 0.4]]), 2.6,
		{"exposure": 1.0, "edge": Tuning.OFF_TRACK_MARGIN_RAILS})
	_add("cross_sheltered", "crossing", "crossing", "sheltered", shelter_pts, 3.5, {"exposure": 0.0})
	# Square: a chicane past the bakery, right turn north, the S round the fountain, the line.
	ops = [["S", 4.0], ["A", 12.0, -35.0], ["A", 12.0, 70.0], ["A", 12.0, -35.0], ["S", 3.0], ["A", 14.0, 360.0 - LEG_SOUTH],
		["S", 3.0], ["A", 12.0, 45.0], ["A", 12.0, -90.0], ["A", 12.0, 45.0], ["S", north]]
	p = _draw_ops(_end("cross_exposed"), _heading("cross_exposed"), ops, [[0.0, 0.4], [30.0, 0.2], [60.0, 0.0]])
	_add("bends", "bends", "", "", p, 3.5, {})
	var b: Dictionary = segments["bends"]
	var blen: float = (b["route"] as Route).length
	b["boosts"] = [[blen - clampf(north, 4.0, 12.0), blen - 1.0]]


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
	var p: Array[String] = ["start", "hills1", ramp, "hills2", pond, "mill", cross, "bends"]
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

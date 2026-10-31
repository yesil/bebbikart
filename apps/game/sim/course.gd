extends RefCounted
## Course V1 (game.md "Course (V1)"): start -> hills (ramp fork) -> pond (water/bridge fork)
## -> crossing (exposed/sheltered fork) -> bends -> finish. All junctions sit at x = 0 so every
## fork variant joins the same next segment. Pure data, no nodes. This is the single source of
## truth for the racing line; the baked world (tools/bake_world.gd) is generated from it.

const Route = preload("res://sim/route.gd")
const Tuning = preload("res://sim/tuning.gd")

## Length of the plank wedge from the jump pit up onto the landing road.
const LANDING_WEDGE := 1.6
## Baked road surface beyond half_width: shoulder plus gutter lip (tools/bake_world.gd).
const SHOULDER := 0.45
const GUTTER := 0.45
## Railed lanes clamp the kart's centre this far inside half_width (sim/racer.gd).
const RAIL_INSET := 0.45

## Segment: {
##   id, section, fork ("" or fork id), choice, route (Route), half_width,
##   edge (extra metres before off_track), rails (bool: d is clamped, no off_track),
##   low_rails (bool, optional: clamped too, but a kart hitting them with |vd| > RAIL_TOPPLE_VD
##   tips over: off_track),
##   exposure (0..1 wind), water: [[a,b]], boosts: [[a,b]], bumps: [s...],
##   ramp: {} or {kick_a, lip_s, lip_h, land_s, pit_depth}, offset (route s at segment start; per path),
##   stretch (the stretch it belongs to: Protocol.TRACK_STRETCHES[NAME], contracts §2d)
## }
const NAME := "countryside"

var segments := {}
var ordered_ids: Array[String] = []
## Problems found while building (a segment without a known stretch). The sim refuses to race.
var errors: PackedStringArray = []


func _init() -> void:
	# The trunk runs along +z near x = 0. Routes are drawn "turtle style" from straights and
	# constant-radius arcs (`_draw`), so radii are exact and every fork is a clean Y-split: both
	# branches leave the junction on a shared straight stub, the detour peels off to one side
	# with a mirrored S-curve while the direct line runs straight on, and they merge the same
	# way. Heights come from smooth (s, y) keys. tools/layout_map.gd checks the result against
	# the terrain features in world/landscape.gd.
	var p := _draw("start", Vector3.ZERO, [["S", 15.0]], [[0.0, 0.0]])
	_add("start", "hills", "", "", p, 5.0, {"stretch": "bumpy_road"})
	# Gentle double chicane over two crests.
	p = _draw("hills1", _end("start"), [["S", 3.0], ["A", 18.0, 15.0], ["A", 18.0, -30.0], ["A", 18.0, 15.0],
		["A", 18.0, -15.0], ["A", 18.0, 30.0], ["A", 18.0, -15.0]],
		[[0.0, 0.0], [14.0, 1.0], [28.0, 0.4], [40.0, 0.0]])
	_add("hills1", "hills", "", "", p, 4.0, {"bumps": [12.0, 26.0], "stretch": "bumpy_road"})
	# Jump: straight over a muddy dip. Around: an S out to the right round a knoll and back.
	# The kicker starts only once the around lane is clear of the jump road (_split_s).
	var ramp_out := [["S", 3.0], ["A", 20.0, 48.4], ["A", 20.0, -48.4], ["S", 2.0], ["A", 20.0, -48.4], ["A", 20.0, 48.4], ["S", 3.0]]
	var j1 := _end("hills1")
	var around_pts := _draw("ramp_around", j1, ramp_out, [[0.0, 0.0]])
	var jump_pts := _draw("ramp_jump", j1, [["S", _forward_pts(around_pts)]], [[0.0, 0.0]])
	var kick := ceilf(_split_s(jump_pts, 3.0, {}, around_pts, 3.5, {}).x * 2.0) * 0.5
	_add("ramp_jump", "hills", "ramp", "jump", jump_pts, 3.0, {
		"ramp": {"kick_a": kick, "lip_s": kick + 6.0, "lip_h": 2.0, "land_s": kick + 24.0, "pit_depth": 0.4},
		"stretch": "kicker",
	})
	_add("ramp_around", "hills", "ramp", "around", around_pts, 3.5, {"stretch": "knoll_road"})
	p = _draw("hills2", _end("ramp_jump"), [["S", 25.0]], [[0.0, 0.0], [13.0, 1.0], [25.0, 0.4]])
	_add("hills2", "hills", "", "", p, 4.0, {"boosts": [[10.0, 20.0]], "stretch": "hilltop"})
	# Water: a shallow stone ford straight through the pond. Bridge: a fenced lane that swings
	# west round the pond and crosses its inflow stream on a humped stone bridge.
	var j3 := _end("hills2")
	# A tight first arc gets the lane clear of the ford before the ford dips into the water.
	var bridge_ops := [["S", 3.0], ["A", 10.5, -80.0], ["A", 25.8, 80.0], ["S", 22.5], ["A", 25.8, 80.0], ["A", 10.5, -80.0], ["S", 3.0]]
	var bridge_pts := _draw("pond_bridge", j3, bridge_ops, [[0.0, 0.4]])
	var bl := _length(bridge_pts)
	bridge_pts = _draw("pond_bridge", j3, bridge_ops, [[0.0, 0.4], [bl * 0.5 - 12.0, 0.4], [bl * 0.5, 1.6], [bl * 0.5 + 12.0, 0.4], [bl, 0.4]])
	var ford_len := _forward_pts(bridge_pts)
	# The ford only dips into the water once the bridge lane is clear of it.
	var ford_flat := _draw("pond_water", j3, [["S", ford_len]], [[0.0, 0.4]])
	var fs := _split_s(ford_flat, 4.0, {}, bridge_pts, 2.8, {"rails": true})
	_add("pond_water", "pond", "pond", "water", _draw("pond_water", j3, [["S", ford_len]],
		[[0.0, 0.4], [fs.x, 0.4], [fs.x + 9.0, -0.2], [fs.y - 9.0, -0.2], [fs.y, 0.4], [ford_len, 0.4]]), 4.0,
		{"water": [[fs.x + 1.0, fs.y - 1.0]], "stretch": "ford"})
	_add("pond_bridge", "pond", "pond", "bridge", bridge_pts, 2.8, {"rails": true, "stretch": "stone_bridge"})
	# Exposed: a low causeway straight across a shallow valley. Sheltered: a hedged lane that
	# loops right round the valley head. The causeway only starts to climb once the lane has
	# split off, so the two never overlap at different heights.
	var j4 := _end("pond_water")
	var shelter_ops := [["S", 3.0], ["A", 14.0, 64.6], ["A", 14.0, -64.6], ["S", 7.0], ["A", 14.0, -64.6], ["A", 14.0, 64.6], ["S", 3.0]]
	var shelter_pts := _draw("cross_sheltered", j4, shelter_ops, [[0.0, 0.4]])
	var xl := _forward_pts(shelter_pts)
	var cs := _split_s(_draw("cross_exposed", j4, [["S", xl]], [[0.0, 0.4]]), 2.6, {"low_rails": true}, shelter_pts, 3.5, {})
	_add("cross_exposed", "crossing", "crossing", "exposed", _draw("cross_exposed", j4, [["S", xl]],
		[[0.0, 0.4], [cs.x, 0.4], [cs.x + 10.0, 1.4], [cs.y - 10.0, 1.4], [cs.y, 0.4], [xl, 0.4]]), 2.6,
		{"exposure": 1.0, "low_rails": true, "stretch": "causeway"})
	_add("cross_sheltered", "crossing", "crossing", "sheltered", shelter_pts, 3.5, {"exposure": 0.0, "stretch": "hedge_lane"})
	# Rainbow bends: two mirrored chicanes, then the finish straight.
	p = _draw("bends", _end("cross_exposed"), [["S", 6.0], ["A", 12.0, -55.0], ["A", 12.0, 110.0], ["A", 12.0, -55.0],
		["A", 12.0, 55.0], ["A", 12.0, -110.0], ["A", 12.0, 55.0], ["S", 20.0]], [[0.0, 0.4], [30.0, 0.2], [70.0, 0.0]])
	_add("bends", "bends", "", "", p, 3.5, {"stretch": "rainbow_bends"})
	var b: Dictionary = segments["bends"]
	var bl2: float = (b["route"] as Route).length
	b["boosts"] = [[bl2 - 18.0, bl2 - 8.0]]
	errors.append_array(stretch_errors(segments, NAME))


## Control points every metre along straights ("S", length) and arcs ("A", radius, degrees;
## positive turns towards +x), starting at `from` heading +z. Heights: smoothstep between
## (s, y) keys, flat at each key.
func _draw(_id: String, from: Vector3, ops: Array, ykeys: Array) -> Array:
	var pos := Vector2(from.x, from.z)
	var h := 0.0
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
				# Chord of the arc step, taken at the mid heading.
				var chord := 2.0 * r * sin(absf(dh) * 0.5)
				pos += Vector2(sin(h + dh * 0.5), cos(h + dh * 0.5)) * chord
				h += dh
				pts2.append(pos)
	var out: Array = []
	var acc := 0.0
	for i in pts2.size():
		if i > 0:
			acc += pts2[i].distance_to(pts2[i - 1])
		out.append(Vector3(pts2[i].x, _key_y(ykeys, acc), pts2[i].y))
	return out


static func _key_y(keys: Array, s: float) -> float:
	if s <= float(keys[0][0]):
		return float(keys[0][1])
	for i in keys.size() - 1:
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if s <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), smoothstep(float(a[0]), float(b[0]), s))
	return float(keys[keys.size() - 1][1])


## [first, last] distance along the direct road `direct` where the detour `detour` is laterally
## clear of it: each road's surface outside the other's drivable corridor (corridor_half), so
## the two may differ in height there and nowhere else. `*_extra` are the segment flags that
## change the corridor (rails, edge).
static func _split_s(direct: Array, direct_hw: float, direct_extra: Dictionary, detour: Array, detour_hw: float, detour_extra: Dictionary) -> Vector2:
	var a := {"half_width": direct_hw, "edge": Tuning.OFF_TRACK_MARGIN, "rails": false}
	a.merge(direct_extra, true)
	var b := {"half_width": detour_hw, "edge": Tuning.OFF_TRACK_MARGIN, "rails": false}
	b.merge(detour_extra, true)
	# The baked world was cut with the old 0.85 m kart (Tuning.RADIUS): a wider one here would move
	# the kicker, the ford dip and the causeway climb away from what is baked (a rebake first).
	var need := maxf(corridor_half(a, Tuning.RADIUS) + surface_half(b), corridor_half(b, Tuning.RADIUS) + surface_half(a))
	var line: Array[Vector2] = []
	for q: Vector3 in detour:
		line.append(Vector2(q.x, q.z))
	var first := INF
	var last := -INF
	var acc := 0.0
	for i in direct.size():
		var q: Vector3 = direct[i]
		if i > 0:
			acc += Vector2(q.x, q.z).distance_to(Vector2(direct[i - 1].x, direct[i - 1].z))
		if _polyline_dist(Vector2(q.x, q.z), line) >= need:
			first = minf(first, acc)
			last = maxf(last, acc)
	assert(first < last, "course: detour never clears the direct road")
	return Vector2(first, last)


static func _polyline_dist(p: Vector2, line: Array[Vector2]) -> float:
	var best := INF
	for i in line.size() - 1:
		var ab := line[i + 1] - line[i]
		var t := clampf((p - line[i]).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
		best = minf(best, p.distance_to(line[i] + ab * t))
	return best


## Half width of the band a kart's body can reach: the centre-line limit the sim enforces
## (clamp inside rails, else off_track beyond the soft edge) plus the kart's half width, by
## default the widest racer's (Tuning.SIZE_HALF_WIDTH). Nothing solid may stand in it except the
## lane's own rails and ramp.
static func corridor_half(seg: Dictionary, kart: float = Tuning.SIZE_HALF_WIDTH.y) -> float:
	var hw: float = seg["half_width"]
	if bool(seg["rails"]) or bool(seg.get("low_rails", false)):
		return hw - RAIL_INSET + kart
	return hw + float(seg["edge"]) + kart


## Id of a segment (other than `except`) whose drivable corridor, grown by `margin`, contains
## the ground point p (x, z); "" if none. For placing props and plants clear of every road.
func corridor_at(p: Vector2, margin := 0.0, except := "") -> String:
	for id in ordered_ids:
		if id == except:
			continue
		var seg: Dictionary = segments[id]
		var r: Route = seg["route"]
		var lim := corridor_half(seg) + margin
		var s := 0.0
		while s <= r.length:
			var q := r.pos_at(s)
			# Points 1 m apart: the true distance is at most 0.5 m below the sampled one.
			if Vector2(q.x, q.z).distance_to(p) < lim + 0.5:
				var t := maxf(0.0, s - 1.0)
				while t <= minf(r.length, s + 1.0):
					var u := r.pos_at(t)
					if Vector2(u.x, u.z).distance_to(p) < lim:
						return id
					t += 0.05
			s += 1.0
	return ""


## Half width of the baked road surface (shoulder and gutter lip included).
static func surface_half(seg: Dictionary) -> float:
	return float(seg["half_width"]) + SHOULDER + GUTTER


func _end(id: String) -> Vector3:
	var r: Route = segments[id]["route"]
	return r.pos_at(r.length)


## Straight-line distance along +z covered by a route (for the direct sibling of a detour).
static func _forward_pts(pts: Array) -> float:
	return (pts[pts.size() - 1] as Vector3).z - (pts[0] as Vector3).z


static func _length(pts: Array) -> float:
	var acc := 0.0
	for i in range(1, pts.size()):
		acc += Vector2(pts[i].x, pts[i].z).distance_to(Vector2(pts[i - 1].x, pts[i - 1].z))
	return acc


func _add(id: String, section: String, fork: String, choice: String, ctrl: Array, half_width: float, extra: Dictionary) -> void:
	var r := Route.new()
	r.build(ctrl)
	var seg := {
		"id": id, "section": section, "fork": fork, "choice": choice, "route": r,
		"half_width": half_width, "edge": Tuning.OFF_TRACK_MARGIN, "rails": false,
		"exposure": 0.4, "water": [], "boosts": [], "bumps": [], "ramp": {},
	}
	for k in extra:
		seg[k] = extra[k]
	segments[id] = seg
	ordered_ids.append(id)


## Every segment must carry a stretch of `track` (Protocol.TRACK_STRETCHES): runs report the time
## on each (contracts §2d). Returns the problems, empty when all is well.
static func stretch_errors(segs: Dictionary, track: String) -> PackedStringArray:
	var out: PackedStringArray = []
	if not Protocol.TRACK_STRETCHES.has(track):
		out.append("track \"%s\" has no stretches in Protocol.TRACK_STRETCHES" % track)
		return out
	var known := {}
	for st in Protocol.TRACK_STRETCHES[track]:
		known[st["id"]] = true
	for id in segs:
		var tag = segs[id].get("stretch")
		if tag == null:
			out.append("segment %s has no stretch" % id)
		elif not known.has(tag):
			out.append("segment %s: stretch \"%s\" is not a %s stretch" % [id, tag, track])
	return out


## Segment ids in driving order for a build's route choices.
func path_for(routes: Dictionary) -> Array[String]:
	var ramp := "ramp_jump" if routes.get("ramp", "around") == "jump" else "ramp_around"
	var pond := "pond_water" if routes.get("pond", "bridge") == "water" else "pond_bridge"
	var cross := "cross_exposed" if routes.get("crossing", "sheltered") == "exposed" else "cross_sheltered"
	var p: Array[String] = ["start", "hills1", ramp, "hills2", pond, cross, "bends"]
	return p


func path_length(path: Array[String]) -> float:
	var total := 0.0
	for id in path:
		total += (segments[id]["route"] as Route).length
	return total


static func in_ranges(ranges: Array, s: float) -> bool:
	for r in ranges:
		if s >= float(r[0]) and s <= float(r[1]):
			return true
	return false


## Ground height offset added to the centre line (ramp kicker and landing pit).
static func surface_offset(seg: Dictionary, s: float) -> float:
	var ramp: Dictionary = seg["ramp"]
	if ramp.is_empty():
		return 0.0
	var a: float = ramp["kick_a"]
	var lip: float = ramp["lip_s"]
	if s >= a and s <= lip:
		var f := (s - a) / (lip - a)
		return float(ramp["lip_h"]) * f * f
	var land: float = ramp["land_s"]
	if s > lip and s < land:
		# The pit floor, rising up the landing wedge (tools/bake_world.gd, tools/bake_village.gd)
		# over its last LANDING_WEDGE metres, so a short lander drives up it, not through it.
		return -float(ramp["pit_depth"]) * (1.0 - smoothstep(land - LANDING_WEDGE, land, s))
	return 0.0


func surface_y(seg: Dictionary, s: float) -> float:
	return (seg["route"] as Route).pos_at(s).y + surface_offset(seg, s)


func all_route_lengths() -> Dictionary:
	var out := {}
	for ramp in ["jump", "around"]:
		for pond in ["water", "bridge"]:
			for cross in ["exposed", "sheltered"]:
				var p := path_for({"ramp": ramp, "pond": pond, "crossing": cross})
				out["%s/%s/%s" % [ramp, pond, cross]] = path_length(p)
	return out

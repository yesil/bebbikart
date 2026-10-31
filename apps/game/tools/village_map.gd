extends SceneTree
## Top-down plan of the village circuit (sim/village_course.gd + world/village/village_plan.gd)
## as an SVG, plus geometry checks. Exits 1 on any failed check:
##   godot --headless --path apps/game --script res://tools/village_map.gd [-- --out=res://docs/village_map.svg]
## Checks: loop closure, junction gaps and kinks, straight stubs, spacing and crossings between
## roads, slopes, curvature, fork angles and separation, lap lengths, buildings clear of roads,
## water and each other, the pond under the ford only.

const VillageCourse = preload("res://sim/village_course.gd")
const VillagePlan = preload("res://world/village/village_plan.gd")
const Route = preload("res://sim/route.gd")

const GAP := 6.0
const MAX_SLOPE := 0.16
const MAX_K := 1.0 / 10.0
const MAX_K_HW := 0.4
const STUB := 3.0
const FORK_ANGLE := 15.0
const FORK_PROBE := 12.0
const END_ZONE := 8.0              # metres from a shared junction where adjacent roads may touch
const LAP_RANGE := Vector2(380.0, 600.0)
const SCALE := 3.0                 # SVG px per metre
const MARGIN := 40.0               # metres round the course in the drawing

const SECTION_COLORS := {
	"hills": "#e8a33d", "pond": "#3d8fe8", "crossing": "#9b6ad6", "bends": "#e85d75",
}
const KIND_COLORS := {
	"inn": "#8a4b2a", "chalet": "#6b3f22", "arcade": "#7d5a3c", "bakery": "#9c5a2c",
	"church": "#f2efe6", "mill": "#7b6a55", "barn": "#8e3b2f", "school": "#c9b48a",
}

var course: VillageCourse
var plan: VillagePlan
var fails: PackedStringArray = []
var notes: PackedStringArray = []


func _init() -> void:
	var out := "res://docs/village_map.svg"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	course = VillageCourse.new()
	plan = VillagePlan.new(course)
	_check_loop()
	_check_roads()
	_check_forks()
	_check_laps()
	_check_buildings()
	_check_water()
	var path := ProjectSettings.globalize_path(out) if out.begins_with("res://") else out
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("village_map: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		quit(1)
		return
	f.store_string(_svg())
	f.close()
	print("village map: ", path)
	for n in notes:
		print("  ", n)
	if fails.is_empty():
		print("CHECKS PASSED")
		quit(0)
	else:
		for x in fails:
			print("  FAIL ", x)
		print("CHECKS FAILED: %d" % fails.size())
		quit(1)


func _route(id: String) -> Route:
	return course.segments[id]["route"]


func _hw(id: String) -> float:
	return float(course.segments[id]["half_width"])


func _xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


func _samples(id: String, step: float) -> Array:
	var r := _route(id)
	var out: Array = []
	var s := 0.0
	while s < r.length:
		out.append([s, _xz(r.pos_at(s))])
		s += step
	out.append([r.length, _xz(r.pos_at(r.length))])
	return out


## Junction ends two segments share: [[s on a, s on b], ...].
func _shared(a: String, b: String) -> Array:
	var ra := _route(a)
	var rb := _route(b)
	var out: Array = []
	for ea in [0.0, ra.length]:
		for eb in [0.0, rb.length]:
			if ra.pos_at(ea).distance_to(rb.pos_at(eb)) < 0.5:
				out.append([ea, eb])
	return out


func _near(s: float, ends: Array, idx: int, zone: float) -> bool:
	for e in ends:
		if absf(s - float(e[idx])) < zone:
			return true
	return false


func _siblings() -> Array:
	var by_fork := {}
	for id in course.ordered_ids:
		var fk: String = course.segments[id]["fork"]
		if fk != "":
			if not by_fork.has(fk):
				by_fork[fk] = []
			by_fork[fk].append(id)
	return by_fork.values()


# ---------------------------------------------------------------- checks

func _check_loop() -> void:
	for e in course.errors:
		fails.append("course: " + e)
	for e in plan.errors:
		fails.append("plan: " + e)
	notes.append("free straights: hill %.1f m, north %.1f m" % [course.free_hill, course.free_north])
	# Every path's consecutive segments meet with no gap, kink or height step, and the last
	# segment runs back into the first.
	var paths := {}
	for ramp in ["jump", "around"]:
		for pond in ["water", "bridge"]:
			for cross in ["exposed", "sheltered"]:
				paths["%s/%s/%s" % [ramp, pond, cross]] = course.path_for({"ramp": ramp, "pond": pond, "crossing": cross})
	var seen := {}
	for key in paths:
		var p: Array = paths[key]
		for i in p.size():
			var a: String = p[i]
			var b: String = p[(i + 1) % p.size()]
			if seen.has(a + ">" + b):
				continue
			seen[a + ">" + b] = true
			var ra := _route(a)
			var rb := _route(b)
			var gap := ra.pos_at(ra.length).distance_to(rb.pos_at(0.0))
			var kink := rad_to_deg(absf(wrapf(ra.heading_at(ra.length) - rb.heading_at(0.0), -PI, PI)))
			if gap > 0.05:
				fails.append("junction %s > %s: gap %.2f m" % [a, b, gap])
			if kink > 3.0:
				fails.append("junction %s > %s: heading kink %.1f deg" % [a, b, kink])
	for id in course.ordered_ids:
		if course.segments[id]["fork"] == "":
			continue
		var r := _route(id)
		for ends in [[0.0, STUB], [r.length - STUB, r.length]]:
			var turn := rad_to_deg(absf(wrapf(r.heading_at(ends[1]) - r.heading_at(ends[0]), -PI, PI)))
			if turn > 1.5:
				fails.append("junction %s: stub at s=%.0f turns %.1f deg" % [id, ends[0], turn])


func _check_roads() -> void:
	var ids := course.ordered_ids
	for i in ids.size():
		var a: String = ids[i]
		var r := _route(a)
		var max_slope := 0.0
		var max_k := 0.0
		var s := 0.0
		while s <= r.length:
			max_slope = maxf(max_slope, absf(tan(r.pitch_at(s))))
			max_k = maxf(max_k, absf(r.curv_at(s)))
			s += 0.5
		notes.append("%-16s len %6.1f m  max slope %4.1f%%  min radius %s" % [a, r.length, max_slope * 100.0,
			"%.1f m" % (1.0 / max_k) if max_k > 0.0001 else "straight"])
		if max_slope > MAX_SLOPE:
			fails.append("slope %s: %.1f%% > %.1f%%" % [a, max_slope * 100.0, MAX_SLOPE * 100.0])
		if max_k > MAX_K:
			fails.append("curvature %s: radius %.1f m < %.1f m" % [a, 1.0 / max_k, 1.0 / MAX_K])
		if max_k * _hw(a) > MAX_K_HW:
			fails.append("curvature %s: |k|*hw %.2f > %.2f" % [a, max_k * _hw(a), MAX_K_HW])
		for j in range(i + 1, ids.size()):
			var b: String = ids[j]
			if course.segments[a]["fork"] != "" and course.segments[a]["fork"] == course.segments[b]["fork"]:
				continue  # siblings: _check_forks
			var ends := _shared(a, b)
			var need := _hw(a) + _hw(b) + GAP
			var best := INF
			var where := Vector2.ZERO
			var sb := _samples(b, 0.5)
			for pa in _samples(a, 0.5):
				if _near(pa[0], ends, 0, END_ZONE):
					continue
				for pb in sb:
					if _near(pb[0], ends, 1, END_ZONE):
						continue
					var dd: float = (pa[1] as Vector2).distance_to(pb[1])
					if dd < best:
						best = dd
						where = pa[1]
			if best < need:
				fails.append("spacing %s vs %s: %.1f m < %.1f m near (%.0f, %.0f)" % [a, b, best, need, where.x, where.y])


func _check_forks() -> void:
	for group in _siblings():
		var a: String = group[0]
		var b: String = group[1]
		var fk: String = course.segments[a]["fork"]
		var ra := _route(a)
		var rb := _route(b)
		for end in ["split", "merge"]:
			var ha := ra.heading_at(FORK_PROBE if end == "split" else ra.length - FORK_PROBE)
			var hb := rb.heading_at(FORK_PROBE if end == "split" else rb.length - FORK_PROBE)
			var ang := rad_to_deg(absf(wrapf(ha - hb, -PI, PI)))
			notes.append("fork %-8s %-5s angle %4.1f deg" % [fk, end, ang])
			if ang < FORK_ANGLE:
				fails.append("fork %s %s angle %.1f deg < %.1f" % [fk, end, ang, FORK_ANGLE])
		var long_id := a if ra.length >= rb.length else b
		var short_id := b if long_id == a else a
		var sb := _samples(short_id, 0.5)
		var widest := 0.0
		for p in _samples(long_id, 1.0):
			var best := INF
			for q in sb:
				best = minf(best, (p[1] as Vector2).distance_to(q[1]))
			widest = maxf(widest, best)
		var need := _hw(a) + _hw(b) + GAP
		notes.append("fork %-8s widest separation %.1f m (need %.1f), %s %.1f m vs %s %.1f m" % [
			fk, widest, need, a, ra.length, b, rb.length])
		if widest < need:
			fails.append("fork %s: branches only %.1f m apart at widest (< %.1f)" % [fk, widest, need])


func _check_laps() -> void:
	var lens := course.all_route_lengths()
	var lo := INF
	var hi := 0.0
	for k in lens:
		lo = minf(lo, lens[k])
		hi = maxf(hi, lens[k])
	notes.append("lap length %.1f to %.1f m" % [lo, hi])
	if lo < LAP_RANGE.x or hi > LAP_RANGE.y:
		fails.append("lap length %.0f..%.0f m outside %.0f..%.0f m" % [lo, hi, LAP_RANGE.x, LAP_RANGE.y])


## Signed distance from p to the nearest road edge (negative on the road), and that road's id.
func _road_edge(p: Vector2) -> Array:
	var best := INF
	var best_id := ""
	for id in course.ordered_ids:
		for q in _samples(id, 1.0):
			var dd: float = p.distance_to(q[1]) - _hw(id)
			if dd < best:
				best = dd
				best_id = id
	return [best, best_id]


func _check_buildings() -> void:
	var polys: Array = []
	for b in plan.buildings:
		polys.append(VillagePlan.footprint(b))
	for i in plan.buildings.size():
		var b: Dictionary = plan.buildings[i]
		var poly: PackedVector2Array = polys[i]
		var pts := Array(poly)
		pts.append((pts[0] + pts[1]) * 0.5)
		pts.append((pts[2] + pts[3]) * 0.5)
		pts.append((pts[0] + pts[3]) * 0.5)
		pts.append((pts[1] + pts[2]) * 0.5)
		for p in pts:
			var e := _road_edge(p)
			if float(e[0]) < VillagePlan.CLEAR - 0.3:
				fails.append("building %s at (%.0f, %.0f) is %.1f m from %s (< %.1f)" % [
					b["kind"], b["pos"].x, b["pos"].y, e[0], e[1], VillagePlan.CLEAR])
				break
			if Geometry2D.is_point_in_polygon(p, plan.pond):
				fails.append("building %s at (%.0f, %.0f) stands in the pond" % [b["kind"], b["pos"].x, b["pos"].y])
				break
			if VillagePlan.polyline_dist(p, plan.brook) < VillagePlan.BROOK_HALF_WIDTH + 1.0:
				fails.append("building %s at (%.0f, %.0f) stands in the brook" % [b["kind"], b["pos"].x, b["pos"].y])
				break
		for j in range(i + 1, plan.buildings.size()):
			var grown_a := Geometry2D.offset_polygon(poly, VillagePlan.BUILDING_GAP * 0.5)
			var grown_b := Geometry2D.offset_polygon(polys[j], VillagePlan.BUILDING_GAP * 0.5)
			if not Geometry2D.intersect_polygons(grown_a[0], grown_b[0]).is_empty():
				var o: Dictionary = plan.buildings[j]
				fails.append("buildings overlap: %s (%.0f, %.0f) and %s (%.0f, %.0f)" % [
					b["kind"], b["pos"].x, b["pos"].y, o["kind"], o["pos"].x, o["pos"].y])
	notes.append("%d buildings" % plan.buildings.size())


func _check_water() -> void:
	var ford := _route("pond_water")
	var wr: Array = course.segments["pond_water"]["water"][0]
	var s := 0.0
	while s <= ford.length:
		var inside := Geometry2D.is_point_in_polygon(_xz(ford.pos_at(s)), plan.pond)
		var want := s >= float(wr[0]) and s <= float(wr[1])
		if inside != want and absf(s - float(wr[0])) > 2.5 and absf(s - float(wr[1])) > 2.5:
			fails.append("pond: ford at s=%.0f is %s the pond" % [s, "inside" if inside else "outside"])
			break
		s += 1.0
	for id in course.ordered_ids:
		if id == "pond_water":
			continue
		for q in _samples(id, 1.0):
			if Geometry2D.is_point_in_polygon(q[1], plan.pond):
				fails.append("pond: %s runs through the pond at s=%.0f" % [id, q[0]])
				break
	# The brook passes under the bridge's hump and crosses no other road.
	for id in course.ordered_ids:
		if id == "pond_bridge" or id == "pond_water":
			continue
		for q in _samples(id, 1.0):
			if VillagePlan.polyline_dist(q[1], plan.brook) < VillagePlan.BROOK_HALF_WIDTH + _hw(id):
				fails.append("brook crosses %s at s=%.0f without a bridge" % [id, q[0]])
				break


# ---------------------------------------------------------------- drawing

var _lo := Vector2.ZERO
var _size := Vector2.ZERO


func _p(v: Vector2) -> String:
	return "%.1f,%.1f" % [(v.x - _lo.x) * SCALE, (_lo.y + _size.y - v.y) * SCALE]


func _pts(line: Array) -> String:
	var parts: PackedStringArray = []
	for v in line:
		parts.append(_p(v))
	return " ".join(parts)


func _svg() -> String:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for id in course.ordered_ids:
		for q in _samples(id, 2.0):
			lo = lo.min(q[1])
			hi = hi.max(q[1])
	lo -= Vector2(MARGIN, MARGIN)
	hi += Vector2(MARGIN, MARGIN)
	_lo = lo
	_size = hi - lo
	var w := _size.x * SCALE
	var h := _size.y * SCALE
	var o: PackedStringArray = []
	o.append('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %.0f %.0f" width="%.0f" height="%.0f" font-family="Helvetica, Arial, sans-serif">' % [w + 360.0, h, w + 360.0, h])
	o.append('<defs><clipPath id="map"><rect width="%.0f" height="%.0f"/></clipPath></defs>' % [w, h])
	o.append('<g clip-path="url(#map)">')
	o.append('<rect width="%.0f" height="%.0f" fill="#9fcf7a"/>' % [w, h])
	o.append('<rect x="%.0f" width="360" height="%.0f" fill="#fbfaf6"/>' % [w, h])
	# Meadows, orchard, square
	var hm := plan.hay_meadow
	var hc := _p(Vector2(hm.x, hm.y)).split(",")
	o.append('<ellipse cx="%s" cy="%s" rx="%.1f" ry="%.1f" transform="rotate(%.1f %s %s)" fill="#d8cf7a" opacity="0.85"/>' % [
		hc[0], hc[1], hm.z * SCALE, hm.w * SCALE, rad_to_deg(plan.hay_yaw) - 90.0, hc[0], hc[1]])
	var mh := plan.meadow_hollow
	o.append('<circle cx="%s" cy="%s" r="%.1f" fill="#b8e08f" stroke="#7fae5a" stroke-dasharray="4 4"/>' % [
		_p(Vector2(mh.x, mh.y)).split(",")[0], _p(Vector2(mh.x, mh.y)).split(",")[1], mh.z * SCALE])
	for q in plan.orchard:
		var c := _p(q).split(",")
		o.append('<circle cx="%s" cy="%s" r="%.1f" fill="#5d9b3f" stroke="#447a2c"/>' % [c[0], c[1], 2.2 * SCALE])
	o.append('<polygon points="%s" fill="#d9d2c3" stroke="#b5ab97"/>' % _pts(Array(plan.square)))
	# Water
	o.append('<polyline points="%s" fill="none" stroke="#5aa9e6" stroke-width="%.1f" stroke-linecap="round" stroke-linejoin="round"/>' % [
		_pts(plan.brook), VillagePlan.BROOK_HALF_WIDTH * 2.0 * SCALE])
	o.append('<polygon points="%s" fill="#5aa9e6" stroke="#3d7fb8" stroke-width="2"/>' % _pts(Array(plan.pond)))
	# Roads: grey bed, section colour centre stripe; detours outlined dashed.
	for id in course.ordered_ids:
		var line: Array = []
		for q in _samples(id, 1.0):
			line.append(q[1])
		o.append('<polyline points="%s" fill="none" stroke="#6f6a63" stroke-width="%.1f" stroke-linejoin="round"/>' % [
			_pts(line), _hw(id) * 2.0 * SCALE + 3.0])
		o.append('<polyline points="%s" fill="none" stroke="#c9c1b3" stroke-width="%.1f" stroke-linejoin="round"/>' % [
			_pts(line), _hw(id) * 2.0 * SCALE])
		var col: String = SECTION_COLORS[course.segments[id]["section"]]
		var dash := ' stroke-dasharray="10 6"' if course.segments[id]["choice"] in ["around", "bridge", "sheltered"] else ""
		o.append('<polyline points="%s" fill="none" stroke="%s" stroke-width="3"%s/>' % [_pts(line), col, dash])
		var seg: Dictionary = course.segments[id]
		for rg in seg["boosts"]:
			o.append(_span(id, float(rg[0]), float(rg[1]), "#ffd400", 7.0))
		if not seg["ramp"].is_empty():
			o.append(_span(id, float(seg["ramp"]["kick_a"]), float(seg["ramp"]["lip_s"]), "#a0622d", _hw(id) * 2.0 * SCALE))
	# Covered bridge roof over the hump.
	var br := _route("pond_bridge")
	var hs := 0.0
	var top := -INF
	var s := 0.0
	while s <= br.length:
		if br.pos_at(s).y > top:
			top = br.pos_at(s).y
			hs = s
		s += 0.5
	o.append(_span("pond_bridge", hs - 7.0, hs + 7.0, "#7a4a26", (_hw("pond_bridge") + 1.0) * 2.0 * SCALE))
	# Start/finish line
	var sr := _route("start")
	var a := _xz(sr.world_at(0.0, _hw("start")))
	var b := _xz(sr.world_at(0.0, -_hw("start")))
	o.append('<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="#111" stroke-width="5" stroke-dasharray="5 5"/>' % [
		_p(a).split(",")[0], _p(a).split(",")[1], _p(b).split(",")[0], _p(b).split(",")[1]])
	# Buildings
	for bd in plan.buildings:
		var col: String = KIND_COLORS[bd["kind"]]
		o.append('<polygon points="%s" fill="%s" stroke="#3a2a1c" stroke-width="1.5"/>' % [_pts(Array(VillagePlan.footprint(bd))), col])
		if bd["kind"] == "church":
			var f := Vector2(sin(bd["yaw"]), cos(bd["yaw"]))
			var tower: Vector2 = bd["pos"] + f * (bd["size"].y * 0.5 + 2.5)
			var c := _p(tower).split(",")
			o.append('<circle cx="%s" cy="%s" r="%.1f" fill="#f2efe6" stroke="#3a2a1c" stroke-width="1.5"/>' % [c[0], c[1], 3.0 * SCALE])
		if bd["label"] != "":
			var c := _p(bd["pos"]).split(",")
			o.append('<text x="%s" y="%s" font-size="13" text-anchor="middle" fill="#222" stroke="#fff" stroke-width="3" paint-order="stroke">%s</text>' % [c[0], c[1], bd["label"]])
	# Fountain and lime tree
	var fc := _p(plan.fountain).split(",")
	o.append('<circle cx="%s" cy="%s" r="%.1f" fill="#9fc9e6" stroke="#777" stroke-width="2"/>' % [fc[0], fc[1], 2.5 * SCALE])
	var lc := _p(plan.lime_tree).split(",")
	o.append('<circle cx="%s" cy="%s" r="%.1f" fill="#3f7f2f"/>' % [lc[0], lc[1], 3.5 * SCALE])
	o.append(_label(plan.fountain + Vector2(0, -6), "Dorfplatz + Brunnen"))
	o.append(_label(Vector2(plan.hay_meadow.x, plan.hay_meadow.y), "Heuwiese"))
	o.append(_label(Vector2(plan.meadow_hollow.x, plan.meadow_hollow.y - 10.0), "Matte (open, windy)"))
	o.append(_label(_xz(br.pos_at(hs)) + Vector2(10, 0), "Covered bridge"))
	o.append(_label(plan.pond[plan.pond.size() * 3 / 4] + Vector2(-8, 0), "Weiher (ford)"))
	o.append(_label(_xz(_route("cross_sheltered").pos_at(_route("cross_sheltered").length * 0.5)) + Vector2(0, 10), "Laubengasse"))
	o.append(_label(_xz(_route("ramp_jump").pos_at(12.0)) + Vector2(0, -7), "Ski-jump kicker"))
	o.append(_label(_xz(sr.pos_at(0.0)) + Vector2(0, -6), "START / FINISH"))
	o.append("</g>")
	# North arrow
	o.append('<text x="%.0f" y="30" font-size="22" font-weight="bold" fill="#222">N &#8593;</text>' % (w - 60.0))
	o.append('<line x1="20" y1="%.0f" x2="%.0f" y2="%.0f" stroke="#222" stroke-width="3"/>' % [h - 20.0, 20.0 + 50.0 * SCALE, h - 20.0])
	o.append('<text x="20" y="%.0f" font-size="13" fill="#222">50 m</text>' % (h - 28.0))
	o.append(_panel(w))
	o.append("</svg>")
	return "\n".join(o)


func _span(id: String, s0: float, s1: float, col: String, width: float) -> String:
	var r := _route(id)
	var line: Array = []
	var s := maxf(0.0, s0)
	while s <= minf(r.length, s1):
		line.append(_xz(r.pos_at(s)))
		s += 1.0
	return '<polyline points="%s" fill="none" stroke="%s" stroke-width="%.1f" opacity="0.9"/>' % [_pts(line), col, width]


func _label(at: Vector2, t: String) -> String:
	var c := _p(at).split(",")
	return '<text x="%s" y="%s" font-size="14" font-weight="bold" text-anchor="middle" fill="#222" stroke="#fff" stroke-width="3" paint-order="stroke">%s</text>' % [c[0], c[1], t]


func _panel(x0: float) -> String:
	var o: PackedStringArray = []
	var y := 36.0
	o.append('<text x="%.0f" y="%.0f" font-size="22" font-weight="bold" fill="#222">Village circuit</text>' % [x0 + 20.0, y])
	y += 26.0
	o.append('<text x="%.0f" y="%.0f" font-size="13" fill="#555">closed loop, clockwise, lap after lap</text>' % [x0 + 20.0, y])
	y += 30.0
	for sec in ["hills", "pond", "crossing", "bends"]:
		o.append('<rect x="%.0f" y="%.0f" width="18" height="10" fill="%s"/>' % [x0 + 20.0, y - 9.0, SECTION_COLORS[sec]])
		o.append('<text x="%.0f" y="%.0f" font-size="14" fill="#222">%s</text>' % [x0 + 46.0, y, sec])
		y += 20.0
	o.append('<text x="%.0f" y="%.0f" font-size="12" fill="#555">dashed = longer, safer fork choice</text>' % [x0 + 20.0, y])
	y += 16.0
	o.append('<text x="%.0f" y="%.0f" font-size="12" fill="#555">yellow = boost zone</text>' % [x0 + 20.0, y])
	y += 28.0
	o.append('<text x="%.0f" y="%.0f" font-size="15" font-weight="bold" fill="#222">Lap lengths</text>' % [x0 + 20.0, y])
	y += 20.0
	var lens := course.all_route_lengths()
	for k in lens:
		o.append('<text x="%.0f" y="%.0f" font-size="12" fill="#222">%s  %.0f m</text>' % [x0 + 20.0, y, k, lens[k]])
		y += 16.0
	y += 16.0
	var ok := fails.is_empty()
	o.append('<text x="%.0f" y="%.0f" font-size="15" font-weight="bold" fill="%s">%s</text>' % [
		x0 + 20.0, y, "#2a7d2a" if ok else "#c0392b", "All checks passed" if ok else "%d checks FAILED" % fails.size()])
	y += 18.0
	for f in fails:
		o.append('<text x="%.0f" y="%.0f" font-size="10" fill="#c0392b">%s</text>' % [x0 + 20.0, y, f.left(60).xml_escape()])
		y += 13.0
	return "\n".join(o)

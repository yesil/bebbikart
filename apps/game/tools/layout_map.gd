extends SceneTree
## Top-down layout map + geometry checks for the course (sim/course.gd) and the planned terrain
## features (world/landscape.gd). Headless, no rendering:
##   godot --headless --path apps/game --script res://tools/layout_map.gd -- [--out=PATH] [--scale=3]
## Writes a PNG (default res://docs/layout_map.png) and exits 1 if any check fails.
##
## Checks:
##   spacing    non-adjacent segments (no shared junction) keep >= hwA + hwB + GAP between centre lines
##   crossing   no two segments cross (shared junction stubs excepted)
##   slope      |dy/ds| of every centre line <= MAX_SLOPE (the ramp kicker is a separate structure)
##   curvature  |k| <= MAX_K and |k| * half_width <= MAX_K_HW (inner edge never folds)
##   junction   branches leave/join the trunk with the trunk's position and heading, on a straight stub
##   fork       sibling branches split and merge at >= FORK_ANGLE, separate by >= hwA + hwB + GAP
##              at their widest, and their separation grows then shrinks (no pinch in between)
##   landscape  pond/stream/dip/valley/knoll sit where the fork data says they are

const Course = preload("res://sim/course.gd")
const Route = preload("res://sim/route.gd")
const Landscape = preload("res://world/landscape.gd")

const GAP := 6.0
const MAX_SLOPE := 0.16
const MAX_K := 1.0 / 10.0
const MAX_K_HW := 0.4
const FORK_ANGLE := 15.0          # degrees, measured FORK_PROBE metres from the junction
const FORK_PROBE := 12.0
const STUB := 3.0                 # straight shared stub at every junction
const SPLIT_ZONE := 6.0           # sibling stubs overlap this far from a junction

const VIEW := Rect2(-110, -30, 180, 445)   # x, z, w, h in metres
const PANEL_W := 420

const SECTION_COLORS := {
	"hills": Color(0.85, 0.62, 0.30), "pond": Color(0.55, 0.55, 0.62),
	"crossing": Color(0.62, 0.42, 0.30), "bends": Color(0.80, 0.40, 0.45),
}

var course: Course
var img: Image
var px := 3.0
var fails: PackedStringArray = []
var notes: PackedStringArray = []


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	px = float(args.get("scale", "3"))
	course = Course.new()
	_check_all()
	_draw()
	var out := String(args.get("out", "res://docs/layout_map.png"))
	if out.begins_with("res://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out.get_base_dir()))
		out = ProjectSettings.globalize_path(out)
	img.save_png(out)
	print("layout map: ", out)
	for n in notes:
		print("  ", n)
	if fails.is_empty():
		print("CHECKS PASSED")
		quit(0)
	else:
		for f in fails:
			print("  FAIL ", f)
		print("CHECKS FAILED: %d" % fails.size())
		quit(1)


# ---------------------------------------------------------------- geometry helpers

func _route(id: String) -> Route:
	return course.segments[id]["route"]


func _hw(id: String) -> float:
	return float(course.segments[id]["half_width"])


func _xz(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)


func _samples(id: String, step := 1.0) -> Array:
	var r := _route(id)
	var out := []
	var n := int(ceil(r.length / step))
	for i in n + 1:
		var s := minf(i * step, r.length)
		out.append([s, _xz(r.pos_at(s))])
	return out


## Shared junction points of two segments as [[point, end_a ("start"|"end"), end_b], ...].
func _shared(a: String, b: String) -> Array:
	var out := []
	var ra := _route(a)
	var rb := _route(b)
	for ea in ["start", "end"]:
		var pa := ra.pos_at(0.0 if ea == "start" else ra.length)
		for eb in ["start", "end"]:
			var pb := rb.pos_at(0.0 if eb == "start" else rb.length)
			if pa.distance_to(pb) < 0.05:
				out.append([pa, ea, eb])
	return out


func _dist_from_end(r: Route, s: float, end: String) -> float:
	return s if end == "start" else r.length - s


func _siblings() -> Array:
	var by_fork := {}
	for id in course.ordered_ids:
		var f: String = course.segments[id]["fork"]
		if f != "":
			if not by_fork.has(f):
				by_fork[f] = []
			by_fork[f].append(id)
	return by_fork.values()


static func _seg_intersect(p1: Vector2, p2: Vector2, q1: Vector2, q2: Vector2) -> bool:
	var d1 := (q2 - q1).cross(p1 - q1)
	var d2 := (q2 - q1).cross(p2 - q1)
	var d3 := (p2 - p1).cross(q1 - p1)
	var d4 := (p2 - p1).cross(q2 - p1)
	return ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0))


# ---------------------------------------------------------------- checks

func _check_all() -> void:
	var ids := course.ordered_ids
	var sibling_pairs := {}
	for group in _siblings():
		for i in group.size():
			for j in range(i + 1, group.size()):
				sibling_pairs[group[i] + "|" + group[j]] = true
	# spacing + crossing
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: String = ids[i]
			var b: String = ids[j]
			var shared := _shared(a, b)
			var sa := _samples(a, 0.5)
			var sb := _samples(b, 0.5)
			if shared.is_empty():
				var need := _hw(a) + _hw(b) + GAP
				var best := INF
				var where := Vector2.ZERO
				for pa in sa:
					for pb in sb:
						var dd: float = (pa[1] as Vector2).distance_to(pb[1])
						if dd < best:
							best = dd
							where = pa[1]
				if best < need:
					fails.append("spacing %s vs %s: %.1f m < %.1f m near (%.0f, %.0f)" % [a, b, best, need, where.x, where.y])
			var skip := SPLIT_ZONE if sibling_pairs.has(a + "|" + b) else 1.5
			for k in sa.size() - 1:
				if _near_shared(a, sa[k][0], shared, skip):
					continue
				for m in sb.size() - 1:
					if _near_shared(b, sb[m][0], shared, skip, true):
						continue
					if _seg_intersect(sa[k][1], sa[k + 1][1], sb[m][1], sb[m + 1][1]):
						fails.append("crossing %s x %s at (%.1f, %.1f)" % [a, b, sa[k][1].x, sa[k][1].y])
						break
	# slope + curvature
	for id in ids:
		var r := _route(id)
		var max_slope := 0.0
		var max_k := 0.0
		var s := 0.0
		while s <= r.length:
			max_slope = maxf(max_slope, absf(tan(r.pitch_at(s))))
			max_k = maxf(max_k, absf(r.curv_at(s)))
			s += 0.5
		notes.append("%-16s len %6.1f m  max slope %4.1f%%  min radius %s" % [id, r.length, max_slope * 100.0,
			"%.1f m" % (1.0 / max_k) if max_k > 0.0001 else "straight"])
		if max_slope > MAX_SLOPE:
			fails.append("slope %s: %.1f%% > %.1f%%" % [id, max_slope * 100.0, MAX_SLOPE * 100.0])
		if max_k > MAX_K:
			fails.append("curvature %s: radius %.1f m < %.1f m" % [id, 1.0 / max_k, 1.0 / MAX_K])
		if max_k * _hw(id) > MAX_K_HW:
			fails.append("curvature %s: |k|*hw %.2f > %.2f" % [id, max_k * _hw(id), MAX_K_HW])
	_check_junctions()
	_check_forks()
	_check_landscape()


func _near_shared(id: String, s: float, shared: Array, dist: float, second := false) -> bool:
	var r := _route(id)
	for sh in shared:
		var end: String = sh[2] if second else sh[1]
		if _dist_from_end(r, s, end) < dist:
			return true
	return false


func _check_junctions() -> void:
	# Every fork branch must leave its predecessors and join its successors with the same
	# position and heading, on a straight stub.
	for id in course.ordered_ids:
		var seg: Dictionary = course.segments[id]
		if seg["fork"] == "":
			continue
		var r := _route(id)
		for other in course.ordered_ids:
			if course.segments[other]["fork"] == seg["fork"]:
				continue
			var ro := _route(other)
			if ro.pos_at(ro.length).distance_to(r.pos_at(0.0)) < 0.5:
				_junction_pair(id, "split", ro.heading_at(ro.length), r.heading_at(0.0), ro.pos_at(ro.length).distance_to(r.pos_at(0.0)))
			if ro.pos_at(0.0).distance_to(r.pos_at(r.length)) < 0.5:
				_junction_pair(id, "merge", r.heading_at(r.length), ro.heading_at(0.0), ro.pos_at(0.0).distance_to(r.pos_at(r.length)))
		# Heading change across each stub (curvature itself is smoothed over +-3 m by the sim).
		for ends in [[0.0, STUB], [r.length - STUB, r.length]]:
			var turn := rad_to_deg(absf(wrapf(r.heading_at(ends[1]) - r.heading_at(ends[0]), -PI, PI)))
			if turn > 1.5:
				fails.append("junction %s: stub at s=%.0f turns %.1f deg" % [id, ends[0], turn])


func _junction_pair(id: String, what: String, ha: float, hb: float, gap: float) -> void:
	if gap > 0.05:
		fails.append("junction %s %s: gap %.2f m" % [id, what, gap])
	var dh := rad_to_deg(absf(wrapf(ha - hb, -PI, PI)))
	if dh > 3.0:
		fails.append("junction %s %s: heading kink %.1f deg" % [id, what, dh])


func _check_forks() -> void:
	for group in _siblings():
		var a: String = group[0]
		var b: String = group[1]
		var ra := _route(a)
		var rb := _route(b)
		for end in ["split", "merge"]:
			var ha := ra.heading_at(FORK_PROBE if end == "split" else ra.length - FORK_PROBE)
			var hb := rb.heading_at(FORK_PROBE if end == "split" else rb.length - FORK_PROBE)
			var ang := rad_to_deg(absf(wrapf(ha - hb, -PI, PI)))
			notes.append("fork %-8s %-5s angle %4.1f deg" % [course.segments[a]["fork"], end, ang])
			if ang < FORK_ANGLE:
				fails.append("fork %s %s angle %.1f deg < %.1f" % [course.segments[a]["fork"], end, ang, FORK_ANGLE])
		# Separation profile: distance from each point of the longer branch to the other branch.
		var long_id := a if ra.length >= rb.length else b
		var short_id := b if long_id == a else a
		var sb := _samples(short_id, 0.5)
		var prof := PackedFloat32Array()
		for p in _samples(long_id, 1.0):
			var best := INF
			for q in sb:
				best = minf(best, (p[1] as Vector2).distance_to(q[1]))
			prof.append(best)
		var peak := 0
		for i in prof.size():
			if prof[i] > prof[peak]:
				peak = i
		var need := _hw(a) + _hw(b) + GAP
		notes.append("fork %-8s widest separation %.1f m (need %.1f)" % [course.segments[a]["fork"], prof[peak], need])
		if prof[peak] < need:
			fails.append("fork %s: branches only %.1f m apart at widest (< %.1f)" % [course.segments[a]["fork"], prof[peak], need])
		for i in range(1, prof.size()):
			var growing := i <= peak
			if (growing and prof[i] < prof[i - 1] - 0.3) or (not growing and prof[i] > prof[i - 1] + 0.3):
				fails.append("fork %s: separation pinches at s=%d of %s" % [course.segments[a]["fork"], i, long_id])
				break


func _check_landscape() -> void:
	# Pond: the ford's water range is inside the pond, the rest of the ford outside; no other road in it.
	var ford := _route("pond_water")
	var wr: Array = course.segments["pond_water"]["water"][0]
	var s := 0.0
	while s <= ford.length:
		var p := _xz(ford.pos_at(s))
		var inside := Landscape.in_pond(p)
		var y := ford.pos_at(s).y
		if s > float(wr[0]) + 5.0 and s < float(wr[1]) - 5.0:
			if not inside:
				fails.append("pond: ford s=%.0f is in the water range but outside the pond" % s)
				break
			if y > Landscape.POND_LEVEL - 0.15:
				fails.append("pond: ford s=%.0f only %.2f m under water" % [s, Landscape.POND_LEVEL - y])
				break
		elif (s < float(wr[0]) - 2.0 or s > float(wr[1]) + 2.0) and inside:
			fails.append("pond: ford s=%.0f is in the pond but outside the water range" % s)
			break
		s += 1.0
	for id in course.ordered_ids:
		if id == "pond_water":
			continue
		for q in _samples(id, 1.0):
			if Landscape.in_pond(q[1], _hw(id) + 2.0):
				fails.append("pond: %s runs into the pond at (%.0f, %.0f)" % [id, q[1].x, q[1].y])
				break
	# Stream: crossed once, by the bridge lane, at its hump.
	var crossings := {}
	for id in course.ordered_ids:
		for q in _samples(id, 0.5):
			if Landscape.stream_dist(q[1]) < Landscape.STREAM_HALF_WIDTH + _hw(id):
				crossings[id] = q[0]
				break
	if crossings.keys() != ["pond_bridge"]:
		fails.append("stream: crossed by %s (want only pond_bridge)" % [crossings.keys()])
	else:
		var br := _route("pond_bridge")
		var hump := 0.0
		var top := -INF
		var t := 0.0
		while t <= br.length:
			if br.pos_at(t).y > top:
				top = br.pos_at(t).y
				hump = t
			t += 0.5
		var cross_s := _stream_crossing_s(br)
		notes.append("stream crosses pond_bridge at s=%.1f, hump at s=%.1f (%.2f m above the lane)" % [cross_s, hump, top - 0.4])
		if absf(cross_s - hump) > 4.0:
			fails.append("stream: bridge hump at s=%.1f but stream at s=%.1f" % [hump, cross_s])
	# Dip: only the jump line crosses it, between the lip and the landing.
	var rp: Dictionary = course.segments["ramp_jump"]["ramp"]
	var jr := _route("ramp_jump")
	var d0 := INF
	var d1 := -INF
	s = 0.0
	while s <= jr.length:
		if Landscape.in_dip(_xz(jr.pos_at(s))):
			d0 = minf(d0, s)
			d1 = maxf(d1, s)
		s += 0.5
	notes.append("dip spans ramp_jump s=%.1f..%.1f (lip %.1f, land %.1f)" % [d0, d1, rp["lip_s"], rp["land_s"]])
	if d0 < float(rp["lip_s"]) - 0.5 or d1 > float(rp["land_s"]) + 0.5 or d1 - d0 < 12.0:
		fails.append("dip: spans s=%.1f..%.1f, want inside lip %.1f..land %.1f" % [d0, d1, rp["lip_s"], rp["land_s"]])
	for id in course.ordered_ids:
		if id == "ramp_jump":
			continue
		for q in _samples(id, 1.0):
			if Landscape.in_dip(q[1]):
				fails.append("dip: %s runs through the dip" % id)
				break
	# Knoll: between the two ramp branches, clear of both road edges.
	for id in ["ramp_jump", "ramp_around"]:
		var best := INF
		for q in _samples(id, 0.5):
			best = minf(best, (q[1] as Vector2).distance_to(Landscape.KNOLL_CENTER))
		var clear := best - _hw(id)
		notes.append("knoll top is %.1f m from the %s road edge" % [clear, id])
		if clear < 2.5:
			fails.append("knoll: only %.1f m from %s" % [clear, id])
	# Valley: only the causeway crosses it; the sheltered lane stays above the valley head.
	for id in course.ordered_ids:
		var hit := false
		for q in _samples(id, 1.0):
			var vi: Array = Landscape.valley_info(q[1])
			if float(vi[0]) < float(vi[1]):
				hit = true
				break
		if hit != (id == "cross_exposed"):
			fails.append("valley: %s %s the valley" % [id, "crosses" if hit else "misses"])


func _stream_crossing_s(r: Route) -> float:
	var best := INF
	var best_s := 0.0
	var s := 0.0
	while s <= r.length:
		var dd := Landscape.stream_dist(_xz(r.pos_at(s)))
		if dd < best:
			best = dd
			best_s = s
		s += 0.25
	return best_s


# ---------------------------------------------------------------- drawing

func _to_px(p: Vector2) -> Vector2:
	return Vector2((p.x - VIEW.position.x) * px, (VIEW.end.y - p.y) * px)


func _disc(c: Vector2, r: float, col: Color) -> void:
	var x0 := maxi(0, int(c.x - r))
	var x1 := mini(img.get_width() - 1, int(c.x + r) + 1)
	var y0 := maxi(0, int(c.y - r))
	var y1 := mini(img.get_height() - 1, int(c.y + r) + 1)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if Vector2(x + 0.5, y + 0.5).distance_squared_to(c) <= r * r:
				img.set_pixel(x, y, col)


func _line(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var n := maxi(1, int(a.distance_to(b) / maxf(0.5, w * 0.5)))
	for i in n + 1:
		_disc(a.lerp(b, float(i) / n), w * 0.5, col)


func _draw() -> void:
	var w := int(VIEW.size.x * px)
	var h := int(VIEW.size.y * px)
	img = Image.create(w + PANEL_W, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.55, 0.72, 0.42))
	# Terrain features: hills (shaded by height), valley, dip, knoll, plazas, pond, stream.
	for y in h:
		for x in w:
			var p := Vector2(VIEW.position.x + (x + 0.5) / px, VIEW.end.y - (y + 0.5) / px)
			var lift := 0.0
			for hl in Landscape.HILLS:
				var dd := p.distance_to(Vector2(hl.x, hl.y)) / hl.z
				if dd < 1.0:
					lift += hl.w * (0.5 + 0.5 * cos(PI * dd))
			var vi: Array = Landscape.valley_info(p)
			var col := Color(0.55, 0.72, 0.42).lightened(clampf(lift / 30.0, 0.0, 0.4))
			if int(lift) % 2 == 1 and fmod(lift, 1.0) < 0.12:
				col = col.darkened(0.12)   # contour every 2 m
			if float(vi[0]) < float(vi[1]):
				col = col.darkened(0.25 * (1.0 - float(vi[0]) / float(vi[1])))
			if Landscape.in_dip(p):
				col = Color(0.50, 0.40, 0.28)
			if p.distance_to(Landscape.KNOLL_CENTER) < Landscape.KNOLL_RADIUS:
				col = col.lightened(0.25 * (1.0 - p.distance_to(Landscape.KNOLL_CENTER) / Landscape.KNOLL_RADIUS))
			if Landscape.FLAT_START.has_point(p) or Landscape.FLAT_FINISH.has_point(p):
				col = col.lerp(Color(0.7, 0.7, 0.62), 0.35)
			if Landscape.in_pond(p):
				col = Color(0.30, 0.55, 0.80)
			elif Landscape.stream_dist(p) < Landscape.STREAM_HALF_WIDTH:
				col = Color(0.30, 0.55, 0.80)
			img.set_pixel(x, y, col)
	# Grid every 10 m, labelled every 50 m.
	var x_m := ceilf(VIEW.position.x / 10.0) * 10.0
	while x_m <= VIEW.end.x:
		var xp := mini(w - 1, int(_to_px(Vector2(x_m, 0)).x))
		for y in h:
			img.set_pixel(xp, y, img.get_pixel(xp, y).darkened(0.18 if int(x_m) % 50 == 0 else 0.07))
		if int(x_m) % 50 == 0:
			_text(str(int(x_m)), Vector2(xp + 3, h - 14), 1, Color.WHITE)
		x_m += 10.0
	var z_m := ceilf(VIEW.position.y / 10.0) * 10.0
	while z_m <= VIEW.end.y:
		var yp := mini(h - 1, int(_to_px(Vector2(0, z_m)).y))
		for x in w:
			img.set_pixel(x, yp, img.get_pixel(x, yp).darkened(0.18 if int(z_m) % 50 == 0 else 0.07))
		if int(z_m) % 50 == 0:
			_text("Z" + str(int(z_m)), Vector2(4, yp + 3), 1, Color.WHITE)
		z_m += 10.0
	# Roads: shoulder, surface, centre line.
	for id in course.ordered_ids:
		for q in _samples(id, 0.5):
			_disc(_to_px(q[1]), (_hw(id) + 1.5) * px, Color(0.62, 0.58, 0.48))
	for id in course.ordered_ids:
		var seg: Dictionary = course.segments[id]
		var col: Color = SECTION_COLORS[seg["section"]]
		if seg["choice"] in ["around", "bridge", "sheltered"]:
			col = col.darkened(0.15)
		for q in _samples(id, 0.5):
			_disc(_to_px(q[1]), _hw(id) * px, col)
	for id in course.ordered_ids:
		var seg: Dictionary = course.segments[id]
		var r := _route(id)
		for z in seg["water"]:
			_span(r, float(z[0]), float(z[1]), Color(0.45, 0.85, 1.0), 2.0)
		for z in seg["boosts"]:
			_span(r, float(z[0]), float(z[1]), Color(1.0, 0.2, 0.8), 3.0)
		var rp: Dictionary = seg["ramp"]
		if not rp.is_empty():
			_span(r, float(rp["kick_a"]), float(rp["lip_s"]), Color(1.0, 0.85, 0.1), 4.0)
			_span(r, float(rp["land_s"]), float(rp["land_s"]) + 3.0, Color(0.2, 0.9, 0.3), 4.0)
		for b in seg["bumps"]:
			_span(r, float(b) - 0.5, float(b) + 0.5, Color.WHITE, 6.0)
		if seg["rails"] or seg["edge"] < 0.5:
			for side in [-1.0, 1.0]:
				var s := 0.0
				while s <= r.length:
					_disc(_to_px(_xz(r.world_at(s, side * (_hw(id) + 0.3)))), 1.2, Color(0.35, 0.22, 0.12))
					s += 0.5
		var mid := _to_px(_xz(r.pos_at(r.length * 0.5)))
		var lx := 1.0 if seg["choice"] in ["around", "sheltered"] else -1.0
		var label: String = id.to_upper().replace("_", " ")
		var tx := mid.x + (14.0 if lx > 0.0 else -14.0 - _text_w(label, 1))
		_text(label, Vector2(tx, mid.y - 4), 1, Color.WHITE, true)
	# Section lines, junctions, start and finish.
	for id in course.ordered_ids:
		var seg: Dictionary = course.segments[id]
		var idx := course.ordered_ids.find(id)
		if seg["fork"] == "" and idx > 0:
			var r := _route(id)
			var prev: String = ""
			for k in range(idx - 1, -1, -1):
				if course.segments[course.ordered_ids[k]]["fork"] == "" or k == idx - 1:
					prev = course.segments[course.ordered_ids[k]]["section"]
					break
			var a := _to_px(_xz(r.world_at(0.0, -_hw(id) - 1.0)))
			var b := _to_px(_xz(r.world_at(0.0, _hw(id) + 1.0)))
			_line(a, b, 2.0, Color.WHITE if prev == seg["section"] else Color.BLACK)
	var r_end := _route("bends")
	_line(_to_px(_xz(r_end.world_at(r_end.length, -5.0))), _to_px(_xz(r_end.world_at(r_end.length, 5.0))), 4.0, Color.BLACK)
	_text("FINISH", _to_px(_xz(r_end.pos_at(r_end.length))) + Vector2(14, -6), 2, Color.BLACK)
	_text("START", _to_px(Vector2(0, 0)) + Vector2(14, -6), 2, Color.BLACK)
	_text("POND", _to_px(Landscape.POND_CENTER) + Vector2(-30, 30), 1, Color(0.85, 0.95, 1.0))
	_text("STREAM", _to_px(Vector2(-90, 182)) + Vector2(0, -16), 1, Color(0.85, 0.95, 1.0))
	_text("VALLEY", _to_px(Vector2(-80, 246)), 1, Color(0.2, 0.25, 0.15))
	_text("DIP", _to_px(Landscape.DIP_CENTER) + Vector2(-34, -4), 1, Color.WHITE)
	_text("KNOLL", _to_px(Landscape.KNOLL_CENTER) + Vector2(-14, -14), 1, Color(0.2, 0.3, 0.15))
	_panel(w)


func _span(r: Route, s0: float, s1: float, col: Color, wpx: float) -> void:
	var s := s0
	while s <= s1:
		_disc(_to_px(_xz(r.pos_at(s))), wpx, col)
		s += 0.25


func _panel(x0: int) -> void:
	for y in img.get_height():
		for x in range(x0, img.get_width()):
			img.set_pixel(x, y, Color(0.13, 0.14, 0.16))
	var y := 14.0
	_text("BEBBIKART COURSE LAYOUT", Vector2(x0 + 14, y), 2, Color.WHITE)
	y += 26.0
	_text("1 GRID SQUARE = 10 M  (%.0f PX/M)" % px, Vector2(x0 + 14, y), 1, Color(0.8, 0.8, 0.8))
	y += 20.0
	var legend := [
		[SECTION_COLORS["hills"], "HILLS SECTION"], [SECTION_COLORS["pond"], "POND SECTION"],
		[SECTION_COLORS["crossing"], "CROSSING SECTION"], [SECTION_COLORS["bends"], "BENDS SECTION"],
		[Color(1.0, 0.2, 0.8), "BOOST ZONE"], [Color(0.45, 0.85, 1.0), "WATER RANGE"],
		[Color(1.0, 0.85, 0.1), "RAMP KICKER"], [Color(0.2, 0.9, 0.3), "LANDING"],
		[Color.WHITE, "BUMP / SAME-SECTION JOIN"], [Color.BLACK, "SECTION LINE"],
		[Color(0.35, 0.22, 0.12), "RAILS / LOW-EDGE ROAD"], [Color(0.30, 0.55, 0.80), "POND + STREAM"],
	]
	for l in legend:
		for yy in 10:
			for xx in 18:
				img.set_pixel(x0 + 14 + xx, int(y) + yy, l[0])
		_text(l[1], Vector2(x0 + 40, y + 2), 1, Color.WHITE)
		y += 16.0
	y += 10.0
	_text("LENGTHS", Vector2(x0 + 14, y), 2, Color.WHITE)
	y += 24.0
	for id in course.ordered_ids:
		_text("%-16s %6.1f M" % [id.to_upper(), _route(id).length], Vector2(x0 + 14, y), 1, Color(0.85, 0.85, 0.85))
		y += 13.0
	y += 6.0
	var lens := course.all_route_lengths()
	for k in lens:
		_text("%-24s %6.1f M" % [String(k).to_upper(), lens[k]], Vector2(x0 + 14, y), 1, Color(0.7, 0.8, 0.9))
		y += 13.0
	y += 12.0
	_text("CHECKS", Vector2(x0 + 14, y), 2, Color.WHITE)
	y += 24.0
	if fails.is_empty():
		_text("ALL PASSED", Vector2(x0 + 14, y), 2, Color(0.4, 1.0, 0.5))
		y += 24.0
	for f in fails:
		_text(f.to_upper(), Vector2(x0 + 14, y), 1, Color(1.0, 0.45, 0.4))
		y += 13.0
	for n in notes:
		if y > img.get_height() - 16:
			break
		_text(n.to_upper(), Vector2(x0 + 14, y), 1, Color(0.75, 0.75, 0.75))
		y += 13.0


# ---------------------------------------------------------------- 5x7 bitmap text

const FONT := {
	"A": [0x0E, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11], "B": [0x1E, 0x11, 0x11, 0x1E, 0x11, 0x11, 0x1E],
	"C": [0x0E, 0x11, 0x10, 0x10, 0x10, 0x11, 0x0E], "D": [0x1C, 0x12, 0x11, 0x11, 0x11, 0x12, 0x1C],
	"E": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x1F], "F": [0x1F, 0x10, 0x10, 0x1E, 0x10, 0x10, 0x10],
	"G": [0x0E, 0x11, 0x10, 0x17, 0x11, 0x11, 0x0F], "H": [0x11, 0x11, 0x11, 0x1F, 0x11, 0x11, 0x11],
	"I": [0x0E, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0E], "J": [0x07, 0x02, 0x02, 0x02, 0x02, 0x12, 0x0C],
	"K": [0x11, 0x12, 0x14, 0x18, 0x14, 0x12, 0x11], "L": [0x10, 0x10, 0x10, 0x10, 0x10, 0x10, 0x1F],
	"M": [0x11, 0x1B, 0x15, 0x15, 0x11, 0x11, 0x11], "N": [0x11, 0x11, 0x19, 0x15, 0x13, 0x11, 0x11],
	"O": [0x0E, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E], "P": [0x1E, 0x11, 0x11, 0x1E, 0x10, 0x10, 0x10],
	"Q": [0x0E, 0x11, 0x11, 0x11, 0x15, 0x12, 0x0D], "R": [0x1E, 0x11, 0x11, 0x1E, 0x14, 0x12, 0x11],
	"S": [0x0F, 0x10, 0x10, 0x0E, 0x01, 0x01, 0x1E], "T": [0x1F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04],
	"U": [0x11, 0x11, 0x11, 0x11, 0x11, 0x11, 0x0E], "V": [0x11, 0x11, 0x11, 0x11, 0x11, 0x0A, 0x04],
	"W": [0x11, 0x11, 0x11, 0x15, 0x15, 0x15, 0x0A], "X": [0x11, 0x11, 0x0A, 0x04, 0x0A, 0x11, 0x11],
	"Y": [0x11, 0x11, 0x0A, 0x04, 0x04, 0x04, 0x04], "Z": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x10, 0x1F],
	"0": [0x0E, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0E], "1": [0x04, 0x0C, 0x04, 0x04, 0x04, 0x04, 0x0E],
	"2": [0x0E, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1F], "3": [0x1F, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0E],
	"4": [0x02, 0x06, 0x0A, 0x12, 0x1F, 0x02, 0x02], "5": [0x1F, 0x10, 0x1E, 0x01, 0x01, 0x11, 0x0E],
	"6": [0x06, 0x08, 0x10, 0x1E, 0x11, 0x11, 0x0E], "7": [0x1F, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08],
	"8": [0x0E, 0x11, 0x11, 0x0E, 0x11, 0x11, 0x0E], "9": [0x0E, 0x11, 0x11, 0x0F, 0x01, 0x02, 0x0C],
	".": [0, 0, 0, 0, 0, 0x0C, 0x0C], "-": [0, 0, 0, 0x1F, 0, 0, 0], "/": [0, 0x01, 0x02, 0x04, 0x08, 0x10, 0],
	":": [0, 0x0C, 0x0C, 0, 0x0C, 0x0C, 0], "+": [0, 0x04, 0x04, 0x1F, 0x04, 0x04, 0],
	"(": [0x02, 0x04, 0x08, 0x08, 0x08, 0x04, 0x02], ")": [0x08, 0x04, 0x02, 0x02, 0x02, 0x04, 0x08],
	"%": [0x18, 0x19, 0x02, 0x04, 0x08, 0x13, 0x03], ">": [0x08, 0x04, 0x02, 0x01, 0x02, 0x04, 0x08],
	"<": [0x02, 0x04, 0x08, 0x10, 0x08, 0x04, 0x02], "=": [0, 0, 0x1F, 0, 0x1F, 0, 0],
	"*": [0, 0x04, 0x15, 0x0E, 0x15, 0x04, 0], ",": [0, 0, 0, 0, 0x0C, 0x04, 0x08],
}


func _text_w(t: String, scale: int) -> float:
	return t.length() * 6 * scale


func _text(t: String, at: Vector2, scale: int, col: Color, shadow := false) -> void:
	if shadow:
		_text(t, at + Vector2(1, 1), scale, Color(0, 0, 0, 1))
	var x := int(at.x)
	for ch in t.to_upper():
		var g: Array = FONT.get(ch, [])
		for row in g.size():
			for bit in 5:
				if int(g[row]) & (1 << (4 - bit)):
					for sy in scale:
						for sx in scale:
							var px_ := x + bit * scale + sx
							var py_ := int(at.y) + row * scale + sy
							if px_ >= 0 and py_ >= 0 and px_ < img.get_width() and py_ < img.get_height():
								img.set_pixel(px_, py_, col)
		x += 6 * scale

extends RefCounted
## Terrain heights and texture layers for the village loop, from sim/village_course.gd and
## world/village/village_plan.gd. Pure data (no nodes): tools/bake_village.gd imports it into
## Terrain3D and tools/village_world_check.gd checks against it.
##
## Heights: the village ground is a smooth blend of the nearby road heights (so the square, the
## main street and the church hill read as one sloping village), with gentle noise; beyond the
## village the ground rises to pastures and then to the mountain ring from the plan. Every road
## corridor is levelled just under the road, except where the road is a structure (covered
## bridge, causeway deck) where the ground drops away underneath. Then the pond basin, the brook
## channel, the meadow hollow under the causeway and the hay meadow dip are cut in.
## Texture layer ids are the same six as the countryside (world/terrain_shape.gd).

const VillageCourse = preload("res://sim/village_course.gd")
const VillagePlan = preload("res://world/village/village_plan.gd")
const Course = preload("res://sim/course.gd")
const Route = preload("res://sim/route.gd")

enum Layer { GRASS, GRASS_DIRT, DIRT, GRAVEL, MUD, ROCK, SNOW }
const LAYER_NAMES := ["grass", "grass_dirt", "dirt", "gravel", "mud", "rock", "snow"]
const SNOW_LINE := 78.0
const ROCK_LINE := 40.0

const MAP_RECT := Rect2(-512, -512, 1024, 1024)  # 4 x 4 Terrain3D regions of 256 m
const UNDER_ROAD := 0.2
const SHOULDER := 0.8
const FALLOFF := 7.0
const CORRIDOR_REACH := 24.0
const POND_LEVEL := 0.12
const POND_FLOOR := -1.3
const BROOK_LEVEL_DROP := 0.55     # water surface above the brook bed
const VILLAGE_REACH := 70.0        # beyond this many metres from a road the pastures start rising
const BASE_CELL := 8.0             # coarse grid for the village base height

var course: VillageCourse
var plan: VillagePlan
var rect := MAP_RECT
var spacing := 1.0
var w := 0
var h := 0
var heights := PackedFloat32Array()
var road_edge := PackedFloat32Array()   # signed distance to the nearest road edge (<0 on a road), within reach
var road_y := PackedFloat32Array()
var structure := PackedByteArray()      # 1 where the nearest road is a deck (bridge, causeway)
var base_id := PackedByteArray()
var overlay_id := PackedByteArray()
var blend := PackedFloat32Array()
var noise := FastNoiseLite.new()
var patch := FastNoiseLite.new()
var rock := FastNoiseLite.new()
var _base := PackedFloat32Array()       # coarse village base heights
var _bw := 0
var _bh := 0
var _road_pts: Array = []               # [Vector2, y] every 4 m, for the base height
var _near_rect := Rect2()               # village box where the local features live
var course_dist := PackedFloat32Array() # metres to the nearest road edge, whole map (chamfer)
var _centre := Vector2.ZERO


func _init(p_course: VillageCourse, p_plan: VillagePlan, p_rect := MAP_RECT, p_spacing := 1.0) -> void:
	course = p_course
	plan = p_plan
	rect = p_rect
	spacing = p_spacing
	w = int(rect.size.x / spacing)
	h = int(rect.size.y / spacing)
	noise.seed = 31
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	patch.seed = 23
	patch.frequency = 0.025
	patch.fractal_octaves = 2
	rock.seed = 77
	rock.frequency = 0.0045
	rock.fractal_octaves = 5


func build() -> void:
	var n := w * h
	heights.resize(n)
	road_edge.resize(n)
	road_y.resize(n)
	structure.resize(n)
	base_id.resize(n)
	overlay_id.resize(n)
	blend.resize(n)
	road_edge.fill(INF)
	structure.fill(0)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for id in course.ordered_ids:
		var r: Route = course.segments[id]["route"]
		var s := 0.0
		while s <= r.length:
			var p := r.pos_at(s)
			_road_pts.append([Vector2(p.x, p.z), p.y])
			lo = lo.min(Vector2(p.x, p.z))
			hi = hi.max(Vector2(p.x, p.z))
			s += 4.0
	_near_rect = Rect2(lo, hi - lo).grow(VILLAGE_REACH)
	_centre = _near_rect.get_center()
	_build_base()
	_stamp_roads()
	_course_distance()
	for j in h:
		for i in w:
			var k := j * w + i
			heights[k] = _with_road(k, natural_at_cell(i, j))
	for j in h:
		for i in w:
			_paint(i, j)


func cell_pos(i: int, j: int) -> Vector2:
	return Vector2(rect.position.x + i * spacing, rect.position.y + j * spacing)


## Bilinear height at world (x, z).
func height_at(x: float, z: float) -> float:
	var fx := clampf((x - rect.position.x) / spacing, 0.0, w - 1.001)
	var fz := clampf((z - rect.position.y) / spacing, 0.0, h - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	var a := lerpf(heights[j * w + i], heights[j * w + i + 1], tx)
	var b := lerpf(heights[(j + 1) * w + i], heights[(j + 1) * w + i + 1], tx)
	return lerpf(a, b, tz)


func course_dist_at(p: Vector2) -> float:
	var i := clampi(int(round((p.x - rect.position.x) / spacing)), 0, w - 1)
	var j := clampi(int(round((p.y - rect.position.y) / spacing)), 0, h - 1)
	return course_dist[j * w + i]


func road_edge_at(x: float, z: float) -> float:
	var i := clampi(int(round((x - rect.position.x) / spacing)), 0, w - 1)
	var j := clampi(int(round((z - rect.position.y) / spacing)), 0, h - 1)
	return road_edge[j * w + i]


# ---------------------------------------------------------------- village base

## Inverse-distance blend of the road heights on a coarse grid: the ground between the roads
## follows them smoothly instead of terracing to the nearest one.
func _build_base() -> void:
	_bw = int(ceil(_near_rect.size.x / BASE_CELL)) + 2
	_bh = int(ceil(_near_rect.size.y / BASE_CELL)) + 2
	_base.resize(_bw * _bh)
	for j in _bh:
		for i in _bw:
			var p := _near_rect.position + Vector2(i, j) * BASE_CELL
			var ws := 0.0
			var acc := 0.0
			for q in _road_pts:
				var d2: float = maxf(4.0, p.distance_squared_to(q[0]))
				var wt := 1.0 / (d2 * d2)
				ws += wt
				acc += wt * float(q[1])
			_base[j * _bw + i] = acc / ws


func _base_at(p: Vector2) -> float:
	var f := (p - _near_rect.position) / BASE_CELL
	f.x = clampf(f.x, 0.0, _bw - 1.001)
	f.y = clampf(f.y, 0.0, _bh - 1.001)
	var i := int(f.x)
	var j := int(f.y)
	var a := lerpf(_base[j * _bw + i], _base[j * _bw + i + 1], f.x - i)
	var b := lerpf(_base[(j + 1) * _bw + i], _base[(j + 1) * _bw + i + 1], f.x - i)
	return lerpf(a, b, f.y - j)


# ---------------------------------------------------------------- roads

## Ground target under a road: NAN where the road is a deck (the ground drops away).
func corridor_target(seg: Dictionary, s: float) -> float:
	var id: String = seg["id"]
	var r: Route = seg["route"]
	if id == "pond_bridge":
		var mid := plan.bridge_s
		if absf(s - mid) < VillagePlan.BRIDGE_HALF_LENGTH:
			return NAN
	# Causeway: a deck wherever it is raised clear of the meadow.
	if id == "cross_exposed" and r.pos_at(s).y - r.pos_at(0.0).y > 0.5:
		return NAN
	# The kicker is a wooden structure on the ground: never raise the terrain under it, only
	# sink it for the landing pit.
	var ramp: Dictionary = seg["ramp"]
	if not ramp.is_empty() and s >= float(ramp["kick_a"]) + 2.0 and s <= float(ramp["lip_s"]):
		# Under the back of the kicker the ground already drops to the pit floor, so nothing
		# stands proud of the pit right behind the lip.
		return r.pos_at(s).y - float(ramp["pit_depth"])
	return r.pos_at(s).y + minf(0.0, Course.surface_offset(seg, s))


func _stamp_roads() -> void:
	for id in course.ordered_ids:
		var seg: Dictionary = course.segments[id]
		var r: Route = seg["route"]
		var hw: float = seg["half_width"]
		var reach := hw + CORRIDOR_REACH
		var s := 0.0
		while s <= r.length:
			var c := r.pos_at(s)
			var target := corridor_target(seg, s)
			var i0 := maxi(0, int((c.x - reach - rect.position.x) / spacing))
			var i1 := mini(w - 1, int((c.x + reach - rect.position.x) / spacing) + 1)
			var j0 := maxi(0, int((c.z - reach - rect.position.y) / spacing))
			var j1 := mini(h - 1, int((c.z + reach - rect.position.y) / spacing) + 1)
			for j in range(j0, j1 + 1):
				for i in range(i0, i1 + 1):
					var p := cell_pos(i, j)
					var e := p.distance_to(Vector2(c.x, c.z)) - hw
					var k := j * w + i
					if e < road_edge[k]:
						road_edge[k] = e
						road_y[k] = c.y if is_nan(target) else target
						structure[k] = 1 if is_nan(target) else 0
			s += 0.5
	# The roundabout ring and side streets: flat at the ring's road height.
	var ry := roundabout_y()
	var pts: Array = []
	for i in 144:
		var t := TAU * i / 144.0
		pts.append([plan.fountain + Vector2(cos(t), sin(t)) * float(course.roundabout["radius"]), plan.ring_hw])
	for arm in plan.arms:
		var a: Vector2 = arm[0]
		var b: Vector2 = arm[1]
		var n := int(a.distance_to(b) * 2.0)
		for i in n + 1:
			pts.append([a.lerp(b, float(i) / n), VillagePlan.ARM_HALF_WIDTH])
	for q in pts:
		_stamp_point(q[0], ry, q[1])


## Road height on the roundabout (the course is flat there).
func roundabout_y() -> float:
	var seg: Dictionary = course.segments["bends"]
	return course.surface_y(seg, float(course.roundabout["s0"]))


func _stamp_point(c: Vector2, y: float, hw: float) -> void:
	var reach := hw + CORRIDOR_REACH
	var i0 := maxi(0, int((c.x - reach - rect.position.x) / spacing))
	var i1 := mini(w - 1, int((c.x + reach - rect.position.x) / spacing) + 1)
	var j0 := maxi(0, int((c.y - reach - rect.position.y) / spacing))
	var j1 := mini(h - 1, int((c.y + reach - rect.position.y) / spacing) + 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var e := cell_pos(i, j).distance_to(c) - hw
			var k := j * w + i
			if e < road_edge[k]:
				road_edge[k] = e
				road_y[k] = y
				structure[k] = 0


func _with_road(k: int, nat: float) -> float:
	var e := road_edge[k]
	if e >= SHOULDER + FALLOFF * 2.5:
		return nat
	var ry := road_y[k]
	if structure[k] == 1:
		return minf(nat, ry - 0.9)
	var flat := ry - UNDER_ROAD
	var reach := FALLOFF + 0.8 * absf(nat - flat)
	return lerpf(flat, nat, smoothstep(SHOULDER, SHOULDER + reach, e))


# ---------------------------------------------------------------- natural ground

## Two-pass chamfer distance from every road cell, so every cell knows how far the village is.
func _course_distance() -> void:
	var n := w * h
	course_dist.resize(n)
	for k in n:
		course_dist[k] = 0.0 if road_edge[k] <= 0.0 else INF
	var d1 := spacing
	var d2 := spacing * 1.4142
	for j in h:
		for i in w:
			var k := j * w + i
			var best := course_dist[k]
			if i > 0:
				best = minf(best, course_dist[k - 1] + d1)
			if j > 0:
				best = minf(best, course_dist[k - w] + d1)
				if i > 0:
					best = minf(best, course_dist[k - w - 1] + d2)
				if i < w - 1:
					best = minf(best, course_dist[k - w + 1] + d2)
			course_dist[k] = best
	for j in range(h - 1, -1, -1):
		for i in range(w - 1, -1, -1):
			var k := j * w + i
			var best := course_dist[k]
			if i < w - 1:
				best = minf(best, course_dist[k + 1] + d1)
			if j < h - 1:
				best = minf(best, course_dist[k + w] + d1)
				if i < w - 1:
					best = minf(best, course_dist[k + w + 1] + d2)
				if i > 0:
					best = minf(best, course_dist[k + w - 1] + d2)
			course_dist[k] = best


func natural_at_cell(i: int, j: int) -> float:
	return natural_at(cell_pos(i, j), course_dist[j * w + i])


## Mountain ring round the village: ridged noise, tallest to the south (the view over the
## meadow from the causeway), starting MOUNTAIN_START metres from the village centre.
const MOUNTAIN_START := 190.0
const MOUNTAIN_FULL := 330.0


func mountain_at(p: Vector2) -> float:
	var d := p.distance_to(_centre)
	if d < MOUNTAIN_START:
		return 0.0
	var dir := (p - _centre) / d
	var south := maxf(0.0, -dir.y)                 # 1 straight south
	var amp := 90.0 + 120.0 * south * south
	var r1 := 1.0 - absf(rock.get_noise_2d(p.x, p.y))
	var r2 := 1.0 - absf(rock.get_noise_2d(p.x * 2.1 + 90.0, p.y * 2.1))
	var ridged := r1 * r1 * 0.75 + r2 * r2 * 0.25
	return smoothstep(MOUNTAIN_START, MOUNTAIN_FULL, d) * amp * (0.35 + 0.65 * ridged)


func natural_at(p: Vector2, dist: float) -> float:
	var near := _near_rect.has_point(p)
	var base := _base_at(p)
	var y := base + noise.get_noise_2d(p.x, p.y) * 0.6
	# Pastures rise gently away from the village, then the mountains.
	var out := maxf(0.0, dist - VILLAGE_REACH * 0.5)
	y += minf(out, 140.0) * 0.08 + noise.get_noise_2d(p.x * 0.3 + 500.0, p.y * 0.3) * 5.0 * smoothstep(0.0, 120.0, out)
	y += mountain_at(p)
	if not near:
		return y
	# Church hill: a knoll under the church.
	for b in plan.buildings:
		if b["kind"] == "church":
			var cd: float = p.distance_to(b["pos"]) / 26.0
			if cd < 1.0:
				y += 1.2 * (0.5 + 0.5 * cos(PI * cd))
	# Hay meadow dip where the jump lands.
	var hm := plan.hay_meadow
	var q := (p - Vector2(hm.x, hm.y)).rotated(plan.hay_yaw)
	var qd := Vector2(q.y / hm.z, q.x / hm.w).length()
	if qd < 1.4:
		y = lerpf(minf(y, plan.hay_floor), y, smoothstep(0.7, 1.4, qd))
	# Meadow hollow beside the causeway.
	var mh := plan.meadow_hollow
	var md := p.distance_to(Vector2(mh.x, mh.y)) / mh.z
	if md < 1.0:
		y -= mh.w * (0.5 + 0.5 * cos(PI * md))
	# Alpbach channel across the detour's ford.
	var ad := VillagePlan.polyline_dist(p, plan.alp_stream)
	var aw := VillagePlan.ALP_HALF_WIDTH
	if ad < aw + 6.0:
		var abed := minf(y - 0.9, plan.alp_level - 0.6) if ad > aw else y - 0.9
		y = lerpf(abed, y, smoothstep(aw * 0.5, aw + 6.0, ad))
	# Brook channel down to the pond.
	var sd := VillagePlan.polyline_dist(p, plan.brook)
	var sw := VillagePlan.BROOK_HALF_WIDTH
	if sd < sw + 6.0:
		var bed := minf(y - 1.1, brook_bed_at(p))
		y = lerpf(bed, y, smoothstep(sw * 0.5, sw + 6.0, sd))
	# Pond basin and banks.
	if plan.pond_box.grow(10.0).has_point(p):
		var shore := plan.pond_shore_dist(p)
		if Geometry2D.is_point_in_polygon(p, plan.pond):
			y = lerpf(POND_LEVEL - 0.35, POND_FLOOR, smoothstep(0.0, 6.0, shore))
		elif shore < 6.0:
			y = lerpf(POND_LEVEL + 0.15, y, smoothstep(0.0, 6.0, shore))
	return y


## Brook bed: falls steadily from the hills to the pond, 1 m below the bank near the bridge.
func brook_bed_at(p: Vector2) -> float:
	var t := plan.brook_t(p)   # 0 at the source, 1 at the pond
	return lerpf(9.0, POND_LEVEL - BROOK_LEVEL_DROP, smoothstep(0.0, 1.0, t))


static func _box_dist(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return Vector2(dx, dy).length()


# ---------------------------------------------------------------- texture layers

func slope_at(i: int, j: int) -> float:
	var i0 := maxi(0, i - 1)
	var i1 := mini(w - 1, i + 1)
	var j0 := maxi(0, j - 1)
	var j1 := mini(h - 1, j + 1)
	var dx := (heights[j * w + i1] - heights[j * w + i0]) / ((i1 - i0) * spacing)
	var dz := (heights[j1 * w + i] - heights[j0 * w + i]) / ((j1 - j0) * spacing)
	return Vector2(dx, dz).length()


func _paint(i: int, j: int) -> void:
	var k := j * w + i
	var p := cell_pos(i, j)
	var b := Layer.GRASS
	var o := Layer.GRASS_DIRT
	var bl := smoothstep(0.2, 0.75, patch.get_noise_2d(p.x, p.y)) * 0.35
	var y := heights[k]
	var slope := slope_at(i, j)
	# Mountains: alpine meadow up to the rock line, rock above and on steep ground, snow on
	# the high, gentler slopes.
	var line := SNOW_LINE + patch.get_noise_2d(p.x * 0.3, p.y * 0.3) * 25.0
	if y > line and slope < 1.4:
		b = Layer.SNOW
		o = Layer.ROCK
		bl = clampf(slope * 0.6, 0.0, 0.7)
	elif y > ROCK_LINE + patch.get_noise_2d(p.x, p.y) * 12.0 or slope > 0.8:
		b = Layer.ROCK
		o = Layer.GRAVEL
		bl = 0.25
	elif y > ROCK_LINE * 0.6:
		o = Layer.ROCK
		bl = smoothstep(ROCK_LINE * 0.6, ROCK_LINE, y) * 0.7
	var e := road_edge[k]
	if e < 0.6 and structure[k] == 0:
		b = Layer.GRAVEL
		o = Layer.GRASS_DIRT
		bl = smoothstep(0.0, 0.6, e) * 0.7
	elif e < 3.0:
		o = Layer.GRASS_DIRT
		bl = maxf(bl, 1.0 - smoothstep(0.6, 3.0, e))
	if _near_rect.has_point(p):
		if plan.pond_box.grow(4.0).has_point(p):
			var shore := plan.pond_shore_dist(p)
			if Geometry2D.is_point_in_polygon(p, plan.pond):
				b = Layer.MUD if shore > 2.5 else Layer.DIRT
				o = Layer.GRAVEL
				bl = 0.0
			elif shore < 2.5:
				b = Layer.DIRT
				o = Layer.GRASS_DIRT
				bl = smoothstep(0.8, 2.5, shore)
		var sd := VillagePlan.polyline_dist(p, plan.brook)
		if sd < VillagePlan.BROOK_HALF_WIDTH + 2.5:
			b = Layer.GRAVEL if sd < VillagePlan.BROOK_HALF_WIDTH else Layer.DIRT
			o = Layer.ROCK
			bl = 0.35
		var hm := plan.hay_meadow
		var q := (p - Vector2(hm.x, hm.y)).rotated(plan.hay_yaw)
		var qd := Vector2(q.y / hm.z, q.x / hm.w).length()
		if qd < 1.0 and e > 0.6:
			b = Layer.GRASS_DIRT
			o = Layer.DIRT
			bl = 0.3
	base_id[k] = b
	overlay_id[k] = o
	blend[k] = bl

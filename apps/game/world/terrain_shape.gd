extends RefCounted
## Terrain heights and texture layers generated from the course + landscape features. Pure data
## (no nodes): tools/bake_world.gd imports the result into Terrain3D, and tools/world_check.gd
## uses the same road-corridor field to verify scatter and props.
##
## Heights: rolling hills + gentle noise, the planned features (pond basin, stream channel, jump
## dip, knoll, valley, flat plazas), then every road corridor levelled just under the route
## height with a soft falloff. Corridors are left natural where the road is a structure (the
## stone bridge over the stream, the causeway over the valley), and the jump's pit is levelled
## to the dip floor so a short landing visibly ends in the mud.
##
## Texture layer ids match the Terrain3D asset list built by bake_world.gd.

const Course = preload("res://sim/course.gd")
const Route = preload("res://sim/route.gd")
const Landscape = preload("res://world/landscape.gd")

enum Layer { GRASS, GRASS_DIRT, DIRT, GRAVEL, MUD, ROCK }
const LAYER_NAMES := ["grass", "grass_dirt", "dirt", "gravel", "mud", "rock"]

const UNDER_ROAD := 0.06          # terrain sits this far below the road surface
const SHOULDER := 0.8             # flat gravel shoulder beyond the road edge (metres)
const FALLOFF := 7.0              # blend from the shoulder back to natural ground
const CORRIDOR_REACH := 22.0      # how far from a road edge the corridor field is stamped
const SCATTER_CLEAR := 2.0        # nothing scattered within this many metres of a road edge

var course: Course
var land: Landscape
var rect: Rect2
var spacing := 1.0
var w := 0
var h := 0
var heights := PackedFloat32Array()
var natural := PackedFloat32Array()
var road_edge := PackedFloat32Array()   # signed distance to nearest road edge (<0 = on the road)
var road_y := PackedFloat32Array()      # road surface height of the nearest road
var course_dist := PackedFloat32Array() # metres to the nearest road edge, whole map (chamfer)
var course_y := PackedFloat32Array()    # road height at that nearest road
var structure := PackedByteArray()      # 1 where the nearest road is a bridge/causeway deck
var base_id := PackedByteArray()
var overlay_id := PackedByteArray()
var blend := PackedFloat32Array()
var noise := FastNoiseLite.new()
var patch := FastNoiseLite.new()


func _init(p_course: Course, p_land: Landscape, p_rect := Landscape.MAP_RECT, p_spacing := 1.0) -> void:
	course = p_course
	land = p_land
	rect = p_rect
	spacing = p_spacing
	w = int(rect.size.x / spacing)
	h = int(rect.size.y / spacing)
	noise.seed = 11
	noise.frequency = 0.018
	noise.fractal_octaves = 3
	patch.seed = 23
	patch.frequency = 0.025
	patch.fractal_octaves = 2


func build() -> void:
	var n := w * h
	heights.resize(n)
	natural.resize(n)
	road_edge.resize(n)
	road_y.resize(n)
	structure.resize(n)
	base_id.resize(n)
	overlay_id.resize(n)
	blend.resize(n)
	road_edge.fill(INF)
	structure.fill(0)
	_stamp_roads()
	_course_distance()
	for j in h:
		for i in w:
			var k := j * w + i
			var p := cell_pos(i, j)
			var nat := _natural(p, course_dist[k], course_y[k])
			natural[k] = nat
			heights[k] = _with_road(k, nat)
	for j in h:
		for i in w:
			_paint(i, j)


## Two-pass chamfer distance transform seeded with every road cell, carrying the road height
## along, so every cell knows how far the course is and how high the road is there.
func _course_distance() -> void:
	var n := w * h
	course_dist.resize(n)
	course_y.resize(n)
	for k in n:
		if road_edge[k] <= 0.0:
			course_dist[k] = 0.0
			course_y[k] = road_y[k]
		else:
			course_dist[k] = INF
			course_y[k] = 0.0
	var d1 := spacing
	var d2 := spacing * 1.4142
	for j in h:
		for i in w:
			var k := j * w + i
			for o in [[-1, 0, d1], [0, -1, d1], [-1, -1, d2], [1, -1, d2]]:
				var ii: int = i + o[0]
				var jj: int = j + o[1]
				if ii < 0 or jj < 0 or ii >= w:
					continue
				var kk := jj * w + ii
				var cand: float = course_dist[kk] + o[2]
				if cand < course_dist[k]:
					course_dist[k] = cand
					course_y[k] = course_y[kk]
	for j in range(h - 1, -1, -1):
		for i in range(w - 1, -1, -1):
			var k := j * w + i
			for o in [[1, 0, d1], [0, 1, d1], [1, 1, d2], [-1, 1, d2]]:
				var ii: int = i + o[0]
				var jj: int = j + o[1]
				if ii < 0 or jj >= h or ii >= w:
					continue
				var kk := jj * w + ii
				var cand: float = course_dist[kk] + o[2]
				if cand < course_dist[k]:
					course_dist[k] = cand
					course_y[k] = course_y[kk]


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


## Bilinear natural (pre-road) ground height at world (x, z).
func natural_at(x: float, z: float) -> float:
	var fx := clampf((x - rect.position.x) / spacing, 0.0, w - 1.001)
	var fz := clampf((z - rect.position.y) / spacing, 0.0, h - 1.001)
	var i := int(fx)
	var j := int(fz)
	var a := lerpf(natural[j * w + i], natural[j * w + i + 1], fx - i)
	var b := lerpf(natural[(j + 1) * w + i], natural[(j + 1) * w + i + 1], fx - i)
	return lerpf(a, b, fz - j)


## Signed distance from (x, z) to the nearest road edge (nearest cell).
func road_edge_at(x: float, z: float) -> float:
	var i := clampi(int(round((x - rect.position.x) / spacing)), 0, w - 1)
	var j := clampi(int(round((z - rect.position.y) / spacing)), 0, h - 1)
	return road_edge[j * w + i]


## True where scatter (trees, rocks, flowers, grass) must not go: roads + shoulders, water.
func blocked(x: float, z: float) -> bool:
	var p := Vector2(x, z)
	return road_edge_at(x, z) < SCATTER_CLEAR or land.in_pond(p, 1.0) \
		or land.stream_dist(p) < Landscape.STREAM_HALF_WIDTH + 1.0 or land.in_dip(p)


# ---------------------------------------------------------------- roads

## Road surface height the terrain should follow at route distance s, or NAN where the road is
## a structure (deck) and the ground underneath stays natural.
func corridor_target(seg: Dictionary, s: float) -> float:
	var r: Route = seg["route"]
	var p := r.pos_at(s)
	var xz := Vector2(p.x, p.z)
	match String(seg["id"]):
		"pond_bridge":
			if land.stream_dist(xz) < Landscape.STREAM_HALF_WIDTH + 3.0:
				return NAN
		"cross_exposed":
			var vi: Array = land.valley_info(xz)
			if float(vi[0]) < float(vi[1]) + 1.0:
				return NAN
		"ramp_jump":
			var rp: Dictionary = seg["ramp"]
			if s > float(rp["lip_s"]) and s < float(rp["land_s"]):
				return p.y - float(rp["pit_depth"])
	return p.y


func _stamp_roads() -> void:
	# Where roads overlap or meet (the shared stub of a Y-split), the ground within 1 m of their
	# edges follows the lowest of them, whatever the stamping order, so it never pokes through.
	var on_road_y := PackedFloat32Array()
	on_road_y.resize(w * h)
	on_road_y.fill(INF)
	var on_road_structure := PackedByteArray()
	on_road_structure.resize(w * h)
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
					var y := c.y if is_nan(target) else target
					if e <= 1.0 and y < on_road_y[k]:
						on_road_y[k] = y
						on_road_structure[k] = 1 if is_nan(target) else 0
					if e < road_edge[k]:
						road_edge[k] = e
						road_y[k] = y
						structure[k] = 1 if is_nan(target) else 0
			s += 0.5
	for k in w * h:
		if on_road_y[k] < INF:
			road_y[k] = on_road_y[k]
			structure[k] = on_road_structure[k]


func _with_road(k: int, nat: float) -> float:
	var e := road_edge[k]
	if e >= SHOULDER + FALLOFF * 2.0:
		return nat
	var ry := road_y[k]
	if structure[k] == 1:
		# Under a deck: keep the natural ground, but never closer than 0.6 m to the deck.
		return minf(nat, ry - 0.6)
	var flat := ry - UNDER_ROAD
	# Longer falloff for deeper cuts and fills so banks stay gentle.
	var reach := FALLOFF + 0.8 * absf(nat - flat)
	var t := smoothstep(SHOULDER, SHOULDER + reach, e)
	return lerpf(flat, nat, t)


# ---------------------------------------------------------------- natural ground

## Meadow near the course, rounded hills only far away: within NEAR metres of any road the
## ground stays within NEAR_RANGE of the road height with gentle swells; the hill list and the
## edge rise fade in only beyond FAR_START metres.
const NEAR := 60.0
const NEAR_RANGE := 3.0
const FAR_START := 90.0


func _natural(p: Vector2, dist: float, ry: float) -> float:
	var swell := noise.get_noise_2d(p.x, p.y) * 2.2 + noise.get_noise_2d(p.x * 0.4 + 300.0, p.y * 0.4) * 1.5
	var far := smoothstep(FAR_START, FAR_START + 80.0, dist)
	var hills := 0.0
	for hl in Landscape.HILLS:
		var d := p.distance_to(Vector2(hl.x, hl.y)) / hl.z
		if d < 1.0:
			hills += hl.w * (0.5 + 0.5 * cos(PI * d))
	var rise := maxf(0.0, dist - FAR_START) * 0.06
	var y := ry + swell + far * (hills + rise)
	# Keep the meadow near the course within +-NEAR_RANGE of the road, softly.
	var near := 1.0 - smoothstep(NEAR * 0.6, NEAR + 30.0, dist)
	var lim := lerpf(40.0, NEAR_RANGE, near)
	y = ry + lim * tanh((y - ry) / lim)
	# Knoll between the ramp branches.
	var kd := p.distance_to(land.knoll_center) / land.knoll_radius
	if kd < 1.0:
		y += Landscape.KNOLL_HEIGHT * (0.5 + 0.5 * cos(PI * kd))
	# Flat plazas.
	for pr: Rect2 in [Landscape.FLAT_START, land.flat_finish]:
		var out := _rect_dist(pr, p)
		y = lerpf(0.0, y, smoothstep(0.0, 10.0, out))
	# Jump dip: an oval of mud at the pit depth with soft rims.
	var q := ((p - land.dip_center) / land.dip_radii).length()
	if q < Landscape.DIP_RIM:
		y = lerpf(land.dip_floor, y, smoothstep(0.75, Landscape.DIP_RIM, q))
	# Valley.
	var vi: Array = land.valley_info(p)
	var vd: float = vi[0]
	var vhw: float = vi[1]
	if vd < vhw * 1.25:
		y = lerpf(float(vi[2]), y, smoothstep(0.2, 1.25, vd / vhw))
	# Stream channel: a constant-depth cut that follows the ground down to the pond.
	var sd := land.stream_dist(p)
	var sw := Landscape.STREAM_HALF_WIDTH
	if sd < sw + 5.0:
		var bed := stream_bed_at(p, y)
		y = lerpf(bed, y, smoothstep(sw * 0.5, sw + 5.0, sd))
	# Pond basin and banks.
	var shore := land.pond_shore_dist(p)
	if land.in_pond(p):
		y = lerpf(Landscape.POND_LEVEL - 0.35, Landscape.POND_FLOOR, smoothstep(0.0, 9.0, shore))
	elif shore < 7.0:
		y = lerpf(Landscape.POND_LEVEL + 0.12, y, smoothstep(0.0, 7.0, shore))
	return y


## Stream bed height under p: ~1.1 m below the surrounding ground, never above the pond-side
## bed level near the bridge so the water reads as one level there.
func stream_bed_at(p: Vector2, ground: float) -> float:
	return minf(ground - 1.1, Landscape.STREAM_BED + maxf(0.0, ground - 0.9) * 0.85)


static func _rect_dist(r: Rect2, p: Vector2) -> float:
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
	# Natural patchiness of worn grass.
	var bl := smoothstep(0.15, 0.7, patch.get_noise_2d(p.x, p.y)) * 0.45
	var e := road_edge[k]
	var slope := slope_at(i, j)
	if e < 0.6 and structure[k] == 0:
		b = Layer.GRAVEL
		o = Layer.GRASS_DIRT
		bl = smoothstep(0.0, 0.6, e) * 0.7
	elif e < 3.0:
		o = Layer.GRASS_DIRT
		bl = maxf(bl, 1.0 - smoothstep(0.6, 3.0, e))
	var pp := Vector2(p.x, p.y)
	var shore := land.pond_shore_dist(pp)
	if land.in_pond(pp):
		b = Layer.MUD if shore > 3.0 else Layer.DIRT
		o = Layer.GRAVEL
		bl = 0.0
	elif shore < 3.0:
		b = Layer.DIRT
		o = Layer.GRASS_DIRT
		bl = smoothstep(1.0, 3.0, shore)
	var sd := land.stream_dist(pp)
	if sd < Landscape.STREAM_HALF_WIDTH + 2.5:
		b = Layer.GRAVEL if sd < Landscape.STREAM_HALF_WIDTH else Layer.DIRT
		o = Layer.ROCK
		bl = 0.35 if sd < Landscape.STREAM_HALF_WIDTH else smoothstep(Landscape.STREAM_HALF_WIDTH, Landscape.STREAM_HALF_WIDTH + 2.5, sd) * 0.5
	var q := ((pp - land.dip_center) / land.dip_radii).length()
	if q < 1.1:
		b = Layer.MUD
		o = Layer.GRASS_DIRT
		bl = smoothstep(0.8, 1.1, q)
	base_id[k] = b
	overlay_id[k] = o
	blend[k] = bl

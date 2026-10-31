extends RefCounted
## The Swiss village around the loop in sim/village_course.gd: where the water, meadows, square
## and every building sit. Pure data (no nodes), anchored to the course, so moving a route moves
## its houses with it. tools/village_map.gd draws and checks it; the village bake places the
## real models from it. Coordinates are world metres (x east, z north, y up).
##
## Modelled on Bernese Oberland and Emmental villages: dark-timber chalets with deep eaves and
## flower boxes along the main street, a white church with a pointed spire on the hill, a stone
## trough fountain and a lime tree on the square, a covered wooden bridge over the brook, a mill,
## hay barns and an orchard. The mountains round it are terrain (village_terrain.gd).

const VillageCourse = preload("res://sim/village_course.gd")
const Route = preload("res://sim/route.gd")

const CLEAR := 1.5                 # metres between a building footprint and a road edge
const BUILDING_GAP := 1.5          # metres between two footprints
const BROOK_HALF_WIDTH := 1.8
const MAX_SETBACK := 14.0          # a landmark that needs more extra setback than this is an error
const BRIDGE_HALF_LENGTH := 7.0    # covered bridge deck either side of the hump

## Rows of buildings along a road: [segment, side (+1 left / -1 right of travel), s from, s to,
## kind, extra setback]. Footprints face the road; each house goes at the first spot from its
## predecessor where it clears every road, the water and the other houses.
const ROWS := [
	["hills1", 1, 4.0, 40.0, "chalet", 0.0],
	["hills1", -1, 2.0, 22.0, "chalet", 0.0],
	["ramp_around", 1, 4.0, 22.0, "chalet", 0.0],
	["hills2", -1, 2.0, 30.0, "chalet", 0.0],
	["hills2", 1, 0.0, 26.0, "barn", 2.0],
	["cross_sheltered", -1, 4.0, 70.0, "arcade", 0.0],
	["cross_sheltered", 1, 4.0, 70.0, "arcade", 0.0],
	["bends", -1, 4.0, 40.0, "chalet", 0.0],
	["bends", 1, 2.0, 40.0, "chalet", 0.0],
	["start", -1, 0.0, 14.0, "chalet", 0.0],
	# Second row inside the loop, behind the main street and the church lane.
	["hills1", -1, 2.0, 30.0, "chalet", 11.0],
	["hills2", -1, 0.0, 30.0, "chalet", 11.0],
]
## Footprint sizes (width along the road, depth back from it) and height to the ridge.
const KINDS := {
	"inn": [14.0, 11.0, 12.0],
	"chalet": [9.0, 8.0, 9.0],
	"arcade": [8.0, 7.0, 10.0],
	"bakery": [9.0, 8.0, 8.0],
	"church": [10.0, 18.0, 26.0],
	"mill": [9.0, 8.0, 8.0],
	"barn": [12.0, 9.0, 8.0],
	"school": [16.0, 10.0, 10.0],
}

var course: VillageCourse
## {kind, pos: Vector2, yaw (radians, the front faces this way), size: Vector2 (width, depth), height, label}
var buildings: Array = []
var _polys: Array = []
var pond: PackedVector2Array
var brook: Array[Vector2] = []
var bridge_mid := Vector3.ZERO
var bridge_s := 0.0                 # s of the hump on pond_bridge
var pond_box := Rect2()
var hay_floor := 0.0                # ground height in the hay meadow where the jump lands
var fountain := Vector2.ZERO
var lime_tree := Vector2.ZERO
var square: PackedVector2Array      # paved area of the Dorfplatz
var meadow_hollow := Vector4.ZERO   # x, z, radius, depth south of the causeway
var hay_meadow := Vector4.ZERO      # x, z, radius along, radius across, between the ramp branches
var hay_yaw := 0.0
var orchard: Array[Vector2] = []    # fruit tree spots in the middle of the loop
var kicker := {}                    # {from: Vector3, to: Vector3} wooden ski-jump ramp on ramp_jump
var errors: PackedStringArray = []
var _road: Array = []               # [Vector2, half width, id] every metre of every road


func _init(p_course: VillageCourse) -> void:
	course = p_course
	for id in course.ordered_ids:
		var r := route(id)
		var s := 0.0
		while s <= r.length:
			var p := r.pos_at(s)
			_road.append([Vector2(p.x, p.z), hw(id), id])
			s += 1.0
	_water()
	_square()
	_landmarks()
	for row in ROWS:
		_row(row[0], int(row[1]), float(row[2]), float(row[3]), row[4], float(row[5]))
	_infill()
	_orchard()


func route(id: String) -> Route:
	return course.segments[id]["route"]


func hw(id: String) -> float:
	return float(course.segments[id]["half_width"])


## World xz of (s, d) on a segment (+d is left of travel).
func at(id: String, s: float, d: float) -> Vector2:
	var p := route(id).world_at(s, d)
	return Vector2(p.x, p.z)


## Signed distance from p to the nearest road edge (negative on a road) and that road's id.
func road_edge(p: Vector2) -> Array:
	var best := INF
	var best_id := ""
	for q in _road:
		var dd: float = p.distance_to(q[0]) - float(q[1])
		if dd < best:
			best = dd
			best_id = q[2]
	return [best, best_id]


func _water() -> void:
	# Duck pond round the ford's water range, bulging away from the bridge lane.
	var ford := route("pond_water")
	var wr: Array = course.segments["pond_water"]["water"][0]
	var a := float(wr[0]) - 2.0
	var b := float(wr[1]) + 2.0
	var mid := (a + b) * 0.5
	var half := (b - a) * 0.5
	var n := 32
	for i in n:
		var t := TAU * i / n
		var side := sin(t)
		# +d is towards the bridge lane: only a narrow strip of water that way.
		var reach := 6.0 if side > 0.0 else 16.0
		var d := side * reach * sqrt(maxf(0.0, 1.0 - pow(absf(cos(t)), 6.0)))
		pond.append(at("pond_water", clampf(mid + cos(t) * half, 0.0, ford.length), d))
	var lo := pond[0]
	var hi := pond[0]
	for q in pond:
		lo = lo.min(q)
		hi = hi.max(q)
	pond_box = Rect2(lo, hi - lo)
	# Brook from the eastern hills, under the covered bridge, into the pond's near shore.
	var br := route("pond_bridge")
	var s := 0.0
	bridge_mid = br.pos_at(0.0)
	while s <= br.length:
		if br.pos_at(s).y > bridge_mid.y:
			bridge_mid = br.pos_at(s)
		s += 0.5
	var bs := _closest_s(br, Vector2(bridge_mid.x, bridge_mid.z))
	bridge_s = bs
	var across := br.normal_at(bs)
	var out := Vector2(across.x, across.z)
	if (Vector2(bridge_mid.x, bridge_mid.z) + out).distance_to(at("pond_water", mid, 0.0)) < Vector2(bridge_mid.x, bridge_mid.z).distance_to(at("pond_water", mid, 0.0)):
		out = -out
	var m := Vector2(bridge_mid.x, bridge_mid.z)
	var up := out.rotated(0.25)
	for k in [110.0, 70.0, 40.0, 16.0]:
		brook.append(m + up * k + out.orthogonal() * sin(k * 0.05) * 6.0)
	brook.append(m)
	brook.append(at("pond_water", mid, 4.0))


func _square() -> void:
	# The fountain sits at the centre of the bends' left-hand arc (the S round the square),
	# the lime tree beside it, and the square is paved round both.
	var r := route("bends")
	var best_k := 0.0
	var best_s := 0.0
	var s := r.length * 0.6
	while s < r.length - 3.0:
		if r.curv_at(s) < best_k:
			best_k = r.curv_at(s)
			best_s = s
		s += 0.5
	var radius := 1.0 / absf(best_k)
	fountain = at("bends", best_s, radius)
	lime_tree = fountain + (at("bends", best_s - 9.0, radius) - fountain).normalized() * 5.0
	var n := 24
	for i in n:
		var t := TAU * i / n
		square.append(fountain + Vector2(cos(t), sin(t)) * (radius - hw("bends") - 0.3))
	# The inn faces the square from the west, across the start line.
	_fit("inn", "start", 3.0, 1, 0.0, "Gasthaus")


func _landmarks() -> void:
	# Church on the hill, outside the around lane's apex, facing it.
	var ar := route("ramp_around")
	_fit("church", "ramp_around", ar.length * 0.5, 1, 0.0, "Kirche")
	# Hay meadow between the jump and the around lane; the jump lands in it.
	var jr := route("ramp_jump")
	var rp: Dictionary = course.segments["ramp_jump"]["ramp"]
	var lip := float(rp["lip_s"])
	var land := float(rp["land_s"])
	var mid := at("ramp_jump", (lip + land) * 0.5, 3.0)
	hay_meadow = Vector4(mid.x, mid.y, (land - lip) * 0.5 + 6.0, 6.0)
	hay_yaw = jr.heading_at(lip)
	hay_floor = jr.pos_at(lip).y - float(rp["pit_depth"])
	kicker = {"from": jr.pos_at(float(rp["kick_a"])), "to": jr.pos_at(lip)}
	_fit("mill", "mill", 3.0, -1, 0.0, "Mühle")
	_fit("school", "hills2", 3.0, -1, 0.0, "Schulhaus")
	_fit("bakery", "bends", 2.0, -1, 0.0, "Bäckerei")
	# Open meadow south of the causeway.
	var cr := route("cross_exposed")
	var outward := at("cross_exposed", cr.length * 0.5, 30.0)
	meadow_hollow = Vector4(outward.x, outward.y, 24.0, 2.0)


## Places one building facing a road at s, pushing it back until it clears everything.
func _fit(kind: String, id: String, s: float, side: int, extra: float, label: String) -> bool:
	var e := extra
	while e <= extra + MAX_SETBACK:
		if _try(kind, id, s, side, e, label):
			return true
		e += 0.5
	errors.append("no room for the %s on %s at s=%.0f" % [kind, id, s])
	return false


func _try(kind: String, id: String, s: float, side: int, extra: float, label: String) -> bool:
	var depth: float = KINDS[kind][1]
	var p := at(id, s, side * (hw(id) + CLEAR + depth * 0.5 + extra))
	var to_road := at(id, s, 0.0) - p
	var b := {"kind": kind, "pos": p, "yaw": atan2(to_road.x, to_road.y),
		"size": Vector2(KINDS[kind][0], depth), "height": KINDS[kind][2], "label": label}
	var poly := footprint(b)
	if not _clear(poly):
		return false
	buildings.append(b)
	_polys.append(poly)
	return true


## A footprint is clear when it keeps CLEAR from every road edge, stays out of the pond, the
## brook and the square, and keeps BUILDING_GAP from every other footprint.
func _clear(poly: PackedVector2Array) -> bool:
	for p in sample_points(poly):
		if float(road_edge(p)[0]) < CLEAR:
			return false
		if Geometry2D.is_point_in_polygon(p, pond) or polyline_dist(p, brook) < BROOK_HALF_WIDTH + 1.5:
			return false
		if not square.is_empty() and Geometry2D.is_point_in_polygon(p, square):
			return false
	var grown := Geometry2D.offset_polygon(poly, BUILDING_GAP * 0.5)[0]
	for o in _polys:
		if not Geometry2D.intersect_polygons(grown, Geometry2D.offset_polygon(o, BUILDING_GAP * 0.5)[0]).is_empty():
			return false
	return true


func _row(id: String, side: int, s0: float, s1: float, kind: String, extra: float) -> void:
	var s := s0
	var end := minf(s1, route(id).length)
	while s <= end:
		if _try(kind, id, s, side, extra, ""):
			s += float(KINDS[kind][0]) + BUILDING_GAP
		else:
			s += 1.0


## The village core: chalets on a loose grid inside the loop, within INFILL_BAND of a road,
## each facing its nearest road. The middle stays an orchard.
const INFILL_BAND := Vector2(9.0, 34.0)


func _infill() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in _road:
		lo = lo.min(q[0])
		hi = hi.max(q[0])
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var z := hi.y
	while z >= lo.y:
		var x := lo.x
		while x <= hi.x:
			var p := Vector2(x, z) + Vector2(rng.randf_range(-2.0, 2.0), rng.randf_range(-2.0, 2.0))
			x += 6.0
			var e := road_edge(p)
			if not _inside_loop(p) or float(e[0]) < INFILL_BAND.x or float(e[0]) > INFILL_BAND.y:
				continue
			var r := route(e[1])
			var s := _closest_s(r, p)
			var q := r.pos_at(s)
			var to_road := Vector2(q.x, q.z) - p
			var yaw := atan2(to_road.x, to_road.y) + rng.randf_range(-0.15, 0.15)
			var b := {"kind": "chalet", "pos": p, "yaw": yaw, "size": Vector2(KINDS["chalet"][0], KINDS["chalet"][1]),
				"height": KINDS["chalet"][2], "label": ""}
			var poly := footprint(b)
			if _clear(poly):
				buildings.append(b)
				_polys.append(poly)
		z -= 6.0


func _orchard() -> void:
	# Fruit trees on a loose grid in the middle of the loop, clear of roads and houses.
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for q in _road:
		lo = lo.min(q[0])
		hi = hi.max(q[0])
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var x := lo.x
	while x <= hi.x:
		var z := lo.y
		while z <= hi.y:
			var p := Vector2(x, z) + Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
			z += 9.0
			if not _inside_loop(p) or float(road_edge(p)[0]) < 6.0:
				continue
			var free := true
			for poly in _polys:
				if Geometry2D.is_point_in_polygon(p, Geometry2D.offset_polygon(poly, 4.0)[0]):
					free = false
					break
			if free and not Geometry2D.is_point_in_polygon(p, pond) and polyline_dist(p, brook) > 5.0:
				orchard.append(p)
		x += 9.0


## Inside the loop driven with the direct routes (winding number of the centre line).
func _inside_loop(p: Vector2) -> bool:
	var ring := PackedVector2Array()
	for id in course.path_for({"ramp": "jump", "pond": "water", "crossing": "exposed"}):
		var r := route(id)
		var s := 0.0
		while s < r.length:
			ring.append(at(id, s, 0.0))
			s += 2.0
	return Geometry2D.is_point_in_polygon(p, ring)


## Footprint corners of a building (front faces along yaw).
static func footprint(b: Dictionary) -> PackedVector2Array:
	var f := Vector2(sin(b["yaw"]), cos(b["yaw"]))
	var rgt := Vector2(f.y, -f.x)
	var sz: Vector2 = b["size"]
	var c: Vector2 = b["pos"]
	return PackedVector2Array([
		c + f * sz.y * 0.5 + rgt * sz.x * 0.5, c + f * sz.y * 0.5 - rgt * sz.x * 0.5,
		c - f * sz.y * 0.5 - rgt * sz.x * 0.5, c - f * sz.y * 0.5 + rgt * sz.x * 0.5,
	])


## Corners, edge midpoints and centre of a footprint.
static func sample_points(poly: PackedVector2Array) -> Array:
	var pts := Array(poly)
	var c := Vector2.ZERO
	for i in poly.size():
		pts.append((poly[i] + poly[(i + 1) % poly.size()]) * 0.5)
		c += poly[i]
	pts.append(c / poly.size())
	return pts


## Distance from p to the pond shore line.
func pond_shore_dist(p: Vector2) -> float:
	var ring := Array(pond)
	ring.append(pond[0])
	return polyline_dist(p, ring)


## 0 at the brook's source, 1 where it enters the pond, for the nearest point of the brook.
func brook_t(p: Vector2) -> float:
	var total := 0.0
	for i in brook.size() - 1:
		total += brook[i].distance_to(brook[i + 1])
	var best := INF
	var best_t := 0.0
	var acc := 0.0
	for i in brook.size() - 1:
		var a := brook[i]
		var ab := brook[i + 1] - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		if d < best:
			best = d
			best_t = (acc + ab.length() * t) / total
		acc += ab.length()
	return best_t


static func _closest_s(r: Route, p: Vector2) -> float:
	var best := INF
	var best_s := 0.0
	var s := 0.0
	while s <= r.length:
		var q := r.pos_at(s)
		var dd := p.distance_squared_to(Vector2(q.x, q.z))
		if dd < best:
			best = dd
			best_s = s
		s += 0.5
	return best_s


static func polyline_dist(p: Vector2, line: Array) -> float:
	var best := INF
	for i in line.size() - 1:
		var a: Vector2 = line[i]
		var ab: Vector2 = line[i + 1] - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best

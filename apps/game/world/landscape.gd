extends RefCounted
## Planned terrain features that give each fork alternative its reason to exist. Pure data (no
## nodes) so tools/layout_map.gd can draw and check it headless and tools/bake_world.gd can
## shape the terrain from it. Features are anchored to the course (sim/course.gd), so editing a
## route moves its feature with it: the dip sits between the ramp lip and landing, the knoll
## between the two ramp branches, the stream under the bridge hump, the valley under the
## causeway. Coordinates are world metres (x right, z forward, y up). Heights are absolute y.

const Course = preload("res://sim/course.gd")
const Route = preload("res://sim/route.gd")

## Pond shore relative to the pond junction (start of "pond_water"). The west shore follows the
## fenced bridge lane ~7 m inside it; the ford enters at the south shore (s ~ 12) and leaves at
## the north shore (s ~ 87), matching its water range s 10..90.
const POND_LOCAL: Array[Vector2] = [
	Vector2(0, 12.5), Vector2(5, 9.9), Vector2(10, 11.9), Vector2(15, 19.1), Vector2(17, 33.1), Vector2(17.5, 50.1),
	Vector2(17, 66.1), Vector2(15, 80.1), Vector2(10, 87.9), Vector2(5, 90.1), Vector2(0, 86.7), Vector2(-4.5, 82.3),
	Vector2(-8.5, 78.5), Vector2(-15.8, 76.3), Vector2(-20.5, 70.9), Vector2(-22.7, 63.9), Vector2(-23, 50.1),
	Vector2(-22.7, 36.1), Vector2(-20.5, 29.1), Vector2(-15.8, 23.7), Vector2(-8.5, 20.9), Vector2(-4.5, 16.7),
]
const POND_LEVEL := 0.12          # water surface y; the ford road sits ~0.3 m below it
const POND_FLOOR := -1.4          # deepest point away from the ford

## Stream feeding the pond from the west, through the bridge hump. Upstream points are offsets
## from the hump; the stream then runs straight on into the pond's west shore.
const STREAM_UPSTREAM: Array[Vector2] = [Vector2(-140, 21), Vector2(-90, 15), Vector2(-50, 8), Vector2(-20, 2)]
const STREAM_HALF_WIDTH := 2.2
const STREAM_LEVEL := 0.16
const STREAM_BED := -0.9

const KNOLL_HEIGHT := 3.0

## Shallow valley under the causeway. Points: x offset from the causeway, z offset from its
## middle, rim half width, floor y. The head is added relative to the hedged lane.
const VALLEY_WEST: Array[Vector4] = [
	Vector4(-180, -23, 22, -4.0), Vector4(-110, -13, 19, -3.4), Vector4(-60, -6, 16, -2.9),
	Vector4(-20, -1.3, 13, -2.5), Vector4(0, 0, 12, -2.2),
]
const VALLEY_HEAD_HW := 3.5
const VALLEY_HEAD_FLOOR := -0.6
const VALLEY_HEAD_CLEAR := 3.0    # metres between the valley head rim and the hedged lane edge

## Rolling hills: x, z, radius, height (added on top of gentle noise away from the road).
const HILLS: Array[Vector4] = [
	Vector4(-38, 25, 26, 7), Vector4(38, 20, 30, 9), Vector4(-42, 92, 22, 6), Vector4(48, 108, 30, 10),
	Vector4(-72, 145, 30, 10), Vector4(45, 182, 26, 9), Vector4(-72, 228, 24, 9), Vector4(50, 265, 24, 8),
	Vector4(-48, 330, 30, 9), Vector4(48, 330, 30, 10), Vector4(-42, 425, 40, 12), Vector4(44, 425, 34, 10),
	Vector4(0, 490, 50, 16), Vector4(0, -60, 45, 12),
]

## Flat plazas: start grid (absolute) and finish area (relative to the finish line).
const FLAT_START := Rect2(-14, -14, 28, 34)
const FLAT_FINISH_LOCAL := Rect2(-26, -32, 52, 46)

## Terrain extents for the playable map (the far-hills ring sits outside it).
const MAP_RECT := Rect2(-200, -120, 400, 640)

var pond: PackedVector2Array
var stream: Array[Vector2] = []
var bridge_hump := Vector3.ZERO
var dip_center := Vector2.ZERO
var dip_radii := Vector2.ZERO
var dip_floor := 0.0
var knoll_center := Vector2.ZERO
var knoll_radius := 0.0
var valley: Array[Vector4] = []
var flat_finish := Rect2()
var finish := Vector3.ZERO


func _init(course: Course) -> void:
	var jp: Vector3 = (course.segments["pond_water"]["route"] as Route).pos_at(0.0)
	for q in POND_LOCAL:
		pond.append(Vector2(jp.x, jp.z) + q)
	# Bridge hump = highest point of the bridge lane; the stream runs under it into the pond.
	var br: Route = course.segments["pond_bridge"]["route"]
	var s := 0.0
	bridge_hump = br.pos_at(0.0)
	while s <= br.length:
		if br.pos_at(s).y > bridge_hump.y + 0.001:
			bridge_hump = br.pos_at(s)
		s += 0.5
	# Centre of the hump plateau (the profile is flat-topped over a metre or so).
	var top := bridge_hump.y
	var s0 := INF
	var s1 := -INF
	s = 0.0
	while s <= br.length:
		if br.pos_at(s).y > top - 0.005:
			s0 = minf(s0, s)
			s1 = maxf(s1, s)
		s += 0.25
	bridge_hump = br.pos_at((s0 + s1) * 0.5)
	var hump := Vector2(bridge_hump.x, bridge_hump.z)
	for q in STREAM_UPSTREAM:
		stream.append(hump + q)
	stream.append(hump)
	var shore := hump
	while not Geometry2D.is_point_in_polygon(shore, pond) and shore.x < jp.x:
		shore.x += 0.5
	stream.append(shore + Vector2(2.0, 0.0))
	# Dip between the ramp lip and the landing, a little wider than the jump road.
	var seg: Dictionary = course.segments["ramp_jump"]
	var jr: Route = seg["route"]
	var rp: Dictionary = seg["ramp"]
	var lip := float(rp["lip_s"])
	var land := float(rp["land_s"])
	var mid := jr.pos_at((lip + land) * 0.5)
	dip_radii = Vector2(9.0, (land - lip) * 0.5 - 0.7)
	dip_center = Vector2(mid.x - 4.0, mid.z)
	dip_floor = mid.y - float(rp["pit_depth"])
	# Knoll between the jump road and the apex of the around road.
	var ar: Route = course.segments["ramp_around"]["route"]
	var x0 := jr.pos_at(0.0).x
	var apex := ar.pos_at(0.0)
	s = 0.0
	while s <= ar.length:
		if absf(ar.pos_at(s).x - x0) > absf(apex.x - x0):
			apex = ar.pos_at(s)
		s += 0.5
	var side := signf(apex.x - x0)
	var jump_edge := x0 + float(seg["half_width"]) * side
	var around_edge := apex.x - float(course.segments["ramp_around"]["half_width"]) * side
	knoll_center = Vector2((jump_edge + around_edge) * 0.5, apex.z)
	knoll_radius = absf(around_edge - jump_edge) * 0.5 + 1.5
	# Valley under the middle of the causeway; its head stops short of the hedged lane.
	var cr: Route = course.segments["cross_exposed"]["route"]
	var cm := cr.pos_at(cr.length * 0.5)
	for v in VALLEY_WEST:
		valley.append(Vector4(cm.x + v.x, cm.z + v.y, v.z, v.w))
	var sr: Route = course.segments["cross_sheltered"]["route"]
	var lane_x := -INF
	s = 0.0
	while s <= sr.length:
		lane_x = maxf(lane_x, sr.pos_at(s).x)
		s += 0.5
	var head_x := lane_x - float(course.segments["cross_sheltered"]["half_width"]) - VALLEY_HEAD_CLEAR - VALLEY_HEAD_HW
	valley.append(Vector4(head_x, cm.z, VALLEY_HEAD_HW, VALLEY_HEAD_FLOOR))
	var fr: Route = course.segments["bends"]["route"]
	finish = fr.pos_at(fr.length)
	flat_finish = Rect2(FLAT_FINISH_LOCAL.position + Vector2(finish.x, finish.z), FLAT_FINISH_LOCAL.size)


func in_pond(p: Vector2, grow := 0.0) -> bool:
	if Geometry2D.is_point_in_polygon(p, pond):
		return true
	return grow > 0.0 and pond_shore_dist(p) < grow


## Distance from p to the pond shore line.
func pond_shore_dist(p: Vector2) -> float:
	var ring: Array[Vector2] = []
	for q in pond:
		ring.append(q)
	ring.append(pond[0])
	return polyline_dist(p, ring)


func pond_center() -> Vector2:
	var c := Vector2.ZERO
	for q in pond:
		c += q
	return c / pond.size()


func in_dip(p: Vector2) -> bool:
	var q := (p - dip_center) / dip_radii
	return q.length_squared() <= 1.0


## Distance from p to the stream centre line.
func stream_dist(p: Vector2) -> float:
	return polyline_dist(p, stream)


## [distance to valley centre line, interpolated rim half width, interpolated floor y].
func valley_info(p: Vector2) -> Array:
	var best := INF
	var hw := 0.0
	var floor_y := 0.0
	for i in valley.size() - 1:
		var a := Vector2(valley[i].x, valley[i].y)
		var b := Vector2(valley[i + 1].x, valley[i + 1].y)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var dist := p.distance_to(a + ab * t)
		if dist < best:
			best = dist
			hw = lerpf(valley[i].z, valley[i + 1].z, t)
			floor_y = lerpf(valley[i].w, valley[i + 1].w, t)
	return [best, hw, floor_y]


static func polyline_dist(p: Vector2, line: Array[Vector2]) -> float:
	var best := INF
	for i in line.size() - 1:
		var a := line[i]
		var ab := line[i + 1] - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best

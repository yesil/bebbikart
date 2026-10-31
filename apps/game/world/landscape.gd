extends RefCounted
## Planned terrain features that give each fork alternative its reason to exist. Pure data (no
## nodes) so tools/layout_map.gd can draw and check it headless and tools/bake_world.gd can
## shape the terrain from it. Coordinates are world metres (x right, z forward, y up), matching
## sim/course.gd. Heights are absolute world y.

## Pond the ford crosses ("pond_water" water range s 10..90). The west shore follows the fenced
## bridge lane ~7 m inside it; the ford enters at the south shore and leaves at the north shore.
const POND: Array[Vector2] = [
	Vector2(0, 140.6), Vector2(5, 138.8), Vector2(10, 140.8), Vector2(15, 148), Vector2(17, 162), Vector2(17.5, 179),
	Vector2(17, 195), Vector2(15, 209), Vector2(10, 216.8), Vector2(5, 219), Vector2(0, 217.2), Vector2(-4, 213.8),
	Vector2(-8, 209.2), Vector2(-15.8, 205.2), Vector2(-20.5, 199.8), Vector2(-22.7, 192.8), Vector2(-23, 179),
	Vector2(-22.7, 165), Vector2(-20.5, 158), Vector2(-15.8, 152.6), Vector2(-8, 148.6), Vector2(-4, 144),
]
const POND_LEVEL := 0.12          # water surface y; the ford road sits ~0.3 m below it
const POND_FLOOR := -1.4          # deepest point away from the ford

## Stream feeding the pond from the west, crossed by the stone bridge at the "pond_bridge" hump.
const STREAM: Array[Vector2] = [
	Vector2(-170, 200), Vector2(-120, 194), Vector2(-80, 187), Vector2(-50, 181), Vector2(-30, 178.9), Vector2(-21, 178.9),
]
const STREAM_HALF_WIDTH := 2.2
const STREAM_LEVEL := 0.16
const STREAM_BED := -0.9

## Muddy dip the jump clears (between the ramp lip and the landing on "ramp_jump").
const DIP_CENTER := Vector2(-4.0, 79.3)
const DIP_RADII := Vector2(9.0, 8.3)

## Knoll the "ramp_around" road curves round.
const KNOLL_CENTER := Vector2(6.8, 79.5)
const KNOLL_RADIUS := 5.0
const KNOLL_HEIGHT := 3.0

## Shallow valley the causeway ("cross_exposed") crosses; its head stops short of the hedged
## lane ("cross_sheltered"). Each point: x, z, half width at the rim, floor y.
const VALLEY: Array[Vector4] = [
	Vector4(-180, 236, 22, -4.0), Vector4(-110, 246, 19, -3.4), Vector4(-60, 253, 16, -2.9),
	Vector4(-20, 257.5, 13, -2.5), Vector4(0, 258.8, 12, -2.2), Vector4(9, 258.8, 4, -0.6),
]

## Rolling hills: x, z, radius, height (added on top of gentle noise away from the road).
const HILLS: Array[Vector4] = [
	Vector4(-38, 25, 26, 7), Vector4(38, 20, 30, 9), Vector4(-40, 90, 22, 6), Vector4(45, 105, 30, 10),
	Vector4(-70, 140, 30, 10), Vector4(42, 175, 26, 9), Vector4(-70, 220, 24, 9), Vector4(48, 255, 24, 8),
	Vector4(-45, 320, 30, 9), Vector4(45, 320, 30, 10), Vector4(-40, 410, 40, 12), Vector4(42, 410, 34, 10),
	Vector4(0, 475, 50, 16), Vector4(0, -60, 45, 12),
]

## Flat plazas (start grid, finish area): rect x, z, w, h and their y.
const FLAT_START := Rect2(-14, -14, 28, 34)
const FLAT_FINISH := Rect2(-26, 362, 52, 46)
const FLAT_START_Y := 0.0
const FLAT_FINISH_Y := 0.0

## Terrain extents for the playable map (the far-hills ring sits outside it).
const MAP_RECT := Rect2(-200, -120, 400, 620)


static func in_pond(p: Vector2, grow := 0.0) -> bool:
	if Geometry2D.is_point_in_polygon(p, PackedVector2Array(POND)):
		return true
	return grow > 0.0 and pond_shore_dist(p) < grow


## Distance from p to the pond shore line.
static func pond_shore_dist(p: Vector2) -> float:
	var ring: Array[Vector2] = POND.duplicate()
	ring.append(POND[0])
	return polyline_dist(p, ring)


static func pond_center() -> Vector2:
	var c := Vector2.ZERO
	for q in POND:
		c += q
	return c / POND.size()


static func in_dip(p: Vector2) -> bool:
	var q := (p - DIP_CENTER) / DIP_RADII
	return q.length_squared() <= 1.0


## Distance from p to the stream centre line.
static func stream_dist(p: Vector2) -> float:
	return polyline_dist(p, STREAM)


## [distance to valley centre line, interpolated half width, interpolated floor y].
static func valley_info(p: Vector2) -> Array:
	var best := INF
	var hw := 0.0
	var floor_y := 0.0
	for i in VALLEY.size() - 1:
		var a := Vector2(VALLEY[i].x, VALLEY[i].y)
		var b := Vector2(VALLEY[i + 1].x, VALLEY[i + 1].y)
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var dist := p.distance_to(a + ab * t)
		if dist < best:
			best = dist
			hw = lerpf(VALLEY[i].z, VALLEY[i + 1].z, t)
			floor_y = lerpf(VALLEY[i].w, VALLEY[i + 1].w, t)
	# Round cap at the valley head.
	var head := Vector2(VALLEY[VALLEY.size() - 1].x, VALLEY[VALLEY.size() - 1].y)
	if p.x > head.x:
		best = maxf(best, p.distance_to(head))
	return [best, hw, floor_y]


static func polyline_dist(p: Vector2, line: Array[Vector2]) -> float:
	var best := INF
	for i in line.size() - 1:
		var a := line[i]
		var ab := line[i + 1] - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best

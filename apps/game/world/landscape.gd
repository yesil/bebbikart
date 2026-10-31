extends RefCounted
## Planned terrain features that give each fork alternative its reason to exist. Pure data (no
## nodes) so tools/layout_map.gd can draw and check it headless and tools/bake_world.gd can
## shape the terrain from it. Coordinates are world metres (x right, z forward, y up), matching
## sim/course.gd. Heights are absolute world y.

## Pond the ford crosses (ramp "pond_water" water range). Ellipse in XZ.
const POND_CENTER := Vector2(-2.0, 171.5)
const POND_RADII := Vector2(16.0, 40.5)
const POND_LEVEL := 0.12          # water surface y; the ford road sits ~0.3 m below it
const POND_FLOOR := -1.4          # deepest point away from the ford

## Stream feeding the pond from the west, crossed by the stone bridge on "pond_bridge".
const STREAM: Array[Vector2] = [
	Vector2(-170, 196), Vector2(-120, 188), Vector2(-80, 180), Vector2(-52, 174), Vector2(-37, 172),
	Vector2(-26, 171.5), Vector2(-17, 171.5),
]
const STREAM_HALF_WIDTH := 2.2
const STREAM_LEVEL := 0.16
const STREAM_BED := -0.9

## Muddy dip the jump clears (between the ramp lip and the landing on "ramp_jump").
const DIP_CENTER := Vector2(-3.0, 79.0)
const DIP_RADII := Vector2(11.0, 9.0)

## Knoll the "ramp_around" road curves round.
const KNOLL_CENTER := Vector2(7.6, 78.0)
const KNOLL_RADIUS := 6.5
const KNOLL_HEIGHT := 3.2

## Shallow valley the causeway ("cross_exposed") crosses; its head stops short of the hedged
## lane ("cross_sheltered"). Each point: x, z, half width at the rim, floor y.
const VALLEY: Array[Vector4] = [
	Vector4(-180, 232, 22, -4.0), Vector4(-110, 240, 19, -3.4), Vector4(-60, 247, 16, -2.9),
	Vector4(-20, 251, 13, -2.5), Vector4(0, 252, 11, -2.2), Vector4(9, 252, 4, -0.6),
]

## Rolling hills: x, z, radius, height (added on top of gentle noise away from the road).
const HILLS: Array[Vector4] = [
	Vector4(-38, 28, 26, 7), Vector4(38, 22, 30, 9), Vector4(-36, 92, 24, 6), Vector4(42, 110, 34, 12),
	Vector4(-75, 135, 30, 10), Vector4(36, 175, 28, 9), Vector4(-80, 215, 40, 14), Vector4(44, 236, 26, 8),
	Vector4(-46, 300, 30, 9), Vector4(46, 320, 34, 11), Vector4(-40, 400, 40, 12), Vector4(40, 405, 36, 10),
	Vector4(0, 440, 50, 16), Vector4(0, -55, 45, 12),
]

## Flat plazas (start grid, finish area): rect x, z, w, h and their y.
const FLAT_START := Rect2(-14, -14, 28, 34)
const FLAT_FINISH := Rect2(-24, 352, 48, 44)
const FLAT_START_Y := 0.0
const FLAT_FINISH_Y := 0.0

## Terrain extents for the playable map (the far-hills ring sits outside it).
const MAP_RECT := Rect2(-200, -120, 400, 620)


static func in_pond(p: Vector2, grow := 0.0) -> bool:
	var q := (p - POND_CENTER) / (POND_RADII + Vector2(grow, grow))
	return q.length_squared() <= 1.0


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

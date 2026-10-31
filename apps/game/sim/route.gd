extends RefCounted
## A sampled centre-line spline (Catmull-Rom through control points, resampled at ~1 m).
## Pure data, no nodes. Lateral normal n = (-t.z, 0, t.x) (left of travel when +z is forward... see below).
## Positive d is along n. Positive curvature k means the heading increases (turning towards +x when going +z).

const STEP := 1.0

var pts := PackedVector3Array()
var ss := PackedFloat64Array()
var heading := PackedFloat64Array()
var curv := PackedFloat64Array()
var length := 0.0


static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func build(ctrl: Array) -> void:
	var c: Array[Vector3] = []
	for p in ctrl:
		c.append(p)
	# Phantom end points by extrapolation.
	var ext: Array[Vector3] = [c[0] * 2.0 - c[1]]
	ext.append_array(c)
	ext.append(c[c.size() - 1] * 2.0 - c[c.size() - 2])
	# Dense sampling.
	var dense: Array[Vector3] = []
	for i in range(1, ext.size() - 2):
		var p0 := ext[i - 1]
		var p1 := ext[i]
		var p2 := ext[i + 1]
		var p3 := ext[i + 2]
		var n := maxi(4, int(ceil(p1.distance_to(p2) * 8.0)))
		for j in n:
			dense.append(_cr(p0, p1, p2, p3, float(j) / n))
	dense.append(c[c.size() - 1])
	# Arc length of dense polyline.
	var acc := PackedFloat64Array()
	acc.resize(dense.size())
	acc[0] = 0.0
	for i in range(1, dense.size()):
		acc[i] = acc[i - 1] + dense[i].distance_to(dense[i - 1])
	length = acc[acc.size() - 1]
	# Resample uniformly.
	var count := maxi(2, int(round(length / STEP)) + 1)
	var step := length / (count - 1)
	pts.resize(count)
	ss.resize(count)
	var k := 0
	for i in count:
		var target := i * step
		while k < dense.size() - 2 and acc[k + 1] < target:
			k += 1
		var seg := acc[k + 1] - acc[k]
		var f := 0.0 if seg <= 0.0 else clampf((target - acc[k]) / seg, 0.0, 1.0)
		pts[i] = dense[k].lerp(dense[k + 1], f)
		ss[i] = target
	# Heading from horizontal tangent.
	heading.resize(count)
	for i in count:
		var a := pts[maxi(0, i - 1)]
		var b := pts[mini(count - 1, i + 1)]
		var t := b - a
		heading[i] = atan2(t.x, t.z)
	# Curvature (per metre), smoothed.
	var raw := PackedFloat64Array()
	raw.resize(count)
	for i in count:
		var i0 := maxi(0, i - 1)
		var i1 := mini(count - 1, i + 1)
		var ds := ss[i1] - ss[i0]
		raw[i] = 0.0 if ds <= 0.0 else wrapf(heading[i1] - heading[i0], -PI, PI) / ds
	curv.resize(count)
	for i in count:
		var sum := 0.0
		var n2 := 0
		for j in range(i - 3, i + 4):
			if j >= 0 and j < count:
				sum += raw[j]
				n2 += 1
		curv[i] = sum / n2


func _idx(s: float) -> Array:
	var x := clampf(s, 0.0, length) / (length / (pts.size() - 1))
	var i := mini(int(x), pts.size() - 2)
	return [i, x - i]


func pos_at(s: float) -> Vector3:
	var r := _idx(s)
	var i: int = r[0]
	return pts[i].lerp(pts[i + 1], r[1])


func heading_at(s: float) -> float:
	var r := _idx(s)
	var i: int = r[0]
	return lerp_angle(heading[i], heading[i + 1], r[1])


func curv_at(s: float) -> float:
	var r := _idx(s)
	var i: int = r[0]
	return lerpf(curv[i], curv[i + 1], r[1])


## Unit horizontal tangent.
func tangent_at(s: float) -> Vector3:
	var h := heading_at(s)
	return Vector3(sin(h), 0.0, cos(h))


## Unit lateral normal (positive d direction).
func normal_at(s: float) -> Vector3:
	var t := tangent_at(s)
	return Vector3(-t.z, 0.0, t.x)


## Slope (dy/ds) of the centre line.
func pitch_at(s: float) -> float:
	var a := pos_at(s - 0.75)
	var b := pos_at(s + 0.75)
	var h := Vector2(b.x - a.x, b.z - a.z).length()
	return atan2(b.y - a.y, maxf(h, 0.001))


func world_at(s: float, d: float) -> Vector3:
	return pos_at(s) + normal_at(s) * d

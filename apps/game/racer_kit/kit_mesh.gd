class_name KitMesh
extends RefCounted
## Procedural mesh generators for the toy-part kit. All meshes are cached by key,
## so building a racer after the first one only creates nodes, not geometry.
##
## Winding: Godot treats clockwise triangles (seen from outside) as front faces.
## Every generator passes an "outward" hint per triangle and _tri() fixes the order.

static var _cache: Dictionary = {}


static func cached(key: String, maker: Callable) -> Mesh:
	var m: Mesh = _cache.get(key)
	if m == null:
		m = maker.call()
		_cache[key] = m
	return m


static func clear_cache() -> void:
	_cache.clear()


# --- Blob: superellipsoid with taper. Used for bodies, heads, chassis, hulls. ---
# params: ax, ay, az (radii), n (2 = ellipsoid, 4+ = rounded box),
# taper (>0 narrower at top), flat_bottom (0..1 squashes the lower half), nose (stretches -Z front)

static func blob_point(p: Dictionary, d: Vector3) -> Vector3:
	var n: float = p.get("n", 2.0)
	var a := Vector3(p.get("ax", 0.5), p.get("ay", 0.5), p.get("az", 0.5))
	var s := pow(absf(d.x) / a.x, n) + pow(absf(d.y) / a.y, n) + pow(absf(d.z) / a.z, n)
	var v := d * pow(maxf(s, 1e-6), -1.0 / n)
	var taper: float = p.get("taper", 0.0)
	var k := 1.0 - taper * clampf(v.y / a.y, -1.0, 1.0)
	v.x *= k
	v.z *= k
	var flat: float = p.get("flat_bottom", 0.0)
	if v.y < 0.0:
		v.y *= 1.0 - flat
	var nose: float = p.get("nose", 0.0)
	if v.z < 0.0:
		v.z *= 1.0 + nose
	return v


static func blob_normal(p: Dictionary, d: Vector3) -> Vector3:
	var t1 := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
	var t2 := d.cross(t1).normalized()
	var e := 0.01
	var a := blob_point(p, (d + t1 * e).normalized()) - blob_point(p, (d - t1 * e).normalized())
	var b := blob_point(p, (d + t2 * e).normalized()) - blob_point(p, (d - t2 * e).normalized())
	var nrm := a.cross(b).normalized()
	if nrm.dot(d) < 0.0:
		nrm = -nrm
	return nrm


## Direction for face-style coordinates: yaw (+ = racer's right), pitch (+ = up), facing -Z.
static func face_dir(yaw: float, pitch: float) -> Vector3:
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


static func blob(p: Dictionary, lat: int = 14, lon: int = 22) -> Mesh:
	var key := "blob:%s:%d:%d" % [JSON.stringify(p), lat, lon]
	return cached(key, func() -> Mesh: return _make_blob(p, lat, lon))


static func _make_blob(p: Dictionary, lat: int, lon: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array[Vector3] = []
	verts.append(blob_point(p, Vector3.UP))
	for i in range(1, lat):
		var th := PI * float(i) / lat
		for j in lon:
			var ph := TAU * float(j) / lon
			verts.append(blob_point(p, Vector3(sin(th) * sin(ph), cos(th), sin(th) * cos(ph))))
	verts.append(blob_point(p, Vector3.DOWN))
	for v in verts:
		st.add_vertex(v)
	var south := verts.size() - 1
	var last_ring := 1 + (lat - 2) * lon
	for j in lon:
		var j2 := (j + 1) % lon
		_tri(st, verts, 0, 1 + j, 1 + j2, verts[1 + j])
		_tri(st, verts, south, last_ring + j2, last_ring + j, verts[last_ring + j])
	for i in range(lat - 2):
		for j in lon:
			var j2 := (j + 1) % lon
			var a := 1 + i * lon + j
			var b := 1 + i * lon + j2
			var c := 1 + (i + 1) * lon + j
			var d := 1 + (i + 1) * lon + j2
			_tri(st, verts, a, c, b, verts[a])
			_tri(st, verts, b, c, d, verts[b])
	st.generate_normals()
	return st.commit()


static func _tri(st: SurfaceTool, verts: Array[Vector3], a: int, b: int, c: int, outward: Vector3) -> void:
	var n := (verts[b] - verts[a]).cross(verts[c] - verts[a])
	if n.dot(outward) > 0.0:
		st.add_index(a)
		st.add_index(c)
		st.add_index(b)
	else:
		st.add_index(a)
		st.add_index(b)
		st.add_index(c)


# --- Tube along a polyline (smiles, brows, swirls, curly tails, antennae). ---

static func tube(points: PackedVector3Array, radius: float, sides: int = 8, key: String = "") -> Mesh:
	if key != "":
		return cached("tube:" + key, func() -> Mesh: return _make_tube(points, radius, sides))
	return _make_tube(points, radius, sides)


static func _make_tube(points: PackedVector3Array, radius: float, sides: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array[Vector3] = []
	var centers: Array[Vector3] = []
	var count := points.size()
	if count < 2:
		points = PackedVector3Array([Vector3.ZERO, Vector3(0, 0.01, 0)])
		count = 2
	var tangent := (points[1] - points[0]).normalized()
	var normal := tangent.cross(Vector3.FORWARD if absf(tangent.z) < 0.9 else Vector3.UP).normalized()
	# Each ring: [center, radius factor, tangent, normal]. Shrunken end rings give rounded ends.
	var rings: Array = []
	rings.append([points[0] - tangent * radius * 0.6, 0.55, tangent, normal])
	for i in count:
		var t: Vector3
		if i == 0:
			t = points[1] - points[0]
		elif i == count - 1:
			t = points[i] - points[i - 1]
		else:
			t = points[i + 1] - points[i - 1]
		t = t.normalized()
		normal = (normal - t * normal.dot(t)).normalized()
		rings.append([points[i], 1.0, t, normal])
	var last: Array = rings[rings.size() - 1]
	var last_t: Vector3 = last[2]
	rings.append([points[count - 1] + last_t * radius * 0.6, 0.55, last_t, last[3]])
	for r in rings:
		var c: Vector3 = r[0]
		var t2: Vector3 = r[2]
		var n2: Vector3 = r[3]
		var b2 := t2.cross(n2)
		var rf: float = r[1]
		for s in sides:
			var ang := TAU * float(s) / sides
			verts.append(c + (n2 * cos(ang) + b2 * sin(ang)) * radius * rf)
			centers.append(c)
	var first_c: Vector3 = rings[0][0]
	var first_t: Vector3 = rings[0][2]
	var end_c: Vector3 = rings[rings.size() - 1][0]
	var first_tip := verts.size()
	verts.append(first_c - first_t * radius * 0.3)
	var last_tip := verts.size()
	verts.append(end_c + last_t * radius * 0.3)
	for v in verts:
		st.add_vertex(v)
	var ring_count := rings.size()
	for i in ring_count - 1:
		for s in sides:
			var s2 := (s + 1) % sides
			var a := i * sides + s
			var b := i * sides + s2
			var c := (i + 1) * sides + s
			var d := (i + 1) * sides + s2
			_tri(st, verts, a, b, c, verts[a] - centers[a])
			_tri(st, verts, b, d, c, verts[b] - centers[b])
	var base := (ring_count - 1) * sides
	for s in sides:
		var s2 := (s + 1) % sides
		_tri(st, verts, first_tip, s, s2, -first_t)
		_tri(st, verts, last_tip, base + s, base + s2, last_t)
	st.generate_normals()
	return st.commit()


# --- Puffy extruded outline (stars, hearts, open mouths, fins, wings). ---
# outline: 2D points in XY, roughly star-shaped around their centroid. Thickness along Z.

static func puffy(outline: PackedVector2Array, thickness: float, key: String = "") -> Mesh:
	if key != "":
		return cached("puffy:" + key, func() -> Mesh: return _make_puffy(outline, thickness))
	return _make_puffy(outline, thickness)


static func _make_puffy(outline: PackedVector2Array, thickness: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c2 := Vector2.ZERO
	for p in outline:
		c2 += p
	c2 /= outline.size()
	var n := outline.size()
	var verts: Array[Vector3] = []
	var h := thickness * 0.5
	# 0..n-1 outline front, n..2n-1 outline back, 2n..3n-1 inset front, 3n..4n-1 inset back
	for p in outline:
		verts.append(Vector3(p.x, p.y, h * 0.55))
	for p in outline:
		verts.append(Vector3(p.x, p.y, -h * 0.55))
	for p in outline:
		var q := c2 + (p - c2) * 0.82
		verts.append(Vector3(q.x, q.y, h))
	for p in outline:
		var q := c2 + (p - c2) * 0.82
		verts.append(Vector3(q.x, q.y, -h))
	var cf := verts.size()
	verts.append(Vector3(c2.x, c2.y, h * 1.1))
	var cb := verts.size()
	verts.append(Vector3(c2.x, c2.y, -h * 1.1))
	for v in verts:
		st.add_vertex(v)
	for i in n:
		var i2 := (i + 1) % n
		var radial := Vector3(outline[i].x - c2.x, outline[i].y - c2.y, 0.0)
		_tri(st, verts, i, n + i, i2, radial)
		_tri(st, verts, i2, n + i, n + i2, radial)
		_tri(st, verts, i, i2, 2 * n + i, radial + Vector3(0, 0, 1))
		_tri(st, verts, i2, 2 * n + i2, 2 * n + i, radial + Vector3(0, 0, 1))
		_tri(st, verts, cf, 2 * n + i, 2 * n + i2, Vector3(0, 0, 1))
		_tri(st, verts, n + i, n + i2, 3 * n + i, radial + Vector3(0, 0, -1))
		_tri(st, verts, n + i2, 3 * n + i2, 3 * n + i, radial + Vector3(0, 0, -1))
		_tri(st, verts, cb, 3 * n + i, 3 * n + i2, Vector3(0, 0, -1))
	st.generate_normals()
	return st.commit()


static func star_outline(points: int = 5, outer: float = 0.12, inner: float = 0.055) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points * 2:
		var r := outer if i % 2 == 0 else inner
		var a := PI * 0.5 + PI * float(i) / points
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


static func heart_outline(size: float = 0.12) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 40:
		var t := TAU * float(i) / 40.0
		var x := 16.0 * pow(sin(t), 3)
		var y := 13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)
		out.append(Vector2(x, y + 2.5) * size / 16.0)
	return out


## Open "D" mouth: flat top edge, round bottom.
static func half_disc_outline(w: float, h: float, segments: int = 14) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in segments + 1:
		var a := PI * float(i) / segments
		out.append(Vector2(cos(a) * w, -sin(a) * h))
	return out


static func ellipse_outline(w: float, h: float, segments: int = 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in segments:
		var a := TAU * float(i) / segments
		out.append(Vector2(cos(a) * w, sin(a) * h))
	return out


# --- Slab: any (also concave) outline extruded along Z with flat caps. ---
# Lightning bolts, crescents, bow ties, capes. bend (optional) moves each vertex after building.
# flat: faceted shading with sharp edges (building blocks) instead of smoothed normals.

static func slab(outline: PackedVector2Array, thickness: float, key: String = "", bend: Callable = Callable(), flat := false) -> Mesh:
	if key != "":
		return cached("slab:" + key, func() -> Mesh: return _make_slab(outline, thickness, bend, flat))
	return _make_slab(outline, thickness, bend, flat)


static func _make_slab(outline: PackedVector2Array, thickness: float, bend: Callable, flat := false) -> ArrayMesh:
	var tris := Geometry2D.triangulate_polygon(outline)
	if tris.is_empty():
		push_error("KitMesh.slab: outline can't be triangulated (%d points)" % outline.size())
		return ArrayMesh.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if flat:
		st.set_smooth_group(-1)
	var h := thickness * 0.5
	var put := func(v: Vector3) -> void:
		st.add_vertex(bend.call(v) if bend.is_valid() else v)
	for z in [h, -h]:
		var verts: Array[Vector3] = []
		for p in outline:
			verts.append(Vector3(p.x, p.y, z))
		for i in range(0, tris.size(), 3):
			var a := verts[tris[i]]
			var b := verts[tris[i + 1]]
			var c := verts[tris[i + 2]]
			# Clockwise seen from outside (+Z for the front cap, -Z for the back).
			if (b - a).cross(c - a).z * signf(z) > 0.0:
				put.call(a); put.call(c); put.call(b)
			else:
				put.call(a); put.call(b); put.call(c)
	var n := outline.size()
	var ccw := 0.0
	for i in n:
		ccw += outline[i].cross(outline[(i + 1) % n])
	for i in n:
		var p0 := outline[i]
		var p1 := outline[(i + 1) % n]
		var a := Vector3(p0.x, p0.y, h)
		var b := Vector3(p1.x, p1.y, h)
		var c := Vector3(p1.x, p1.y, -h)
		var d := Vector3(p0.x, p0.y, -h)
		# Clockwise seen from outside, like the caps (the walls used to face inwards).
		if ccw > 0.0:
			put.call(a); put.call(b); put.call(c)
			put.call(a); put.call(c); put.call(d)
		else:
			put.call(a); put.call(c); put.call(b)
			put.call(a); put.call(d); put.call(c)
	st.generate_normals()
	return st.commit()


## Dome = top half of a blob with a flat base at y=0 (glass cabins).
static func dome(ax: float, ay: float, az: float) -> Mesh:
	return blob({"ax": ax, "ay": ay, "az": az, "n": 2.0, "flat_bottom": 0.96}, 12, 22)


## Outline shapes for the flat extras, about 1 unit across (centred on the origin).
static func shape_outline(shape: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	match shape:
		"lightning":
			for p in [[0.12, 0.5], [-0.28, 0.02], [-0.02, 0.02], [-0.16, -0.5], [0.3, 0.06], [0.04, 0.06], [0.26, 0.5]]:
				out.append(Vector2(p[0], p[1]))
		"flame":
			for i in 40:
				var t := TAU * float(i) / 40.0
				var r := 0.3 * (1.0 + 0.25 * sin(t * 3.0 + 1.0))
				var y := -sin(t) * r * 0.9
				var x := cos(t) * r
				if y > 0.0:  # stretch the top into a flickering tip
					y *= 1.0 + 1.6 * (1.0 - absf(x) / 0.38)
					x *= 1.0 - y * 0.7
				out.append(Vector2(x, y - 0.12))
		"moon":
			# Outer circle (r 0.5) minus a circle (r 0.42) shifted right: they meet at ±57°.
			for i in 25:
				var a := deg_to_rad(lerpf(57.0, 303.0, float(i) / 24.0))
				out.append(Vector2(cos(a), sin(a)) * 0.5)
			for i in range(1, 24):
				var a := deg_to_rad(lerpf(273.0, 87.0, float(i) / 24.0))
				out.append(Vector2(0.25 + cos(a) * 0.42, sin(a) * 0.42))
		"flower":
			for i in 60:
				var t := TAU * float(i) / 60.0
				out.append(Vector2(cos(t), sin(t)) * (0.24 + 0.26 * absf(cos(t * 2.5))))
		"leaf":
			for i in 32:
				var t := TAU * float(i) / 32.0
				out.append(Vector2(sin(t) * 0.24 * (1.0 - 0.3 * cos(t)), cos(t) * 0.5))
		"cloud":
			for i in 48:
				var t := TAU * float(i) / 48.0
				var r := 0.36 + 0.09 * absf(sin(t * 3.0))
				out.append(Vector2(cos(t) * r * 1.3, sin(t) * r * 0.8))
		"diamond":
			for p in [[0.0, 0.5], [0.34, 0.12], [0.0, -0.5], [-0.34, 0.12]]:
				out.append(Vector2(p[0], p[1]))
		"drop":
			for i in 40:
				var t := TAU * float(i) / 40.0
				out.append(Vector2(0.42 * sin(t) * sin(t * 0.5), 0.5 * cos(t)))
		"bowtie":
			for p in [[-0.5, 0.3], [-0.08, 0.06], [0.08, 0.06], [0.5, 0.3], [0.5, -0.3], [0.08, -0.06], [-0.08, -0.06], [-0.5, -0.3]]:
				out.append(Vector2(p[0], p[1]))
		"cape":
			for p in [[-0.22, 0.0], [0.22, 0.0], [0.5, -1.0], [-0.5, -1.0]]:
				out.append(Vector2(p[0], p[1]))
	return out


# --- Godot primitives, cached ---

static func sphere(r: float, hemisphere: bool = false) -> Mesh:
	return cached("sphere:%f:%s" % [r, hemisphere], func() -> Mesh:
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * (1.0 if hemisphere else 2.0)
		m.is_hemisphere = hemisphere
		m.radial_segments = 20
		m.rings = 10
		return m)


static func capsule(r: float, h: float) -> Mesh:
	return cached("capsule:%f:%f" % [r, h], func() -> Mesh:
		var m := CapsuleMesh.new()
		m.radius = r
		m.height = maxf(h, r * 2.0)
		m.radial_segments = 16
		m.rings = 6
		return m)


static func cylinder(top: float, bottom: float, h: float, segments: int = 20) -> Mesh:
	return cached("cyl:%f:%f:%f:%d" % [top, bottom, h, segments], func() -> Mesh:
		var m := CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = h
		m.radial_segments = segments
		m.rings = 1
		return m)


static func torus(inner: float, outer: float) -> Mesh:
	return cached("torus:%f:%f" % [inner, outer], func() -> Mesh:
		var m := TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 24
		m.ring_segments = 10
		return m)


static func rounded_box(size: Vector3, roundness: float = 5.0) -> Mesh:
	return blob({"ax": size.x * 0.5, "ay": size.y * 0.5, "az": size.z * 0.5, "n": roundness}, 12, 20)

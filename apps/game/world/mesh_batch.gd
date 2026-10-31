extends RefCounted
## Merges many simple pieces (boxes, cylinders, ribbons) into one mesh so props like fences and
## piers cost one draw call per material. UVs are in metres / uv_m so tiling textures keep their
## scale on every piece. Used by tools/bake_world.gd and tools/seed_decor.gd.

var st := SurfaceTool.new()
var uv_m := 1.0
var count := 0


func _init(p_uv_m := 1.0) -> void:
	uv_m = p_uv_m
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


## a-b-c-d counter-clockwise seen from the outside; emitted clockwise (Godot's front face).
func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	for v in [[a, ua], [c, uc], [b, ub], [a, ua], [d, ud], [c, uc]]:
		st.set_uv(v[1] / uv_m)
		st.add_vertex(v[0])
	count += 1


## Box of `size` centred on xf.origin, oriented by xf.basis.
func box(xf: Transform3D, size: Vector3) -> void:
	var h := size * 0.5
	var c := [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	var p: Array[Vector3] = []
	for v in c:
		p.append(xf * v)
	var sx := size.x
	var sy := size.y
	var sz := size.z
	_quad(p[4], p[5], p[6], p[7], Vector2(0, 0), Vector2(sx, 0), Vector2(sx, sy), Vector2(0, sy))     # +z
	_quad(p[1], p[0], p[3], p[2], Vector2(0, 0), Vector2(sx, 0), Vector2(sx, sy), Vector2(0, sy))     # -z
	_quad(p[5], p[1], p[2], p[6], Vector2(0, 0), Vector2(sz, 0), Vector2(sz, sy), Vector2(0, sy))     # +x
	_quad(p[0], p[4], p[7], p[3], Vector2(0, 0), Vector2(sz, 0), Vector2(sz, sy), Vector2(0, sy))     # -x
	_quad(p[7], p[6], p[2], p[3], Vector2(0, 0), Vector2(sx, 0), Vector2(sx, sz), Vector2(0, sz))     # +y
	_quad(p[0], p[1], p[5], p[4], Vector2(0, 0), Vector2(sx, 0), Vector2(sx, sz), Vector2(0, sz))     # -y


## Box spanning from a to b (both centre points of its end faces), with cross-section w x h.
func beam(a: Vector3, b: Vector3, w: float, h: float, up := Vector3.UP) -> void:
	var dir := b - a
	var len := dir.length()
	if len < 0.001:
		return
	var z := dir / len
	var x := up.cross(z).normalized()
	if x.length() < 0.5:
		x = Vector3.RIGHT
	var y := z.cross(x)
	box(Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, h, len))


## Upright cylinder (n sides) from base point `at` up `height` metres.
func cylinder(at: Vector3, radius: float, height: float, n := 8, top_radius := -1.0) -> void:
	var rt := radius if top_radius < 0.0 else top_radius
	var circ := TAU * radius
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var u0 := circ * i / n
		var u1 := circ * (i + 1) / n
		_quad(at + d1 * radius, at + d0 * radius, at + d0 * rt + Vector3(0, height, 0), at + d1 * rt + Vector3(0, height, 0),
			Vector2(u1, 0), Vector2(u0, 0), Vector2(u0, height), Vector2(u1, height))
		var top := at + Vector3(0, height, 0)
		for v in [[top, Vector2.ZERO], [top + d1 * rt, Vector2(d1.x, d1.z) * rt], [top + d0 * rt, Vector2(d0.x, d0.z) * rt]]:
			st.set_uv(v[1] / uv_m)
			st.add_vertex(v[0])


## Ribbon strip through `left`/`right` edge points (same count); v runs along the strip.
## `facing` is roughly the direction the visible side should face (e.g. Vector3.UP for a deck);
## the strip is flipped if needed, so callers never have to reason about winding.
func ribbon(left: PackedVector3Array, right: PackedVector3Array, facing := Vector3.ZERO) -> void:
	if facing != Vector3.ZERO and left.size() > 1:
		var n := (right[0] - left[0]).cross(left[1] - left[0])
		if n.dot(facing) < 0.0:
			var tmp := left
			left = right
			right = tmp
	var v := 0.0
	for i in left.size() - 1:
		var dv := (left[i + 1] - left[i]).length()
		var w0 := (right[i] - left[i]).length()
		var w1 := (right[i + 1] - left[i + 1]).length()
		_quad(left[i], right[i], right[i + 1], left[i + 1], Vector2(0, v), Vector2(w0, v), Vector2(w1, v + dv), Vector2(0, v + dv))
		v += dv


func commit(mat: Material) -> ArrayMesh:
	st.generate_normals()
	st.generate_tangents()
	st.set_material(mat)
	return st.commit()

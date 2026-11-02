extends RefCounted
## Real geometry for the village's buildings, one kind of world/village/village_plan.gd at a
## time: a rubble-stone plinth, whitewashed lime-plaster ground floors, upper floors of logs with
## interlocking corners (Blockbau), recessed windows with frames, mullions, sills, shutters and
## geranium boxes, wooden balconies with cut-out boards, low gable roofs with deep eaves,
## rafters, purlins on stepped brackets and bargeboards, chimneys; plus the church, the arcades
## of the Laubengasse and the covered bridge. Each building varies with its seed (timber tone,
## shutter paint, roof covering, which shutters are half open, ...).
##
## Pieces are built in the building's frame (front facing +z, origin at the footprint centre on
## the floor) with UVs in metres, so world/village/house.gdshader keeps one texel density on
## every piece. Geometry is merged per material and per CHUNK of the village: a few draw calls
## for the whole village, and the renderer can still skip chunks behind the camera. Small
## pieces (geraniums, glazing bars, log ends, cut-out boards, rafters, ...) go to a separate
## detail mesh per chunk that casts no shadow and is hidden from DETAIL_RANGE on.
## world/village/village_houses.gd builds it when the village loads; tools/bake_village.gd runs
## it too, for the Kenney props the buildings keep (stalls, banners, the water wheel).

const MAT_DIR := "res://world/village/materials/"
## Surfaces in this order; each is world/village/materials/house_<name>.tres.
const MATS := ["stone", "plaster", "wood", "boards", "paint", "shingles", "slate", "tiles", "glass", "flowers"]
enum { STONE, PLASTER, WOOD, BOARDS, PAINT, SHINGLES, SLATE, TILES, GLASS, FLOWERS }
## Patterns (UV2.x, house.gdshader).
const LOGS := 1.0
const FLAME_R := 2.0
const FLAME_L := 3.0
const LOUVRE := 4.0

const CHUNK := 96.0          # metres
const DETAIL_RANGE := 130.0  # metres from a chunk's centre at which its small pieces go
const FLOOR_H := 2.6         # ground storey
const UPPER_H := 2.4         # timber storeys (a whole number of log courses)
const COURSE := 0.2          # log course height, as house_wood.tres course_m
const STREAK_LEN := 1.6      # metres a rain streak runs down under a sill
const LOG_END := 0.2         # how far the log ends stick out at the corners
const SHUTTER_GAP := 0.03

## Colours are sRGB; _lin() makes the linear vertex colours house.gdshader multiplies by.
## Sun-tanned timber, from a younger honey brown to old dark brown.
const WOOD_TONES := [Color(0.7, 0.49, 0.31), Color(0.6, 0.4, 0.25), Color(0.51, 0.33, 0.21), Color(0.42, 0.27, 0.17), Color(0.34, 0.22, 0.15)]
## Weathered wooden shingles, silver grey to brown.
const SHINGLE_TONES := [Color(0.44, 0.4, 0.36), Color(0.5, 0.42, 0.34), Color(0.38, 0.35, 0.33), Color(0.47, 0.41, 0.37)]
const SHUTTER_PAINTS := [Color(0.22, 0.45, 0.26), Color(0.14, 0.34, 0.21), Color(0.68, 0.15, 0.11), Color(0.38, 0.49, 0.57), Color(0.86, 0.83, 0.74)]
const PLASTER_WHITES := [Color(0.91, 0.9, 0.86), Color(0.92, 0.89, 0.82), Color(0.89, 0.89, 0.87), Color(0.93, 0.88, 0.79)]
## The Laubengasse's coloured plaster (Bern's old town: sandstone, ochre, pale green and pink).
const ARCADE_PLASTERS := [Color(0.86, 0.8, 0.66), Color(0.93, 0.83, 0.6), Color(0.78, 0.84, 0.74), Color(0.93, 0.8, 0.74), Color(0.9, 0.88, 0.82)]
const WHITE_PAINT := Color(0.93, 0.92, 0.88)
const DARK_PAINT := Color(0.12, 0.11, 0.1)
const GOLD := Color(0.86, 0.66, 0.24)
const GERANIUMS := [Color(0.86, 0.06, 0.08), Color(0.8, 0.03, 0.1), Color(0.92, 0.16, 0.18), Color(0.94, 0.32, 0.46)]
const LEAVES := [Color(0.2, 0.38, 0.13), Color(0.26, 0.44, 0.15), Color(0.15, 0.31, 0.1)]


class Batch:
	var base := 0
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()


var errors: PackedStringArray = []
## Kenney kit props the buildings keep: [module, Transform3D in world space].
var props: Array = []
var rng := RandomNumberGenerator.new()
var _chunks := {}            # Vector2i -> Array of Batch, one per material, then the detail ones
var _centres := {}           # Vector2i -> [sum of building positions, count]
## While true, pieces go to the detail batches.
var detail := false
var _target: Array = []      # the chunk batches the current building goes to
var _cur: Array = []         # the current building's batches, in its own frame
var _local_props: Array = []
var _board: Array = []       # cut-out balcony board: [front polygon, triangle indices]

# The building being built.
var _w := 0.0                # footprint width (x)
var _d := 0.0                # footprint depth (z)
var _wood := Color.WHITE     # timber tone (linear)
var _style := {}             # window style (_window_style)


func _init() -> void:
	# Balcony board outline (metres, x across, y up): straight edges with a waisted notch on
	# both sides, so two neighbours cut out a vase between them.
	var h := 0.8
	var hw := 0.075
	var right := [Vector2(hw, 0.0), Vector2(hw, 0.24), Vector2(0.03, 0.33), Vector2(0.045, 0.4), Vector2(0.03, 0.47),
		Vector2(hw, 0.56), Vector2(hw, h)]
	var poly := PackedVector2Array()
	for p: Vector2 in right:
		poly.append(p)
	for i in range(right.size() - 1, -1, -1):
		poly.append(Vector2(-right[i].x, right[i].y))
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		errors.append("the balcony board outline does not triangulate")
	_board = [poly, tris]


# ---------------------------------------------------------------- public

## Adds one building: footprint centre `pos` on its floor (the lowest ground under the
## footprint, a little below it), front facing +z turned by `yaw`, `size` = (width, depth), the
## ground climbing up to `rise` metres above the floor under the footprint. False (with errors)
## for an unknown kind.
func add_building(kind: String, pos: Vector3, yaw: float, size: Vector2, seed_: int, rise: float) -> bool:
	rng.seed = seed_
	_w = size.x
	_d = size.y
	_begin(pos)
	var base := maxf(0.0, rise - 0.5)
	match kind:
		"chalet":
			_chalet(base, "")
		"bakery", "shop":
			_chalet(base, kind)
		"inn":
			_inn(base)
		"arcade":
			_arcade(base)
		"church":
			_church(base)
		"mill":
			_mill(base)
		"barn":
			_barn(base)
		"school":
			_school(base)
		"factory":
			_factory(base)
		"farmhouse":
			_farmhouse(base)
		_:
			errors.append("unknown building kind '%s'" % kind)
			_cur = []
			return false
	_end(Transform3D(Basis(Vector3.UP, yaw), pos))
	return true


## The covered wooden bridge: `cells` are the deck frames (origin on the road's centre line,
## +z along the road), each `cell_len` long; `half_width` from the centre line to its walls.
func add_bridge(cells: Array, cell_len: float, half_width: float) -> void:
	rng.seed = 1848
	_wood = _lin(WOOD_TONES[3])
	var pitch := atan2(1.95, half_width + 0.7)
	for k in cells.size():
		var xf: Transform3D = cells[k]
		_begin(xf.origin)
		_bridge_cell(k, cells.size(), cell_len, half_width, pitch)
		_end(xf)


## Per chunk (key Vector2i): {centre: Vector3, main: ArrayMesh, detail: ArrayMesh} (either
## mesh null when empty), vertices relative to the centre, a surface per material. Empty
## (with errors) if a material is missing.
func meshes() -> Dictionary:
	var mats: Array[Material] = []
	for name: String in MATS:
		var path := MAT_DIR + "house_%s.tres" % name
		var m: Material = load(path) if ResourceLoader.exists(path) else null
		if m == null:
			errors.append("missing material %s" % path)
			return {}
		mats.append(m)
	var out := {}
	for key: Vector2i in _chunks:
		var c: Array = _centres[key]
		var centre: Vector3 = c[0] / float(c[1])
		var to_local := Transform3D(Basis(), -centre)
		var parts := {"centre": centre, "main": null, "detail": null}
		for half in 2:
			var mesh := ArrayMesh.new()
			for m in MATS.size():
				var b: Batch = _chunks[key][m + half * MATS.size()]
				if b.v.is_empty():
					continue
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays(b, to_local, m != FLOWERS and m != GLASS))
				mesh.surface_set_material(mesh.get_surface_count() - 1, mats[m])
			if mesh.get_surface_count() > 0:
				parts["detail" if half == 1 else "main"] = mesh
		out[key] = parts
	return out


## Surface arrays of a batch moved by xf, with tangents for normal mapping when `tangents`.
static func _arrays(b: Batch, xf: Transform3D, tangents: bool) -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = xf * b.v
	arrays[Mesh.ARRAY_NORMAL] = b.n
	arrays[Mesh.ARRAY_TEX_UV] = b.uv
	arrays[Mesh.ARRAY_TEX_UV2] = b.uv2
	arrays[Mesh.ARRAY_COLOR] = b.c
	arrays[Mesh.ARRAY_INDEX] = b.idx
	if tangents:
		var st := SurfaceTool.new()
		st.create_from_arrays(arrays)
		st.generate_tangents()
		arrays = st.commit_to_arrays()
	return arrays


## Vertex count of everything built so far (main and detail).
func vertex_count() -> int:
	var n := 0
	for key in _chunks:
		for b: Batch in _chunks[key]:
			n += b.v.size()
	return n


# ---------------------------------------------------------------- batching

func _begin(pos: Vector3) -> void:
	var key := Vector2i(floori(pos.x / CHUNK), floori(pos.z / CHUNK))
	if not _chunks.has(key):
		var list := []
		for m in MATS.size() * 2:
			list.append(Batch.new())
		_chunks[key] = list
		_centres[key] = [Vector3.ZERO, 0]
	_centres[key][0] += pos
	_centres[key][1] += 1
	_target = _chunks[key]
	_cur = []
	for m in MATS.size() * 2:
		var b := Batch.new()
		b.base = (_target[m] as Batch).v.size()
		_cur.append(b)
	_local_props = []
	detail = false


func _end(xf: Transform3D) -> void:
	var rot := Transform3D(xf.basis, Vector3.ZERO)
	for m in _cur.size():
		var b: Batch = _cur[m]
		if b.v.is_empty():
			continue
		var t: Batch = _target[m]
		t.v.append_array(xf * b.v)
		t.n.append_array(rot * b.n)
		t.uv.append_array(b.uv)
		t.uv2.append_array(b.uv2)
		t.c.append_array(b.c)
		t.idx.append_array(b.idx)
	for p in _local_props:
		props.append([p[0], xf * (p[1] as Transform3D)])
	_cur = []


static func _lin(c: Color) -> Color:
	return c.srgb_to_linear()


## A random tone near `c` (linear), each channel scaled alike by 1 +- amount.
func _jit(c: Color, amount: float) -> Color:
	var k := 1.0 + rng.randf_range(-amount, amount)
	return Color(c.r * k, c.g * k, c.b * k, c.a)


# ---------------------------------------------------------------- primitives

## Quad a-b-c-d, counter-clockwise seen from its front, UVs in metres. sa..sd: rain streak per
## corner. The height in UV2.y is the corner's height in the building frame.
func _q(m: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2,
		col: Color, flag := 0.0, sa := 0.0, sb := 0.0, sc := 0.0, sd := 0.0) -> void:
	var bt: Batch = _cur[m + (MATS.size() if detail else 0)]
	var nrm := (b - a).cross(d - a).normalized()
	var i := bt.base + bt.v.size()
	bt.v.append(a)
	bt.v.append(b)
	bt.v.append(c)
	bt.v.append(d)
	bt.n.append(nrm)
	bt.n.append(nrm)
	bt.n.append(nrm)
	bt.n.append(nrm)
	bt.uv.append(ua)
	bt.uv.append(ub)
	bt.uv.append(uc)
	bt.uv.append(ud)
	bt.uv2.append(Vector2(flag, a.y))
	bt.uv2.append(Vector2(flag, b.y))
	bt.uv2.append(Vector2(flag, c.y))
	bt.uv2.append(Vector2(flag, d.y))
	bt.c.append(Color(col.r, col.g, col.b, sa))
	bt.c.append(Color(col.r, col.g, col.b, sb))
	bt.c.append(Color(col.r, col.g, col.b, sc))
	bt.c.append(Color(col.r, col.g, col.b, sd))
	# Clockwise: Godot's front face.
	bt.idx.append(i)
	bt.idx.append(i + 2)
	bt.idx.append(i + 1)
	bt.idx.append(i)
	bt.idx.append(i + 3)
	bt.idx.append(i + 2)


## Quad that faces `facing`, whichever way round its corners come.
func _qf(m: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2,
		col: Color, facing: Vector3, flag := 0.0) -> void:
	if (b - a).cross(d - a).dot(facing) < 0.0:
		_q(m, a, d, c, b, ua, ud, uc, ub, col, flag)
	else:
		_q(m, a, b, c, d, ua, ub, uc, ud, col, flag)


## Triangle a-b-c, counter-clockwise seen from its front.
func _tri(m: int, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, col: Color, flag := 0.0) -> void:
	var bt: Batch = _cur[m + (MATS.size() if detail else 0)]
	var nrm := (b - a).cross(c - a).normalized()
	var i := bt.base + bt.v.size()
	for p in [[a, ua], [b, ub], [c, uc]]:
		bt.v.append(p[0])
		bt.n.append(nrm)
		bt.uv.append(p[1])
		bt.uv2.append(Vector2(flag, (p[0] as Vector3).y))
		bt.c.append(Color(col.r, col.g, col.b, 0.0))
	bt.idx.append(i)
	bt.idx.append(i + 2)
	bt.idx.append(i + 1)


## Box of `size` centred on xf.origin along xf's axes. `skip` leaves faces out: 1 +x, 2 -x,
## 4 +y, 8 -y, 16 +z, 32 -z. `grain` (0 x, 1 y, 2 z) is the axis the texture's u runs along.
## `front` is the pattern of the +z face only (shutter stripes); `flag` that of every face.
func _box(m: int, xf: Transform3D, size: Vector3, col: Color, skip := 0, grain := 0, flag := 0.0, front := -1.0) -> void:
	var h := size * 0.5
	var p0 := xf * Vector3(-h.x, -h.y, -h.z)
	var p1 := xf * Vector3(h.x, -h.y, -h.z)
	var p2 := xf * Vector3(h.x, h.y, -h.z)
	var p3 := xf * Vector3(-h.x, h.y, -h.z)
	var p4 := xf * Vector3(-h.x, -h.y, h.z)
	var p5 := xf * Vector3(h.x, -h.y, h.z)
	var p6 := xf * Vector3(h.x, h.y, h.z)
	var p7 := xf * Vector3(-h.x, h.y, h.z)
	var sx := size.x
	var sy := size.y
	var sz := size.z
	var ff := flag if front < 0.0 else front
	if skip & 16 == 0:
		_box_face(m, p4, p5, p6, p7, sx, sy, grain == 1, col, ff)
	if skip & 32 == 0:
		_box_face(m, p1, p0, p3, p2, sx, sy, grain == 1, col, flag)
	if skip & 1 == 0:
		_box_face(m, p5, p1, p2, p6, sz, sy, grain == 1, col, flag)
	if skip & 2 == 0:
		_box_face(m, p0, p4, p7, p3, sz, sy, grain == 1, col, flag)
	if skip & 4 == 0:
		_box_face(m, p7, p6, p2, p3, sx, sz, grain == 2, col, flag)
	if skip & 8 == 0:
		_box_face(m, p0, p1, p5, p4, sx, sz, grain == 2, col, flag)


func _box_face(m: int, a: Vector3, b: Vector3, c: Vector3, d: Vector3, s: float, t: float, swap: bool, col: Color, flag: float) -> void:
	if swap:
		_q(m, a, b, c, d, Vector2(0, 0), Vector2(0, s), Vector2(-t, s), Vector2(-t, 0), col, flag)
	else:
		_q(m, a, b, c, d, Vector2(0, 0), Vector2(s, 0), Vector2(s, -t), Vector2(0, -t), col, flag)


## Box from a to b (centres of its end faces) with cross-section w (sideways) x h (`up`-ish).
func _beam(m: int, a: Vector3, b: Vector3, w: float, h: float, col: Color, up := Vector3.UP, skip := 0) -> void:
	var dir := b - a
	var len := dir.length()
	if len < 0.001:
		return
	var z := dir / len
	var x := up.cross(z)
	if x.length() < 0.01:
		x = Vector3.RIGHT
	x = x.normalized()
	var y := z.cross(x)
	_box(m, Transform3D(Basis(x, y, z), (a + b) * 0.5), Vector3(w, h, len), col, skip, 2)


## Small blob (an octahedron with round normals) for leaves and blossoms.
func _blob(m: int, c: Vector3, r: Vector3, col: Color) -> void:
	var bt: Batch = _cur[m + (MATS.size() if detail else 0)]
	var i := bt.base + bt.v.size()
	var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for d: Vector3 in dirs:
		bt.v.append(c + d * r)
		bt.n.append(d)
		bt.uv.append(Vector2.ZERO)
		bt.uv2.append(Vector2(0.0, c.y))
		bt.c.append(col)
	# Faces by octant: (x, y, z) counter-clockwise when x*y*z > 0, else (x, z, y); emitted clockwise.
	for sx in [0, 1]:
		for sy in [2, 3]:
			for sz in [4, 5]:
				var pos: bool = ((sx == 0) == (sy == 2)) == (sz == 4)
				if pos:
					bt.idx.append_array([i + sx, i + sz, i + sy])
				else:
					bt.idx.append_array([i + sx, i + sy, i + sz])


## Triangle that faces `facing`, whichever way round its corners come.
func _tf(m: int, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, col: Color, facing: Vector3, flag := 0.0) -> void:
	if (b - a).cross(c - a).dot(facing) < 0.0:
		_tri(m, a, c, b, ua, uc, ub, col, flag)
	else:
		_tri(m, a, b, c, ua, ub, uc, col, flag)


# ---------------------------------------------------------------- walls

## The four walls of the footprint: [left end seen from outside, outward normal, length].
## 0 front (+z), 1 right (+x), 2 back (-z), 3 left (-x).
func _sides(grow := 0.0) -> Array:
	var hw := _w * 0.5 + grow
	var hd := _d * 0.5 + grow
	return [
		[Vector3(-hw, 0, hd), Vector3.BACK, hw * 2.0],
		[Vector3(hw, 0, hd), Vector3.RIGHT, hd * 2.0],
		[Vector3(hw, 0, -hd), Vector3.FORWARD, hw * 2.0],
		[Vector3(-hw, 0, -hd), Vector3.LEFT, hd * 2.0],
	]


## Wall from `left` (its left end seen from outside, y ignored) for `length` metres, from y0 up
## to y1, facing `out`, with rectangular `openings` [u0, u1, v0, v1, ...] (metres from the left
## end and from y0). Cells under an opening get rain streaks. `vertical` turns the texture so
## its u runs up the wall (vertical boards).
func _wall(m: int, left: Vector3, out: Vector3, length: float, y0: float, y1: float, openings: Array, col: Color,
		flag := 0.0, u_off := 0.0, vertical := false) -> void:
	var dir := Vector3.UP.cross(out)
	var us := [0.0, length]
	var vs := [0.0, y1 - y0]
	for o in openings:
		us.append(clampf(o[0], 0.0, length))
		us.append(clampf(o[1], 0.0, length))
		vs.append(clampf(o[2], 0.0, y1 - y0))
		vs.append(clampf(o[3], 0.0, y1 - y0))
	us.sort()
	vs.sort()
	var base := Vector3(left.x, 0.0, left.z)
	for i in us.size() - 1:
		var u0: float = us[i]
		var u1: float = us[i + 1]
		if u1 - u0 < 0.002:
			continue
		var uc := (u0 + u1) * 0.5
		for j in vs.size() - 1:
			var v0: float = vs[j]
			var v1: float = vs[j + 1]
			if v1 - v0 < 0.002:
				continue
			var vc := (v0 + v1) * 0.5
			var hole := false
			var above := -1.0
			for o in openings:
				if uc > o[0] and uc < o[1]:
					if vc > o[2] and vc < o[3]:
						hole = true
						break
					if vc < o[2] and o[2] > 0.05:
						above = o[2] if above < 0.0 else minf(above, o[2])
			if hole:
				continue
			var a := base + dir * u0 + Vector3(0, y0 + v0, 0)
			var b := base + dir * u1 + Vector3(0, y0 + v0, 0)
			var c := base + dir * u1 + Vector3(0, y0 + v1, 0)
			var d := base + dir * u0 + Vector3(0, y0 + v1, 0)
			var s0 := 0.0
			var s1 := 0.0
			if above >= 0.0:
				s0 = clampf(1.0 - (above - v0) / STREAK_LEN, 0.0, 1.0)
				s1 = clampf(1.0 - (above - v1) / STREAK_LEN, 0.0, 1.0)
			var ua := Vector2(u_off + u0, -(y0 + v0))
			var ub := Vector2(u_off + u1, -(y0 + v0))
			var uc2 := Vector2(u_off + u1, -(y0 + v1))
			var ud := Vector2(u_off + u0, -(y0 + v1))
			if vertical:
				ua = Vector2(ua.y, ua.x)
				ub = Vector2(ub.y, ub.x)
				uc2 = Vector2(uc2.y, uc2.x)
				ud = Vector2(ud.y, ud.x)
			_q(m, a, b, c, d, ua, ub, uc2, ud, col, flag, s0, s0, s1, s1)


## The recess of an opening in a wall: jambs, head and (with `bottom`) the bottom, `depth` deep.
func _reveal(m: int, left: Vector3, out: Vector3, o: Array, y0: float, depth: float, col: Color, flag := 0.0, bottom := false) -> void:
	var dir := Vector3.UP.cross(out)
	var base := Vector3(left.x, 0.0, left.z)
	var yb := y0 + float(o[2])
	var yt := y0 + float(o[3])
	var lb := base + dir * float(o[0]) + Vector3(0, yb, 0)
	var rb := base + dir * float(o[1]) + Vector3(0, yb, 0)
	var rt := base + dir * float(o[1]) + Vector3(0, yt, 0)
	var lt := base + dir * float(o[0]) + Vector3(0, yt, 0)
	var inn := -out * depth
	var w: float = o[1] - o[0]
	_qf(m, lb, lt, lt + inn, lb + inn, Vector2(0, -yb), Vector2(0, -yt), Vector2(depth, -yt), Vector2(depth, -yb), col, dir, flag)
	_qf(m, rb, rt, rt + inn, rb + inn, Vector2(0, -yb), Vector2(0, -yt), Vector2(depth, -yt), Vector2(depth, -yb), col, -dir, flag)
	_qf(m, lt, rt, rt + inn, lt + inn, Vector2(0, 0), Vector2(w, 0), Vector2(w, depth), Vector2(0, depth), col, Vector3.DOWN, flag)
	if bottom:
		_qf(m, lb, rb, rb + inn, lb + inn, Vector2(0, 0), Vector2(w, 0), Vector2(w, depth), Vector2(0, depth), col, Vector3.UP, flag)


## The frame of an opening: origin at its bottom-left on the wall face, x right, y up, z out.
static func _frame(left: Vector3, out: Vector3, o: Array, y0: float) -> Transform3D:
	var dir := Vector3.UP.cross(out)
	return Transform3D(Basis(dir, Vector3.UP, out), Vector3(left.x, y0 + float(o[2]), left.z) + dir * float(o[0]))


## Window centres along a wall: `n` windows `w` wide spread evenly, or as many as fit `pitch`.
static func _spread(length: float, w: float, pitch: float, margin: float, n := -1) -> Array:
	if n < 0:
		n = int(floor((length - 2.0 * margin + pitch - w) / pitch))
	var out := []
	if n <= 0:
		return out
	var step := (length - 2.0 * margin) / n
	for i in n:
		out.append(margin + step * (i + 0.5))
	return out


## Openings moved up by dv (for a wall that starts dv lower than the storey's floor, pass -dv).
static func _shift(openings: Array, dv: float) -> Array:
	var out := []
	for side in openings:
		out.append(_shift_list(side, dv))
	return out


static func _shift_list(list: Array, dv: float) -> Array:
	var out := []
	for o in list:
		var c: Array = o.duplicate()
		c[2] = float(c[2]) + dv
		c[3] = float(c[3]) + dv
		out.append(c)
	return out


# ---------------------------------------------------------------- windows and doors

## The building's window look, picked once per building.
func _window_style(shutters_p: float, flowers_p: float) -> Dictionary:
	var paint: Color = SHUTTER_PAINTS[rng.randi_range(0, SHUTTER_PAINTS.size() - 1)]
	var kind := "plain"
	var r := rng.randf()
	if r < 0.3:
		kind = "flame"
	elif r < 0.55:
		kind = "louvre"
	return {
		"shutters": rng.randf() < shutters_p,
		"shutter_kind": kind,
		"shutter_col": _lin(paint),
		"frame_white": rng.randf() < 0.7,
		"flowers": flowers_p,
		"geranium": _lin(GERANIUMS[rng.randi_range(0, 1)]),
	}


## Window in opening `o` of a wall: frame, glass (with curtains), mullions, sill, and per the
## style: shutters (some half open) and a geranium box. `depth` of the recess; `sill_m` the
## sill's material.
func _window(left: Vector3, out: Vector3, o: Array, y0: float, depth: float, sill_m: int, shutters := true, flowers := true) -> void:
	var t := _frame(left, out, o, y0)
	var w: float = o[1] - o[0]
	var h: float = o[3] - o[2]
	var ft := 0.065
	var fd := 0.08
	var zf := -depth + fd * 0.5 + 0.02
	var fm := PAINT if _style["frame_white"] else WOOD
	var fc := _lin(WHITE_PAINT) if _style["frame_white"] else _jit(_wood, 0.05)
	_box(fm, t * Transform3D(Basis(), Vector3(ft * 0.5, h * 0.5, zf)), Vector3(ft, h, fd), fc, 32 | 2, 1)
	_box(fm, t * Transform3D(Basis(), Vector3(w - ft * 0.5, h * 0.5, zf)), Vector3(ft, h, fd), fc, 32 | 1, 1)
	_box(fm, t * Transform3D(Basis(), Vector3(w * 0.5, h - ft * 0.5, zf)), Vector3(w - 2.0 * ft, ft, fd), fc, 32 | 4 | 1 | 2)
	_box(fm, t * Transform3D(Basis(), Vector3(w * 0.5, ft * 0.5, zf)), Vector3(w - 2.0 * ft, ft, fd), fc, 32 | 8 | 1 | 2)
	# Glass: curtain style in COLOR.r, the room's shade in COLOR.g.
	var gz := zf - 0.015
	var curtain := rng.randf()
	_q(GLASS, t * Vector3(ft, ft, gz), t * Vector3(w - ft, ft, gz), t * Vector3(w - ft, h - ft, gz), t * Vector3(ft, h - ft, gz),
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(0.0 if curtain < 0.3 else curtain, rng.randf(), 0.0, 0.0))
	# Mullions: a vertical bar and two glazing bars (six panes), one for small windows.
	detail = true
	var mz := zf + 0.01
	var bar := 0.04
	_box(fm, t * Transform3D(Basis(), Vector3(w * 0.5, h * 0.5, mz)), Vector3(bar, h - 2.0 * ft, bar), fc, 32 | 4 | 8, 1)
	var rows := [0.5] if h < 0.9 else [0.36, 0.68]
	for f: float in rows:
		_box(fm, t * Transform3D(Basis(), Vector3(w * 0.5, ft + (h - 2.0 * ft) * f, mz)), Vector3(w - 2.0 * ft, bar, bar), fc, 32 | 1 | 2)
	detail = false
	# Sill, standing out of the wall; it covers the bottom of the recess.
	var sc := _lin(Color(0.8, 0.78, 0.74)) if sill_m == STONE else _jit(_wood, 0.05)
	_box(sill_m, t * Transform3D(Basis(), Vector3(w * 0.5, -0.03, (0.07 - depth) * 0.5)), Vector3(w + 0.12, 0.06, depth + 0.07), sc)
	if shutters and _style["shutters"]:
		_shutters(t, w, h)
	if flowers and rng.randf() < float(_style["flowers"]):
		var bw := w + 0.16
		var painted := rng.randf() < 0.3
		var box_c: Color = _style["shutter_col"] if painted else _jit(_wood, 0.08)
		_box(PAINT if painted else WOOD, t * Transform3D(Basis(), Vector3(w * 0.5, -0.17, 0.14)), Vector3(bw, 0.2, 0.22), box_c, 32)
		_geraniums(t * Transform3D(Basis(), Vector3(w * 0.5, -0.07, 0.14)), bw - 0.04, 0.16)


## Two shutter leaves beside an opening (frame t, w x h): open flat against the wall, now and
## then half open. Flame stripes lean opposite ways on the two leaves.
func _shutters(t: Transform3D, w: float, h: float) -> void:
	var lw := w * 0.5 + 0.02
	var kind: String = _style["shutter_kind"]
	var col := _jit(_style["shutter_col"], 0.04)
	var th := 0.035
	for side in [-1, 1]:
		var swing := 0.0
		if rng.randf() < 0.12:
			swing = rng.randf_range(0.5, 1.2)
		# Hinged at the opening's edge on the wall face; flat open it lies on the wall beside the
		# opening, `swing` turns it out from the wall.
		var hinge := Vector3(0.0 if side < 0 else w, h * 0.5, 0.012)
		var b := Basis(Vector3.UP, swing * float(-side))
		var c := hinge + b * Vector3(side * (lw * 0.5 + SHUTTER_GAP), 0, th * 0.5)
		var front := 0.0
		if kind == "flame":
			front = FLAME_R if side < 0 else FLAME_L
		elif kind == "louvre":
			front = LOUVRE
		_box(PAINT, t * Transform3D(b, c), Vector3(lw, h + 0.04, th), col, 0, 1, 0.0, front)


## A row of geraniums `length` long along xf's x on a box top: leafy clumps, red blossoms over
## them and a few trailing stems hanging over the front (+z).
func _geraniums(xf: Transform3D, length: float, depth: float) -> void:
	var red: Color = _style.get("geranium", _lin(GERANIUMS[0]))
	var was := detail
	detail = true
	var n := maxi(2, int(length / 0.15))
	for i in n:
		var x := -length * 0.5 + length * (i + 0.5) / n + rng.randf_range(-0.02, 0.02)
		var leaf := _lin(LEAVES[rng.randi_range(0, LEAVES.size() - 1)])
		_blob(FLOWERS, xf * Vector3(x, 0.07, rng.randf_range(-0.03, 0.03)), Vector3(0.085, 0.07, depth * 0.55), leaf)
		var bloom := red if rng.randf() < 0.85 else _lin(GERANIUMS[rng.randi_range(2, 3)])
		_blob(FLOWERS, xf * Vector3(x + rng.randf_range(-0.03, 0.03), rng.randf_range(0.15, 0.2), rng.randf_range(-0.02, 0.06)), Vector3(0.06, 0.05, 0.06), bloom)
		if rng.randf() < 0.55:
			_blob(FLOWERS, xf * Vector3(x + 0.05, rng.randf_range(0.12, 0.17), rng.randf_range(-0.05, 0.02)), Vector3(0.05, 0.045, 0.05), bloom)
		if rng.randf() < 0.45:
			var hang := rng.randf_range(0.12, 0.3)
			_blob(FLOWERS, xf * Vector3(x, -hang * 0.5, depth * 0.55 + 0.03), Vector3(0.05, hang * 0.6, 0.04), leaf)
			if rng.randf() < 0.6:
				_blob(FLOWERS, xf * Vector3(x, -hang, depth * 0.55 + 0.05), Vector3(0.045, 0.04, 0.045), bloom)
	detail = was


## A wooden door in opening `o` (from the floor): plank leaf, frame, a stone step in front.
func _door(left: Vector3, out: Vector3, o: Array, y0: float, depth: float, step := true) -> void:
	var t := _frame(left, out, o, y0)
	var w: float = o[1] - o[0]
	var h: float = o[3] - o[2]
	var fc := _jit(_wood, 0.06)
	var painted := rng.randf() < 0.35
	var leaf: Color = _style.get("shutter_col", fc) if painted else _lin(Color(0.55, 0.36, 0.22))
	_box(PAINT if painted else BOARDS, t * Transform3D(Basis(), Vector3(w * 0.5, h * 0.5, -depth + 0.06)), Vector3(w - 0.1, h - 0.05, 0.05), leaf, 32, 1)
	for x: float in [0.05, w - 0.05]:
		_box(WOOD, t * Transform3D(Basis(), Vector3(x, h * 0.5, -depth + 0.07)), Vector3(0.1, h, 0.1), fc, 32, 1)
	_box(WOOD, t * Transform3D(Basis(), Vector3(w * 0.5, h - 0.05, -depth + 0.07)), Vector3(w - 0.2, 0.1, 0.1), fc, 32)
	if step:
		_box(STONE, t * Transform3D(Basis(), Vector3(w * 0.5, -0.13, 0.25 - depth * 0.5)), Vector3(w + 0.5, 0.3, 0.5 + depth), _lin(Color(0.9, 0.9, 0.88)), 32)


## A shop window: big panes with thin bars, a wooden frame, no shutters.
func _shop_window(left: Vector3, out: Vector3, o: Array, y0: float, depth: float) -> void:
	var t := _frame(left, out, o, y0)
	var w: float = o[1] - o[0]
	var h: float = o[3] - o[2]
	var fc := _jit(_wood, 0.05)
	var zf := -depth + 0.06
	for x: float in [0.05, w - 0.05]:
		_box(WOOD, t * Transform3D(Basis(), Vector3(x, h * 0.5, zf)), Vector3(0.1, h, 0.1), fc, 32, 1)
	_box(WOOD, t * Transform3D(Basis(), Vector3(w * 0.5, h - 0.05, zf)), Vector3(w - 0.2, 0.1, 0.1), fc, 32)
	_box(WOOD, t * Transform3D(Basis(), Vector3(w * 0.5, 0.06, zf)), Vector3(w - 0.2, 0.12, 0.1), fc, 32)
	var n := maxi(2, int(round(w / 0.8)))
	for i in range(1, n):
		_box(WOOD, t * Transform3D(Basis(), Vector3(w * i / n, h * 0.5, zf + 0.01)), Vector3(0.05, h - 0.2, 0.06), fc, 32 | 4 | 8, 1)
	_box(WOOD, t * Transform3D(Basis(), Vector3(w * 0.5, h * 0.72, zf + 0.01)), Vector3(w - 0.2, 0.05, 0.06), fc, 32 | 1 | 2)
	_q(GLASS, t * Vector3(0.1, 0.12, zf - 0.02), t * Vector3(w - 0.1, 0.12, zf - 0.02), t * Vector3(w - 0.1, h - 0.1, zf - 0.02),
		t * Vector3(0.1, h - 0.1, zf - 0.02), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(0.0, 0.9, 0.0))
	_box(STONE, t * Transform3D(Basis(), Vector3(w * 0.5, -0.03, (0.07 - depth) * 0.5)), Vector3(w + 0.1, 0.06, depth + 0.07), _lin(Color(0.8, 0.78, 0.74)))


# ---------------------------------------------------------------- storeys

## One storey of the footprint from y0 to y1 in material m (pattern flag), with openings per
## side (4 Arrays of [u0, u1, v0, v1, type, shutters?, flowers?], v from y0); type "w" window,
## "d" door, "s" shop window. Builds the walls, the recesses and what fills each opening.
func _storey(m: int, y0: float, y1: float, openings: Array, col: Color, flag := 0.0, depth := 0.2,
		sill_m := STONE, flowers := true) -> void:
	var sides := _sides()
	var u_off := 0.0
	for k in 4:
		var s: Array = sides[k]
		var ops: Array = openings[k]
		_wall(m, s[0], s[1], s[2], y0, y1, ops, col, flag, u_off)
		for o in ops:
			_reveal(m, s[0], s[1], o, y0, depth, col, flag)
			if o[4] == "d":
				_door(s[0], s[1], o, y0, depth)
			elif o[4] == "s":
				_shop_window(s[0], s[1], o, y0, depth)
			else:
				_window(s[0], s[1], o, y0, depth, sill_m, o.size() < 6 or o[5], flowers and (o.size() < 7 or o[6]))
		u_off += float(s[2])


## Openings for one storey, v measured from the storey's floor: per side windows w x h at sill
## height `sill`, spread at `pitch` (sides_n caps the count per side, -1 = as many as fit).
## `door` [side, u centre] puts a door_w x door_h door there instead of the windows it meets.
func _openings(w: float, h: float, sill: float, pitch: float, door := [], sides_n := [-1, -1, -1, -1], door_w := 1.0, door_h := 2.05) -> Array:
	var out := []
	var dims := [_w, _d, _w, _d]
	for k in 4:
		var list := []
		var n: int = sides_n[k]
		if n != 0:
			for c: float in _spread(dims[k], w, pitch, 0.7, n):
				list.append([c - w * 0.5, c + w * 0.5, sill, sill + h, "w"])
		if not door.is_empty() and int(door[0]) == k:
			var dc: float = door[1]
			var keep := []
			for o in list:
				if absf((o[0] + o[1]) * 0.5 - dc) > (w + door_w) * 0.5 + 0.15:
					keep.append(o)
			keep.append([dc - door_w * 0.5, dc + door_w * 0.5, 0.0, door_h, "d"])
			list = keep
		out.append(list)
	return out


## Interlocking log ends at the four corners from y0 to y1: on even courses the front and back
## walls' logs stick out, on odd courses the side walls'.
func _log_corners(y0: float, y1: float) -> void:
	var hw := _w * 0.5
	var hd := _d * 0.5
	var t := 0.16
	var k0 := int(ceil(y0 / COURSE - 0.01))
	var k1 := int(floor(y1 / COURSE + 0.01))
	detail = true
	for k in range(k0, k1):
		var y := (k + 0.5) * COURSE
		var col := _jit(_wood, 0.1)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				if k % 2 == 0:
					var c := Vector3(sx * (hw + LOG_END * 0.5 - 0.02), y, sz * (hd - t * 0.5))
					_box(WOOD, Transform3D(Basis(), c), Vector3(LOG_END + 0.04, COURSE - 0.012, t), col, 4 | 8 | (2 if sx > 0.0 else 1))
				else:
					var c := Vector3(sx * (hw - t * 0.5), y, sz * (hd + LOG_END * 0.5 - 0.02))
					_box(WOOD, Transform3D(Basis(), c), Vector3(t, COURSE - 0.012, LOG_END + 0.04), col, 4 | 8 | (32 if sz > 0.0 else 16), 2)
	detail = false


## Stone plinth round the footprint from below the ground up to `top`, standing 6 cm proud of
## the walls, its cap, and the doors of `openings` (v from `base`, the storey's floor) cut out.
func _plinth(base: float, top: float, openings: Array) -> void:
	var g := 0.06
	var y0 := -0.8
	var sides := _sides(g)
	var col := _jit(_lin(Color(1.0, 0.98, 0.95)), 0.06)
	var u_off := 0.0
	for k in 4:
		var s: Array = sides[k]
		var out: Vector3 = s[1]
		var length: float = s[2]
		var ops := []
		for o in openings[k]:
			if o[4] == "d" and base + float(o[2]) < top:
				ops.append([float(o[0]) + g, float(o[1]) + g, base + float(o[2]) - y0, top - y0, "d"])
		_wall(STONE, s[0], out, length, y0, top, ops, col, 0.0, u_off)
		for o in ops:
			_reveal(STONE, s[0], out, o, y0, g, col)
		u_off += length
		# Cap: the top of the proud band, between the door cuts.
		var dir := Vector3.UP.cross(out)
		var a: Vector3 = Vector3((s[0] as Vector3).x, top, (s[0] as Vector3).z)
		var cuts := [0.0]
		for o in ops:
			cuts.append(float(o[0]))
			cuts.append(float(o[1]))
		cuts.append(length)
		for i in range(0, cuts.size() - 1, 2):
			var u0: float = cuts[i]
			var u1: float = cuts[i + 1]
			if u1 - u0 < 0.01:
				continue
			# The cap's inner edge runs along the wall, shortened at the corners by g.
			var i0 := a + dir * (u0 + (g if u0 < 0.001 else 0.0)) - out * g
			var i1 := a + dir * (u1 - (g if u1 > length - 0.001 else 0.0)) - out * g
			_qf(STONE, a + dir * u0, a + dir * u1, i1, i0, Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, g), Vector2(u0, g), col, Vector3.UP)


## Timber sill beam round the footprint at height y (where the timber storeys start).
func _sill_beam(y: float, h := 0.22, proud := 0.05) -> void:
	var col := _jit(_wood, 0.05)
	var hw := _w * 0.5
	var hd := _d * 0.5
	_box(WOOD, Transform3D(Basis(), Vector3(0, y + h * 0.5, hd + proud * 0.5)), Vector3(_w + 2.0 * proud, h, proud), col, 32)
	_box(WOOD, Transform3D(Basis(), Vector3(0, y + h * 0.5, -hd - proud * 0.5)), Vector3(_w + 2.0 * proud, h, proud), col, 16)
	_box(WOOD, Transform3D(Basis(), Vector3(hw + proud * 0.5, y + h * 0.5, 0)), Vector3(proud, h, _d), col, 2 | 16 | 32, 2)
	_box(WOOD, Transform3D(Basis(), Vector3(-hw - proud * 0.5, y + h * 0.5, 0)), Vector3(proud, h, _d), col, 1 | 16 | 32, 2)


## Row of carved dentils (Würfelfries) along the front at height y, `length` wide, under a rail.
func _dentils(y: float, z: float, length: float, col: Color) -> void:
	detail = true
	var n := int(length / 0.2)
	for i in n:
		var x := -length * 0.5 + (i + 0.5) * length / n
		var deep := 0.07 if i % 2 == 0 else 0.045
		_box(WOOD, Transform3D(Basis(), Vector3(x, y, z + deep * 0.5)), Vector3(0.09, 0.09, deep), col, 32 | 4)
	detail = false
	_box(WOOD, Transform3D(Basis(), Vector3(0, y + 0.075, z + 0.035)), Vector3(length, 0.06, 0.07), col, 32)


# ---------------------------------------------------------------- roofs

## Gable roof with its ridge along z over the footprint, eaves at y_eave on the side walls.
## `pitch` (radians), overhangs past the side walls (o_side) and the gables (o_front, o_back),
## covering `cover` tinted `cover_col`. Builds the slab (covering on top, boards under), fascia
## and bargeboards, a ridge cap, rafters under the side eaves, purlins on stepped brackets under
## the gable overhangs and the two gable walls (material gm, tint gcol, pattern gflag) with
## `gable_windows` small windows each. Returns the height of the ridge's top.
func _gable_roof(y_eave: float, pitch: float, o_side: float, o_front: float, o_back: float, cover: int, cover_col: Color,
		gm: int, gcol: Color, gflag: float, gable_windows := 2) -> float:
	var hw := _w * 0.5
	var hd := _d * 0.5
	var tp := tan(pitch)
	var cp := cos(pitch)
	var tv := 0.22 / cp                 # slab thickness, measured vertically
	var xe := hw + o_side
	var zf := hd + o_front
	var zb := -hd - o_back
	var y_ridge := y_eave + hw * tp
	var y_e := y_eave - o_side * tp     # underside at the eave edge
	var rc := _jit(_wood, 0.06)
	var top := Vector3(0, tv, 0)
	var slope := xe / cp
	for side: float in [-1.0, 1.0]:
		var nrm := Vector3(side * sin(pitch), cp, 0.0)
		var e0 := Vector3(side * xe, y_e, zb)
		var e1 := Vector3(side * xe, y_e, zf)
		var r1 := Vector3(0, y_ridge, zf)
		var r0 := Vector3(0, y_ridge, zb)
		# Covering on top, u along the ridge, v down the slope from it.
		_qf(cover, e0 + top, e1 + top, r1 + top, r0 + top, Vector2(zb, slope), Vector2(zf, slope), Vector2(zf, 0), Vector2(zb, 0), cover_col, nrm)
		# Boards underneath (soffit), running down the slope.
		_qf(BOARDS, e0, e1, r1, r0, Vector2(slope, zb), Vector2(slope, zf), Vector2(0, zf), Vector2(0, zb), rc, -nrm)
		# Plumb fascia board along the eave.
		_box(WOOD, Transform3D(Basis(), Vector3(side * (xe + 0.025), y_e + tv * 0.5 - 0.03, (zf + zb) * 0.5)), Vector3(0.05, tv + 0.1, zf - zb + 0.1), rc, 0, 2)
		# Bargeboards up both verges.
		for gz: float in [zf, zb]:
			var a := Vector3(side * (xe + 0.05), y_e, gz + signf(gz) * 0.03)
			var b := Vector3(0, y_ridge, gz + signf(gz) * 0.03)
			_box(WOOD, Transform3D(Basis(Vector3.BACK, -side * pitch), (a + b) * 0.5 + Vector3(0, tv * 0.5 - 0.05, 0)), Vector3(a.distance_to(b) + 0.06, tv + 0.16, 0.06), rc, 0, 0)
		# Rafters under the side eave, from inside the wall out to the fascia.
		var nz := maxi(1, int((zf - zb - 0.6) / 0.9))
		var down := Vector3(0, -0.07 / cp, 0)
		detail = true
		for i in nz + 1:
			var z := zb + 0.3 + (zf - zb - 0.6) * i / nz
			var a := Vector3(side * (hw - 0.1), y_eave + 0.1 * tp, z) + down
			var b := Vector3(side * (xe - 0.03), y_e + 0.03 * tp, z) + down
			_beam(WOOD, a, b, 0.1, 0.13, rc, Vector3.UP, 4 | 32)
		detail = false
	# Ridge cap.
	_box(cover, Transform3D(Basis(), Vector3(0, y_ridge + tv + 0.03, (zf + zb) * 0.5)), Vector3(0.3, 0.08, zf - zb + 0.06), cover_col * 0.8, 0, 2)
	# Purlins under the gable overhangs, on stepped brackets at the wall.
	for gz: float in [1.0, -1.0]:
		var o := o_front if gz > 0.0 else o_back
		if o < 0.3:
			continue
		for px: float in [0.0, -hw * 0.5, hw * 0.5, -hw + 0.12, hw - 0.12]:
			var yu := y_eave + (hw - absf(px)) * tp
			var z1 := gz * (hd + o - 0.1)
			_box(WOOD, Transform3D(Basis(), Vector3(px, yu - 0.11, (gz * hd + z1) * 0.5)), Vector3(0.16, 0.22, o - 0.1), rc, 4 | (32 if gz > 0.0 else 16), 2)
			var steps := 3 if absf(px) < hw - 0.5 else 2
			for k in steps:
				var len := o * (0.7 - 0.2 * k)
				_box(WOOD, Transform3D(Basis(), Vector3(px, yu - 0.22 - 0.15 * (k + 0.5), gz * (hd + len * 0.5))), Vector3(0.14, 0.15, len), rc, 32 if gz > 0.0 else 16, 2)
	# Gable walls.
	var gh := y_ridge - y_eave
	for gz: float in [1.0, -1.0]:
		var ops := []
		if gable_windows > 0:
			var gw := 0.7
			var gwh := 0.9
			var gy := 0.35
			var room := (gh - gy - gwh) / tp - 0.15
			var spread := minf(1.6, room * 2.0 - gw - 0.3)
			for i in gable_windows:
				var cx := 0.0 if gable_windows == 1 else lerpf(-spread * 0.5, spread * 0.5, float(i) / (gable_windows - 1))
				if absf(cx) + gw * 0.5 < room:
					ops.append([cx - gw * 0.5, cx + gw * 0.5, gy, gy + gwh])
		_gable_wall(gz, y_eave, tp, gh, ops, gm, gcol, gflag)
	return y_ridge + tv


## Gable triangle on the front (gz 1) or back (-1) wall from y_eave up under the roof, as
## horizontal bands split round the openings (x from the centre, v from y_eave).
func _gable_wall(gz: float, y_eave: float, tp: float, gh: float, ops: Array, m: int, col: Color, flag: float) -> void:
	var hw := _w * 0.5
	var z := gz * _d * 0.5
	var out := Vector3(0, 0, gz)
	var vs := [0.0, gh]
	for o in ops:
		vs.append(o[2])
		vs.append(o[3])
	vs.sort()
	for j in vs.size() - 1:
		var v0: float = vs[j]
		var v1: float = vs[j + 1]
		if v1 - v0 < 0.002:
			continue
		var vc := (v0 + v1) * 0.5
		var cuts := []
		for o in ops:
			if vc > o[2] and vc < o[3]:
				cuts.append(o)
		cuts.sort_custom(func(a, b): return a[0] < b[0])
		var edges := [-INF]
		for c in cuts:
			edges.append(c[0])
			edges.append(c[1])
		edges.append(INF)
		for i in range(0, edges.size(), 2):
			var lo: float = edges[i]
			var hi: float = edges[i + 1]
			var l0 := -(hw - v0 / tp) if lo == -INF else lo
			var l1 := -(hw - v1 / tp) if lo == -INF else lo
			var r0 := (hw - v0 / tp) if hi == INF else hi
			var r1 := (hw - v1 / tp) if hi == INF else hi
			var a := Vector3(l0, y_eave + v0, z)
			var b := Vector3(r0, y_eave + v0, z)
			var c := Vector3(r1, y_eave + v1, z)
			var d := Vector3(l1, y_eave + v1, z)
			var ua := Vector2(l0 * gz, -(y_eave + v0))
			var ub := Vector2(r0 * gz, -(y_eave + v0))
			var uc := Vector2(r1 * gz, -(y_eave + v1))
			var ud := Vector2(l1 * gz, -(y_eave + v1))
			if r1 - l1 < 0.002:
				_tf(m, a, b, c, ua, ub, uc, col, out, flag)
			else:
				_qf(m, a, b, c, d, ua, ub, uc, ud, col, out, flag)
	# The windows in the gable (u from the wall's left end seen from outside).
	var left := Vector3(-hw * gz, 0, z)
	for o in ops:
		var u0: float = (o[0] + hw) if gz > 0.0 else (hw - o[1])
		var u1: float = (o[1] + hw) if gz > 0.0 else (hw - o[0])
		var wo := [u0, u1, o[2], o[3], "w"]
		_reveal(m, left, out, wo, y_eave, 0.14, col, flag)
		_window(left, out, wo, y_eave, 0.14, WOOD, true, false)


## Stone (or plaster) chimney through the roof at (x, z), from below the roof to `top`, with a
## cap slab on little piers.
func _chimney(x: float, z: float, from_y: float, top: float, plaster := false) -> void:
	var m := PLASTER if plaster else STONE
	var col := _lin(PLASTER_WHITES[0]) if plaster else _jit(_lin(Color(0.95, 0.93, 0.9)), 0.05)
	var s := 0.62
	var cap := _lin(Color(0.62, 0.62, 0.6))
	_box(m, Transform3D(Basis(), Vector3(x, (from_y + top) * 0.5, z)), Vector3(s, top - from_y, s), col, 8)
	_box(STONE, Transform3D(Basis(), Vector3(x, top + 0.04, z)), Vector3(s + 0.14, 0.08, s + 0.14), cap)
	_box(STONE, Transform3D(Basis(), Vector3(x, top + 0.3, z)), Vector3(s + 0.06, 0.08, s + 0.06), cap)
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		_box(STONE, Transform3D(Basis(), Vector3(x + c.x * s * 0.32, top + 0.17, z + c.y * s * 0.32)), Vector3(0.1, 0.18, 0.1), cap, 4 | 8)


## Wooden balcony across the front at floor height y, out `depth` from the wall, `length` wide:
## deck, joists on diagonal braces, cut-out board balustrade with a handrail and geraniums.
func _balcony(y: float, depth: float, length: float, flowers := 0.9) -> void:
	var hd := _d * 0.5
	var col := _jit(_wood, 0.05)
	var light := Color(col.r * 1.15, col.g * 1.12, col.b * 1.1)
	var z0 := hd
	var z1 := hd + depth
	_box(BOARDS, Transform3D(Basis(), Vector3(0, y - 0.07, (z0 + z1) * 0.5)), Vector3(length, 0.14, depth), col, 32)
	var nj := maxi(2, int(length / 1.6) + 1)
	for i in nj:
		var x := -length * 0.5 + 0.15 + (length - 0.3) * i / (nj - 1)
		_box(WOOD, Transform3D(Basis(), Vector3(x, y - 0.22, (z0 + z1 - 0.06) * 0.5)), Vector3(0.12, 0.16, depth - 0.06), col, 32, 2)
		_beam(WOOD, Vector3(x, y - 1.05, z0 + 0.05), Vector3(x, y - 0.3, z0 + depth * 0.62), 0.1, 0.12, col)
	# Balustrade on the front and both ends: [from, to, outward].
	var runs := [[Vector3(-length * 0.5, y, z1 - 0.05), Vector3(length * 0.5, y, z1 - 0.05), Vector3.BACK],
		[Vector3(-length * 0.5 + 0.04, y, z0), Vector3(-length * 0.5 + 0.04, y, z1 - 0.05), Vector3.LEFT],
		[Vector3(length * 0.5 - 0.04, y, z1 - 0.05), Vector3(length * 0.5 - 0.04, y, z0), Vector3.RIGHT]]
	for run in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var out: Vector3 = run[2]
		var dir := (b - a).normalized()
		var len := a.distance_to(b)
		_beam(WOOD, a + Vector3(0, 0.07, 0), b + Vector3(0, 0.07, 0), 0.07, 0.1, col)
		_beam(WOOD, a + Vector3(0, 0.95, 0) + out * 0.01, b + Vector3(0, 0.95, 0) + out * 0.01, 0.13, 0.08, col)
		var n := int(len / 0.15)
		var basis := Basis(dir, Vector3.UP, out)
		detail = true
		for i in n:
			_board_piece(Transform3D(basis, a + dir * (len * (i + 0.5) / n) + Vector3(0, 0.12, 0)), light)
		detail = false
		if out == Vector3.BACK and rng.randf() < flowers:
			var fb := Transform3D(basis, (a + b) * 0.5 + Vector3(0, 0.78, 0) + out * 0.17)
			_box(WOOD, fb, Vector3(len - 0.3, 0.2, 0.22), col, 32)
			_geraniums(fb * Transform3D(Basis(), Vector3(0, 0.1, 0)), len - 0.34, 0.18)


## One cut-out balustrade board (front and back faces of the outline) at xf, 2.5 cm thick.
func _board_piece(xf: Transform3D, col: Color) -> void:
	var poly: PackedVector2Array = _board[0]
	var tris: PackedInt32Array = _board[1]
	var bt: Batch = _cur[WOOD + (MATS.size() if detail else 0)]
	for face: float in [1.0, -1.0]:
		var i := bt.base + bt.v.size()
		var nrm := xf.basis * Vector3(0, 0, face)
		for p: Vector2 in poly:
			var v := xf * Vector3(p.x, p.y, face * 0.0125)
			bt.v.append(v)
			bt.n.append(nrm)
			bt.uv.append(Vector2(p.y, p.x))
			bt.uv2.append(Vector2(0.0, v.y))
			bt.c.append(col)
		# The outline runs counter-clockwise seen from +z; the front face is emitted clockwise.
		for k in range(0, tris.size(), 3):
			if face > 0.0:
				bt.idx.append_array([i + tris[k], i + tris[k + 2], i + tris[k + 1]])
			else:
				bt.idx.append_array([i + tris[k], i + tris[k + 1], i + tris[k + 2]])


# ---------------------------------------------------------------- building kinds

## Roof covering [material, tint]: wooden shingles, slate or clay tiles with these odds.
func _roof_cover(shingles_p: float, slate_p: float) -> Array:
	var r := rng.randf()
	if r < shingles_p:
		return [SHINGLES, _shingles()]
	if r < shingles_p + slate_p:
		return [SLATE, _jit(Color(1, 1, 1), 0.1)]
	return [TILES, _jit(Color(1, 1, 1), 0.12)]


## A weathered shingle tone (linear) for this building.
func _shingles() -> Color:
	return _jit(_lin(SHINGLE_TONES[rng.randi_range(0, SHINGLE_TONES.size() - 1)]), 0.1)


## Ground floor openings of the trade houses: the doors of `side` kept, shop windows between.
func _shop_front(side: Array) -> Array:
	var doors := []
	for o in side:
		if o[4] == "d":
			doors.append(o)
	doors.sort_custom(func(a, b): return a[0] < b[0])
	var out := doors.duplicate()
	var x0 := 0.6
	for o in doors:
		if float(o[0]) - 0.3 - x0 > 1.2:
			out.append([x0, float(o[0]) - 0.3, 0.6, 2.2, "s"])
		x0 = float(o[1]) + 0.3
	if _w - 0.6 - x0 > 1.2:
		out.append([x0, _w - 0.6, 0.6, 2.2, "s"])
	return out


## Bernese chalet: a stone plinth, the ground floor in plaster (or logs), one or two log storeys
## with shutters and geraniums, a balcony across the gable front, low roof with deep eaves.
## The bakery and the shops get shop windows (and keep their Kenney stall).
func _chalet(base: float, trade: String) -> void:
	_wood = _lin(WOOD_TONES[rng.randi_range(0, WOOD_TONES.size() - 1)]).lerp(_lin(WOOD_TONES[rng.randi_range(0, WOOD_TONES.size() - 1)]), rng.randf())
	_style = _window_style(0.8, 0.75)
	var plaster := _lin(PLASTER_WHITES[rng.randi_range(0, PLASTER_WHITES.size() - 1)])
	var plinth := base + rng.randf_range(0.65, 0.9)
	var floors := 2 if rng.randf() < 0.65 else 3
	var ground_logs := trade == "" and rng.randf() < 0.25
	var g_top := base + FLOOR_H
	var door_u := 1.0 if trade == "shop" else rng.randf_range(_w * 0.2, _w * 0.8)
	var ground := _openings(0.9, 1.1, 0.95, 1.9, [0, door_u], [-1, 2, 2, 2])
	if trade != "":
		ground[0] = _shop_front(ground[0])
	_plinth(base, plinth, ground)
	var gops := _shift(ground, base - plinth)
	if ground_logs:
		_storey(WOOD, plinth, g_top, gops, _wood, LOGS, 0.16, WOOD)
		_log_corners(plinth, g_top)
	else:
		_storey(PLASTER, plinth, g_top, gops, plaster, 0.0, 0.22, STONE, rng.randf() < 0.5)
	var y := g_top
	_sill_beam(y)
	y += 0.22
	var balcony := trade == "" and rng.randf() < 0.75
	for f in range(1, floors):
		var h := UPPER_H - (0.22 if f == 1 else 0.0)
		var ups := _openings(0.85, 1.15, 0.8, 1.75, [], [-1, 2, 2, 2])
		if balcony and f == 1:
			# A balcony door in the middle of the front.
			var keep := []
			for o in ups[0]:
				if absf((o[0] + o[1]) * 0.5 - _w * 0.5) > 1.0:
					keep.append(o)
			keep.append([_w * 0.5 - 0.5, _w * 0.5 + 0.5, 0.05, 2.05, "w", false, false])
			ups[0] = keep
		if trade != "" and f == 1:
			# The shop's name board hangs here: no flower boxes on the front.
			for o in ups[0]:
				o.append_array([true, false])
		_storey(WOOD, y, y + h, ups, _wood, LOGS, 0.16, WOOD)
		_log_corners(y, y + h)
		if balcony and f == 1:
			_balcony(y, 1.15, _w + 0.5)
		y += h
	var cover := _roof_cover(0.55, 0.25)
	var pitch := deg_to_rad(rng.randf_range(20.0, 25.0))
	var top := _gable_roof(y, pitch, 0.9, rng.randf_range(1.15, 1.5), 0.6, cover[0], cover[1], WOOD, _wood, LOGS, 2 if rng.randf() < 0.8 else 1)
	if rng.randf() < 0.5:
		_dentils(y + 0.06, _d * 0.5, _w - 0.3, _jit(_wood, 0.1))
	if rng.randf() < 0.75:
		var cx := _w * rng.randf_range(0.12, 0.3) * (1.0 if rng.randf() < 0.5 else -1.0)
		_chimney(cx, -_d * rng.randf_range(0.05, 0.25), y + (_w * 0.5 - absf(cx)) * tan(pitch) - 0.2, top + 0.7, rng.randf() < 0.4)
	if trade == "bakery":
		_local_props.append(["stall-red", Transform3D(Basis(Vector3.UP, PI * 0.5).scaled_local(Vector3(2.2, 2.2, 2.2)), Vector3(_w * 0.25, 0, _d * 0.5 + 0.45))])
	elif trade == "shop":
		_local_props.append(["stall-red", Transform3D(Basis(Vector3.UP, PI * 0.5).scaled_local(Vector3(2.0, 2.0, 2.0)), Vector3(_w * 0.5 / _cells(_w), 0, _d * 0.5 + 0.4))])


## Kenney cell count across a width (the old layout), kept for the shop stall's place, which
## world/village/village_kit.gd puts the cheese and chocolate on.
static func _cells(size: float) -> int:
	var n := maxi(1, int(round(size / 2.25)))
	if n % 2 == 1:
		n += 1 if size / 2.25 > n else -1
		n = maxi(2, n)
	return n


## Gasthaus: plaster ground floor with a wide door, two log storeys with red-and-white flamed
## shutters, a balcony, a big roof; keeps its red Kenney banners.
func _inn(base: float) -> void:
	_wood = _lin(WOOD_TONES[3])
	_style = _window_style(1.0, 0.9)
	_style["shutters"] = true
	_style["shutter_kind"] = "flame"
	_style["shutter_col"] = _lin(SHUTTER_PAINTS[2])
	var plaster := _lin(PLASTER_WHITES[0])
	var plinth := base + 0.7
	var g_top := base + FLOOR_H
	var ground := _openings(1.0, 1.2, 0.95, 2.1, [0, _w * 0.5], [-1, -1, -1, -1], 1.6, 2.3)
	_plinth(base, plinth, ground)
	_storey(PLASTER, plinth, g_top, _shift(ground, base - plinth), plaster, 0.0, 0.24, STONE, true)
	var y := g_top
	_sill_beam(y)
	y += 0.22
	for f in [1, 2]:
		var h := UPPER_H - (0.22 if f == 1 else 0.0)
		_storey(WOOD, y, y + h, _openings(0.9, 1.2, 0.8, 1.8), _wood, LOGS, 0.16, WOOD)
		_log_corners(y, y + h)
		if f == 1:
			_balcony(y, 1.0, _w * 0.6, 1.0)
		y += h
	var pitch := deg_to_rad(24.0)
	var top := _gable_roof(y, pitch, 1.0, 1.6, 0.8, SHINGLES, _shingles(), WOOD, _wood, LOGS, 3)
	_dentils(y + 0.06, _d * 0.5, _w - 0.3, _jit(_wood, 0.1))
	_chimney(-_w * 0.18, 0.0, y + _w * 0.32 * tan(pitch) - 0.2, top + 0.8)
	for x: float in [-_w * 0.5 + 1.2, _w * 0.5 - 1.2]:
		_local_props.append(["banner-red", Transform3D(Basis(Vector3.UP, -PI * 0.5).scaled_local(Vector3(2.0, 2.4, 2.0)), Vector3(x, base + FLOOR_H + 0.3, _d * 0.5 - 0.6))])


## Laubengasse house: round arches of sandstone on the ground floor over a walkway with shop
## fronts, two plaster storeys above in Bern's soft colours, shutters, a clay tile roof.
func _arcade(base: float) -> void:
	_wood = _lin(WOOD_TONES[2])
	_style = _window_style(0.85, 0.5)
	var plaster := _lin(ARCADE_PLASTERS[rng.randi_range(0, ARCADE_PLASTERS.size() - 1)])
	var stone := _lin(Color(0.93, 0.88, 0.78))
	var hd := _d * 0.5
	var hw := _w * 0.5
	var g_top := base + FLOOR_H + 0.8
	var walk := 2.2                    # walkway depth behind the arches
	var thick := 0.5                   # front wall
	var bz := hd - walk
	var n := maxi(2, int(round(_w / 3.2)))
	var bay := _w / n
	var pier := 0.55
	var spring := g_top - (bay - pier) * 0.5 - 0.3
	var t := Transform3D(Basis(), Vector3(-hw, 0, hd))
	# Piers between the arches (front face, both sides and the walkway face).
	for i in n + 1:
		var x0 := maxf(0.0, i * bay - pier * 0.5) if i > 0 else 0.0
		var x1 := minf(_w, i * bay + pier * 0.5) if i < n else _w
		if i == 0:
			x1 = pier
		if i == n:
			x0 = _w - pier
		_wall(STONE, Vector3(-hw + x0, 0, hd), Vector3.BACK, x1 - x0, -0.8, spring, [], stone)
		_wall(STONE, Vector3(-hw + x1, 0, hd - thick), Vector3.FORWARD, x1 - x0, base, spring, [], stone)
		for e in [[x1, Vector3.RIGHT, i < n], [x0, Vector3.LEFT, i > 0]]:
			if not e[2]:
				continue
			var px: float = -hw + float(e[0])
			_qf(STONE, Vector3(px, base, hd), Vector3(px, spring, hd), Vector3(px, spring, hd - thick), Vector3(px, base, hd - thick),
				Vector2(0, -base), Vector2(0, -spring), Vector2(thick, -spring), Vector2(thick, -base), stone, e[1])
	for i in n:
		var x0 := i * bay + (pier * 0.5 if i > 0 else pier)
		var x1 := (i + 1) * bay - (pier * 0.5 if i < n - 1 else pier)
		_arch_bay(t, x0, x1, spring, g_top, thick, STONE, stone)
	# The walkway: back wall with doors and shop windows, vaulted... flat ceiling, stone floor.
	var back_ops := []
	for i in n:
		var c := (i + 0.5) * bay
		if i % 2 == 0:
			back_ops.append([c - 0.5, c + 0.5, 0.0, 2.1, "d"])
		else:
			back_ops.append([c - 0.9, c + 0.9, 0.5, 2.3, "s"])
	var back_left := Vector3(-hw, 0, bz)
	_wall(PLASTER, back_left, Vector3.BACK, _w, base, g_top, back_ops, plaster)
	for o in back_ops:
		_reveal(PLASTER, back_left, Vector3.BACK, o, base, 0.2, plaster)
		if o[4] == "d":
			_door(back_left, Vector3.BACK, o, base, 0.2, false)
		else:
			_shop_window(back_left, Vector3.BACK, o, base, 0.2)
	_qf(PLASTER, Vector3(-hw, g_top, bz), Vector3(hw, g_top, bz), Vector3(hw, g_top, hd - thick), Vector3(-hw, g_top, hd - thick),
		Vector2(0, 0), Vector2(_w, 0), Vector2(_w, walk), Vector2(0, walk), plaster * 0.9, Vector3.DOWN)
	_qf(STONE, Vector3(-hw, base + 0.02, bz), Vector3(hw, base + 0.02, bz), Vector3(hw, base + 0.02, hd), Vector3(-hw, base + 0.02, hd),
		Vector2(0, 0), Vector2(_w, 0), Vector2(_w, walk), Vector2(0, walk), stone * 0.8, Vector3.UP)
	# Sides and back of the ground floor: a stone base, plaster above; the walkway's ends are
	# open below the arches' spring line, like the next house's arcade would carry on.
	_wall(STONE, Vector3(-hw, 0, -hd), Vector3.LEFT, _d - walk, -0.8, base + 0.5, [], stone)
	_wall(STONE, Vector3(hw, 0, bz), Vector3.RIGHT, _d - walk, -0.8, base + 0.5, [], stone)
	_wall(STONE, Vector3(hw, 0, -hd), Vector3.FORWARD, _w, -0.8, base + 0.5, [], stone)
	_wall(PLASTER, Vector3(-hw, 0, -hd), Vector3.LEFT, _d - walk, base + 0.5, g_top, [], plaster)
	_wall(PLASTER, Vector3(hw, 0, bz), Vector3.RIGHT, _d - walk, base + 0.5, g_top, [], plaster)
	_wall(PLASTER, Vector3(hw, 0, -hd), Vector3.FORWARD, _w, base + 0.5, g_top, [], plaster)
	_wall(STONE, Vector3(-hw, 0, bz), Vector3.LEFT, walk, spring, g_top, [], stone)
	_wall(STONE, Vector3(hw, 0, hd), Vector3.RIGHT, walk, spring, g_top, [], stone)
	# A sandstone string course, then two plaster storeys and a cornice.
	_box(STONE, Transform3D(Basis(), Vector3(0, g_top + 0.08, 0)), Vector3(_w + 0.12, 0.16, _d + 0.12), stone, 8)
	var y := g_top + 0.16
	for f in 2:
		_storey(PLASTER, y, y + 2.5, _openings(0.95, 1.35, 0.8, 1.9, [], [-1, 2, -1, 2]), plaster, 0.0, 0.24, STONE, f == 0)
		y += 2.5
	_box(STONE, Transform3D(Basis(), Vector3(0, y - 0.06, 0)), Vector3(_w + 0.1, 0.12, _d + 0.1), stone, 8 | 4)
	_gable_roof(y, deg_to_rad(28.0), 0.6, 0.6, 0.4, TILES, _jit(Color(1, 1, 1), 0.1), PLASTER, plaster, 0.0, 1)


## One arcade bay in frame t (x along the front from its left end, z out): an arch over x0..x1
## springing at `spring`, the wall over it up to y_top, the arch's soffit through `thick`
## metres of wall, the same wall face again on the walkway side, and a keystone.
func _arch_bay(t: Transform3D, x0: float, x1: float, spring: float, y_top: float, thick: float, m: int, col: Color) -> void:
	var r := (x1 - x0) * 0.5
	var cx := (x0 + x1) * 0.5
	var crown := spring + r
	var seg := 10
	var out := t.basis.z
	var d := Vector3(0, 0, -thick)
	for i in seg:
		var a0 := PI - PI * i / seg
		var a1 := PI - PI * (i + 1) / seg
		var p0 := Vector3(cx + cos(a0) * r, spring + sin(a0) * r, 0)
		var p1 := Vector3(cx + cos(a1) * r, spring + sin(a1) * r, 0)
		var q0 := Vector3(p0.x, crown, 0)
		var q1 := Vector3(p1.x, crown, 0)
		var u := [Vector2(p0.x, -p0.y), Vector2(p1.x, -p1.y), Vector2(q1.x, -crown), Vector2(q0.x, -crown)]
		_qf(m, t * p0, t * p1, t * q1, t * q0, u[0], u[1], u[2], u[3], col, out)
		_qf(m, t * (p0 + d), t * (p1 + d), t * (q1 + d), t * (q0 + d), u[0], u[1], u[2], u[3], col, -out)
		var mid := (a0 + a1) * 0.5
		_qf(m, t * p0, t * p1, t * (p1 + d), t * (p0 + d), Vector2(r * a0, 0), Vector2(r * a1, 0), Vector2(r * a1, thick), Vector2(r * a0, thick),
			col, t.basis * Vector3(-cos(mid), -sin(mid), 0))
	for z: float in [0.0, -thick]:
		_qf(m, t * Vector3(x0, crown, z), t * Vector3(x1, crown, z), t * Vector3(x1, y_top, z), t * Vector3(x0, y_top, z),
			Vector2(x0, -crown), Vector2(x1, -crown), Vector2(x1, -y_top), Vector2(x0, -y_top), col, out if z == 0.0 else -out)
	_box(m, t * Transform3D(Basis(), Vector3(cx, crown - 0.12, 0.03)), Vector3(0.3, 0.42, 0.06), col * 1.06, 32)


## Village church: a white nave on a stone plinth with tall round-arched windows and corner
## stones, a steep clay tile roof, a tower on the front with louvred belfry, clocks, a tall
## spire with a gilded ball and cross.
func _church(base: float) -> void:
	_wood = _lin(WOOD_TONES[3])
	_style = _window_style(0.0, 0.0)
	_style["frame_white"] = false
	var white := _lin(Color(0.97, 0.96, 0.93))
	var stone := _lin(Color(0.88, 0.86, 0.82))
	var plinth := base + 0.8
	var nave_h := base + 6.2
	var hd := _d * 0.5
	var tw := 3.8
	var tz := hd - tw * 0.5 + 0.3       # the tower stands 30 cm proud of the nave's front
	# Nave: arched windows down both sides (clear of the tower) and one in the back wall.
	var ops := [[], [], [], []]
	for c: float in _spread(_d - tw, 1.1, 3.4, 0.8):
		ops[1].append([tw + c - 0.55, tw + c + 0.55, 2.0, 4.6, "a"])
		ops[3].append([c - 0.55, c + 0.55, 2.0, 4.6, "a"])
	ops[2].append([_w * 0.5 - 0.7, _w * 0.5 + 0.7, 2.6, 4.8, "a"])
	_plinth(base, plinth, [[], [], [], []])
	var sides := _sides()
	for k in 4:
		var s: Array = sides[k]
		_wall(PLASTER, s[0], s[1], s[2], plinth, nave_h, _shift_list(ops[k], base - plinth), white)
		for o in ops[k]:
			_arch_window(s[0], s[1], o, base, 0.32, white)
	_quoins(plinth, nave_h, stone)
	_gable_roof(nave_h, deg_to_rad(45.0), 0.5, 0.3, 0.4, TILES, _jit(Color(1, 1, 1), 0.05), PLASTER, white, 0.0, 0)
	# Tower, built on its own footprint centred at (0, tz).
	var saved := Vector2(_w, _d)
	_w = tw
	_d = tw
	var tower_top := base + 15.5
	var belfry := tower_top - 3.0       # height of the belfry openings' sill
	var shift := Vector3(0, 0, tz)
	var tsides := _sides()
	for k in 4:
		var s: Array = tsides[k]
		var left: Vector3 = (s[0] as Vector3) + shift
		var out: Vector3 = s[1]
		var length: float = s[2]
		var mid := length * 0.5
		var lo := [[mid - 0.6, mid + 0.6, belfry - base + 0.2, belfry - base + 2.0, "b"]]
		if k == 0:
			lo.append([mid - 0.65, mid + 0.65, 0.0, 2.7, "d"])
			lo.append([mid - 0.3, mid + 0.3, 5.0, 6.4, "a"])
		elif k != 2:
			lo.append([mid - 0.3, mid + 0.3, 5.0, 6.4, "a"])
		_wall(PLASTER, left, out, length, plinth, tower_top, _shift_list(lo, base - plinth), white)
		var cuts := []
		for o in lo:
			if o[4] == "d":
				_arch_door(left, out, o, base, 0.4, white)
				cuts.append([float(o[0]) + 0.06, float(o[1]) + 0.06, base + 0.8, plinth + 0.8, "d"])
			else:
				_arch_window(left, out, o, base, 0.4, white, o[4] == "b")
		if k != 2:
			_clock(left, out, mid, belfry - 1.0)
		var dir := Vector3.UP.cross(out)
		_wall(STONE, left + out * 0.06 - dir * 0.06, out, length + 0.12, -0.8, plinth, cuts, stone)
		for o in cuts:
			_reveal(STONE, left + out * 0.06 - dir * 0.06, out, o, -0.8, 0.06, stone)
	_w = saved.x
	_d = saved.y
	# Corner stones up the tower.
	var y := plinth
	var k2 := 0
	while y < tower_top - 0.4:
		var long := k2 % 2 == 0
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var lx := 0.55 if long else 0.3
			var lz := 0.3 if long else 0.55
			_box(STONE, Transform3D(Basis(), Vector3(c.x * (tw * 0.5 - lx * 0.5 + 0.03), y + 0.19, tz + c.y * (tw * 0.5 - lz * 0.5 + 0.03))), Vector3(lx, 0.36, lz), stone)
		y += 0.4
		k2 += 1
	# Cornice and the spire: a tall eight-sided needle.
	_box(STONE, Transform3D(Basis(), Vector3(0, tower_top + 0.1, tz)), Vector3(tw + 0.3, 0.2, tw + 0.3), stone)
	var sb := tower_top + 0.2
	var apex := Vector3(0, base + 25.0, tz)
	var r0 := (tw * 0.5 + 0.3) / cos(PI / 8.0)
	var spire_col := _lin(Color(0.86, 0.8, 0.76))
	for i in 8:
		var a0 := TAU * (i + 0.5) / 8.0
		var a1 := TAU * (i + 1.5) / 8.0
		var p0 := Vector3(cos(a0) * r0, sb, tz + sin(a0) * r0)
		var p1 := Vector3(cos(a1) * r0, sb, tz + sin(a1) * r0)
		var m := (p0 + p1) * 0.5
		var w := p0.distance_to(p1)
		var len := m.distance_to(apex)
		_tf(TILES, p0, p1, apex, Vector2(-w * 0.5, len), Vector2(w * 0.5, len), Vector2(0, 0), spire_col, Vector3(m.x, 0.3, m.z - tz))
	_blob(PAINT, apex + Vector3(0, 0.2, 0), Vector3(0.22, 0.22, 0.22), _lin(GOLD))
	_box(PAINT, Transform3D(Basis(), apex + Vector3(0, 0.95, 0)), Vector3(0.07, 1.1, 0.07), _lin(GOLD))
	_box(PAINT, Transform3D(Basis(), apex + Vector3(0, 1.15, 0)), Vector3(0.55, 0.07, 0.07), _lin(GOLD))


## Corner stones (quoins) up the four corners of the footprint, alternately long and short.
func _quoins(y0: float, y1: float, col: Color) -> void:
	var hw := _w * 0.5
	var hd := _d * 0.5
	var y := y0
	var k := 0
	while y < y1 - 0.3:
		var long := k % 2 == 0
		for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var lx := 0.55 if long else 0.3
			var lz := 0.3 if long else 0.55
			_box(STONE, Transform3D(Basis(), Vector3(c.x * (hw - lx * 0.5 + 0.03), y + 0.19, c.y * (hd - lz * 0.5 + 0.03))), Vector3(lx, 0.36, lz), col)
		y += 0.4
		k += 1


## A window with a round head in opening o (a rectangle up to the crown): the corners above the
## arch filled with plaster, a reveal round the arch, glass with lead bars; or louvres for a
## belfry.
func _arch_window(left: Vector3, out: Vector3, o: Array, y0: float, depth: float, col: Color, louvred := false) -> void:
	var t := _frame(left, out, o, y0)
	var w: float = o[1] - o[0]
	var h: float = o[3] - o[2]
	var r := w * 0.5
	var spring := h - r
	var seg := 8
	var inn := Vector3(0, 0, -depth)
	for side in [0, 1]:
		var corner := Vector3(0.0 if side == 0 else w, h, 0)
		for i in seg:
			var a0 := PI * (0.5 + 0.5 * float(i) / seg) if side == 0 else PI * (0.5 - 0.5 * float(i) / seg)
			var a1 := PI * (0.5 + 0.5 * float(i + 1) / seg) if side == 0 else PI * (0.5 - 0.5 * float(i + 1) / seg)
			var p0 := Vector3(r + cos(a0) * r, spring + sin(a0) * r, 0)
			var p1 := Vector3(r + cos(a1) * r, spring + sin(a1) * r, 0)
			_tf(PLASTER, t * p0, t * p1, t * corner, Vector2(p0.x, -p0.y), Vector2(p1.x, -p1.y), Vector2(corner.x, -corner.y), col, out)
			var mid := (a0 + a1) * 0.5
			_qf(PLASTER, t * p0, t * p1, t * (p1 + inn), t * (p0 + inn), Vector2(r * a0, 0), Vector2(r * a1, 0), Vector2(r * a1, depth),
				Vector2(r * a0, depth), col, t.basis * Vector3(-cos(mid), -sin(mid), 0))
	# Straight jambs and the sill.
	for x: float in [0.0, w]:
		_qf(PLASTER, t * Vector3(x, 0, 0), t * Vector3(x, spring, 0), t * Vector3(x, spring, -depth), t * Vector3(x, 0, -depth),
			Vector2(0, 0), Vector2(0, -spring), Vector2(depth, -spring), Vector2(depth, 0), col, t.basis.x * (1.0 if x == 0.0 else -1.0))
	_box(STONE, t * Transform3D(Basis(), Vector3(w * 0.5, -0.04, (0.06 - depth) * 0.5)), Vector3(w + 0.1, 0.08, depth + 0.06), _lin(Color(0.85, 0.83, 0.8)))
	var z := -depth + 0.05
	if louvred:
		var n := int(spring / 0.22)
		for i in n:
			_box(BOARDS, t * Transform3D(Basis(Vector3.RIGHT, -0.6), Vector3(w * 0.5, 0.15 + i * (spring - 0.1) / n, z)), Vector3(w, 0.2, 0.02), _jit(_wood, 0.05))
		_q(GLASS, t * Vector3(0, 0, z - 0.12), t * Vector3(w, 0, z - 0.12), t * Vector3(w, h, z - 0.12), t * Vector3(0, h, z - 0.12),
			Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(0.0, 0.0, 0.0))
		return
	_q(GLASS, t * Vector3(0, 0, z), t * Vector3(w, 0, z), t * Vector3(w, h, z), t * Vector3(0, h, z),
		Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0), Color(0.0, 0.5, 0.0))
	var bc := _lin(DARK_PAINT)
	detail = true
	_box(PAINT, t * Transform3D(Basis(), Vector3(w * 0.5, h * 0.5, z + 0.02)), Vector3(0.03, h, 0.02), bc, 32)
	for f in range(1, 5):
		_box(PAINT, t * Transform3D(Basis(), Vector3(w * 0.5, spring * f / 5.0, z + 0.02)), Vector3(w, 0.025, 0.02), bc, 32)
	detail = false


## Round-headed door: an arched opening with a plank door under its fanlight and a stone step.
func _arch_door(left: Vector3, out: Vector3, o: Array, y0: float, depth: float, col: Color) -> void:
	_arch_window(left, out, o, y0, depth, col)
	var t := _frame(left, out, o, y0)
	var w: float = o[1] - o[0]
	var h: float = o[3] - o[2]
	var dh := h - w * 0.5
	_box(BOARDS, t * Transform3D(Basis(), Vector3(w * 0.5, dh * 0.5, -depth + 0.11)), Vector3(w, dh, 0.06), _lin(Color(0.45, 0.28, 0.16)), 32, 1)
	_box(STONE, t * Transform3D(Basis(), Vector3(w * 0.5, -0.13, 0.25 - depth * 0.5)), Vector3(w + 0.8, 0.3, 0.5 + depth), _lin(Color(0.9, 0.9, 0.88)), 32)


## Clock face on a wall at u metres from its left end, centred at height y: white dial, gilded
## ring, black hands.
func _clock(left: Vector3, out: Vector3, u: float, y: float) -> void:
	var dir := Vector3.UP.cross(out)
	var c := Vector3(left.x, y, left.z) + dir * u + out * 0.04
	var r := 0.75
	var n := 16
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var e0 := dir * cos(a0) + Vector3.UP * sin(a0)
		var e1 := dir * cos(a1) + Vector3.UP * sin(a1)
		_tf(PAINT, c, c + e0 * r, c + e1 * r, Vector2.ZERO, Vector2(cos(a0), sin(a0)), Vector2(cos(a1), sin(a1)), _lin(WHITE_PAINT), out)
		_qf(PAINT, c + e0 * r, c + e0 * (r + 0.1), c + e1 * (r + 0.1), c + e1 * r, Vector2(0, 0), Vector2(0.1, 0), Vector2(0.1, 0.3), Vector2(0, 0.3), _lin(GOLD), out)
	var hand := Basis(dir, Vector3.UP, out)
	for hnd: Vector2 in [Vector2(0.4, 0.45), Vector2(-2.1, 0.62)]:
		var a := hnd.x
		var along := Vector3.UP * cos(a) - dir * sin(a)
		_box(PAINT, Transform3D(hand * Basis(Vector3.BACK, a), c + out * 0.02 + along * hnd.y * 0.5), Vector3(0.05, hnd.y, 0.02), _lin(DARK_PAINT), 32)


## Mill on the pond: rubble stone ground floor, a log storey, shingles; keeps its water wheel.
func _mill(base: float) -> void:
	_wood = _lin(WOOD_TONES[2])
	_style = _window_style(0.7, 0.4)
	var ground := _openings(0.8, 0.9, 1.1, 2.2, [0, 1.6], [-1, 2, -1, 2])
	var g_top := base + FLOOR_H
	_storey(STONE, -0.8, g_top, _shift(ground, base + 0.8), _lin(Color(1.0, 0.98, 0.95)), 0.0, 0.3, STONE, false)
	var y := g_top
	_sill_beam(y)
	y += 0.22
	_storey(WOOD, y, y + UPPER_H - 0.22, _openings(0.85, 1.1, 0.8, 1.9), _wood, LOGS, 0.16, WOOD)
	_log_corners(y, y + UPPER_H - 0.22)
	y += UPPER_H - 0.22
	_gable_roof(y, deg_to_rad(24.0), 0.8, 1.0, 0.6, SHINGLES, _shingles(), WOOD, _wood, LOGS, 1)
	_local_props.append(["watermill", Transform3D(Basis(Vector3.UP, PI * 0.5).scaled_local(Vector3(3.0, 3.0, 3.0)), Vector3(0, 1.4, -_d * 0.5 - 0.9))])


## Hay barn: dark vertical boards with battens on a low stone plinth, wide double doors with Z
## braces, a big low shingle roof, air slits in the gables.
func _barn(base: float) -> void:
	_wood = _lin(WOOD_TONES[4]) * 0.9
	_style = _window_style(0.0, 0.0)
	var plinth := base + 0.45
	var top := base + FLOOR_H * 1.3
	var door_w := 3.2
	var door := [_w * 0.5 - door_w * 0.5, _w * 0.5 + door_w * 0.5, 0.0, 2.9, "d"]
	_plinth(base, plinth, [[door], [], [], []])
	var sides := _sides()
	var u_off := 0.0
	for k in 4:
		var s: Array = sides[k]
		var lo := _shift_list([door], base - plinth) if k == 0 else []
		_wall(BOARDS, s[0], s[1], s[2], plinth, top, lo, _wood, 0.0, u_off, true)
		for o in lo:
			_reveal(BOARDS, s[0], s[1], o, plinth, 0.16, _wood)
		_battens(s[0], s[1], s[2], plinth, top, lo)
		u_off += float(s[2])
	# Big doors: two plank leaves with Z braces, a dark barn behind them.
	var t := _frame(sides[0][0], sides[0][1], door, base)
	var lw := door_w * 0.5
	for side: int in [0, 1]:
		var x := lw * 0.5 + side * lw
		var col := _jit(_wood, 0.08)
		_box(BOARDS, t * Transform3D(Basis(), Vector3(x, 1.45, -0.08)), Vector3(lw - 0.02, 2.9, 0.06), col, 32, 1)
		for y: float in [0.4, 2.5]:
			_box(WOOD, t * Transform3D(Basis(), Vector3(x, y, -0.03)), Vector3(lw - 0.15, 0.16, 0.05), col * 1.1, 32)
		var ang := atan2(2.1, lw - 0.3) * (1.0 if side == 0 else -1.0)
		_box(WOOD, t * Transform3D(Basis(Vector3.BACK, ang), Vector3(x, 1.45, -0.03)), Vector3(Vector2(lw - 0.3, 2.1).length(), 0.15, 0.05), col * 1.1, 32)
	_gable_roof(top, deg_to_rad(22.0), 1.2, 1.4, 1.0, SHINGLES, _shingles(), BOARDS, _wood, 0.0, 0)
	# Air slits in the gable fronts.
	for gz: float in [1.0, -1.0]:
		for i in 5:
			_box(PAINT, Transform3D(Basis(), Vector3((i - 2) * 0.45, top + 1.0, gz * (_d * 0.5 + 0.03))), Vector3(0.08, 0.9, 0.02), Color(0.015, 0.015, 0.015), 32 if gz > 0.0 else 16)


## Vertical battens over the joints of a board wall, clear of its openings.
func _battens(left: Vector3, out: Vector3, length: float, y0: float, y1: float, ops: Array) -> void:
	var dir := Vector3.UP.cross(out)
	var n := int(length / 0.9)
	for i in range(1, n):
		var u := length * i / n
		var clear := true
		for o in ops:
			if u > o[0] - 0.1 and u < o[1] + 0.1:
				clear = false
		if clear:
			var p := Vector3(left.x, (y0 + y1) * 0.5, left.z) + dir * u + out * 0.02
			detail = true
			_box(WOOD, Transform3D(Basis(dir, Vector3.UP, out), p), Vector3(0.08, y1 - y0, 0.04), _wood * 0.85, 32, 1)
			detail = false


## Schoolhouse: two plaster storeys with rows of green-shuttered windows, corner pilasters, a
## slate roof with a little bell turret on the ridge.
func _school(base: float) -> void:
	_wood = _lin(WOOD_TONES[2])
	_style = _window_style(1.0, 0.3)
	_style["shutter_col"] = _lin(SHUTTER_PAINTS[0])
	_style["shutter_kind"] = "louvre"
	_style["frame_white"] = true
	var plaster := _lin(PLASTER_WHITES[2])
	var plinth := base + 0.8
	var ground := _openings(1.0, 1.4, 1.0, 1.9, [0, _w * 0.5], [-1, -1, -1, -1], 1.4, 2.4)
	_plinth(base, plinth, ground)
	var y := base + FLOOR_H + 0.3
	_storey(PLASTER, plinth, y, _shift(ground, base - plinth), plaster, 0.0, 0.24, STONE, false)
	_box(STONE, Transform3D(Basis(), Vector3(0, y + 0.07, 0)), Vector3(_w + 0.1, 0.14, _d + 0.1), _lin(Color(0.85, 0.83, 0.8)), 8)
	y += 0.14
	_storey(PLASTER, y, y + FLOOR_H + 0.2, _openings(1.0, 1.4, 0.9, 1.9), plaster, 0.0, 0.24, STONE, false)
	y += FLOOR_H + 0.2
	_pilasters(plinth, y)
	var ridge := _gable_roof(y, deg_to_rad(28.0), 0.8, 0.8, 0.6, SLATE, Color(1, 1, 1), PLASTER, plaster, 0.0, 2)
	# Bell turret on the ridge: a timber box with louvres and a pointed slate roof.
	var tb := ridge - 0.3
	var s := 1.4
	_box(BOARDS, Transform3D(Basis(), Vector3(0, tb + 0.9, 0)), Vector3(s, 1.8, s), _wood, 8, 1)
	for k in 4:
		var b := Basis(Vector3.UP, k * PI * 0.5)
		_box(PAINT, Transform3D(b, b * Vector3(0, tb + 1.15, s * 0.5 + 0.015)), Vector3(0.7, 0.8, 0.02), _lin(SHUTTER_PAINTS[0]), 32, 1, 0.0, LOUVRE)
	var apex := Vector3(0, tb + 3.6, 0)
	var r := s * 0.5 + 0.2
	var corners := [Vector3(-r, tb + 1.8, -r), Vector3(r, tb + 1.8, -r), Vector3(r, tb + 1.8, r), Vector3(-r, tb + 1.8, r)]
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[(k + 1) % 4]
		var m := (a + b) * 0.5
		var len := m.distance_to(apex)
		_tf(SLATE, a, b, apex, Vector2(0, len), Vector2(a.distance_to(b), len), Vector2(a.distance_to(b) * 0.5, 0), Color(1, 1, 1), Vector3(m.x, 0.3, m.z))
	_blob(PAINT, apex + Vector3(0, 0.15, 0), Vector3(0.12, 0.12, 0.12), _lin(GOLD))


## Plain stone corner pilasters for plaster buildings.
func _pilasters(y0: float, y1: float) -> void:
	var col := _lin(Color(0.82, 0.8, 0.76))
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		_box(STONE, Transform3D(Basis(), Vector3(c.x * (_w * 0.5 - 0.15), (y0 + y1) * 0.5, c.y * (_d * 0.5 - 0.15))), Vector3(0.36, y1 - y0, 0.36), col, 4 | 8)


## Cheese dairy or chocolate works: a long plaster hall with big windows, a log storey (its
## name board on the front), a slate roof and two tall stone chimneys.
func _factory(base: float) -> void:
	_wood = _lin(WOOD_TONES[1])
	_style = _window_style(0.0, 0.0)
	_style["frame_white"] = true
	var plaster := _lin(PLASTER_WHITES[1])
	var plinth := base + 0.7
	var g_top := base + FLOOR_H * 1.2
	var ground := _openings(1.4, 1.6, 0.9, 2.5, [0, _w * 0.5], [-1, -1, -1, -1], 2.4, 2.6)
	_plinth(base, plinth, ground)
	_storey(PLASTER, plinth, g_top, _shift(ground, base - plinth), plaster, 0.0, 0.24, STONE, false)
	var y := g_top
	_sill_beam(y)
	y += 0.22
	_storey(WOOD, y, y + UPPER_H - 0.22, _openings(0.9, 1.0, 0.9, 1.8), _wood, LOGS, 0.16, WOOD, false)
	_log_corners(y, y + UPPER_H - 0.22)
	y += UPPER_H - 0.22
	var pitch := deg_to_rad(22.0)
	var ridge := _gable_roof(y, pitch, 0.8, 0.8, 0.6, SLATE, Color(1, 1, 1), WOOD, _wood, LOGS, 2)
	for x: float in [-_w * 0.3, _w * 0.3]:
		_chimney(x, -_d * 0.3, y + (_w * 0.5 - absf(x)) * tan(pitch) - 0.3, ridge + 4.5)


## Emmental farmhouse: stone and plaster below, logs above, a big steep shingle roof coming down
## low with deep eaves, rows of windows with geraniums.
func _farmhouse(base: float) -> void:
	_wood = _lin(WOOD_TONES[2])
	_style = _window_style(0.9, 0.95)
	var plaster := _lin(PLASTER_WHITES[3])
	var plinth := base + 0.7
	var g_top := base + FLOOR_H
	var ground := _openings(0.85, 1.05, 0.95, 1.7, [0, 2.0], [-1, -1, -1, -1])
	_plinth(base, plinth, ground)
	_storey(PLASTER, plinth, g_top, _shift(ground, base - plinth), plaster, 0.0, 0.24, STONE, true)
	var y := g_top
	_sill_beam(y)
	y += 0.22
	var ups := _openings(0.85, 1.1, 0.8, 1.6)
	for o in ups[0]:
		o.append_array([true, false])
	_storey(WOOD, y, y + UPPER_H - 0.22, ups, _wood, LOGS, 0.16, WOOD)
	_log_corners(y, y + UPPER_H - 0.22)
	y += UPPER_H - 0.22
	var pitch := deg_to_rad(30.0)
	var top := _gable_roof(y, pitch, 1.4, 1.8, 1.2, SHINGLES, _shingles(), WOOD, _wood, LOGS, 3)
	_chimney(_w * 0.15, -_d * 0.2, y + _w * 0.35 * tan(pitch) - 0.2, top + 0.6)


# ---------------------------------------------------------------- covered bridge

## One cell of the covered bridge in its deck frame (+z along the road): board walls with a
## window band on every other cell, inside faces too, posts and a tie beam at the joint, the
## shingle roof over it and, on the first and last cells, the gable over the portal.
func _bridge_cell(k: int, n: int, len: float, hw: float, pitch: float) -> void:
	var eave := 2.5
	var col := _jit(_wood, 0.04)
	var z0 := -len * 0.5
	var z1 := len * 0.5
	var ops := [[0.25, len - 0.25, 1.4, 2.1, "w"]] if k % 2 == 1 else []
	for side: float in [-1.0, 1.0]:
		var out := Vector3(side, 0, 0)
		var outer := Vector3(side * hw, 0, z1 if side > 0.0 else z0)
		var inner := Vector3(side * (hw - 0.08), 0, z0 if side > 0.0 else z1)
		_wall(BOARDS, outer, out, len, -0.35, eave, ops, col, 0.0, 0.0, true)
		_wall(BOARDS, inner, -out, len, -0.05, eave, ops, col * 0.8, 0.0, 0.0, true)
		for o in ops:
			_reveal(BOARDS, outer, out, o, -0.35, 0.08, col, 0.0, true)
		_box(WOOD, Transform3D(Basis(), Vector3(side * (hw - 0.04), eave * 0.5 - 0.2, z0)), Vector3(0.18, eave + 0.3, 0.18), col * 0.9, 0, 1)
	_box(WOOD, Transform3D(Basis(), Vector3(0, eave - 0.1, z0)), Vector3(hw * 2.0, 0.2, 0.16), col * 0.9, 0)
	var o_side := 0.7
	var tp := tan(pitch)
	var ridge := eave + hw * tp
	var th := 0.2 / cos(pitch)
	var zz0 := z0 - (0.9 if k == 0 else 0.0)
	var zz1 := z1 + (0.9 if k == n - 1 else 0.0)
	for side: float in [-1.0, 1.0]:
		var e := Vector3(side * (hw + o_side), eave - o_side * tp, 0)
		var nrm := Vector3(side * sin(pitch), cos(pitch), 0)
		var slope := (hw + o_side) / cos(pitch)
		_qf(SHINGLES, Vector3(e.x, e.y + th, zz0), Vector3(e.x, e.y + th, zz1), Vector3(0, ridge + th, zz1), Vector3(0, ridge + th, zz0),
			Vector2(zz0 + k * len, slope), Vector2(zz1 + k * len, slope), Vector2(zz1 + k * len, 0), Vector2(zz0 + k * len, 0), _lin(SHINGLE_TONES[1]), nrm)
		_qf(BOARDS, Vector3(e.x, e.y, zz0), Vector3(e.x, e.y, zz1), Vector3(0, ridge, zz1), Vector3(0, ridge, zz0),
			Vector2(slope, zz0), Vector2(slope, zz1), Vector2(0, zz1), Vector2(0, zz0), col, -nrm)
		_box(WOOD, Transform3D(Basis(), Vector3(side * (hw + o_side + 0.025), e.y + th * 0.5 - 0.03, (zz0 + zz1) * 0.5)), Vector3(0.05, th + 0.1, zz1 - zz0), col, 0, 2)
	_box(SHINGLES, Transform3D(Basis(), Vector3(0, ridge + th + 0.03, (zz0 + zz1) * 0.5)), Vector3(0.3, 0.08, zz1 - zz0), _lin(SHINGLE_TONES[1]) * 0.8, 0, 2)
	if k == 0 or k == n - 1:
		var gz := z0 if k == 0 else z1
		var facing := Vector3(0, 0, -1.0 if k == 0 else 1.0)
		var a := Vector3(-hw, eave, gz)
		var b := Vector3(hw, eave, gz)
		var c := Vector3(0, ridge, gz)
		_tf(BOARDS, a, b, c, Vector2(-hw, -eave), Vector2(hw, -eave), Vector2(0, -ridge), col, facing)
		_tf(BOARDS, a, b, c, Vector2(-hw, -eave), Vector2(hw, -eave), Vector2(0, -ridge), col * 0.8, -facing)
		_box(WOOD, Transform3D(Basis(), Vector3(0, eave - 0.15, gz)), Vector3(hw * 2.0 + 0.3, 0.3, 0.2), col * 0.9, 0)

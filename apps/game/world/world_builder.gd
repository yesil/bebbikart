extends RefCounted
## Grey-box toy world built procedurally from the course data (WS3a placeholder art):
## track strips with skirts for every fork variant, section lines, boost strips, the pond,
## bridge rails, hedges, the jump ramp, start gate, finish castle and toy scenery.

const Course = preload("res://sim/course.gd")
const Route = preload("res://sim/route.gd")

const SECTION_COLORS := {
	"hills": Color(0.93, 0.80, 0.55),
	"pond": Color(0.78, 0.74, 0.66),
	"crossing": Color(0.72, 0.52, 0.34),
	"bends": Color(0.95, 0.66, 0.42),
}
const GROUND := Color(0.45, 0.74, 0.36)
const POND_RECT := Rect2(-26.0, 128.0, 36.0, 84.0)   # x, z, w, h
const GROUND_RECT := Rect2(-90.0, -40.0, 180.0, 470.0)

var course: Course
var root: Node3D
var rng := RandomNumberGenerator.new()
var _mats := {}


func build(p_course: Course, parent: Node3D, seed_: int = 7) -> Node3D:
	course = p_course
	rng.seed = seed_
	root = Node3D.new()
	root.name = "World"
	parent.add_child(root)
	_ground()
	_pond()
	for id in course.ordered_ids:
		_segment(course.segments[id])
	_section_lines()
	_start_gate()
	_castle(Vector3(0, 0, _finish_z() + 14.0))
	_hedges(course.segments["cross_sheltered"])
	_supports(course.segments["cross_exposed"])
	_scenery()
	return root


func _finish_z() -> float:
	var r: Route = course.segments["bends"]["route"]
	return r.pos_at(r.length).z


# ---------------------------------------------------------------- materials

func mat(c: Color, unshaded := false, alpha := 1.0) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [c.to_html(), unshaded, alpha]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, alpha)
	m.roughness = 0.85
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


func _mesh(mesh: Mesh, m: Material, pos: Vector3, parent: Node3D = null, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	(parent if parent != null else root).add_child(mi)
	return mi


func _box(size: Vector3, c: Color, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(b, mat(c), pos, null, rot)


# ---------------------------------------------------------------- ground and pond

func _ground() -> void:
	var g := GROUND_RECT
	var p := POND_RECT
	# Four tiles around the pond hole.
	var tiles := [
		Rect2(g.position.x, g.position.y, g.size.x, p.position.y - g.position.y),
		Rect2(g.position.x, p.end.y, g.size.x, g.end.y - p.end.y),
		Rect2(g.position.x, p.position.y, p.position.x - g.position.x, p.size.y),
		Rect2(p.end.x, p.position.y, g.end.x - p.end.x, p.size.y),
	]
	for t: Rect2 in tiles:
		var pm := PlaneMesh.new()
		pm.size = t.size
		_mesh(pm, mat(GROUND), Vector3(t.get_center().x, -0.05, t.get_center().y))


func _pond() -> void:
	var p := POND_RECT
	_box(Vector3(p.size.x, 0.1, p.size.y), Color(0.35, 0.5, 0.45), Vector3(p.get_center().x, -0.9, p.get_center().y))
	for side in [[Vector3(p.size.x, 0.9, 0.3), Vector3(p.get_center().x, -0.5, p.position.y)],
			[Vector3(p.size.x, 0.9, 0.3), Vector3(p.get_center().x, -0.5, p.end.y)],
			[Vector3(0.3, 0.9, p.size.y), Vector3(p.position.x, -0.5, p.get_center().y)],
			[Vector3(0.3, 0.9, p.size.y), Vector3(p.end.x, -0.5, p.get_center().y)]]:
		_box(side[0], Color(0.55, 0.45, 0.35), side[1])
	var w := PlaneMesh.new()
	w.size = p.size
	var wm := mat(Color(0.25, 0.55, 0.95), false, 0.7)
	wm.roughness = 0.1
	wm.metallic_specular = 0.9
	_mesh(w, wm, Vector3(p.get_center().x, -0.12, p.get_center().y))
	# Lily pads.
	for i in 14:
		var c := CylinderMesh.new()
		c.top_radius = rng.randf_range(0.4, 0.9)
		c.bottom_radius = c.top_radius
		c.height = 0.04
		var pos := Vector3(rng.randf_range(p.position.x + 1, p.end.x - 1), -0.09, rng.randf_range(p.position.y + 2, p.end.y - 2))
		if _near_track(pos, 1.5):
			continue
		_mesh(c, mat(Color(0.3, 0.65, 0.3)), pos)


# ---------------------------------------------------------------- track

func _segment(seg: Dictionary) -> void:
	var r: Route = seg["route"]
	var hw: float = seg["half_width"]
	var col: Color = SECTION_COLORS.get(seg["section"], Color.WHITE)
	if seg["choice"] in ["around", "bridge", "sheltered"]:
		col = col.darkened(0.08)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skirt := SurfaceTool.new()
	skirt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := 0.75
	var n := int(ceil(r.length / step))
	var prev: Array = []
	for i in n + 1:
		var s := minf(i * step, r.length)
		var y := course.surface_y(seg, s) + 0.02
		var l := r.world_at(s, -hw)
		var rr := r.world_at(s, hw)
		l.y = y
		rr.y = y
		var lb := Vector3(l.x, minf(y, 0.0) - 0.8, l.z)
		var rb := Vector3(rr.x, minf(y, 0.0) - 0.8, rr.z)
		var cur := [l, rr, lb, rb]
		if not prev.is_empty():
			_quad(st, prev[0], prev[1], cur[1], cur[0])
			_quad(skirt, prev[2], prev[0], cur[0], cur[2])
			_quad(skirt, prev[1], prev[3], cur[3], cur[1])
		prev = cur
	st.generate_normals()
	skirt.generate_normals()
	var track := _mesh(st.commit(), mat(col), Vector3.ZERO)
	track.name = "Track_" + String(seg["id"])
	_mesh(skirt.commit(), mat(col.darkened(0.35)), Vector3.ZERO)
	_edges(seg)
	for z in seg["boosts"]:
		_strip(seg, float(z[0]), float(z[1]), hw * 0.8, Color(1.0, 0.25, 0.75), 0.05, true)
	for b in seg["bumps"]:
		_strip(seg, float(b) - 0.4, float(b) + 0.4, hw, Color(0.9, 0.9, 0.9), 0.06)
	if seg["rails"]:
		_rails(seg)
	if not (seg["ramp"] as Dictionary).is_empty():
		var rp: Dictionary = seg["ramp"]
		_strip(seg, float(rp["kick_a"]), float(rp["lip_s"]), hw, Color(1.0, 0.85, 0.2), 0.04)
		_strip(seg, float(rp["land_s"]) - 1.0, float(rp["land_s"]) + 4.0, hw, Color(0.4, 0.85, 0.4), 0.04)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)


## Flat coloured strip lying on the track between s0 and s1.
func _strip(seg: Dictionary, s0: float, s1: float, hw: float, c: Color, lift: float, arrows := false) -> void:
	var r: Route = seg["route"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := maxi(2, int((s1 - s0) / 0.5))
	for i in n:
		var a := s0 + (s1 - s0) * i / n
		var b := s0 + (s1 - s0) * (i + 1) / n
		var pts := []
		for sd in [[a, -hw], [a, hw], [b, hw], [b, -hw]]:
			var p := r.world_at(sd[0], sd[1])
			p.y = course.surface_y(seg, sd[0]) + lift
			pts.append(p)
		_quad(st, pts[0], pts[1], pts[2], pts[3])
	st.generate_normals()
	_mesh(st.commit(), mat(c, arrows), Vector3.ZERO)
	if arrows:
		var k := 0
		var s := s0 + 1.0
		while s < s1 - 0.5:
			var p := r.world_at(s, 0)
			p.y = course.surface_y(seg, s) + lift + 0.02
			var pr := PrismMesh.new()
			pr.size = Vector3(hw * 1.1, 0.9, 0.05)
			_mesh(pr, mat(Color(1, 1, 0.6), true), p, null, Vector3(-PI / 2, r.heading_at(s), 0)).rotation_order = EULER_ORDER_YXZ
			s += 2.5
			k += 1


func _edges(seg: Dictionary) -> void:
	var r: Route = seg["route"]
	var hw: float = seg["half_width"]
	var s := 0.0
	var k := 0
	while s < r.length:
		for side in [-1.0, 1.0]:
			var p := r.world_at(s + 0.6, side * (hw + 0.15))
			p.y = course.surface_y(seg, s + 0.6) + 0.06
			var c := Color(0.95, 0.2, 0.2) if k % 2 == 0 else Color(1, 1, 1)
			_box(Vector3(0.3, 0.12, 1.2), c, p, Vector3(0, r.heading_at(s + 0.6), 0))
		s += 1.2
		k += 1


func _rails(seg: Dictionary) -> void:
	var r: Route = seg["route"]
	var hw: float = seg["half_width"]
	var s := 1.0
	while s < r.length - 1.0:
		for side in [-1.0, 1.0]:
			var p := r.world_at(s, side * (hw + 0.35))
			p.y = course.surface_y(seg, s) + 0.45
			_box(Vector3(0.15, 0.9, 0.15), Color(0.55, 0.35, 0.2), p)
			var q := r.world_at(s + 1.0, side * (hw + 0.35))
			q.y = course.surface_y(seg, s + 1.0) + 0.85
			var mid := (Vector3(p.x, p.y + 0.4, p.z) + q) * 0.5
			_box(Vector3(0.1, 0.1, 2.05), Color(0.85, 0.3, 0.25), mid, Vector3(0, r.heading_at(s + 1.0), 0))
		s += 2.0


func _supports(seg: Dictionary) -> void:
	var r: Route = seg["route"]
	var s := 6.0
	while s < r.length - 6.0:
		var y := course.surface_y(seg, s)
		if y > 0.6:
			for side in [-1.0, 1.0]:
				var p := r.world_at(s, side * float(seg["half_width"]) * 0.8)
				p.y = y * 0.5 - 0.4
				_box(Vector3(0.35, y + 0.8, 0.35), Color(0.45, 0.3, 0.2), p)
		s += 4.0


func _section_lines() -> void:
	for id in course.ordered_ids:
		var seg: Dictionary = course.segments[id]
		if seg["choice"] in ["around", "bridge", "sheltered"]:
			continue
		var prev_section := ""
		var idx := course.ordered_ids.find(id)
		if idx > 0:
			prev_section = course.segments[course.ordered_ids[idx - 1]]["section"]
		if prev_section != "" and prev_section != seg["section"]:
			_checker(seg, 0.0, 6)
	var bends: Dictionary = course.segments["bends"]
	_checker(bends, (bends["route"] as Route).length - 0.6, 10)
	_checker(course.segments["start"], 0.4, 8)


func _checker(seg: Dictionary, s: float, n: int) -> void:
	var r: Route = seg["route"]
	var hw: float = seg["half_width"]
	for row in 2:
		for i in n:
			var d := -hw + (i + 0.5) * 2.0 * hw / n
			var p := r.world_at(s + row * 0.5, d)
			p.y = course.surface_y(seg, s) + 0.05
			var c := Color.WHITE if (i + row) % 2 == 0 else Color(0.1, 0.1, 0.1)
			_box(Vector3(2.0 * hw / n, 0.04, 0.5), c, p, Vector3(0, r.heading_at(s), 0))


# ---------------------------------------------------------------- set pieces

func _start_gate() -> void:
	var z := 1.0
	for x in [-6.0, 6.0]:
		_box(Vector3(0.6, 4.5, 0.6), Color(0.3, 0.5, 0.95), Vector3(x, 2.25, z))
	_box(Vector3(12.6, 0.9, 0.6), Color(1.0, 0.85, 0.2), Vector3(0, 4.6, z))
	var l := Label3D.new()
	l.text = "BEBBIKART"
	l.font_size = 96
	l.pixel_size = 0.01
	l.modulate = Color(0.2, 0.2, 0.5)
	l.position = Vector3(0, 4.6, z - 0.35)
	l.rotation = Vector3(0, PI, 0)
	root.add_child(l)
	# Start pads for the four lanes.
	for lane in [-3.0, -1.0, 1.0, 3.0]:
		_box(Vector3(1.6, 0.03, 2.0), Color(1, 1, 1), Vector3(lane, 0.04, 2.5))


func _castle(c: Vector3) -> void:
	var wall := Color(0.92, 0.88, 0.95)
	_box(Vector3(22, 6, 3), wall, c + Vector3(0, 3, 4))
	_box(Vector3(7, 4.6, 3.2), Color(0.3, 0.2, 0.2), c + Vector3(0, 2.3, 4))  # gate
	for x in [-11.0, 11.0, -4.5, 4.5]:
		var t := CylinderMesh.new()
		t.top_radius = 1.8 if absf(x) > 5 else 1.3
		t.bottom_radius = t.top_radius
		t.height = 9.0 if absf(x) > 5 else 8.0
		_mesh(t, mat(wall), c + Vector3(x, t.height / 2, 4))
		var roof := CylinderMesh.new()
		roof.top_radius = 0.0
		roof.bottom_radius = t.top_radius + 0.4
		roof.height = 3.2
		var rc: Color = [Color(0.95, 0.35, 0.5), Color(0.4, 0.6, 1.0), Color(1.0, 0.75, 0.2)][rng.randi_range(0, 2)]
		_mesh(roof, mat(rc), c + Vector3(x, t.height + 1.6, 4))
	for i in 9:
		_box(Vector3(1.2, 1.0, 3), wall, c + Vector3(-10 + i * 2.5, 6.5, 4))
	var flag := _box(Vector3(1.6, 1.0, 0.05), Color(1, 0.3, 0.3), c + Vector3(-10.2, 13.7, 4))
	flag.name = "Flag"
	var l := Label3D.new()
	l.text = "FINISH"
	l.font_size = 128
	l.pixel_size = 0.012
	l.modulate = Color(1, 0.85, 0.2)
	l.outline_size = 24
	l.position = c + Vector3(0, 5.2, 2.4)
	l.rotation = Vector3(0, PI, 0)
	root.add_child(l)


func _hedges(seg: Dictionary) -> void:
	var r: Route = seg["route"]
	var hw: float = seg["half_width"]
	var s := 4.0
	while s < r.length - 4.0:
		for side in [-1.0, 1.0]:
			var p := r.world_at(s, side * (hw + 1.2))
			p.y = 0.8
			_box(Vector3(1.2, 1.6, 2.1), Color(0.2, 0.5, 0.22), p, Vector3(0, r.heading_at(s), 0))
		s += 2.0


func _scenery() -> void:
	var tries := 0
	var placed := 0
	while placed < 140 and tries < 3000:
		tries += 1
		var pos := Vector3(rng.randf_range(GROUND_RECT.position.x + 4, GROUND_RECT.end.x - 4), 0,
			rng.randf_range(GROUND_RECT.position.y + 4, GROUND_RECT.end.y - 4))
		if POND_RECT.grow(2.0).has_point(Vector2(pos.x, pos.z)) or _near_track(pos, 5.0):
			continue
		if absf(pos.x) < 16 and pos.z > _finish_z() + 4 and pos.z < _finish_z() + 24:
			continue
		placed += 1
		match rng.randi_range(0, 3):
			0, 1:
				_tree(pos)
			2:
				var c := Color.from_hsv(rng.randf(), 0.6, 0.95)
				var sz := rng.randf_range(0.8, 2.2)
				_box(Vector3(sz, sz, sz), c, pos + Vector3(0, sz / 2, 0), Vector3(0, rng.randf() * TAU, 0))
			3:
				var sp := SphereMesh.new()
				sp.radius = rng.randf_range(0.6, 1.4)
				sp.height = sp.radius * 2
				_mesh(sp, mat(Color.from_hsv(rng.randf(), 0.5, 1.0)), pos + Vector3(0, sp.radius, 0))


func _tree(pos: Vector3) -> void:
	var h := rng.randf_range(1.2, 2.4)
	var t := CylinderMesh.new()
	t.top_radius = 0.2
	t.bottom_radius = 0.28
	t.height = h
	_mesh(t, mat(Color(0.5, 0.33, 0.2)), pos + Vector3(0, h / 2, 0))
	var crown := SphereMesh.new()
	crown.radius = rng.randf_range(1.0, 1.8)
	crown.height = crown.radius * 2
	_mesh(crown, mat(Color(0.2, 0.55 + rng.randf() * 0.2, 0.25)), pos + Vector3(0, h + crown.radius * 0.7, 0))


func _near_track(pos: Vector3, margin: float) -> bool:
	for id in course.segments:
		var seg: Dictionary = course.segments[id]
		var r: Route = seg["route"]
		var hw: float = seg["half_width"]
		var s := 0.0
		while s <= r.length:
			var p := r.pos_at(s)
			if Vector2(p.x - pos.x, p.z - pos.z).length() < hw + margin:
				return true
			s += 2.0
	return false

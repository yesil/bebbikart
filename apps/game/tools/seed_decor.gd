extends SceneTree
## Seeds res://world/decor.tscn, the hand-editable landmark layer, from the course data:
##   godot --headless --path apps/game --script res://tools/seed_decor.gd [-- --force]
## It refuses to overwrite an existing decor.tscn unless --force is given: after seeding, the
## scene belongs to whoever edits it in the Godot editor (move, rescale, restyle freely).
## Contents: start grid + gantry, finish line + gantry + flags, grandstand, signposts at the
## three fork splits, the stone bridge carrying the lakeside lane over the stream, ford posts.

const Course = preload("res://sim/course.gd")
const Route = preload("res://sim/route.gd")
const Landscape = preload("res://world/landscape.gd")
const TerrainShape = preload("res://world/terrain_shape.gd")
const MeshBatch = preload("res://world/mesh_batch.gd")

const DECOR_PATH := "res://world/decor.tscn"
const MAT_DIR := "res://world/materials/"
const TEX := "res://assets/textures/"

var course: Course
var land: Landscape
var shape: TerrainShape
var decor: Node3D
var mats := {}
var failed := false


func _initialize() -> void:
	var force := "--force" in OS.get_cmdline_user_args()
	if ResourceLoader.exists(DECOR_PATH) and not force:
		push_error("seed_decor: %s exists and is hand-edited; pass --force to replace it" % DECOR_PATH)
		quit(1)
		return
	course = Course.new()
	land = Landscape.new(course)
	shape = TerrainShape.new(course, land)
	shape.build()
	decor = Node3D.new()
	decor.name = "Decor"
	_materials()
	_start()
	_finish()
	_grandstand()
	_signposts()
	_stone_bridge()
	_ford_posts()
	if failed:
		push_error("seed_decor: errors above, %s NOT saved" % DECOR_PATH)
		quit(1)
		return
	_own(decor)
	var ps := PackedScene.new()
	ps.pack(decor)
	var err := ResourceSaver.save(ps, DECOR_PATH)
	if err != OK:
		push_error("seed_decor: saving failed (%d)" % err)
		quit(1)
		return
	print("seed_decor: saved %s" % DECOR_PATH)
	quit(0)


func _own(n: Node) -> void:
	for c in n.get_children():
		c.owner = decor
		_own(c)


func _res(path: String) -> Resource:
	var r: Resource = load(path) if ResourceLoader.exists(path) else null
	if r == null:
		push_error("seed_decor: missing resource %s" % path)
		failed = true
	return r


# ---------------------------------------------------------------- materials

func _materials() -> void:
	mats.wood = _res(MAT_DIR + "wood_dark.tres")
	mats.wood_light = _res(MAT_DIR + "wood_light.tres")
	mats.white = _res(MAT_DIR + "paint_white.tres")
	mats.yellow = _res(MAT_DIR + "paint_yellow.tres")
	mats.stone = _std("stone_bricks", "Bricks076C", Color(1.05, 1.02, 0.95), 0.9, Vector3(0.5, 0.5, 0.5))
	mats.metal_red = _plain("painted_red", Color(0.82, 0.13, 0.12), 0.45, 0.3)
	mats.metal_blue = _plain("painted_blue", Color(0.12, 0.32, 0.78), 0.45, 0.3)
	mats.metal_grey = _plain("painted_grey", Color(0.62, 0.64, 0.66), 0.4, 0.6)
	mats.seat_colors = [_plain("seat_red", Color(0.85, 0.2, 0.18), 0.6, 0.0), _plain("seat_yellow", Color(0.95, 0.75, 0.15), 0.6, 0.0),
		_plain("seat_blue", Color(0.15, 0.45, 0.85), 0.6, 0.0), _plain("seat_green", Color(0.2, 0.65, 0.3), 0.6, 0.0)]
	mats.banner = _plain("banner_white", Color(0.97, 0.97, 0.95), 0.8, 0.0)
	mats.lamp_red = _emissive("lamp_red", Color(1.0, 0.12, 0.1))
	mats.lamp_green = _emissive("lamp_green", Color(0.2, 1.0, 0.3))
	mats.checker_road = _checker("checker_road", Vector2(10.0, 2.0), 0.0012)
	mats.checker_banner = _checker("checker_banner", Vector2(24.0, 2.0), 0.0)


func _std(name: String, tex: String, tint: Color, rough: float, uv: Vector3) -> Material:
	var path := MAT_DIR + name + ".tres"
	if not ResourceLoader.exists(path):
		var m := StandardMaterial3D.new()
		var base := TEX + "%s/%s_1K-JPG_" % [tex, tex]
		m.albedo_texture = _res(base + "Color.jpg")
		m.albedo_color = tint
		m.normal_enabled = true
		m.normal_texture = _res(base + "NormalGL.jpg")
		m.roughness_texture = _res(base + "Roughness.jpg")
		m.roughness = rough
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = uv
		ResourceSaver.save(m, path)
	return _res(path) as Material


func _plain(name: String, c: Color, rough: float, metal: float) -> Material:
	var path := MAT_DIR + name + ".tres"
	if not ResourceLoader.exists(path):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		ResourceSaver.save(m, path)
	return _res(path) as Material


func _emissive(name: String, c: Color) -> Material:
	var path := MAT_DIR + name + ".tres"
	if not ResourceLoader.exists(path):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 2.5
		ResourceSaver.save(m, path)
	return _res(path) as Material


func _checker(name: String, cells: Vector2, pull: float) -> Material:
	var path := MAT_DIR + name + ".tres"
	if not ResourceLoader.exists(path):
		var m := ShaderMaterial.new()
		m.shader = _res(MAT_DIR + "checker.gdshader")
		m.set_shader_parameter("cells", cells)
		m.set_shader_parameter("depth_pull", pull)
		ResourceSaver.save(m, path)
	return _res(path) as Material


func _flag_mat(name: String, c: Color, c2: Color, stripes: float, amplitude := 0.12) -> Material:
	var path := MAT_DIR + name + ".tres"
	if not ResourceLoader.exists(path):
		var m := ShaderMaterial.new()
		m.shader = _res(MAT_DIR + "flag.gdshader")
		m.set_shader_parameter("color", c)
		m.set_shader_parameter("color2", c2)
		m.set_shader_parameter("stripes", stripes)
		m.set_shader_parameter("amplitude", amplitude)
		ResourceSaver.save(m, path)
	return _res(path) as Material


# ---------------------------------------------------------------- node helpers

func _group(parent: Node, name: String, xf := Transform3D.IDENTITY) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.transform = xf
	parent.add_child(n)
	return n


func _box(parent: Node, name: String, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _cyl(parent: Node, name: String, r: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	mi.mesh = c
	mi.material_override = mat
	mi.position = pos + Vector3(0, h * 0.5, 0)
	parent.add_child(mi)
	return mi


func _label(parent: Node, name: String, text: String, pos: Vector3, px: float, col: Color, rot_y := 0.0) -> Label3D:
	var l := Label3D.new()
	l.name = name
	l.text = text
	l.font_size = 128
	l.pixel_size = px
	l.outline_size = 18
	l.modulate = col
	l.outline_modulate = Color(0.05, 0.05, 0.08)
	l.position = pos
	l.rotation.y = rot_y
	l.double_sided = false
	parent.add_child(l)
	return l


func _flag(parent: Node, name: String, pos: Vector3, mat: Material, w := 1.2, h := 0.8, pole := 4.5) -> void:
	var g := _group(parent, name, Transform3D(Basis.IDENTITY, pos))
	_cyl(g, "Pole", 0.05, pole, Vector3.ZERO, mats.metal_grey)
	var cloth := MeshInstance3D.new()
	cloth.name = "Cloth"
	var pm := PlaneMesh.new()
	pm.size = Vector2(w, h)
	pm.subdivide_width = 12
	pm.orientation = PlaneMesh.FACE_Z
	cloth.mesh = pm
	cloth.material_override = mat
	cloth.position = Vector3(w * 0.5, pole - h * 0.5 - 0.1, 0)
	g.add_child(cloth)


## Frame on the road at route distance s: origin on the centre line at road height, -Z along
## the direction of travel... expressed as basis (x = right of travel, y = up, z = forward).
func _road_xf(r: Route, s: float) -> Transform3D:
	var p := r.pos_at(s)
	var fwd := r.tangent_at(s)
	return Transform3D(Basis(fwd.cross(Vector3.UP) * -1.0, Vector3.UP, fwd), p)


func _ground(p: Vector3) -> float:
	return shape.height_at(p.x, p.z)


# ---------------------------------------------------------------- start / finish

func _start() -> void:
	var seg: Dictionary = course.segments["start"]
	var r: Route = seg["route"]
	var hw: float = seg["half_width"]
	var g := _group(decor, "StartGrid", _road_xf(r, 0.0))
	# Chequered start line across the road and four grid slots behind it.
	var line := MeshInstance3D.new()
	line.name = "StartLine"
	var q := PlaneMesh.new()
	q.size = Vector2(2.0 * hw, 1.0)
	line.mesh = q
	line.material_override = mats.checker_road
	line.position = Vector3(0, 0.015, 1.2)
	g.add_child(line)
	for lane in [-3.0, -1.0, 1.0, 3.0]:
		var slot := _group(g, "Slot_%+d" % int(lane), Transform3D(Basis.IDENTITY, Vector3(lane, 0.015, -0.4)))
		for side: float in [-1.0, 1.0]:
			_box(slot, "Side%+d" % int(side), Vector3(0.1, 0.01, 1.8), Vector3(side * 0.85, 0, 0), mats.white)
		_box(slot, "Front", Vector3(1.8, 0.01, 0.1), Vector3(0, 0, 0.85), mats.white)
	_gantry(g, "StartGantry", 3.5, hw, "START", mats.metal_blue, true)


func _finish() -> void:
	var seg: Dictionary = course.segments["bends"]
	var r: Route = seg["route"]
	var hw: float = seg["half_width"]
	var L := r.length
	var g := _group(decor, "Finish", _road_xf(r, L))
	var line := MeshInstance3D.new()
	line.name = "FinishLine"
	var q := PlaneMesh.new()
	q.size = Vector2(2.0 * hw + 1.0, 1.4)
	line.mesh = q
	line.material_override = mats.checker_road
	line.position = Vector3(0, 0.015, -0.7)
	g.add_child(line)
	_gantry(g, "FinishGantry", 0.0, hw + 0.6, "FINISH", mats.metal_red, false)
	# Flag line on both sides of the finish straight.
	var colors := [Color(0.9, 0.15, 0.15), Color(1.0, 0.8, 0.1), Color(0.15, 0.45, 0.9), Color(0.2, 0.7, 0.3)]
	var i := 0
	for s in range(int(L) - 26, int(L) - 2, 6):
		for side: float in [-1.0, 1.0]:
			var p := r.world_at(float(s), side * (hw + 2.4))
			p.y = _ground(p)
			_flag(decor, "Flag_%d_%s" % [s, "L" if side < 0.0 else "R"], p,
				_flag_mat("flag_%d" % (i % 4), colors[i % 4], Color.WHITE, 0.0))
			i += 1


## Gantry spanning the road: two lattice towers, a deep beam with a chequered trim and the
## caption on both faces. z_off along the road from the group origin.
func _gantry(parent: Node, name: String, z_off: float, half_span: float, caption: String, paint: Material, lights: bool) -> void:
	var g := _group(parent, name, Transform3D(Basis.IDENTITY, Vector3(0, 0, z_off)))
	var h := 5.6
	var x := half_span + 0.9
	for side: float in [-1.0, 1.0]:
		var tower := _group(g, "Tower" + ("L" if side < 0.0 else "R"), Transform3D(Basis.IDENTITY, Vector3(side * x, 0, 0)))
		var mb := MeshBatch.new()
		for cx: float in [-0.35, 0.35]:
			for cz: float in [-0.35, 0.35]:
				mb.box(Transform3D(Basis.IDENTITY, Vector3(cx, h * 0.5, cz)), Vector3(0.14, h, 0.14))
		var y := 0.4
		while y < h:
			for face in [[Vector3(-0.35, y, -0.35), Vector3(0.35, y + 0.7, -0.35)], [Vector3(-0.35, y, 0.35), Vector3(0.35, y + 0.7, 0.35)],
					[Vector3(-0.35, y, -0.35), Vector3(-0.35, y + 0.7, 0.35)], [Vector3(0.35, y, -0.35), Vector3(0.35, y + 0.7, 0.35)]]:
				mb.beam(face[0], face[1], 0.06, 0.06)
			y += 0.7
		var mi := MeshInstance3D.new()
		mi.name = "Lattice"
		mi.mesh = mb.commit(paint)
		tower.add_child(mi)
		_box(tower, "Foot", Vector3(1.2, 0.3, 1.2), Vector3(0, 0.15, 0), mats.metal_grey)
	var span := 2.0 * x + 0.8
	_box(g, "Beam", Vector3(span, 1.6, 0.5), Vector3(0, h + 0.5, 0), mats.banner)
	for yy: float in [h - 0.15, h + 1.15]:
		var trim := _box(g, "Trim_%d" % int(yy * 10), Vector3(span, 0.3, 0.52), Vector3(0, yy, 0), mats.checker_banner)
		trim.name = "Trim" + ("Low" if yy < h else "High")
	_label(g, "CaptionFront", caption, Vector3(0, h + 0.5, -0.27), 0.009, Color(0.1, 0.1, 0.14), PI)
	_label(g, "CaptionBack", caption, Vector3(0, h + 0.5, 0.27), 0.009, Color(0.1, 0.1, 0.14))
	if lights:
		for k in 5:
			var lx := -1.6 + k * 0.8
			_box(g, "LampHousing%d" % k, Vector3(0.6, 0.6, 0.3), Vector3(lx, h - 0.6, -0.15), mats.metal_grey)
			var lamp := _cyl(g, "Lamp%d" % k, 0.2, 0.12, Vector3(lx, h - 0.6, -0.33), mats.lamp_green if k == 4 else mats.lamp_red)
			lamp.rotation.x = PI * 0.5


func _grandstand() -> void:
	var seg: Dictionary = course.segments["bends"]
	var r: Route = seg["route"]
	var L := r.length
	var hw: float = seg["half_width"]
	var s := L - 12.0
	var p := r.world_at(s, hw + 6.5)
	p.y = _ground(p)
	var fwd := r.tangent_at(s)
	# Faces the road: local -X points at the track.
	var right := fwd.cross(Vector3.UP) * -1.0
	var g := _group(decor, "Grandstand", Transform3D(Basis(fwd * -1.0, Vector3.UP, right), p))
	var length := 18.0
	var steps := 5
	for k in steps:
		var y := 0.45 * (k + 1)
		var x := 1.0 * k
		_box(g, "Step%d" % k, Vector3(length, y, 1.0), Vector3(0, y * 0.5, x), mats.metal_grey)
		var n := 12
		for i in n:
			var sx := -length * 0.5 + 0.75 + i * (length - 1.5) / (n - 1)
			_box(g, "Seat%d_%d" % [k, i], Vector3(0.55, 0.12, 0.45), Vector3(sx, y + 0.06, x - 0.1), mats.seat_colors[(i + k) % 4])
	var top := 0.45 * steps
	for xi: float in [-length * 0.5, length * 0.5]:
		for zi: float in [0.0, steps * 1.0]:
			_cyl(g, "Post_%d_%d" % [int(xi), int(zi)], 0.08, top + 2.4, Vector3(xi, 0, zi), mats.metal_grey)
	_box(g, "Roof", Vector3(length + 0.6, 0.15, steps + 1.2), Vector3(0, top + 2.45, steps * 0.5 - 0.3), mats.metal_blue, Vector3(-0.08, 0, 0))
	_box(g, "Backboard", Vector3(length, 2.2, 0.1), Vector3(0, top + 1.3, steps * 1.0 + 0.4), mats.banner)
	_label(g, "Sponsor", "BEBBIKART", Vector3(0, top + 1.3, steps * 1.0 + 0.34), 0.012, Color(0.85, 0.15, 0.15))


# ---------------------------------------------------------------- forks

## Signpost on the island where each fork's branches separate, facing the oncoming racers.
func _signposts() -> void:
	var forks := [
		["ramp", "ramp_jump", "ramp_around", "JUMP", "AROUND"],
		["pond", "pond_water", "pond_bridge", "FORD", "BRIDGE"],
		["crossing", "cross_exposed", "cross_sheltered", "CAUSEWAY", "LANE"],
	]
	for f in forks:
		var direct: Dictionary = course.segments[f[1]]
		var detour: Dictionary = course.segments[f[2]]
		var rd: Route = direct["route"]
		var rt: Route = detour["route"]
		var need: float = float(direct["half_width"]) + float(detour["half_width"]) + 3.0
		var s := 2.0
		while s < rt.length * 0.5:
			var p := rt.pos_at(s)
			var q := rd.pos_at(_closest_s(rd, Vector2(p.x, p.z)))
			if Vector2(p.x - q.x, p.z - q.z).length() >= need:
				break
			s += 0.5
		var p := rt.pos_at(s)
		var q := rd.pos_at(_closest_s(rd, Vector2(p.x, p.z)))
		var mid := (p + q) * 0.5
		mid.y = _ground(mid)
		var fwd := rd.tangent_at(0.0)
		var g := _group(decor, "Signpost_" + f[0], Transform3D(Basis(fwd.cross(Vector3.UP) * -1.0, Vector3.UP, fwd), mid))
		_cyl(g, "Post", 0.12, 3.4, Vector3.ZERO, mats.wood)
		var detour_side := signf((p - q).dot(fwd.cross(Vector3.UP) * -1.0))
		for k in 2:
			var to_detour := k == 1
			var side := detour_side if to_detour else -detour_side
			var y := 3.0 - k * 0.85
			var board := _group(g, "Arrow" + str(k), Transform3D(Basis.IDENTITY, Vector3(side * 1.0, y, 0)))
			_box(board, "Board", Vector3(2.0, 0.7, 0.08), Vector3.ZERO, mats.wood_light)
			var tip := _box(board, "Tip", Vector3(0.5, 0.5, 0.08), Vector3(side * 1.0, 0, 0), mats.wood_light, Vector3(0, 0, PI * 0.25))
			tip.name = "Tip"
			_label(board, "Text", f[4] if to_detour else f[3], Vector3(0, 0, -0.05), 0.0042, Color(0.12, 0.08, 0.05), PI)


func _closest_s(r: Route, p: Vector2) -> float:
	var best := INF
	var best_s := 0.0
	var s := 0.0
	while s <= r.length:
		var q := r.pos_at(s)
		var d := Vector2(q.x, q.z).distance_to(p)
		if d < best:
			best = d
			best_s = s
		s += 0.25
	return best_s


## Stone parapets and abutments where the lakeside lane crosses the stream.
func _stone_bridge() -> void:
	var seg: Dictionary = course.segments["pond_bridge"]
	var r: Route = seg["route"]
	var hump := _closest_s(r, Vector2(land.bridge_hump.x, land.bridge_hump.z))
	var g := _group(decor, "StoneBridge")
	var walls := MeshBatch.new(1.0)
	var hw: float = seg["half_width"] + 0.35
	var prev := {}
	var s := hump - 9.0
	while s <= hump + 9.0:
		var c := r.pos_at(s)
		var nrm := r.normal_at(s)
		for side: float in [-1.0, 1.0]:
			var top := c + nrm * side * (hw + 0.2) + Vector3(0, 0.65, 0)
			if prev.has(side):
				walls.beam(prev[side], top, 0.4, 1.3, Vector3.UP)
			prev[side] = top
		s += 1.0
	# Abutments: stone walls down to the stream bed on each bank, under the deck edges.
	for off: float in [-3.4, 3.4]:
		var c := r.pos_at(hump + off)
		var nrm := r.normal_at(hump + off)
		var a := c - nrm * (hw + 0.4)
		var b := c + nrm * (hw + 0.4)
		var bed := minf(_ground(a), _ground(b)) - 0.6
		var mid := (a + b) * 0.5
		walls.box(Transform3D(Basis(nrm, Vector3.UP, r.tangent_at(hump + off)), Vector3(mid.x, (c.y - 0.45 + bed) * 0.5, mid.z)),
			Vector3(2.0 * (hw + 0.4), c.y - 0.45 - bed, 0.9))
	var mi := MeshInstance3D.new()
	mi.name = "Walls"
	mi.mesh = walls.commit(mats.stone)
	g.add_child(mi)


## Red-and-white depth posts at both ends of the ford so the water route reads instantly.
func _ford_posts() -> void:
	var seg: Dictionary = course.segments["pond_water"]
	var r: Route = seg["route"]
	var wr: Array = seg["water"][0]
	var g := _group(decor, "FordPosts")
	var stripe := _flag_mat("depth_post", Color(0.85, 0.12, 0.1), Color.WHITE, 6.0, 0.0)
	var i := 0
	for s: float in [float(wr[0]) + 3.0, float(wr[1]) - 3.0]:
		for side: float in [-1.0, 1.0]:
			var p := r.world_at(s, side * (float(seg["half_width"]) + 0.6))
			p.y = _ground(p)
			var post := _cyl(g, "Post%d" % i, 0.08, 1.6, p - Vector3(0, 0.4, 0), stripe)
			post.name = "Post%d" % i
			i += 1

class_name KitParts
extends RefCounted
## Toy part factory. Every function returns plain nodes painted with the shared toon
## material. Geometry is cached in KitMesh, so this only allocates nodes.
## Frame: -Z forward, +X right, +Y up, metres.

const DARK := Color("#3a2f3a")
const WHITE := Color("#fffaf2")
const GOLD := Color("#ffc93c")

const BODY_PARAMS := {
	"bean": {"ax": 0.19, "ay": 0.24, "az": 0.17, "n": 2.2, "taper": 0.12, "flat_bottom": 0.25},
	"round": {"ax": 0.22, "ay": 0.22, "az": 0.2, "n": 2.0, "flat_bottom": 0.2},
	"pear": {"ax": 0.21, "ay": 0.24, "az": 0.19, "n": 2.0, "taper": 0.35, "flat_bottom": 0.3},
	"box": {"ax": 0.19, "ay": 0.23, "az": 0.16, "n": 4.0, "flat_bottom": 0.1},
	"tall": {"ax": 0.15, "ay": 0.3, "az": 0.14, "n": 2.3, "taper": 0.1, "flat_bottom": 0.2},
	"star": {"ax": 0.22, "ay": 0.24, "az": 0.13, "n": 2.0, "flat_bottom": 0.15},
}

const HEAD_PARAMS := {
	"round": {"ax": 0.21, "ay": 0.2, "az": 0.2, "n": 2.0},
	"oval": {"ax": 0.18, "ay": 0.24, "az": 0.19, "n": 2.0},
	"square": {"ax": 0.2, "ay": 0.19, "az": 0.18, "n": 4.0},
	"wide": {"ax": 0.26, "ay": 0.17, "az": 0.2, "n": 2.4},
	"drop": {"ax": 0.2, "ay": 0.23, "az": 0.2, "n": 2.0, "taper": 0.38, "nose": 0.0},
}


static func mi(mesh: Mesh, color: Color, pos := Vector3.ZERO, glow := 0.0) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.position = pos
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	KitMaterial.paint(m, color, glow)
	return m


static func node(name: String, pos := Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	return n


## Dome = top half of a blob with a flat base at y=0 (hair caps, hats, helmets).
static func dome(ax: float, ay: float, az: float, n := 2.0) -> Mesh:
	return KitMesh.blob({"ax": ax, "ay": ay, "az": az, "n": n, "flat_bottom": 0.96}, 10, 20)


## Rotates a node so its local +Y points along dir.
static func aim_y(n: Node3D, dir: Vector3) -> void:
	if dir.length_squared() < 1e-6:
		return
	n.quaternion = Quaternion(Vector3.UP, dir.normalized())


## Rotates a node so its local +Z points along dir (flat features on surfaces).
static func aim_z(n: Node3D, dir: Vector3) -> void:
	if dir.length_squared() < 1e-6:
		return
	var z := dir.normalized()
	var up := Vector3.UP if absf(z.y) < 0.95 else Vector3.BACK
	var x := up.cross(z).normalized()
	n.basis = Basis(x, z.cross(x), z)


# --- character ---

## Clothes over a body blob (p = body params, bscale = body scale, cy = body centre height).
static func outfit(type: String, color: Color, p: Dictionary, bscale: Vector3, cy: float) -> Node3D:
	var root := node("Outfit_" + type)
	var ax: float = p.ax * bscale.x
	var ay: float = p.ay * bscale.y
	var zr: float = p.az / p.ax * bscale.z / bscale.x  # keep the body's depth/width ratio
	var band := func(y0: float, y1: float, r0: float, r1: float) -> MeshInstance3D:
		var m := mi(KitMesh.cylinder(r1, r0, y1 - y0, 24), color, Vector3(0, (y0 + y1) * 0.5, 0))
		m.scale = Vector3(1, 1, zr)
		return m
	match type:
		"tshirt", "jacket":
			root.add_child(band.call(cy - ay * 0.15, cy + ay * 0.6, ax * 1.06, ax * 0.98))
			for s in [-1, 1]:
				root.add_child(mi(KitMesh.sphere(ax * 0.32), color, Vector3(s * ax * 0.92, cy + ay * 0.45, 0)))
			if type == "jacket":
				var collar := mi(KitMesh.torus(ax * 0.55, ax * 0.72), color.darkened(0.15), Vector3(0, cy + ay * 0.72, 0))
				collar.scale = Vector3(1, 1.4, zr)
				root.add_child(collar)
		"dress":
			root.add_child(band.call(ay * 0.05, cy + ay * 0.55, ax * 1.5, ax * 1.0))
		"skirt":
			root.add_child(band.call(ay * 0.12, cy - ay * 0.05, ax * 1.45, ax * 1.04))
		"ruffle_skirt":
			# Two flared tiers with a puffy frill at each hem.
			root.add_child(band.call(ay * 0.3, cy - ay * 0.05, ax * 1.35, ax * 1.04))
			root.add_child(band.call(ay * 0.0, ay * 0.32, ax * 1.65, ax * 1.3))
			for hem in [[ay * 0.3, ax * 1.33], [ay * 0.0, ax * 1.63]]:
				var frill := mi(KitMesh.torus(hem[1] - 0.025, hem[1] + 0.02), color.lightened(0.12), Vector3(0, hem[0], 0))
				frill.scale = Vector3(1, 1.6, zr)
				root.add_child(frill)
		"shorts":
			root.add_child(band.call(ay * 0.05, cy - ay * 0.1, ax * 1.08, ax * 1.05))
		"overalls":
			root.add_child(band.call(ay * 0.05, cy - ay * 0.05, ax * 1.08, ax * 1.05))
			var bib := mi(KitMesh.rounded_box(Vector3(ax * 0.9, ay * 0.6, 0.03)), color, Vector3(0, cy + ay * 0.2, -p.az * bscale.z * 0.98))
			root.add_child(bib)
			for s in [-1, 1]:
				root.add_child(mi(KitMesh.sphere(0.022), GOLD, Vector3(s * ax * 0.35, cy + ay * 0.45, -p.az * bscale.z - 0.01)))
	return root


## Two legs from the hips with shoes. sitting: legs reach forward (-Z); otherwise straight down.
## socks: Color for knee socks over the lower half of each leg, or null.
static func legs(color: Color, shoes: String, shoe_color: Color, p: Dictionary, bscale: Vector3, length: float, sitting: bool, socks: Variant = null) -> Node3D:
	var root := node("Legs")
	for s in [-1, 1]:
		var hip := Vector3(s * p.ax * bscale.x * 0.45, p.ay * bscale.y * 0.25, 0)
		var dir := Vector3(0, -0.45, -1).normalized() if sitting else Vector3.DOWN
		var leg := node("Leg", hip)
		aim_y(leg, -dir)
		leg.add_child(mi(KitMesh.capsule(0.045, length + 0.06), color, Vector3(0, -length / 2, 0)))
		if socks != null:
			leg.add_child(mi(KitMesh.capsule(0.05, length * 0.55), socks, Vector3(0, -length * 0.75, 0)))
		var foot := node("Foot", Vector3(0, -length, 0))
		foot.basis = leg.basis.inverse()  # shoes stay level with the ground
		match shoes:
			"sneakers":
				foot.add_child(mi(KitMesh.rounded_box(Vector3(0.11, 0.07, 0.17)), shoe_color, Vector3(0, -0.01, -0.03)))
				foot.add_child(mi(KitMesh.rounded_box(Vector3(0.115, 0.02, 0.175)), WHITE, Vector3(0, -0.045, -0.03)))
			"boots":
				foot.add_child(mi(KitMesh.capsule(0.06, 0.2), shoe_color, Vector3(0, 0.05, 0)))
				foot.add_child(mi(KitMesh.rounded_box(Vector3(0.12, 0.07, 0.17)), shoe_color, Vector3(0, -0.03, -0.03)))
			_:
				foot.add_child(mi(KitMesh.sphere(0.055), color.lightened(0.1)))
		leg.add_child(foot)
		root.add_child(leg)
	return root


## Body mesh whose bottom sits at y=0. Returns {node, params, top, center}.
static func body(shape: String, color: Color) -> Dictionary:
	var p: Dictionary = BODY_PARAMS.get(shape, BODY_PARAMS.bean)
	var cy: float = p.ay * (1.0 - p.get("flat_bottom", 0.0))
	var m := mi(KitMesh.blob(p), color, Vector3(0, cy, 0))
	if shape == "star":
		# Chunky five-point star; blob params stay for sockets/face placement.
		var o := KitMesh.star_outline(5, p.ay * 1.12, p.ay * 0.62)
		m.mesh = KitMesh.puffy(o, p.az * 2.0, "body_star")
	m.name = "BodyMesh"
	return {"node": m, "params": p, "center": cy, "top": cy + p.ay * 0.92}


static func head_mesh(shape: String, color: Color) -> MeshInstance3D:
	var m := mi(KitMesh.blob(HEAD_PARAMS.get(shape, HEAD_PARAMS.round)), color)
	m.name = "HeadMesh"
	return m


## Point on a head/body blob surface along a face direction, pushed out by lift.
static func surface(p: Dictionary, yaw: float, pitch: float, lift := 0.0) -> Vector3:
	var d := KitMesh.face_dir(yaw, pitch)
	return KitMesh.blob_point(p, d) + KitMesh.blob_normal(p, d) * lift


## reach: distance (head-local units) from the head centre down to the seat, for hair that
## falls to the seat ("very_long", "braid").
static func hair(style: String, color: Color, p: Dictionary, reach := 1.5) -> Node3D:
	var root := node("Hair")
	var ax: float = p.ax
	var ay: float = p.ay
	var az: float = p.az
	match style:
		"spiky":
			var cap := mi(dome(ax * 1.05, ay * 0.55, az * 1.05), color, Vector3(0, ay * 0.45, az * 0.05))
			root.add_child(cap)
			for i in 9:
				var yaw := -1.2 + i * 0.3 + (0.15 if i % 2 else 0.0)
				var pitch := 0.75 + (0.35 if i % 2 else 0.0)
				var base := surface(p, yaw + PI * 0.12 * (1 if i % 3 == 0 else 0), pitch)
				var spike := mi(KitMesh.cylinder(0.0, 0.05, 0.14, 10), color, base)
				aim_y(spike, KitMesh.blob_normal(p, KitMesh.face_dir(yaw, pitch)) + Vector3(0, 0.6, 0.2))
				spike.position += spike.basis.y * 0.05
				root.add_child(spike)
		"curly":
			for i in 14:
				var yaw := -2.6 + (i % 7) * 0.87
				var pitch := 0.55 if i < 7 else 1.05
				root.add_child(mi(KitMesh.sphere(0.075), color, surface(p, yaw + PI, pitch, 0.0) * Vector3(1, 1, 1)))
			root.add_child(mi(KitMesh.sphere(0.08), color, Vector3(0, ay * 1.02, 0)))
		"long":
			var b := mi(dome(ax * 1.12, ay * 0.95, az * 1.12), color, Vector3(0, -ay * 0.25, 0))
			b.rotation.x = 0.4
			root.add_child(b)
			var back := mi(KitMesh.rounded_box(Vector3(ax * 1.9, ay * 1.5, 0.07)), color, Vector3(0, -ay * 0.45, az * 0.85))
			back.rotation.x = -0.12
			root.add_child(back)
			var fringe := mi(KitMesh.capsule(0.05, ax * 1.7), color, surface(p, 0, 0.62, 0.01))
			fringe.rotation.z = PI / 2
			root.add_child(fringe)
		"very_long", "braid":
			# Cap over the whole crown, tilted back so the face stays clear.
			var cap4 := mi(dome(ax * 1.1, ay * 1.08, az * 1.1), color, Vector3(0, -ay * 0.02, az * 0.06))
			cap4.rotation.x = 0.22
			root.add_child(cap4)
			var fr2 := mi(KitMesh.capsule(0.045, ax * 1.5), color, surface(p, 0, 0.9, 0.012))
			fr2.rotation.z = PI / 2
			root.add_child(fr2)
			if style == "very_long":
				# A curtain of hair down the back to the seat, a little wider at the bottom.
				var drop := reach + ay * 0.2
				var curtain := mi(KitMesh.cylinder(ax * 1.05, ax * 1.35, drop, 20), color, Vector3(0, -drop * 0.5 + ay * 0.1, az * 0.45))
				curtain.scale = Vector3(1, 1, 0.45)
				root.add_child(curtain)
				# Two long locks framing the face.
				for s in [-1, 1]:
					var lock := mi(KitMesh.capsule(0.055, drop * 0.75), color, Vector3(s * ax * 0.95, -drop * 0.35, az * 0.1))
					root.add_child(lock)
			else:
				# One thick braid down the back to the seat, with a tie at the end.
				var n := maxi(4, int(reach / 0.11))
				for i in n:
					var t := float(i) / float(n - 1)
					var bead := mi(KitMesh.sphere(0.075 - t * 0.025), color, Vector3(sin(i * 1.3) * 0.015, -ay * 0.3 - t * reach, az * 0.95 + 0.02))
					bead.scale = Vector3(1, 1.25, 0.9)
					root.add_child(bead)
				root.add_child(mi(KitMesh.sphere(0.035), GOLD, Vector3(0, -ay * 0.3 - reach - 0.07, az * 0.95 + 0.02)))
		"ponytail":
			var cap2 := mi(dome(ax * 1.07, ay * 0.7, az * 1.07), color, Vector3(0, ay * 0.3, 0))
			cap2.rotation.x = 0.35
			root.add_child(cap2)
			var tie := surface(p, PI, 0.45, 0.02)
			root.add_child(mi(KitMesh.sphere(0.04), GOLD, tie))
			var tail := mi(KitMesh.capsule(0.07, 0.3), color, tie + Vector3(0, -0.1, 0.07))
			tail.rotation.x = -0.5
			root.add_child(tail)
		"mohawk":
			for i in 6:
				var pitch := 0.2 + i * 0.32
				var pos := surface(p, 0, pitch, 0.02)
				if pitch > PI / 2:
					pos = surface(p, PI, PI - pitch, 0.02)
				root.add_child(mi(KitMesh.sphere(0.065 - absf(i - 2.5) * 0.006), color, pos))
		"buns", "pigtails":
			var cap3 := mi(dome(ax * 1.06, ay * 0.62, az * 1.06), color, Vector3(0, ay * 0.4, 0))
			cap3.rotation.x = 0.25
			root.add_child(cap3)
			for s in [-1, 1]:
				if style == "buns":
					root.add_child(mi(KitMesh.sphere(0.085), color, surface(p, s * 0.9, 1.0, 0.05)))
				else:
					var at := surface(p, s * 1.45, 0.25, 0.0)
					var tail := mi(KitMesh.capsule(0.055, 0.24), color, at + Vector3(s * 0.08, -0.04, 0))
					tail.rotation.z = s * 1.1
					root.add_child(tail)
					root.add_child(mi(KitMesh.sphere(0.03), GOLD, at))
		"bob":
			var b2 := mi(dome(ax * 1.12, ay * 0.9, az * 1.12), color, Vector3(0, -ay * 0.15, 0.02))
			b2.rotation.x = 0.25
			root.add_child(b2)
			var fr := mi(KitMesh.capsule(0.05, ax * 1.6), color, surface(p, 0, 0.6, 0.01))
			fr.rotation.z = PI / 2
			root.add_child(fr)
		_:  # tuft
			for i in 3:
				var t := mi(KitMesh.capsule(0.025, 0.14), color, Vector3((i - 1) * 0.04, ay * 1.02, 0))
				t.rotation.z = (1 - i) * 0.45
				t.position += t.basis.y * 0.05
				root.add_child(t)
	return root


static func hat(type: String, color: Color, accent: Color, p: Dictionary) -> Node3D:
	var root := node("Hat", Vector3(0, p.ay * 0.62, 0))
	var ax: float = p.ax
	var az: float = p.az
	match type:
		"cap":
			root.add_child(mi(dome(ax * 1.04, p.ay * 0.6, az * 1.04), color))
			var brim := mi(KitMesh.cylinder(0.13, 0.13, 0.02, 20), color, Vector3(0, 0.0, -az * 0.95))
			brim.scale = Vector3(1.1, 1, 0.8)
			root.add_child(brim)
			root.add_child(mi(KitMesh.sphere(0.025), accent, Vector3(0, p.ay * 0.6, 0)))
		"beanie":
			root.add_child(mi(dome(ax * 1.05, p.ay * 0.7, az * 1.05), color))
			var rim := mi(KitMesh.torus(ax * 0.92, ax * 1.1), accent, Vector3(0, 0.02, 0))
			rim.scale = Vector3(1, 1.2, az / ax)
			root.add_child(rim)
			root.add_child(mi(KitMesh.sphere(0.06), accent, Vector3(0, p.ay * 0.72, 0)))
		"wizard":
			root.position.y = p.ay * 0.7
			root.add_child(mi(KitMesh.cylinder(ax * 1.35, ax * 1.35, 0.025, 24), color, Vector3(0, 0.01, 0)))
			var pts := PackedVector3Array()
			for i in 7:
				var t := i / 6.0
				pts.append(Vector3(0, t * 0.42, t * t * 0.14))
			root.add_child(mi(_taper_tube(pts, ax * 0.68), color))
			root.add_child(mi(KitMesh.torus(ax * 0.62, ax * 0.74), accent, Vector3(0, 0.04, 0)))
			var star := mi(KitMesh.puffy(KitMesh.star_outline(5, 0.05, 0.022), 0.02, "wiz_star"), GOLD, Vector3(0, 0.16, -ax * 0.52))
			star.rotation.x = 0.2
			root.add_child(star)
		"crown":
			root.position.y = p.ay * 0.78
			var ring := mi(KitMesh.cylinder(ax * 0.62, ax * 0.55, 0.09, 16), GOLD.lerp(color, 0.2), Vector3(0, 0.03, 0))
			root.add_child(ring)
			for i in 5:
				var a := TAU * i / 5.0
				var pos := Vector3(sin(a) * ax * 0.58, 0.11, -cos(a) * ax * 0.58)
				root.add_child(mi(KitMesh.cylinder(0.0, 0.035, 0.09, 8), GOLD.lerp(color, 0.2), pos))
				root.add_child(mi(KitMesh.sphere(0.018), accent, pos + Vector3(0, 0.05, 0)))
		"helmet":
			root.position.y = -p.ay * 0.15
			var shell := mi(dome(ax * 1.14, p.ay * 1.0, az * 1.14), color)
			shell.rotation.x = 0.25
			root.add_child(shell)
			var stripe := mi(KitMesh.capsule(0.03, p.ay * 1.6), accent, Vector3(0, p.ay * 0.55, 0.02))
			stripe.rotation.x = PI / 2 + 0.25
			stripe.scale = Vector3(1, 1, 0.5)
			root.add_child(stripe)
		"tophat":
			root.add_child(mi(KitMesh.cylinder(ax * 1.0, ax * 1.0, 0.02, 20), color, Vector3(0, 0.01, 0)))
			root.add_child(mi(KitMesh.cylinder(ax * 0.62, ax * 0.6, 0.26, 20), color, Vector3(0, 0.14, 0)))
			root.add_child(mi(KitMesh.cylinder(ax * 0.615, ax * 0.615, 0.05, 20), accent, Vector3(0, 0.05, 0)))
		"party":
			root.add_child(mi(KitMesh.cylinder(0.0, ax * 0.55, 0.3, 16), color, Vector3(0, 0.15, 0)))
			root.add_child(mi(KitMesh.sphere(0.045), accent, Vector3(0, 0.31, 0)))
			root.add_child(mi(KitMesh.torus(ax * 0.45, ax * 0.58), accent, Vector3(0, 0.02, 0)))
		"bow":
			root.position.y = p.ay * 0.82
			for sd in [-1, 1]:
				var loop := mi(KitMesh.puffy(KitMesh.ellipse_outline(0.09, 0.06), 0.06, "bow_loop"), color, Vector3(sd * 0.085, 0.03, 0.02))
				loop.rotation.z = sd * 0.35
				root.add_child(loop)
			root.add_child(mi(KitMesh.sphere(0.04), accent, Vector3(0, 0.03, 0.02)))
	return root


## Cone-like bent tube: a tube whose radius shrinks to a point along the path.
static func _taper_tube(pts: PackedVector3Array, r: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 14
	var verts: Array[Vector3] = []
	for i in pts.size():
		var t := float(i) / (pts.size() - 1)
		var fwd := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var y := fwd.cross(Vector3.RIGHT).normalized()
		for k in sides:
			var a := TAU * k / sides
			verts.append(pts[i] + (Vector3.RIGHT * cos(a) + y * sin(a)) * r * (1.0 - t))
	for v in verts:
		st.add_vertex(v)
	for i in pts.size() - 1:
		for k in sides:
			var a := i * sides + k
			var b := i * sides + (k + 1) % sides
			var out := verts[a] - pts[i] + verts[b] - pts[i]
			KitMesh._tri(st, verts, a, a + sides, b, out)
			KitMesh._tri(st, verts, b, a + sides, b + sides, out)
	st.generate_normals()
	return st.commit()


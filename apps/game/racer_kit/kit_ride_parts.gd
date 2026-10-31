class_name KitRideParts
extends RefCounted
## Wheels, legs, wings, tails, extras and the drawing sticker.
## Animated sub-nodes are tagged with metadata the ToyRacer animator looks for:
##   "wheel_spin" (radius) on a node spun around X, "leg_swing" (phase) on a leg pivot,
##   "wing_flap" (side) on a wing pivot, "spin" (rad/s) around Y, "flicker" on flames.

const P = preload("res://racer_kit/kit_parts.gd")
const BASE_WHEEL_R := 0.18


## Wheel centred on its axle (X axis). r is the final radius.
static func wheel(style: String, tire: Color, hub: Color, r: float) -> Node3D:
	var root := P.node("Wheel")
	var spin := P.node("Spin")
	spin.set_meta("wheel_spin", r)
	root.add_child(spin)
	var k := r / BASE_WHEEL_R
	match style:
		"monster":
			var t := P.mi(KitMesh.cylinder(r, r, 0.22 * k, 18), P.DARK)
			t.rotation.z = PI / 2
			spin.add_child(t)
			for i in 8:
				var a := TAU * i / 8.0
				var lug := P.mi(KitMesh.rounded_box(Vector3(0.24, 0.05, 0.05) * k), P.DARK.lightened(0.15), Vector3(0, sin(a), cos(a)) * r)
				lug.rotation.x = -a
				spin.add_child(lug)
			for s in [-1, 1]:
				var cap := P.mi(KitMesh.sphere(r * 0.5), hub, Vector3(s * 0.1 * k, 0, 0))
				cap.scale = Vector3(0.4, 1, 1)
				spin.add_child(cap)
		"donut":
			var ring := P.mi(KitMesh.torus(r * 0.42, r), hub)
			ring.rotation.z = PI / 2
			ring.scale = Vector3(1, 1.6, 1)
			spin.add_child(ring)
			var axle := P.mi(KitMesh.sphere(r * 0.25), P.DARK)
			axle.scale = Vector3(1.5, 1, 1)
			spin.add_child(axle)
		"spoked":
			var tire2 := P.mi(KitMesh.torus(r * 0.8, r), P.DARK)
			tire2.rotation.z = PI / 2
			tire2.scale = Vector3(1, 1.3, 1)
			spin.add_child(tire2)
			var rim := P.mi(KitMesh.torus(r * 0.74, r * 0.82), hub)
			rim.rotation.z = PI / 2
			spin.add_child(rim)
			for i in 6:
				var spoke := P.mi(KitMesh.capsule(r * 0.05, r * 1.56), hub.lightened(0.2))
				spoke.rotation.x = TAU * i / 12.0
				spin.add_child(spoke)
			var hubc := P.mi(KitMesh.sphere(r * 0.2), P.GOLD)
			hubc.scale = Vector3(1.4, 1, 1)
			spin.add_child(hubc)
		_:
			var t2 := P.mi(KitMesh.cylinder(r, r, 0.15 * k, 20), P.DARK)
			t2.rotation.z = PI / 2
			spin.add_child(t2)
			for s in [-1, 1]:
				var cap2 := P.mi(KitMesh.sphere(r * 0.55), hub, Vector3(s * 0.065 * k, 0, 0))
				cap2.scale = Vector3(0.35, 1, 1)
				spin.add_child(cap2)
				spin.add_child(P.mi(KitMesh.sphere(r * 0.14), P.WHITE, Vector3(s * 0.09 * k, r * 0.25, 0)))
	return root


## Leg hanging from its hip pivot down to y = -length.
static func leg(style: String, color: Color, length: float, phase: float) -> Node3D:
	var pivot := P.node("Leg")
	pivot.set_meta("leg_swing", phase)
	var c2 := P.GOLD.lerp(color, 0.3)
	match style:
		"bird":
			var top := Vector3.ZERO
			var knee := Vector3(0, -length * 0.5, -0.04)
			var foot := Vector3(0, -length + 0.03, 0)
			pivot.add_child(P.mi(KitMesh.tube(PackedVector3Array([top, knee, foot]), 0.035, 8), c2))
			pivot.add_child(P.mi(KitMesh.sphere(0.05), c2, knee))
			for a in [-0.5, 0.0, 0.5]:
				var toe := P.mi(KitMesh.capsule(0.025, 0.14), c2, foot + Vector3(sin(a) * 0.05, 0.0, -cos(a) * 0.05))
				toe.rotation = Vector3(PI / 2, -a, 0)
				pivot.add_child(toe)
		"hooves":
			var knee2 := Vector3(0, -length * 0.5, 0.02)
			var ankle := Vector3(0, -length + 0.09, -0.01)
			pivot.add_child(P.mi(KitMesh.tube(PackedVector3Array([Vector3.ZERO, knee2, ankle]), 0.06, 10), color))
			pivot.add_child(P.mi(KitMesh.sphere(0.065), color, knee2))
			pivot.add_child(P.mi(KitMesh.cylinder(0.075, 0.09, 0.09, 14), P.DARK, Vector3(0, -length + 0.045, -0.01)))
		"claws":
			var thigh := P.mi(KitMesh.capsule(0.1, length * 0.7), color, Vector3(0, -length * 0.32, 0))
			pivot.add_child(thigh)
			var foot3 := Vector3(0, -length + 0.05, -0.03)
			var pad := P.mi(KitMesh.sphere(0.09), color, foot3)
			pad.scale = Vector3(1.1, 0.6, 1.2)
			pivot.add_child(pad)
			for a in [-0.45, 0.0, 0.45]:
				var claw := P.mi(KitMesh.cylinder(0.0, 0.03, 0.09, 8), P.WHITE, foot3 + Vector3(sin(a) * 0.08, -0.02, -cos(a) * 0.1))
				claw.rotation = Vector3(-PI / 2 + 0.3, a, 0)
				pivot.add_child(claw)
		"paws":
			pivot.add_child(P.mi(KitMesh.capsule(0.085, length), color, Vector3(0, -length * 0.45, 0)))
			var paw := P.mi(KitMesh.sphere(0.12), color.lightened(0.1), Vector3(0, -length + 0.06, -0.04))
			paw.scale = Vector3(1, 0.55, 1.15)
			pivot.add_child(paw)
			for k in 3:
				pivot.add_child(P.mi(KitMesh.sphere(0.025), Color("#ff9fb2"), Vector3((k - 1) * 0.045, -length + 0.07, -0.16)))
		_:  # stumpy
			pivot.add_child(P.mi(KitMesh.capsule(0.095, length), color, Vector3(0, -length * 0.45, 0)))
			var foot2 := P.mi(KitMesh.sphere(0.1), color.darkened(0.15), Vector3(0, -length + 0.05, -0.02))
			foot2.scale = Vector3(1, 0.6, 1.2)
			pivot.add_child(foot2)
	return pivot


## Wing extending toward side (+1 right, -1 left) from its root pivot.
static func wing(style: String, color: Color, accent: Color, size: float, side: int) -> Node3D:
	var pivot := P.node("WingR" if side > 0 else "WingL")
	pivot.set_meta("wing_flap", side)
	var holder := P.node("Shape")
	holder.scale = Vector3(side * size, size, size)
	pivot.add_child(holder)
	match style:
		"fairy":
			var up := P.mi(KitMesh.puffy(KitMesh.ellipse_outline(0.26, 0.2), 0.03, "wing_bf_up"), color, Vector3(0.24, 0, -0.06))
			up.rotation.x = -PI / 2 + 0.25
			holder.add_child(up)
			var lo := P.mi(KitMesh.puffy(KitMesh.ellipse_outline(0.17, 0.14), 0.03, "wing_bf_lo"), accent, Vector3(0.17, -0.02, 0.18))
			lo.rotation.x = -PI / 2 + 0.25
			holder.add_child(lo)
			var dot := P.mi(KitMesh.sphere(0.06), accent, Vector3(0.3, 0.02, -0.06))
			dot.scale = Vector3(1, 0.3, 1)
			holder.add_child(dot)
		"plane":
			var outline := PackedVector2Array([Vector2(0, 0.12), Vector2(0.5, -0.08), Vector2(0.5, -0.18), Vector2(0, -0.14)])
			var j := P.mi(KitMesh.puffy(outline, 0.06, "wing_jet"), color)
			j.rotation.x = -PI / 2
			holder.add_child(j)
			var tip := P.mi(KitMesh.capsule(0.04, 0.22), accent, Vector3(0.5, 0, 0.13))
			tip.rotation.x = PI / 2
			holder.add_child(tip)
		"bat":
			var o := PackedVector2Array()
			o.append(Vector2(0, 0.06))
			o.append(Vector2(0.52, 0.1))
			for i in 4:
				var x0 := 0.52 - i * 0.13
				for k in range(1, 5):
					var t := k / 4.0
					o.append(Vector2(x0 - t * 0.13, -0.16 + sin(t * PI) * 0.07 + i * 0.02))
			o.append(Vector2(0, -0.06))
			var bat := P.mi(KitMesh.puffy(o, 0.04, "wing_bat"), color)
			bat.rotation.x = -PI / 2
			holder.add_child(bat)
			var bone := P.mi(KitMesh.capsule(0.025, 0.54), accent, Vector3(0.26, 0.01, -0.08))
			bone.rotation = Vector3(0, 0, PI / 2)
			holder.add_child(bone)
		_:  # feather
			for i in 4:
				var f := P.mi(KitMesh.capsule(0.06, 0.42 - i * 0.07), color if i % 2 == 0 else color.lightened(0.15))
				f.rotation = Vector3(-PI / 2, 0, PI / 2 + 0.25 + i * 0.22)
				f.position = Vector3(0.18 - i * 0.02, 0, 0.04 + i * 0.06)
				f.scale = Vector3(1, 1, 0.4)
				holder.add_child(f)
	return pivot


## Tail attached at its root, extending backward (+Z).
static func tail(style: String, color: Color) -> Node3D:
	var root := P.node("Tail")
	match style:
		"feathers":
			for i in 5:
				var a := (i - 2) * 0.32
				var f := P.mi(KitMesh.capsule(0.05, 0.36), color if i % 2 == 0 else color.lightened(0.2))
				f.rotation = Vector3(PI / 2 - 0.5, a, 0)
				f.position = f.basis.y * 0.16 + Vector3(0, 0.02, 0)
				f.scale = Vector3(1, 1, 0.45)
				root.add_child(f)
			root.set_meta("tail_wag", true)
		"dino":
			var pts := PackedVector3Array()
			for i in 7:
				var t := i / 6.0
				pts.append(Vector3(0, -t * 0.12 + t * t * 0.06, t * 0.5))
			root.add_child(P.mi(KitParts._taper_tube(pts, 0.11), color))
			for i in 3:
				var spike := P.mi(KitMesh.cylinder(0.0, 0.035, 0.07, 8), color.lightened(0.25), Vector3(0, 0.08 - i * 0.04, 0.08 + i * 0.12))
				root.add_child(spike)
			root.set_meta("tail_wag", true)
		"flame":
			var flame := P.node("Flame")
			flame.set_meta("flicker", true)
			var outer := P.mi(KitMesh.cylinder(0.0, 0.15, 0.4, 14), Color("#ff7a2f"), Vector3(0, 0, 0.2), 1.0)
			outer.rotation.x = PI / 2
			flame.add_child(outer)
			var inner := P.mi(KitMesh.cylinder(0.0, 0.09, 0.26, 12), Color("#fff07a"), Vector3(0, 0, 0.13), 1.4)
			inner.rotation.x = PI / 2
			flame.add_child(inner)
			root.add_child(flame)
		_:
			root.add_child(P.mi(KitMesh.sphere(0.12), color.lightened(0.2), Vector3(0, 0.02, 0.08)))
			root.set_meta("tail_wag", true)
	return root


## Extra shapes at unit size (about 1 m across at scale 1, like the designer's "1.0 = normal").
static func extra_mesh(shape: String) -> Mesh:
	match shape:
		"capsule": return KitMesh.capsule(0.25, 1.0)
		"box": return KitMesh.rounded_box(Vector3.ONE)
		"cone": return KitMesh.cylinder(0.0, 0.5, 1.0, 16)
		"cylinder": return KitMesh.cylinder(0.5, 0.5, 1.0, 18)
		"torus": return KitMesh.torus(0.3, 0.5)
		"star": return KitMesh.puffy(KitMesh.star_outline(5, 0.5, 0.23), 0.3, "extra_star")
		"heart": return KitMesh.puffy(KitMesh.heart_outline(0.5), 0.3, "extra_heart")
		"flower", "leaf", "cloud", "diamond", "drop":
			return KitMesh.puffy(KitMesh.shape_outline(shape), 0.3, "extra_" + shape)
		"lightning", "moon", "bowtie", "flame":
			return KitMesh.slab(KitMesh.shape_outline(shape), 0.22, "extra_" + shape)
		"cape":
			# Hangs down from the socket, flows backwards (+Z) and wraps around the body.
			var bend := func(v: Vector3) -> Vector3:
				return Vector3(v.x, v.y, v.z + 0.35 * pow(-v.y, 1.4) - 0.3 * v.x * v.x)
			return KitMesh.slab(KitMesh.shape_outline("cape"), 0.05, "extra_cape", bend)
	return KitMesh.sphere(0.5)


## Round glasses about 1 unit wide, facing forward (-Z).
static func _glasses(color: Color) -> Node3D:
	var g := P.node("Glasses")
	for side in [-1, 1]:
		var ring := P.mi(KitMesh.torus(0.15, 0.22), color, Vector3(side * 0.26, 0, 0))
		ring.rotation.x = PI / 2
		g.add_child(ring)
		var lens := P.mi(KitMesh.cylinder(0.16, 0.16, 0.02, 20), Color(0.85, 0.95, 1.0), Vector3(side * 0.26, 0, 0.01), 0.15)
		lens.rotation.x = PI / 2
		g.add_child(lens)
	var bridge := P.mi(KitMesh.capsule(0.03, 0.16), color)
	bridge.rotation.z = PI / 2
	g.add_child(bridge)
	return g


## Extra on a socket. e is a normalised Extra (spec frame); unit converts spec units to metres.
## mirror reflects it across the socket's local X (the other side of the racer).
static func extra(e: Dictionary, color: Color, unit: float, mirror := false) -> Node3D:
	var root := P.node("Extra_" + str(e.shape))
	var pos := RacerSpec.to_godot(e.offset)
	var rot := RacerSpec.rot_to_godot(e.rotationDeg)
	if mirror:
		pos.x = -pos.x
		rot.y = -rot.y
		rot.z = -rot.z
	root.position = pos
	root.rotation = rot
	var sc: Array = e.scale
	var m: Node3D = _glasses(color) if e.shape == "glasses" else P.mi(extra_mesh(e.shape), color)
	m.scale = Vector3(sc[0], sc[1], sc[2]) * unit
	# Cones, capsules and cylinders stand on their base, so horns, antennae, poles and whiskers grow
	# out of the socket (their tip is scale.y × unit away) instead of through it.
	if e.shape in ["cone", "capsule", "cylinder"]:
		m.position.y = 0.5 * sc[1] * unit
	root.add_child(m)
	return root


static func sticker(tex: Texture2D, size: float) -> MeshInstance3D:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := MeshInstance3D.new()
	m.name = "Sticker"
	m.mesh = q
	m.material_override = KitMaterial.sticker(tex)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


## Placeholder drawing when drawingSticker is set but no drawing texture was given.
static func placeholder_drawing(c1: Color, c2: Color) -> Texture2D:
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	img.fill(P.WHITE)
	for y in 64:
		for x in 64:
			var d := Vector2(x - 32, y - 30).length()
			if d < 18:
				img.set_pixel(x, y, c1)
			elif d < 22 and y > 30:
				img.set_pixel(x, y, c2)
	return ImageTexture.create_from_image(img)

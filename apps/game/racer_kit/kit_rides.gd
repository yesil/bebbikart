class_name KitRides
extends RefCounted
## The 8 ride bases. build() returns the ride body (meshes only, scaled later by
## ride.scale) plus anchor points in unscaled ride space:
##   seat, handle (or null), hand_spread, stand, wheel_r, ground {2,3,4: wheel centres},
##   hips (leg tops) + leg_len, wing (right side), tail, sockets {name: pos}, sticker {pos,size},
##   hover (extra height), defaults {wheels/legs/wings/tail} used when the spec has none.

const P = preload("res://racer_kit/kit_parts.gd")


static func build(base: String, main: Color, accent: Color) -> Dictionary:
	match base:
		"car": return _car(main, accent)
		"bike": return _bike(main, accent)
		"animal4": return _animal4(main, accent)
		"bird": return _bird(main, accent)
		"board": return _board(main, accent)
		"rocket": return _rocket(main, accent)
		"boat": return _boat(main, accent)
		"blob": return _blob(main, accent)
	return _kart(main, accent)


static func _wheel_sets(y: float, x: float, zf: float, zb: float) -> Dictionary:
	return {
		2: [Vector3(0, y, zf), Vector3(0, y, zb)],
		3: [Vector3(0, y, zf), Vector3(-x, y, zb), Vector3(x, y, zb)],
		4: [Vector3(-x, y, zf), Vector3(x, y, zf), Vector3(-x, y, zb), Vector3(x, y, zb)],
	}


static func _hips(y: float, x: float, zf: float, zb: float) -> Array:
	return [Vector3(-x, y, zf), Vector3(x, y, zf), Vector3(-x, y, zb), Vector3(x, y, zb)]


static func _steering(root: Node3D, at: Vector3, from: Vector3) -> void:
	root.add_child(P.mi(KitMesh.tube(PackedVector3Array([from, at]), 0.025, 8), P.DARK))
	var wheel := P.mi(KitMesh.torus(0.09, 0.13), P.DARK, at)
	wheel.rotation.x = deg_to_rad(55)
	root.add_child(wheel)
	root.add_child(P.mi(KitMesh.sphere(0.035), P.GOLD, at))


## Cartoon eye on a ride (animals, blob): white ball + pupil + shine, facing dir.
static func eye(root: Node3D, pos: Vector3, dir: Vector3, r: float) -> void:
	var e := P.node("RideEye", pos)
	P.aim_z(e, dir)
	var white := P.mi(KitMesh.sphere(r), P.WHITE)
	white.scale = Vector3(1, 1, 0.6)
	e.add_child(white)
	var pupil := P.mi(KitMesh.sphere(r * 0.55), P.DARK, Vector3(0, -r * 0.05, r * 0.42))
	pupil.scale = Vector3(1, 1, 0.5)
	e.add_child(pupil)
	e.add_child(P.mi(KitMesh.sphere(r * 0.18), P.WHITE, Vector3(r * 0.2, r * 0.2, r * 0.66)))
	root.add_child(e)


static func _base(seat: Vector3, extra: Dictionary) -> Dictionary:
	var d := {
		"body": P.node("RideBody"), "seat": seat, "handle": null, "hand_spread": 0.2,
		"stand": false, "wheel_r": 0.18, "ground": {}, "hips": [], "leg_len": 0.4,
		"wing": Vector3(0.4, seat.y - 0.05, 0.1), "tail": Vector3(0, seat.y - 0.1, 0.7),
		"sockets": {}, "sticker": {"pos": Vector3(0.45, 0.3, 0.05), "size": 0.38},
		"hover": 0.0, "defaults": {},
	}
	d.merge(extra, true)
	return d


static func _kart(main: Color, accent: Color) -> Dictionary:
	var d := _base(Vector3(0, 0.36, 0.12), {
		"handle": Vector3(0, 0.6, -0.36), "hand_spread": 0.11,
		"ground": _wheel_sets(0.18, 0.5, -0.48, 0.46),
		"wing": Vector3(0.42, 0.4, 0.15), "tail": Vector3(0, 0.38, 0.74),
		"sticker": {"pos": Vector3(0.47, 0.3, 0.0), "size": 0.36},
		"defaults": {"wheels": {"count": 4, "style": "toy"}},
		"sockets": {"ride_front": Vector3(0, 0.27, -0.82), "ride_back": Vector3(0, 0.38, 0.74),
			"ride_top": Vector3(0, 0.42, -0.5), "ride_left": Vector3(-0.47, 0.3, 0),
			"ride_right": Vector3(0.47, 0.3, 0), "ride_bottom": Vector3(0, 0.12, 0)},
	})
	var b: Node3D = d.body
	b.add_child(P.mi(KitMesh.blob({"ax": 0.44, "ay": 0.14, "az": 0.72, "n": 3.2, "nose": 0.08}), main, Vector3(0, 0.27, 0)))
	var bumper := P.mi(KitMesh.capsule(0.08, 0.86), accent, Vector3(0, 0.22, -0.78))
	bumper.rotation.z = PI / 2
	b.add_child(bumper)
	b.add_child(P.mi(KitMesh.rounded_box(Vector3(0.44, 0.34, 0.12)), accent, Vector3(0, 0.5, 0.36)))
	var stripe := P.mi(KitMesh.rounded_box(Vector3(0.9, 0.06, 0.5)), accent, Vector3(0, 0.36, -0.42))
	b.add_child(stripe)
	_steering(b, Vector3(0, 0.6, -0.36), Vector3(0, 0.38, -0.2))
	return d


## Closed car / van: long low body, the driver sits under a see-through glass cabin.
static func _car(main: Color, accent: Color) -> Dictionary:
	var d := _base(Vector3(0, 0.36, 0.1), {
		"handle": Vector3(0, 0.58, -0.32), "hand_spread": 0.11, "wheel_r": 0.2,
		"ground": _wheel_sets(0.2, 0.52, -0.58, 0.56),
		"wing": Vector3(0.45, 0.4, 0.15), "tail": Vector3(0, 0.36, 0.95),
		"sticker": {"pos": Vector3(0.5, 0.3, 0.42), "size": 0.3},
		"defaults": {"wheels": {"count": 4, "style": "toy"}},
		"sockets": {"ride_front": Vector3(0, 0.3, -0.98), "ride_back": Vector3(0, 0.36, 0.95),
			"ride_top": Vector3(0, 0.98, 0.1), "ride_left": Vector3(-0.5, 0.3, 0),
			"ride_right": Vector3(0.5, 0.3, 0), "ride_bottom": Vector3(0, 0.12, 0)},
	})
	var b: Node3D = d.body
	b.add_child(P.mi(KitMesh.blob({"ax": 0.5, "ay": 0.17, "az": 0.96, "n": 3.0, "nose": 0.06}), main, Vector3(0, 0.3, 0)))
	# Side stripe and bumpers in the accent colour.
	for s in [-1, 1]:
		var stripe := P.mi(KitMesh.rounded_box(Vector3(0.04, 0.07, 1.6)), accent, Vector3(s * 0.49, 0.28, 0))
		b.add_child(stripe)
	for z in [-0.96, 0.95]:
		var bumper := P.mi(KitMesh.capsule(0.06, 0.92), accent, Vector3(0, 0.2, z))
		bumper.rotation.z = PI / 2
		b.add_child(bumper)
	# Cabin: glass dome over the seat, roof rim in the main colour.
	var cabin := MeshInstance3D.new()
	cabin.name = "Glass"
	cabin.mesh = KitMesh.dome(0.44, 0.56, 0.62)
	cabin.material_override = KitMaterial.glass()
	cabin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cabin.position = Vector3(0, 0.42, 0.08)
	b.add_child(cabin)
	var rim := P.mi(KitMesh.torus(0.42, 0.47), main.darkened(0.15), Vector3(0, 0.43, 0.08))
	rim.scale = Vector3(1, 1, 1.4)
	b.add_child(rim)
	for s in [-1, 1]:
		b.add_child(P.mi(KitMesh.sphere(0.07), P.GOLD, Vector3(s * 0.32, 0.32, -0.93), 0.6))
	_steering(b, Vector3(0, 0.58, -0.32), Vector3(0, 0.4, -0.2))
	return d


static func _bike(main: Color, accent: Color) -> Dictionary:
	var d := _base(Vector3(0, 0.62, 0.12), {
		"handle": Vector3(0, 0.8, -0.38), "hand_spread": 0.26, "wheel_r": 0.25,
		"ground": _wheel_sets(0.25, 0.28, -0.56, 0.52),
		"wing": Vector3(0.2, 0.6, 0.2), "tail": Vector3(0, 0.6, 0.62),
		"sticker": {"pos": Vector3(0.19, 0.48, -0.12), "size": 0.3},
		"defaults": {"wheels": {"count": 2, "style": "toy"}},
		"sockets": {"ride_front": Vector3(0, 0.62, -0.62), "ride_back": Vector3(0, 0.62, 0.62),
			"ride_top": Vector3(0, 0.66, -0.22), "ride_left": Vector3(-0.19, 0.45, 0),
			"ride_right": Vector3(0.19, 0.45, 0), "ride_bottom": Vector3(0, 0.25, 0)},
	})
	var b: Node3D = d.body
	b.add_child(P.mi(KitMesh.blob({"ax": 0.17, "ay": 0.17, "az": 0.42, "n": 2.4, "nose": 0.1}), main, Vector3(0, 0.47, -0.08)))
	b.add_child(P.mi(KitMesh.blob({"ax": 0.15, "ay": 0.06, "az": 0.22, "n": 3.0}), accent, Vector3(0, 0.58, 0.16)))
	b.add_child(P.mi(KitMesh.tube(PackedVector3Array([Vector3(0, 0.25, -0.56), Vector3(0, 0.82, -0.36)]), 0.03, 8), P.DARK))
	b.add_child(P.mi(KitMesh.tube(PackedVector3Array([Vector3(0, 0.3, 0.2), Vector3(0, 0.25, 0.52)]), 0.03, 8), P.DARK))
	var bar := P.mi(KitMesh.capsule(0.025, 0.6), P.DARK, Vector3(0, 0.82, -0.38))
	bar.rotation.z = PI / 2
	b.add_child(bar)
	for s in [-1, 1]:
		var grip := P.mi(KitMesh.capsule(0.035, 0.12), accent, Vector3(s * 0.27, 0.82, -0.38))
		grip.rotation.z = PI / 2
		b.add_child(grip)
	var lamp := P.mi(KitMesh.sphere(0.07), P.GOLD, Vector3(0, 0.72, -0.5), 0.6)
	b.add_child(lamp)
	return d


static func _animal4(main: Color, accent: Color) -> Dictionary:
	var d := _base(Vector3(0, 0.86, 0.08), {
		"handle": Vector3(0, 0.95, -0.36), "hand_spread": 0.14,
		"hips": _hips(0.55, 0.2, -0.36, 0.36), "leg_len": 0.42,
		"wing": Vector3(0.28, 0.82, -0.05), "tail": Vector3(0, 0.78, 0.6),
		"sticker": {"pos": Vector3(0.3, 0.7, 0.1), "size": 0.3},
		"defaults": {"legs": {"style": "stumpy"}, "tail": {"style": "fluffy"}},
		"sockets": {"ride_front": Vector3(0, 1.0, -0.82), "ride_back": Vector3(0, 0.78, 0.6),
			"ride_top": Vector3(0, 1.22, -0.62), "ride_left": Vector3(-0.3, 0.7, 0),
			"ride_right": Vector3(0.3, 0.7, 0), "ride_bottom": Vector3(0, 0.45, 0)},
	})
	var b: Node3D = d.body
	b.add_child(P.mi(KitMesh.blob({"ax": 0.3, "ay": 0.26, "az": 0.56, "n": 2.2}), main, Vector3(0, 0.7, 0)))
	var hp := {"ax": 0.2, "ay": 0.19, "az": 0.22, "n": 2.0}
	var head := P.node("RideHead", Vector3(0, 1.02, -0.6))
	head.add_child(P.mi(KitMesh.blob(hp), main))
	head.add_child(P.mi(KitMesh.blob({"ax": 0.12, "ay": 0.09, "az": 0.1}), accent, Vector3(0, -0.06, -0.2)))
	head.add_child(P.mi(KitMesh.sphere(0.03), P.DARK, Vector3(0, -0.02, -0.3)))
	for s in [-1, 1]:
		var ear := P.mi(KitMesh.capsule(0.05, 0.16), main, Vector3(s * 0.12, 0.18, 0.02))
		ear.rotation.z = -s * 0.4
		ear.scale = Vector3(1, 1, 0.5)
		head.add_child(ear)
		eye(head, KitMesh.blob_point(hp, KitMesh.face_dir(s * 0.45, 0.25)), KitMesh.face_dir(s * 0.45, 0.25), 0.055)
	b.add_child(head)
	b.add_child(P.mi(KitMesh.tube(PackedVector3Array([Vector3(0, 0.82, -0.36), Vector3(0, 0.95, -0.5)]), 0.13, 10), main))
	var saddle := P.mi(KitMesh.blob({"ax": 0.24, "ay": 0.05, "az": 0.22, "n": 2.5}), accent, Vector3(0, 0.93, 0.08))
	b.add_child(saddle)
	var rein := P.mi(KitMesh.tube(PackedVector3Array([Vector3(-0.14, 0.95, -0.36), Vector3(-0.15, 0.98, -0.62), Vector3(0.15, 0.98, -0.62), Vector3(0.14, 0.95, -0.36)]), 0.012, 6), P.DARK)
	b.add_child(rein)
	return d


static func _bird(main: Color, accent: Color) -> Dictionary:
	var d := _base(Vector3(0, 1.05, 0.08), {
		"handle": Vector3(0, 1.12, -0.26), "hand_spread": 0.14,
		"hips": [Vector3(-0.14, 0.62, 0.02), Vector3(0.14, 0.62, 0.02)], "leg_len": 0.55,
		"wing": Vector3(0.3, 0.92, 0.02), "tail": Vector3(0, 0.95, 0.46),
		"sticker": {"pos": Vector3(0.31, 0.82, -0.08), "size": 0.26},
		"defaults": {"legs": {"style": "bird"}, "wings": {"style": "feather"}},
		"sockets": {"ride_front": Vector3(0, 1.28, -0.7), "ride_back": Vector3(0, 0.95, 0.46),
			"ride_top": Vector3(0, 1.48, -0.42), "ride_left": Vector3(-0.32, 0.85, 0),
			"ride_right": Vector3(0.32, 0.85, 0), "ride_bottom": Vector3(0, 0.6, 0)},
	})
	var b: Node3D = d.body
	b.add_child(P.mi(KitMesh.blob({"ax": 0.32, "ay": 0.3, "az": 0.44, "n": 2.0, "taper": -0.1}), main, Vector3(0, 0.88, 0)))
	var hp := {"ax": 0.19, "ay": 0.19, "az": 0.19, "n": 2.0}
	var head := P.node("RideHead", Vector3(0, 1.3, -0.44))
	head.add_child(P.mi(KitMesh.blob(hp), main))
	var beak := P.mi(KitMesh.cylinder(0.0, 0.07, 0.16, 10), P.GOLD, Vector3(0, -0.02, -0.24))
	beak.rotation.x = -PI / 2
	head.add_child(beak)
	head.add_child(P.mi(KitMesh.sphere(0.05), accent, Vector3(0, 0.2, 0.0)))
	for s in [-1, 1]:
		eye(head, KitMesh.blob_point(hp, KitMesh.face_dir(s * 0.5, 0.2)), KitMesh.face_dir(s * 0.5, 0.2), 0.05)
	b.add_child(head)
	b.add_child(P.mi(KitMesh.tube(PackedVector3Array([Vector3(0, 1.0, -0.3), Vector3(0, 1.22, -0.42)]), 0.11, 10), main))
	b.add_child(P.mi(KitMesh.blob({"ax": 0.22, "ay": 0.05, "az": 0.2, "n": 2.5}), accent, Vector3(0, 1.13, 0.08)))
	return d


static func _board(main: Color, accent: Color) -> Dictionary:
	var d := _base(Vector3(0, 0.22, 0.0), {
		"stand": true, "hand_spread": 0.3, "wheel_r": 0.09,
		"ground": _wheel_sets(0.09, 0.15, -0.44, 0.44),
		"wing": Vector3(0.22, 0.25, 0.1), "tail": Vector3(0, 0.24, 0.66),
		"sticker": {"pos": Vector3(0.23, 0.2, 0.3), "size": 0.16},
		"defaults": {"wheels": {"count": 4, "style": "toy", "size": 1.0}},
		"sockets": {"ride_front": Vector3(0, 0.24, -0.66), "ride_back": Vector3(0, 0.24, 0.66),
			"ride_top": Vector3(0, 0.25, -0.45), "ride_left": Vector3(-0.23, 0.2, 0),
			"ride_right": Vector3(0.23, 0.2, 0), "ride_bottom": Vector3(0, 0.12, 0)},
	})
	var b: Node3D = d.body
	var deck := P.mi(KitMesh.blob({"ax": 0.23, "ay": 0.035, "az": 0.66, "n": 3.0}), main, Vector3(0, 0.19, 0))
	b.add_child(deck)
	b.add_child(P.mi(KitMesh.blob({"ax": 0.08, "ay": 0.01, "az": 0.5, "n": 3.0}), accent, Vector3(0, 0.225, 0)))
	for z in [-0.44, 0.44]:
		b.add_child(P.mi(KitMesh.rounded_box(Vector3(0.3, 0.05, 0.06)), P.DARK, Vector3(0, 0.13, z)))
	return d


static func _rocket(main: Color, accent: Color) -> Dictionary:
	var d := _base(Vector3(0, 0.6, 0.12), {
		"handle": Vector3(0, 0.72, -0.24), "hand_spread": 0.1, "hover": 0.3,
		"wing": Vector3(0.3, 0.42, 0.25), "tail": Vector3(0, 0.42, 0.86),
		"sticker": {"pos": Vector3(0.3, 0.45, -0.2), "size": 0.3},
		"defaults": {"tail": {"style": "flame"}},
		"sockets": {"ride_front": Vector3(0, 0.42, -1.02), "ride_back": Vector3(0, 0.42, 0.86),
			"ride_top": Vector3(0, 0.66, -0.5), "ride_left": Vector3(-0.3, 0.42, 0),
			"ride_right": Vector3(0.3, 0.42, 0), "ride_bottom": Vector3(0, 0.12, 0)},
	})
	var b: Node3D = d.body
	b.add_child(P.mi(KitMesh.blob({"ax": 0.3, "ay": 0.28, "az": 0.72, "n": 2.0, "nose": 0.4}), main, Vector3(0, 0.42, 0)))
	b.add_child(P.mi(KitMesh.blob({"ax": 0.16, "ay": 0.16, "az": 0.2}), accent, Vector3(0, 0.42, -0.92)))
	var fin_shape := KitMesh.puffy(KitMesh.half_disc_outline(0.34, 0.3), 0.05, "rocket_fin")
	for a in [-PI / 2, PI / 2, 0.0]:
		var fin := P.mi(fin_shape, accent, Vector3(0, 0.42, 0.5))
		fin.rotation = Vector3(0, PI / 2, a)
		fin.position += Vector3(sin(a) * 0.22, cos(a) * 0.22, 0)
		b.add_child(fin)
	var nozzle := P.mi(KitMesh.cylinder(0.18, 0.12, 0.14, 16), P.DARK, Vector3(0, 0.42, 0.74))
	nozzle.rotation.x = PI / 2
	b.add_child(nozzle)
	var stick := P.mi(KitMesh.tube(PackedVector3Array([Vector3(0, 0.6, -0.18), Vector3(0, 0.72, -0.24)]), 0.02, 6), P.DARK)
	b.add_child(stick)
	b.add_child(P.mi(KitMesh.sphere(0.04), Color("#ff4f5e"), Vector3(0, 0.73, -0.24)))
	return d


static func _boat(main: Color, accent: Color) -> Dictionary:
	var d := _base(Vector3(0, 0.36, 0.14), {
		"handle": Vector3(0, 0.62, -0.32), "hand_spread": 0.11,
		"wing": Vector3(0.44, 0.38, 0.1), "tail": Vector3(0, 0.36, 0.78),
		"sticker": {"pos": Vector3(0.46, 0.26, 0.0), "size": 0.34},
		"sockets": {"ride_front": Vector3(0, 0.38, -0.92), "ride_back": Vector3(0, 0.38, 0.76),
			"ride_top": Vector3(0, 0.46, -0.52), "ride_left": Vector3(-0.47, 0.28, 0),
			"ride_right": Vector3(0.47, 0.28, 0), "ride_bottom": Vector3(0, 0.04, 0)},
	})
	var b: Node3D = d.body
	b.add_child(P.mi(KitMesh.blob({"ax": 0.46, "ay": 0.22, "az": 0.76, "n": 2.6, "taper": -0.25, "nose": 0.18, "flat_bottom": 0.3}), main, Vector3(0, 0.22, 0)))
	var rim := P.mi(KitMesh.torus(0.36, 0.44), accent, Vector3(0, 0.4, 0))
	rim.scale = Vector3(1.25, 1.2, 1.9)
	b.add_child(rim)
	b.add_child(P.mi(KitMesh.blob({"ax": 0.4, "ay": 0.03, "az": 0.66, "n": 2.6}), main.darkened(0.25), Vector3(0, 0.36, 0)))
	_steering(b, Vector3(0, 0.62, -0.32), Vector3(0, 0.36, -0.22))
	var flag := P.mi(KitMesh.tube(PackedVector3Array([Vector3(0, 0.38, 0.62), Vector3(0, 0.95, 0.62)]), 0.015, 6), P.DARK)
	b.add_child(flag)
	var cloth := P.mi(KitMesh.puffy(PackedVector2Array([Vector2(0, 0), Vector2(0.2, -0.07), Vector2(0, -0.14)]), 0.02, "boat_flag"), accent, Vector3(0, 0.94, 0.62))
	cloth.rotation.y = -PI / 2
	b.add_child(cloth)
	return d


static func _blob(main: Color, accent: Color) -> Dictionary:
	var d := _base(Vector3(0, 0.82, 0.08), {
		"hand_spread": 0.3,
		"wing": Vector3(0.48, 0.55, 0.05), "tail": Vector3(0, 0.45, 0.6),
		"sticker": {"pos": Vector3(0.53, 0.42, 0.12), "size": 0.32},
		"sockets": {"ride_front": Vector3(0, 0.45, -0.62), "ride_back": Vector3(0, 0.45, 0.6),
			"ride_top": Vector3(0, 0.85, -0.3), "ride_left": Vector3(-0.55, 0.42, 0),
			"ride_right": Vector3(0.55, 0.42, 0), "ride_bottom": Vector3(0, 0.02, 0)},
	})
	var b: Node3D = d.body
	var bp := {"ax": 0.55, "ay": 0.44, "az": 0.6, "n": 2.0, "taper": 0.15, "flat_bottom": 0.15}
	var core := P.node("Jelly", Vector3(0, 0.38, 0))
	core.set_meta("jiggle", true)
	core.add_child(P.mi(KitMesh.blob(bp), main))
	for s in [-1, 1]:
		var dir := KitMesh.face_dir(s * 0.32, 0.15)
		eye(core, KitMesh.blob_point(bp, dir), dir, 0.09)
	var mouth_pts := PackedVector3Array()
	for i in 9:
		var t := -0.3 + 0.6 * i / 8.0
		var dir2 := KitMesh.face_dir(t, -0.12 - 0.08 * cos(t / 0.3 * PI / 2))
		mouth_pts.append(KitMesh.blob_point(bp, dir2) + dir2 * 0.01)
	core.add_child(P.mi(KitMesh.tube(mouth_pts, 0.02, 6, "blob_mouth"), P.DARK))
	core.add_child(P.mi(KitMesh.sphere(0.12), accent, Vector3(0, 0.4, 0.05)))
	b.add_child(core)
	return d

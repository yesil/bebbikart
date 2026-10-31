class_name RacerFace
extends Node3D
## Toy face on a head blob: eyes, brows, mouth, cheeks and a tear, with one set of
## overlays per mood (contracts §3 Mood). Built once; set_mood() only toggles visibility
## and transforms, so mood changes are free at runtime.
## On top of the mood, an in-game expression (EXPRESSIONS, not part of the Mood contract):
## "eek" (eyes wide, tiny pupils, brows up, a small round mouth), "smug" (half-lidded eyes, one
## brow up, a lopsided smirk), "grumpy" (brows down hard, squint, a frown); set_expression("")
## shows the mood again.
## Face-plane anchors use +Z out of the head surface, +X toward the racer's right.

const P = preload("res://racer_kit/kit_parts.gd")
const PINK := Color("#ff8fa3")
const TEAR := Color("#7fd3ff")

var mood := "happy"
const EXPRESSIONS := ["eek", "smug", "grumpy"]
var expression := ""
var eye_style := "big_round"
var mouth_style := "smile"

var _p: Dictionary
var _eyes: Array[Node3D] = []        # open-eye nodes (blink + scale)
var _pupils: Array[Node3D] = []      # googly pupils
var _overlays := {}                  # name -> Array[Node3D] (spirals, arcs)
var _brows: Array[Node3D] = []
var _mouths := {}                    # name -> Node3D
var _cheeks: Array[Node3D] = []
var _tear: Node3D
var _blink_t := 2.0
var _blink := 0.0
var _time := 0.0
var _has_cheeks := false
var _eye_y := 1.0                    # eye height factor (squint / half lids), for tick()
var _pupil_all: Array[Node3D] = []   # every pupil (eek shrinks them)
var _mouth_rest := {}                # mouth name -> rest transform (smirk, small o)


## p = head blob params; face = normalised spec.character.face; colors = palette Colors.
func setup(p: Dictionary, face: Dictionary, colors: Array[Color], skin: Color) -> void:
	name = "Face"
	_p = p
	eye_style = str(face.get("eyes", "big_round"))
	mouth_style = str(face.get("mouth", "smile"))
	var eye_col := Color.html(str(face.get("eyeColor", "#2b2140")))
	var eye_spots: Array = [0.0] if eye_style in ["one_eye", "visor"] else [-0.36, 0.36]
	for yaw in eye_spots:
		var a := _anchor("Eye", yaw, 0.12)
		_build_eye(a, eye_col, skin)
		_eyes.append(a)
		_add_overlay("spiral", a, _spiral(eye_col))
		_add_overlay("arc", a, P.mi(KitMesh.tube(_arc(0.045, 0.035, true), 0.012, 6, "face_arc"), eye_col))
	if eye_style == "visor":
		for s in [-0.36, 0.36]:  # mood overlays sit on the visor where the eyes would be
			var a2 := _anchor("VisorMood", s, 0.12, 0.03)
			_add_overlay("spiral", a2, _spiral(P.WHITE))
			_add_overlay("arc", a2, P.mi(KitMesh.tube(_arc(0.045, 0.035, true), 0.012, 6, "face_arc"), P.WHITE))
	if bool(face.get("brows", true)) and eye_style != "visor":
		for yaw in eye_spots:
			var b := _anchor("Brow", yaw, 0.42, 0.005)
			var m := P.mi(KitMesh.capsule(0.014, 0.075 if eye_spots.size() > 1 else 0.11), P.DARK)
			m.rotation.z = PI / 2
			b.add_child(m)
			b.set_meta("side", signf(yaw))
			_brows.append(b)
	var mouth := _anchor("Mouth", 0.0, -0.34)
	_build_mouths(mouth, skin)
	_has_cheeks = face.get("cheeks") != null
	var cheek_col: Color = colors[int(face.cheeks)].lerp(PINK, 0.5) if _has_cheeks else PINK
	for yaw in [-0.62, 0.62]:
		var c := _anchor("Cheek", yaw, -0.12)
		var disc := P.mi(KitMesh.sphere(0.04), cheek_col)
		disc.scale = Vector3(1.2, 0.75, 0.25)
		c.add_child(disc)
		_cheeks.append(c)
	_tear = _anchor("Tear", -0.4, -0.05, 0.01)
	var drop := P.mi(KitMesh.sphere(0.022), TEAR, Vector3.ZERO, 0.3)
	drop.scale = Vector3(0.8, 1.3, 0.6)
	_tear.add_child(drop)
	for k in _mouths:
		_mouth_rest[k] = (_mouths[k] as Node3D).transform
	set_mood("happy")


func set_mood(m: String) -> void:
	mood = m if m in KitCatalog.MOODS else "happy"
	_apply()


## An expression on top of the mood (EXPRESSIONS), or "" for none. False (and an error) for an
## unknown name.
func set_expression(x: String) -> bool:
	if x != "" and x not in EXPRESSIONS:
		push_error("RacerFace: unknown expression \"%s\" (known: %s)" % [x, ", ".join(EXPRESSIONS)])
		return false
	if x != expression:
		expression = x
		_apply()
	return true


func _apply() -> void:
	var eyes_open := mood not in ["dizzy", "cheering"] or expression != ""
	for e in _eyes:
		e.visible = eyes_open
	for e in _eyes:
		var k := 1.0
		match mood:
			"excited": k = 1.25
			"sad": k = 0.9
		_eye_y = 0.6 if mood == "determined" else 1.0
		match expression:
			"eek":
				k = 1.4
				_eye_y = 1.15
			"smug":
				_eye_y = 0.5
			"grumpy":
				k = 0.95
				_eye_y = 0.5
		e.scale = Vector3(k, k * _eye_y, k)
	for pu in _pupil_all:
		pu.scale = Vector3.ONE * (0.55 if expression == "eek" else 1.0)
	for key in _overlays:
		var on: bool = expression == "" and ((key == "spiral" and mood == "dizzy") or (key == "arc" and mood == "cheering"))
		for o in _overlays[key]:
			o.visible = on
	for b in _brows:
		var side: float = b.get_meta("side")
		var tilt := 0.0
		var lift := 0.0
		match mood:
			"determined": tilt = 0.45
			"sad": tilt = -0.4
			"excited", "cheering": lift = 0.025
			"dizzy": tilt = 0.25 * side
		match expression:
			"eek":
				tilt = -0.3
				lift = 0.045
			"smug":
				tilt = 0.0 if side > 0.0 else 0.35  # one brow up, one down
				lift = 0.03 if side > 0.0 else -0.005
			"grumpy":
				tilt = 0.65
				lift = -0.015
		b.rotation.z = -tilt * side
		b.position = b.get_meta("base_pos", b.position)
		b.set_meta("base_pos", b.position)
		b.position += b.basis.y * lift
	var shown := mouth_style
	if mouth_style not in ["none", "beak"]:
		match mood:
			"excited", "cheering": shown = "open_big"
			"sad": shown = "frown"
			"dizzy": shown = "wavy"
			"determined": shown = "fangs" if mouth_style == "fangs" else "flat"
		match expression:
			"eek": shown = "open"
			"smug": shown = "smile"
			"grumpy": shown = "fangs" if mouth_style == "fangs" else "frown"
	for k in _mouths:
		_mouths[k].visible = k == shown
		_mouths[k].transform = _mouth_rest.get(k, _mouths[k].transform)
	if expression == "eek" and shown == "open":
		_mouths.open.scale = Vector3(0.7, 1.2, 1.0)  # a small round "o"
	if expression == "smug" and shown == "smile":
		var w: float = _p.ax * 0.4
		_mouths.smile.rotation.z = 0.3  # a lopsided smirk
		_mouths.smile.position.x += w * 0.25
	if mouth_style == "beak" and _mouths.has("beak"):
		_mouths.beak.scale = Vector3.ONE * (1.15 if mood in ["excited", "cheering"] or expression == "eek" else 1.0)
	for c in _cheeks:
		c.visible = _has_cheeks or (mood in ["cheering", "excited"] and expression != "grumpy") or expression == "smug"
	_tear.visible = mood == "sad" and expression == ""


## Called every frame by ToyRacer.
func tick(delta: float) -> void:
	_time += delta
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink = 0.14
		_blink_t = randf_range(2.0, 5.0)
	if _blink > 0.0:
		_blink -= delta
	var lid := 0.12 if _blink > 0.0 and eye_style != "visor" else 1.0
	for e in _eyes:
		e.scale.y = e.scale.x * _eye_y * lid
	for pu in _pupils:
		pu.position = Vector3(sin(_time * 9.0) * 0.012, cos(_time * 7.0) * 0.01, pu.position.z)
	for o in _overlays.get("spiral", []):
		o.rotation.z = -_time * 6.0
	if _tear.visible:
		_tear.position = _tear.get_meta("base", _tear.position)
		_tear.set_meta("base", _tear.position)
		_tear.position.y -= fmod(_time * 0.12, 0.08)


# --- construction ---

func _anchor(n: String, yaw: float, pitch: float, lift := 0.0) -> Node3D:
	var a := P.node(n, P.surface(_p, yaw, pitch, lift))
	P.aim_z(a, KitMesh.blob_normal(_p, KitMesh.face_dir(yaw, pitch)))
	add_child(a)
	return a


func _add_overlay(key: String, parent: Node3D, n: Node3D) -> void:
	if not _overlays.has(key):
		_overlays[key] = []
	n.visible = false
	# Overlays live next to (not inside) the eye node so hiding the eye keeps them visible.
	var holder := P.node(key.capitalize(), parent.position)
	holder.basis = parent.basis
	holder.add_child(n)
	add_child(holder)
	_overlays[key].append(n)


func _build_eye(a: Node3D, col: Color, skin: Color) -> void:
	match eye_style:
		"dots":
			var d := P.mi(KitMesh.sphere(0.028), col)
			d.scale = Vector3(1, 1.25, 0.45)
			a.add_child(d)
			a.add_child(P.mi(KitMesh.sphere(0.008), P.WHITE, Vector3(0.008, 0.012, 0.012)))
		"visor":
			var v := P.mi(KitMesh.capsule(0.06, _p.ax * 1.7), Color("#2b2f4a"), Vector3.ZERO, 0.15)
			v.rotation.z = PI / 2
			v.scale = Vector3(1, 1, 0.45)
			a.add_child(v)
			var shine := P.mi(KitMesh.capsule(0.012, _p.ax * 0.7), P.WHITE, Vector3(-_p.ax * 0.25, 0.025, 0.026), 0.4)
			shine.rotation.z = PI / 2
			a.add_child(shine)
		_:
			if eye_style == "wink" and a.position.x > 0.0:
				# The winking eye: a closed happy arc.
				a.add_child(P.mi(KitMesh.tube(_arc(0.04, 0.03, true), 0.013, 6, "face_wink"), P.DARK))
				return
			var r := 0.075 if eye_style == "one_eye" else 0.05
			if eye_style in ["star", "heart", "lashes"]:
				r = 0.056
			if eye_style == "googly":
				r = 0.058
			var white := P.mi(KitMesh.sphere(r), P.WHITE)
			white.scale = Vector3(1, 1.1, 0.5)
			a.add_child(white)
			var pr := r * (0.4 if eye_style == "googly" else 0.58)
			var pupil := P.node("Pupil", Vector3(0, -r * 0.08, r * 0.38))
			_pupil_all.append(pupil)
			var pm: MeshInstance3D
			if eye_style == "star":
				pm = P.mi(KitMesh.puffy(KitMesh.star_outline(5, pr * 1.35, pr * 0.62), pr * 0.5, "eye_star%.3f" % pr), col)
			elif eye_style == "heart":
				pm = P.mi(KitMesh.puffy(KitMesh.heart_outline(pr * 1.25), pr * 0.5, "eye_heart%.3f" % pr), col)
			else:
				pm = P.mi(KitMesh.sphere(pr), col)
				pm.scale = Vector3(1, 1.1, 0.5)
			pupil.add_child(pm)
			pupil.add_child(P.mi(KitMesh.sphere(pr * 0.32), P.WHITE, Vector3(pr * 0.35, pr * 0.4, pr * 0.4)))
			a.add_child(pupil)
			if eye_style == "googly":
				_pupils.append(pupil)
			if eye_style == "lashes":
				var side := signf(a.position.x) if a.position.x != 0.0 else 1.0
				for i in 3:
					var ang := (0.35 + 0.3 * i) * side
					var lash := P.mi(KitMesh.capsule(0.007, 0.04), P.DARK, Vector3(sin(ang) * r * 1.05, cos(ang) * r * 1.1, 0.0))
					lash.rotation.z = -ang
					a.add_child(lash)
			if eye_style == "angry":
				var side2 := signf(a.position.x) if a.position.x != 0.0 else 1.0
				var brow_lid := P.mi(KitMesh.sphere(r * 1.08, true), skin.darkened(0.12), Vector3(0, r * 0.25, 0.004))
				brow_lid.scale = Vector3(1, 0.7, 0.55)
				brow_lid.rotation.z = 0.45 * side2
				a.add_child(brow_lid)
			if eye_style == "sleepy":
				var lid := P.mi(KitMesh.sphere(r * 1.08, true), skin.darkened(0.08), Vector3(0, r * 0.05, 0.004))
				lid.scale = Vector3(1, 0.9, 0.55)
				a.add_child(lid)


func _build_mouths(m: Node3D, skin: Color) -> void:
	var red := Color("#c2364b")
	var w: float = _p.ax * 0.4
	_mouths.smile = _add(m, P.mi(KitMesh.tube(_arc(w, w * 0.45, false), 0.014, 6, "m_smile%.3f" % w), P.DARK))
	_mouths.frown = _add(m, P.mi(KitMesh.tube(_arc(w * 0.8, w * 0.3, true), 0.014, 6, "m_frown%.3f" % w), P.DARK))
	_mouths.flat = _add(m, P.mi(KitMesh.tube(PackedVector3Array([Vector3(-w * 0.7, 0.01, 0), Vector3(0, 0, 0.004), Vector3(w * 0.7, 0.01, 0)]), 0.014, 6), P.DARK))
	var wav := PackedVector3Array()
	for i in 9:
		var t := i / 8.0
		wav.append(Vector3((t - 0.5) * w * 1.6, sin(t * TAU * 1.5) * 0.012, 0))
	_mouths.wavy = _add(m, P.mi(KitMesh.tube(wav, 0.012, 6), P.DARK))
	# Resting mouths that reuse a mood shape: a nervous zigzag, a worried frown.
	if mouth_style == "zigzag":
		_mouths.zigzag = _add(m, _mouths.wavy.duplicate())
	if mouth_style == "worried":
		_mouths.worried = _add(m, _mouths.frown.duplicate())
	var grin := P.node("Grin")
	var gm := P.mi(KitMesh.sphere(w, true), P.DARK, Vector3(0, 0.012, 0))
	gm.rotation.x = PI
	gm.scale = Vector3(1.15, 0.8, 0.3)
	grin.add_child(gm)
	var teeth := P.mi(KitMesh.rounded_box(Vector3(w * 1.7, 0.022, 0.01)), P.WHITE, Vector3(0, 0.0, 0.012))
	grin.add_child(teeth)
	_mouths.grin = _add(m, grin)
	var open := P.node("Open")
	var om := P.mi(KitMesh.sphere(w * 0.6), P.DARK)
	om.scale = Vector3(1, 0.8, 0.3)
	open.add_child(om)
	open.add_child(P.mi(KitMesh.sphere(w * 0.32), red, Vector3(0, -w * 0.2, 0.01)))
	_mouths.open = _add(m, open)
	var big := open.duplicate() as Node3D
	big.scale = Vector3(1.25, 1.45, 1)
	_mouths.open_big = _add(m, big)
	var fangs := P.node("Fangs")
	fangs.add_child(P.mi(KitMesh.tube(_arc(w, w * 0.4, false), 0.014, 6, "m_smile%.3f" % w), P.DARK))
	for s in [-1, 1]:
		var f := P.mi(KitMesh.cylinder(0.012, 0.0, 0.035, 8), P.WHITE, Vector3(s * w * 0.45, -w * 0.32, 0.008))
		fangs.add_child(f)
	_mouths.fangs = _add(m, fangs)
	var tongue := P.node("Tongue")
	tongue.add_child(P.mi(KitMesh.tube(_arc(w, w * 0.45, false), 0.014, 6, "m_smile%.3f" % w), P.DARK))
	var tm := P.mi(KitMesh.sphere(w * 0.32), Color("#ff6f91"), Vector3(w * 0.25, -w * 0.5, 0.01))
	tm.scale = Vector3(1, 1.3, 0.5)
	tongue.add_child(tm)
	_mouths.tongue = _add(m, tongue)
	var buck := P.node("BuckTeeth")
	buck.add_child(P.mi(KitMesh.tube(_arc(w, w * 0.35, false), 0.014, 6, "m_buck%.3f" % w), P.DARK))
	for sx in [-1, 1]:
		buck.add_child(P.mi(KitMesh.rounded_box(Vector3(w * 0.32, w * 0.42, 0.012)), P.WHITE, Vector3(sx * w * 0.17, -w * 0.5, 0.01)))
	_mouths.buck_teeth = _add(m, buck)
	if mouth_style == "mustache":
		_mouths.mustache = _add(m, P.mi(KitMesh.tube(_arc(w * 0.8, w * 0.35, false), 0.014, 6, "m_must%.3f" % w), P.DARK))
		# The mustache itself stays on in every mood.
		var ms := P.node("Mustache", Vector3(0, w * 0.55, 0.01))
		for sx in [-1, 1]:
			var lobe := P.mi(KitMesh.sphere(w * 0.42), P.DARK.lightened(0.1), Vector3(sx * w * 0.42, 0, 0))
			lobe.scale = Vector3(1.25, 0.6, 0.45)
			lobe.rotation.z = sx * 0.3
			ms.add_child(lobe)
		m.add_child(ms)
	if mouth_style == "beak":
		var beak := P.mi(KitMesh.cylinder(0.0, 0.05, 0.11, 10), P.GOLD, Vector3(0, 0.03, 0.04))
		beak.rotation.x = PI / 2
		_mouths.beak = _add(m, beak)


func _add(parent: Node3D, n: Node3D) -> Node3D:
	parent.add_child(n)
	n.visible = false
	return n


## Arc in the face plane: smile (dips down) or frown/happy-eye (bumps up).
func _arc(w: float, depth: float, up: bool) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in 9:
		var t := (i / 8.0) * 2.0 - 1.0
		var y := (1.0 - t * t) * depth * (1.0 if up else -1.0)
		pts.append(Vector3(t * w, y, -t * t * 0.01))
	return pts


func _spiral(col: Color) -> Node3D:
	var pts := PackedVector3Array()
	for i in 24:
		var t := i / 23.0
		var a := t * TAU * 2.0
		pts.append(Vector3(cos(a), sin(a), 0) * (0.008 + t * 0.04))
	return P.mi(KitMesh.tube(pts, 0.008, 5, "face_spiral"), col)

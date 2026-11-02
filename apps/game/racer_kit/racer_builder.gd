class_name RacerBuilder
extends RefCounted
## Turns a RacerSpec (contracts §5) into a ToyRacer node tree.
##
##   var racer := RacerBuilder.build(spec)            # ToyRacer (extends Node3D)
##   var racer := RacerBuilder.build(spec, drawing)   # drawing = kid's vehicle drawing (sticker)
##   RacerBuilder.last_errors                          # why the last build() returned null
##
## The spec is validated first (RacerSpec.validate). An invalid spec is not built: build()
## pushes every problem as an error and returns null; nothing is guessed or clamped. Spec frame: +y up, +z forward, +x racer's left;
## Godot: -Z forward, +X right. Extra offsets are metres, extra scale 1.0 = CHAR_UNIT
## (character sockets) or RIDE_UNIT (ride sockets).

const P = preload("res://racer_kit/kit_parts.gd")
const R = preload("res://racer_kit/kit_ride_parts.gd")
const CHAR_UNIT := 0.5
## The driver is the child's own drawing, so it is drawn bigger than toy scale against the ride.
## Creatures you sit on (horses, birds, blobs) are drawn big too, so their riders grow less.
const CHAR_SCALE := 1.25
const CHAR_SCALE_ON_CREATURE := 1.05
const CREATURE_BASES := ["animal4", "bird", "blob"]
const RIDE_UNIT := 1.0
const BOUNCY := ["bouncy", "silly", "speedy", "zoomy", "cheerful", "playful", "wild", "hyper", "quick"]
const CALM := ["calm", "sleepy", "chill", "gentle", "shy", "wise", "cool"]


static var last_errors := PackedStringArray()


static func build(raw: Dictionary, drawing: Texture2D = null) -> ToyRacer:
	var res := RacerSpec.validate(raw)
	last_errors = res.errors
	if not last_errors.is_empty():
		for err in last_errors:
			push_error("RacerBuilder: invalid spec \"%s\": %s" % [str(raw.get("title", "?")), err])
		return null
	var spec: Dictionary = res.spec
	var cols := RacerSpec.palette_colors(spec)
	var racer := ToyRacer.new()
	racer.name = "ToyRacer"
	racer.spec = spec
	racer.set_meta("spec", spec)
	racer.bounciness = _bounciness(spec.personality)
	if spec.has("motion"):
		racer.motion_style = spec.motion.style
		racer.motion_energy = float(spec.motion.energy)
		racer.bounciness *= float(spec.motion.energy)

	var rig := P.node("Rig")
	racer.add_child(rig)
	var model := P.node("Model")
	rig.add_child(model)

	var r: Dictionary = spec.ride
	var d := KitRides.build(r.base, cols[r.color], cols[r.accent])
	var ride := P.node("Ride")
	var rs: Array = r.scale
	ride.scale = Vector3(rs[0], rs[1], rs[2])
	ride.add_child(d.body)
	model.add_child(ride)
	_ride_parts(ride, r, d, cols, drawing)

	var refs := _character(spec.character, d, ride.scale, cols, r.base)
	var ch: Node3D = refs.character
	model.add_child(ch)
	_extras(ride, spec.ride.extras, d.sockets, cols, RIDE_UNIT, true)
	# The ride's finish and pattern cover its body and its extras (a chassis body is all extras);
	# the pattern only goes on parts in the ride's main colour.
	var painted: Array[Node] = [d.body]
	for sock in ride.get_children():
		if String(sock.name).begins_with("Socket_ride_"):
			painted.append(sock)
	for n in painted:
		if r.has("finish"):
			KitMaterial.look(n, {}, Color.WHITE, r.finish)
		if r.has("pattern"):
			KitMaterial.look(n, r.pattern, cols[r.pattern.color], "", cols[r.color])

	var box := _aabb(model, Transform3D.IDENTITY)
	model.position.y = -box.position.y + float(d.hover)
	var tag := Label3D.new()
	tag.name = "NameTag"
	tag.text = spec.title
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.font_size = 48
	tag.outline_size = 12
	tag.pixel_size = 0.004
	tag.no_depth_test = true
	tag.modulate = cols[0].lightened(0.15)
	tag.outline_modulate = Color("#2b2140")
	tag.position = Vector3(0, box.end.y - box.position.y + float(d.hover) + 0.22, 0)
	rig.add_child(tag)

	refs.rig = rig
	refs.model = model
	refs.name_tag = tag
	racer.setup(refs)
	return racer


static func _bounciness(personality: Array) -> float:
	var b := 1.0
	for p in personality:
		if p in BOUNCY:
			b += 0.2
		elif p in CALM:
			b -= 0.2
	return clampf(b, 0.6, 1.4)


# --- ride ---

static func _ride_parts(ride: Node3D, r: Dictionary, d: Dictionary, cols: Array[Color], drawing: Texture2D) -> void:
	var defs: Dictionary = d.defaults
	var wheels = r.get("wheels")
	var legs = r.get("legs")
	if wheels == null and legs == null:
		wheels = _def(defs.get("wheels"), {"count": 4, "style": "toy", "color": r.accent, "size": 1.0}, r)
		legs = _def(defs.get("legs"), {"style": "stumpy", "color": r.color}, r)
	if wheels != null:
		var count := int(wheels.count)
		var rad: float = float(d.wheel_r) * float(wheels.size)
		var spots: Array = d.ground.get(count, d.ground.get(4, []))
		var hub := cols[r.accent] if wheels.color != r.accent else cols[r.color]
		for i in spots.size():
			var w := R.wheel(wheels.style, cols[wheels.color], hub, rad)
			var at: Vector3 = spots[i]
			w.position = Vector3(at.x, at.y - float(d.wheel_r) + rad, at.z)
			ride.add_child(w)
	if legs != null:
		var hips: Array = d.hips
		var length: float = d.leg_len
		if hips.is_empty():
			var g: Array = d.ground.get(4, [])
			length = maxf(0.25, float(d.seat.y) * 0.5)
			for at in g:
				hips.append(Vector3(at.x, length, at.z))
		var style: String = legs.style
		if style == "stumpy" and r.base == "bird" and r.get("legs") == null:
			style = "bird"
		for i in hips.size():
			var l := R.leg(style, cols[legs.color], length, PI * ((i + i / 2) % 2))
			l.position = hips[i]
			ride.add_child(l)
	var wings = r.get("wings", _def(defs.get("wings"), {"style": "feather", "color": r.accent, "size": 1.0}, r))
	if wings != null:
		for side in [-1, 1]:
			var wg := R.wing(wings.style, cols[wings.color], cols[r.color], float(wings.size), side)
			var at2: Vector3 = d.wing
			wg.position = Vector3(at2.x * side, at2.y, at2.z)
			ride.add_child(wg)
	var tail = r.get("tail", _def(defs.get("tail"), {"style": "fluffy", "color": r.accent}, r))
	if tail != null:
		var t := R.tail(tail.style, cols[tail.color])
		t.position = d.tail
		ride.add_child(t)
	if r.has("number"):
		_number(ride, d, r, cols)
	if r.drawingSticker:
		var tex := drawing if drawing else R.placeholder_drawing(cols[r.accent], cols[r.color])
		for side in [-1, 1]:
			var s := R.sticker(tex, float(d.sticker.size))
			var sp: Vector3 = d.sticker.pos
			s.position = Vector3(absf(sp.x) * side + side * 0.01, sp.y, sp.z)
			s.rotation.y = side * PI / 2
			ride.add_child(s)
	# Ride socket markers.
	for sock in d.sockets:
		var m := Marker3D.new()
		m.name = "Socket_" + sock
		m.position = d.sockets[sock]
		ride.add_child(m)


## Fills a ride part from the base's defaults (null when the base has no default).
static func _def(base_default, fallback: Dictionary, r: Dictionary):
	if base_default == null:
		return null
	var out := fallback.duplicate()
	out.merge(base_default, true)
	return out


## Racing number on both sides of the ride (next to the drawing sticker when there is one).
static func _number(ride: Node3D, d: Dictionary, r: Dictionary, cols: Array[Color]) -> void:
	var size: float = float(d.sticker.size)
	var sp: Vector3 = d.sticker.pos
	var z := sp.z - (size * 0.75 if r.drawingSticker else 0.0)
	for side in [-1, 1]:
		var plate := P.node("Number", Vector3(absf(sp.x) * side + side * 0.02, sp.y, z))
		plate.rotation.y = side * PI / 2
		var disc := P.mi(KitMesh.cylinder(size * 0.42, size * 0.42, 0.02, 24), P.WHITE)
		disc.rotation.x = PI / 2
		plate.add_child(disc)
		var tm := TextMesh.new()
		tm.text = str(int(r.number.value))
		tm.font_size = 64
		tm.pixel_size = size * 0.009
		tm.depth = 0.02
		var label := P.mi(tm, cols[r.number.color], Vector3(0, -size * 0.03, 0.02))
		plate.add_child(label)
		ride.add_child(plate)


# --- character ---

static func _character(c: Dictionary, d: Dictionary, ride_scale: Vector3, cols: Array[Color], base: String) -> Dictionary:
	var ch := P.node("Character", d.seat * ride_scale)
	var cs := CHAR_SCALE_ON_CREATURE if base in CREATURE_BASES else CHAR_SCALE
	ch.scale = Vector3.ONE * cs
	var bs: Array = c.body.scale
	var bscale := Vector3(bs[0], bs[1], bs[2])
	var b := P.body(c.body.shape, cols[c.body.color])
	var bp: Dictionary = b.params
	var body_node := P.node("Body")
	body_node.scale = bscale
	body_node.add_child(b.node)
	ch.add_child(body_node)
	if c.body.has("pattern"):
		KitMaterial.look(b.node, c.body.pattern, cols[c.body.pattern.color], "")
	for piece in c.get("outfit", []):
		var o := P.outfit(piece.type, cols[piece.color], bp, bscale, b.center * bscale.y)
		if piece.has("pattern"):
			KitMaterial.look(o, piece.pattern, cols[piece.pattern.color], "")
		ch.add_child(o)
	if c.has("legs"):
		const LEG := 0.24
		if d.stand:
			ch.position.y += LEG * cs  # stand on the deck
		var socks = cols[c.legs.socks] if c.legs.has("socks") else null
		ch.add_child(P.legs(cols[c.legs.color], c.legs.shoes, cols[c.legs.shoeColor], bp, bscale, LEG, not d.stand, socks))
	var center: float = b.center * bscale.y

	# Head
	var hp: Dictionary = P.HEAD_PARAMS.get(c.head.shape, P.HEAD_PARAMS.round)
	var hs: float = c.head.size
	var head_pivot := P.node("HeadPivot", Vector3(0, b.top * bscale.y, 0))
	ch.add_child(head_pivot)
	var head := P.node("Head", Vector3(0, float(hp.ay) * hs * 0.85, 0))
	head.scale = Vector3.ONE * hs
	head_pivot.add_child(head)
	var skin := cols[c.head.color]
	var head_mesh := P.head_mesh(c.head.shape, skin)
	head.add_child(head_mesh)
	if c.head.has("pattern"):
		KitMaterial.look(head_mesh, c.head.pattern, cols[c.head.pattern.color], "")
	var face := RacerFace.new()
	face.setup(hp, c.face, cols, skin)
	head.add_child(face)
	if c.has("hair"):
		# Head centre to the seat, in head-local units (long hair falls to the seat).
		var reach: float = (float(b.top) * bscale.y + float(hp.ay) * hs * 0.85) / hs
		head.add_child(P.hair(c.hair.style, cols[c.hair.color], hp, reach))
	if c.has("hat"):
		var hat_acc := cols[(int(c.hat.color) + 1) % cols.size()]
		head.add_child(P.hat(c.hat.type, cols[c.hat.color], hat_acc, hp))

	# Arms: pivot at the shoulder, local -Y runs down the arm to the hand.
	var arm_col := cols[c.arms.color]
	var arms := []
	for side in [-1, 1]:
		var sh := Vector3(side * float(bp.ax) * 0.92 * bscale.x, center + float(bp.ay) * 0.42 * bscale.y, 0)
		var hand: Vector3
		if d.handle != null and not d.stand:
			var hpos: Vector3 = (d.handle * ride_scale - ch.position) / cs
			hand = hpos + Vector3(side * float(d.hand_spread), 0, 0)
		else:
			hand = sh + Vector3(side * 0.13, -0.2, -0.06)
		var dir := hand - sh
		var length := clampf(dir.length(), 0.12, 0.6)
		var arm := P.node("ArmL" if side < 0 else "ArmR", sh)
		P.aim_y(arm, -dir)
		arm.add_child(P.mi(KitMesh.capsule(0.042, length + 0.06), arm_col, Vector3(0, -length / 2, 0)))
		var hand_node := P.node("Hand", Vector3(0, -length, 0))
		hand_node.add_child(P.mi(KitMesh.sphere(0.058), arm_col.lightened(0.12)))
		arm.add_child(hand_node)
		ch.add_child(arm)
		arms.append(arm)

	# Character socket markers (racer's left = Godot -X).
	var sockets := {
		"head_top": [head, Vector3(0, float(hp.ay) * 0.92, 0)],
		"head_side": [head, Vector3(-float(hp.ax) * 0.95, 0.02, 0)],
		"head_side_r": [head, Vector3(float(hp.ax) * 0.95, 0.02, 0)],
		"head_front": [head, P.surface(hp, 0.0, -0.05)],
		"body_front": [ch, Vector3(0, center + float(bp.ay) * 0.1 * bscale.y, -float(bp.az) * bscale.z)],
		"body_back": [ch, Vector3(0, center + float(bp.ay) * 0.1 * bscale.y, float(bp.az) * bscale.z)],
		"hand": [arms[1].get_node("Hand"), Vector3.ZERO],
		"hand_l": [arms[0].get_node("Hand"), Vector3.ZERO],
	}
	var where := {}
	for k in sockets:
		var m := Marker3D.new()
		m.name = "Socket_" + k
		m.position = sockets[k][1]
		sockets[k][0].add_child(m)
		where[k] = m
	_extras(null, c.extras, where, cols, CHAR_UNIT, false)
	if c.body.has("finish"):
		KitMaterial.look(ch, {}, Color.WHITE, c.body.finish)
	return {"character": ch, "head_pivot": head_pivot, "arm_l": arms[0], "arm_r": arms[1], "face": face}


# --- extras ---

const OTHER_SIDE := {"head_side": "head_side_r", "hand": "hand_l", "ride_side": "ride_right", "ride_left": "ride_right"}


## sockets: name -> Marker3D (character) or name -> Vector3 (ride, markers under parent).
static func _extras(parent: Node3D, extras: Array, sockets: Dictionary, cols: Array[Color], unit: float, ride: bool) -> void:
	for e in extras:
		var sock: String = e.socket
		if ride and sock == "ride_side":
			sock = "ride_left"
		var copies := [[sock, false]]
		if e.mirror:
			copies.append([OTHER_SIDE.get(sock, sock), true])
		for cp in copies:
			var marker := _marker(parent, sockets, cp[0])
			if marker == null:
				continue
			marker.add_child(R.extra(e, cols[e.color], unit, cp[1]))


static func _marker(parent: Node3D, sockets: Dictionary, name: String) -> Node3D:
	var v = sockets.get(name)
	if v is Node3D:
		return v
	if parent:
		return parent.get_node_or_null("Socket_" + name)
	return null


## AABB of all meshes under n, in the space of n's parent transform xf.
static func _aabb(n: Node, xf: Transform3D) -> AABB:
	var out := AABB()
	var first := true
	for c in n.get_children():
		if not c is Node3D:
			continue
		var cx: Transform3D = xf * c.transform
		var box := AABB()
		var has := false
		if c is MeshInstance3D and c.mesh:
			box = cx * c.mesh.get_aabb()
			has = true
		var sub := _aabb(c, cx)
		if sub.size != Vector3.ZERO or sub.position != Vector3.ZERO:
			box = sub if not has else box.merge(sub)
			has = true
		if has:
			out = box if first else out.merge(box)
			first = false
	return out

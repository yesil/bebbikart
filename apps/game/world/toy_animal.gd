extends Node3D
## A toy cow or sheep for the village surprises (world/obstacle_views.gd), made in the racer kit's
## style (KitMesh blobs, capsules and tubes, the toon material, big eyes like RacerFace) and moved
## in code: walking, grazing and chewing, ear flicks, a swishing tail, a swinging cow bell,
## galloping or bouncing off, a look at karts coming near, a startled hop when one shaves past, and
## a comic spin (cow) or tumble (sheep) with spiral eyes and stars when one hits it.
##
## The cow is a Swiss dairy cow (white with black or red-brown patches like the cows in the fields,
## pink muzzle, cream horns, a brass bell on a red strap); the sheep a Valais Blacknose (fluffy
## cream wool, black face, ears, knees and feet, curled horns). Both face -Z like the kit, measure
## in metres and stay inside their sim footprint (sim/obstacles.gd KINDS: cow 1.0 x 2.6 m, sheep
## 0.7 x 1.5 m).
##
## Each part that moves is ONE mesh: its pieces are merged with per-vertex colours (the toon shader
## multiplies them in, their alpha says where the patches may show) and cached for every animal, so
## a cow is 14 meshes (about 9k triangles), a sheep 9 (11k; its woolly body casts the shadow of a
## plain ellipsoid), Godot draws the same mesh of several animals together, and making one only
## makes nodes.

const P = preload("res://racer_kit/kit_parts.gd")

const EYE_DARK := Color("#2b2140")
const COW_WHITE := Color("#fbf6ec")
const COW_PATCHES := [Color("#2d2930"), Color("#2d2930"), Color("#7a3c20")]   # black like the
const MUZZLE := Color("#f5a3ad")                                              # Holsteins, or
const NOSTRIL := Color("#8a3a4a")                                             # Simmental red
const HORN := Color("#f1e3c0")
const TUFT := Color("#fff8e8")
const HOOF := Color("#3a2f3a")
const STRAP := Color("#c4302a")
const BRASS := Color("#e7ae3c")
const WOOL := [Color("#f8f1df"), Color("#efe3c6"), Color("#fcf8ee"), Color("#f3e9d2")]
const SHIN := Color("#efe6d4")
const FACE := Color("#2b262b")
const SNOUT := Color("#3b3439")
const SHEEP_HORN := Color("#c9a467")
const PATCHES := 9           # toon.gdshader pattern "patches"

## Body layout per kind (metres; the root stands on the road, facing -Z): how much the whole toy
## is scaled up (and pushed back to stay inside its footprint), where the body, the neck and the
## four legs (front left, front right, back left, back right) pivot, leg length, stride
## (metres one leg cycle covers walking and running), leg swing (rad) walking and running, its
## walking speed (m/s), how far the head turns to look, and within what distance (m) of a kart
## its eyes go wide and it hops out of its skin.
const SPEC := {
	"cow": {"size": 1.12, "back": 0.1, "hips": Vector3(0, 0.84, 0.12), "neck": Vector3(0, 1.04, -0.5),
		"legs": [Vector3(-0.25, 0.7, -0.36), Vector3(0.25, 0.7, -0.36), Vector3(-0.25, 0.7, 0.55), Vector3(0.25, 0.7, 0.55)],
		"leg_len": 0.7, "stride": [1.0, 1.9], "swing": [0.34, 0.72], "walk_v": 1.2, "look": 1.0,
		"wide_m": 5.0, "near_m": 2.6},
	"sheep": {"size": 1.0, "back": 0.0, "hips": Vector3(0, 0.6, 0.05), "neck": Vector3(0, 0.74, -0.34),
		"legs": [Vector3(-0.14, 0.36, -0.26), Vector3(0.14, 0.36, -0.26), Vector3(-0.14, 0.36, 0.34), Vector3(0.14, 0.36, 0.34)],
		"leg_len": 0.36, "stride": [0.6, 1.1], "swing": [0.42, 0.8], "walk_v": 1.1, "look": 1.2,
		"wide_m": 4.0, "near_m": 2.1},
}
const WALK_OFF := [0.0, PI, PI, 0.0]       # diagonal pairs
const RUN_OFF := [0.0, 0.6, PI, PI + 0.6]  # a gallop: the front pair, then the back pair
const COW_HEAD := {"ax": 0.33, "ay": 0.3, "az": 0.29, "n": 2.2}
const COW_HEAD_AT := Vector3(0, 0.16, -0.3)        # in the neck's frame
const COLLAR_AT := Vector3(0, -0.14, 0.02)
const COLLAR_TILT := -0.45                         # lower at the throat, where the bell hangs
const BELL_AT := Vector3(0, -0.34, -0.24)
const BELL_LEN := 0.2                              # pendulum length (m)
const SHEEP_FACE := {"ax": 0.185, "ay": 0.2, "az": 0.19, "n": 2.1, "taper": 0.12}
const SHEEP_FACE_AT := Vector3(0, 0.07, -0.15)
const SPIN_S := 0.7          # a hit cow spins round once in this long
const TUMBLE_S := 0.75       # a hit sheep rolls over once
const DIZZY_S := 1.8
const HOP_S := 0.42

var kind := ""
var _hips: Node3D
var _neck: Node3D
var _jaw: Node3D
var _bell: Node3D
var _tail: Array[Node3D] = []
var _legs: Array[Node3D] = []
var _ears: Array[Node3D] = []
var _ear_rest: Array[Vector3] = []
var _eyes: Array[Node3D] = []
var _dizzy_eyes: Array[Node3D] = []
var _spirals: Array[Node3D] = []
var _stars: Node3D
var _hips_rest := Vector3.ZERO

var _t := 0.0
var _phase := 0.0
var _gait := 0.0             # 0 walking .. 1 running
var _amp := 0.0              # leg swing now (rad)
var _head_yaw := 0.0
var _head_pitch := 0.0
var _graze_up := false
var _graze_t := 0.0
var _jaw_open := 0.0
var _wide := 0.0
var _blink := 0.0
var _blink_t := 2.0
var _ear_t: Array[float] = [1.0, 2.0]
var _ear_kick: Array[float] = [0.0, 0.0]
var _alert := 0.0
var _tail_burst := 0.0
var _hop_t := -1.0
var _react_t := -1.0
var _dizzy := 0.0
var _bell_a := Vector2.ZERO  # swing about x (fore and aft) and z (sideways), rad
var _bell_w := Vector2.ZERO
var _bell_p := Vector3.ZERO
var _bell_v := Vector3.ZERO
var _bell_seen := false


## Builds the animal (kind "cow" or "sheep"); rng picks its looks (a cow's patch colour and
## layout) and where it is in its walk and graze.
func setup(p_kind: String, rng: RandomNumberGenerator) -> void:
	kind = p_kind
	var sp: Dictionary = SPEC[kind]
	_hips_rest = sp["hips"]
	var rig := P.node("Rig", Vector3(0, 0, float(sp["back"])))
	rig.scale = Vector3.ONE * float(sp["size"])
	add_child(rig)
	_hips = P.node("Hips", _hips_rest)
	rig.add_child(_hips)
	_neck = P.node("Neck", (sp["neck"] as Vector3) - _hips_rest)
	_neck.rotation_order = EULER_ORDER_YXZ
	_hips.add_child(_neck)
	var legs: Array = sp["legs"]
	for i in 4:
		var leg := P.node("Leg%d" % i, (legs[i] as Vector3) - _hips_rest)
		_hips.add_child(leg)
		_legs.append(leg)
	if kind == "cow":
		_build_cow(rng)
	else:
		_build_sheep()
	_stars = P.node("Stars", COW_HEAD_AT + Vector3(0, 0.55, 0) if kind == "cow" else SHEEP_FACE_AT + Vector3(0, 0.4, 0))
	for i in 3:
		var a := TAU * i / 3.0
		var st := _mi(_star_mesh(), P.GOLD, Vector3(cos(a), 0, sin(a)) * (0.3 if kind == "cow" else 0.22), false)
		KitMaterial.paint(st, P.GOLD, 0.35)
		_stars.add_child(st)
	_stars.visible = false
	_neck.add_child(_stars)
	_phase = rng.randf() * TAU
	_graze_t = rng.randf_range(0.5, 3.0)
	_blink_t = rng.randf_range(0.5, 4.0)
	_ear_t = [rng.randf_range(0.5, 3.0), rng.randf_range(0.5, 3.0)]


func _build_cow(rng: RandomNumberGenerator) -> void:
	var patch: Color = COW_PATCHES[rng.randi() % COW_PATCHES.size()]
	var torso := _mi(_cow_torso(), Color.WHITE, Vector3.ZERO, true)
	_patches(torso, patch, rng.randf_range(0.85, 1.15))
	_hips.add_child(torso)
	var head := _mi(_cow_head(), Color.WHITE, Vector3.ZERO, true)
	_patches(head, patch, rng.randf_range(0.85, 1.15))
	_neck.add_child(head)
	_jaw = P.node("Jaw", Vector3(0, -0.12, -0.4))
	_jaw.add_child(_mi(_cow_jaw(), Color.WHITE, Vector3.ZERO, false))
	_neck.add_child(_jaw)
	for side: float in [-1.0, 1.0]:
		var eye := P.node("Eye", COW_HEAD_AT + P.surface(COW_HEAD, 0.43 * side, 0.2))
		P.aim_z(eye, KitMesh.blob_normal(COW_HEAD, KitMesh.face_dir(0.43 * side, 0.2)))
		eye.add_child(_mi(_eye_mesh(0.088, side, true), Color.WHITE, Vector3.ZERO, false))
		_neck.add_child(eye)
		_eyes.append(eye)
		_add_spiral(eye, 0.088)
		var ear := P.node("Ear", COW_HEAD_AT + Vector3(0.31 * side, 0.08, 0.06))
		ear.rotation = Vector3(0.0, -0.25 * side, -0.4 * side)
		var em := _mi(_cow_ear(side), Color.WHITE, Vector3.ZERO, true)
		_patches(em, patch, 1.0)
		ear.add_child(em)
		_neck.add_child(ear)
		_ears.append(ear)
		_ear_rest.append(ear.rotation)
	_bell = P.node("Bell", BELL_AT)
	var bell := _mi(_cow_bell(), Color.WHITE, Vector3.ZERO, true)
	bell.set_instance_shader_parameter("finish", 2)   # metallic brass
	_bell.add_child(bell)
	_neck.add_child(_bell)
	for i in 4:
		_legs[i].add_child(_mi(_cow_leg(), Color.WHITE, Vector3.ZERO, true))
	var t1 := P.node("Tail", Vector3(0, 0.28, 0.7))
	var tm := _mi(_cow_tail(0), Color.WHITE, Vector3.ZERO, true)
	_patches(tm, patch, 1.0)
	t1.add_child(tm)
	_hips.add_child(t1)
	var t2 := P.node("TailEnd", Vector3(0, -0.34, 0.12))
	t2.add_child(_mi(_cow_tail(1), Color.WHITE, Vector3.ZERO, true))
	t1.add_child(t2)
	_tail = [t1, t2]


func _build_sheep() -> void:
	# The woolly body's shadow comes from a plain ellipsoid of its size (the puffs are many triangles
	# for every shadow pass, and nobody sees a shadow's bumps).
	_hips.add_child(_mi(_sheep_body(), Color.WHITE, Vector3.ZERO, false))
	var shadow := _mi(_lo({"ax": 0.34, "ay": 0.33, "az": 0.6}), Color.WHITE, Vector3(0, 0.0, 0.05), true)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_hips.add_child(shadow)
	_neck.add_child(_mi(_sheep_head(), Color.WHITE, Vector3.ZERO, true))
	for side: float in [-1.0, 1.0]:
		var eye := P.node("Eye", SHEEP_FACE_AT + P.surface(SHEEP_FACE, 0.5 * side, 0.22))
		P.aim_z(eye, KitMesh.blob_normal(SHEEP_FACE, KitMesh.face_dir(0.5 * side, 0.22)))
		eye.add_child(_mi(_eye_mesh(0.068, side, false), Color.WHITE, Vector3.ZERO, false))
		_neck.add_child(eye)
		_eyes.append(eye)
		_add_spiral(eye, 0.068)
	for i in 4:
		_legs[i].add_child(_mi(_sheep_leg(), Color.WHITE, Vector3.ZERO, true))


static func _mi(mesh: Mesh, color: Color, pos: Vector3, shadow: bool) -> MeshInstance3D:
	var m := P.mi(mesh, color, pos)
	if not shadow:
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return m


static func _patches(gi: GeometryInstance3D, color: Color, scale_: float) -> void:
	gi.set_instance_shader_parameter("pattern", PATCHES)
	gi.set_instance_shader_parameter("pattern_color", color)
	gi.set_instance_shader_parameter("pattern_scale", scale_)


## A dizzy eye where the eye is (hidden until a hit): white with a spiral.
func _add_spiral(eye: Node3D, r: float) -> void:
	var holder := P.node("DizzyEye", eye.position)
	holder.basis = eye.basis
	var white := _mi(KitMesh.sphere(r), P.WHITE, Vector3.ZERO, false)
	white.scale = Vector3(1, 1.15, 0.5)
	holder.add_child(white)
	var s := _mi(_spiral_mesh(), EYE_DARK, Vector3(0, 0, r * 0.32), false)
	s.scale = Vector3.ONE * r / 0.045
	holder.add_child(s)
	holder.visible = false
	_neck.add_child(holder)
	_dizzy_eyes.append(holder)
	_spirals.append(s)


# ---------------------------------------------------------------- moving

## A frame of it. speed: m/s it walks its own way; state: its sim item's state (in, stay, out,
## scared); yaw_rate: rad/s the view turns it; look: world point of the kart it watches, or null;
## near_m: that kart's distance (INF without one).
func animate(delta: float, speed: float, state: String, yaw_rate: float, look: Variant, near_m: float) -> void:
	_t += delta
	var sp: Dictionary = SPEC[kind]
	var swing: Array = sp["swing"]
	var stride: Array = sp["stride"]
	var leg_len: float = sp["leg_len"]
	# Walk or run: the legs swing with the distance covered.
	_gait = move_toward(_gait, 1.0 if speed > 2.0 else 0.0, delta * 3.0)
	var want := 0.0
	if speed > 0.05:
		want = lerpf(float(swing[0]) * clampf(speed / float(sp["walk_v"]), 0.4, 1.0), float(swing[1]), _gait)
	elif absf(yaw_rate) > 0.3:
		want = float(swing[0]) * 0.5       # shuffling round on the spot
	_amp = move_toward(_amp, want, delta * 2.5)
	_phase = fmod(_phase + (speed / lerpf(float(stride[0]), float(stride[1]), _gait) + absf(yaw_rate) * 0.3) * TAU * delta, TAU)
	var hop := 0.0
	var splay := 0.0
	if _hop_t >= 0.0:
		_hop_t += delta
		var k := _hop_t / HOP_S
		if k >= 1.0:
			_hop_t = -1.0
		else:
			hop = (0.2 if kind == "cow" else 0.26) * sin(PI * k)
			splay = 0.35 * sin(PI * k)
	var spin := 0.0
	var roll := 0.0
	if _react_t >= 0.0:
		_react_t += delta
		var k := _react_t / (SPIN_S if kind == "cow" else TUMBLE_S)
		if k < 1.0:
			var e := 1.0 - pow(1.0 - k, 2.0)
			hop = maxf(hop, (0.5 if kind == "cow" else 0.42) * sin(PI * k))
			splay = maxf(splay, 0.45 * sin(PI * k))
			if kind == "cow":
				spin = TAU * e
			else:
				roll = TAU * e
		_dizzy = maxf(0.0, DIZZY_S - _react_t)
	# Legs: the body sits on the most upright one; a little splay when it hops.
	var drop := leg_len
	for i in 4:
		var a := sin(_phase + lerpf(WALK_OFF[i], RUN_OFF[i], _gait)) * _amp
		_legs[i].rotation = Vector3(a, 0.0, splay * (1.0 if i % 2 == 1 else -1.0))
		drop = minf(drop, leg_len * (1.0 - cos(a)))
	var walk_k := _amp / float(swing[0])
	var bounce: float
	if kind == "sheep":
		bounce = (0.03 + 0.13 * _gait) * maxf(0.0, sin(_phase * 2.0)) * minf(1.0, walk_k)
	else:
		bounce = 0.06 * _gait * absf(sin(_phase))
	_hips.position = _hips_rest + Vector3(0.0, bounce + hop - drop, 0.0)
	_hips.rotation = Vector3((0.1 if kind == "cow" else 0.05) * _gait * sin(_phase + 0.5),
		0.0, 0.035 * sin(_phase) * minf(1.0, walk_k) + roll)
	rotation.y = PI + spin
	_move_head(delta, state, look, near_m, walk_k)
	_move_face(delta, state, near_m)
	if kind == "cow":
		_move_tail(delta)
		_move_bell(delta)


func _move_head(delta: float, state: String, look: Variant, near_m: float, walk_k: float) -> void:
	var sp: Dictionary = SPEC[kind]
	var yaw := 0.0
	var pitch := -0.05 + sin(_phase * 2.0) * 0.06 * minf(1.0, walk_k)    # nodding with its steps
	_alert = move_toward(_alert, 1.0 if look != null else 0.0, delta * 3.0)
	if state == "scared":
		pitch = -0.2 if kind == "cow" else 0.15                         # head down and off
	elif look != null and _react_t < 0.0:
		# Watching the kart: head round (as far as a neck goes) and up at it.
		var rel: Vector3 = _hips.to_local(look as Vector3) - _neck.position
		yaw = clampf(atan2(-rel.x, -rel.z), -float(sp["look"]), float(sp["look"]))
		pitch = clampf(atan2(rel.y, Vector2(rel.x, rel.z).length()), -0.2, 0.3) + 0.08
	elif state == "stay" and kind == "cow":
		# Grazing: head down nibbling, now and then up chewing and looking about.
		_graze_t -= delta
		if _graze_t <= 0.0:
			_graze_up = not _graze_up
			_graze_t = randf_range(1.2, 2.6) if _graze_up else randf_range(2.5, 5.0)
		if _graze_up:
			pitch = 0.02
			yaw = sin(_t * 0.5) * 0.35
		else:
			pitch = -1.1 + sin(_t * 3.0) * 0.04
			yaw = sin(_t * 0.8) * 0.15
	var k := 1.0 - exp(-delta * (7.0 if look != null else 3.5))
	_head_yaw = lerpf(_head_yaw, yaw, k)
	_head_pitch = lerpf(_head_pitch, pitch, k)
	_neck.rotation = Vector3(_head_pitch, _head_yaw, sin(_t * 7.0) * 0.18 * minf(1.0, _dizzy))
	if _jaw != null:
		# Chewing the cud from side to side; mouth wide open (MOO!) when hit.
		var chew := 1.0 if state == "stay" else 0.25
		_jaw_open = move_toward(_jaw_open, 1.0 if _react_t >= 0.0 and _react_t < 1.0 else 0.0, delta * 6.0)
		_jaw.rotation = Vector3(-0.06 * chew * (0.5 + 0.5 * sin(_t * 9.0)) - 0.35 * _jaw_open, sin(_t * 4.5) * 0.14 * chew, 0.0)


func _move_face(delta: float, state: String, near_m: float) -> void:
	var sp: Dictionary = SPEC[kind]
	var wide := near_m < float(sp["wide_m"]) or _hop_t >= 0.0 or (_react_t >= 0.0 and _react_t < 2.5) or state == "scared"
	_wide = move_toward(_wide, 1.0 if wide else 0.0, delta * (9.0 if wide else 1.5))
	_blink_t -= delta
	if _blink_t <= 0.0:
		_blink = 0.13
		_blink_t = randf_range(2.0, 5.0)
	_blink = maxf(0.0, _blink - delta)
	var lid := 0.12 if _blink > 0.0 and _wide < 0.5 else 1.0
	var s := 1.0 + 0.45 * _wide
	var dizzy := _dizzy > 0.0
	for e in _eyes:
		e.scale = Vector3(s, s * lid, s)
		e.visible = not dizzy
	for d in _dizzy_eyes:
		d.visible = dizzy
	for sp_ in _spirals:
		sp_.rotation.z = -_t * 7.0
	_stars.visible = dizzy
	if dizzy:
		_stars.rotation.y = _t * 5.0
		_stars.position.y = (COW_HEAD_AT.y + 0.55 if kind == "cow" else SHEEP_FACE_AT.y + 0.4) + sin(_t * 6.0) * 0.03
	for i in _ears.size():
		_ear_t[i] -= delta
		if _ear_t[i] <= 0.0:
			_ear_kick[i] = 1.0
			_ear_t[i] = randf_range(1.5, 4.5)
		_ear_kick[i] = maxf(0.0, _ear_kick[i] - delta * 4.0)
		var side := -1.0 if i == 0 else 1.0
		var flick := sin(_ear_kick[i] * PI)
		_ears[i].rotation = _ear_rest[i] + Vector3(0.5 * flick * _ear_kick[i], 0.0, side * (0.45 * _alert + 0.35 * flick))


func _move_tail(delta: float) -> void:
	_tail_burst = maxf(0.0, _tail_burst - delta)
	if randf() < delta * 0.3:
		_tail_burst = 1.4
	var burst := minf(1.0, _tail_burst)
	var lift := -(0.12 + 0.95 * _gait)
	_tail[0].rotation = Vector3(lift, 0.0, sin(_t * 1.6) * 0.22 + sin(_t * 9.0) * 0.55 * burst)
	_tail[1].rotation = Vector3(lift * 0.4, 0.0, sin(_t * 1.6 - 0.7) * 0.3 + sin(_t * 9.0 - 1.2) * 0.6 * burst)


## The bell hangs from the strap and swings like a pendulum as the cow moves.
func _move_bell(delta: float) -> void:
	var p := _bell.global_position
	if not _bell_seen or delta <= 0.0:
		_bell_seen = true
		_bell_p = p
		_bell_v = Vector3.ZERO
		return
	var v := (p - _bell_p) / delta
	var acc := ((v - _bell_v) / delta).limit_length(40.0)
	_bell_p = p
	_bell_v = v
	var la := global_basis.inverse() * acc
	var g := 9.8 / BELL_LEN
	var dt := minf(delta, 0.05)
	_bell_w.x += (-g * sin(_bell_a.x) + la.z / BELL_LEN - 1.6 * _bell_w.x) * dt
	_bell_w.y += (-g * sin(_bell_a.y) - la.x / BELL_LEN - 1.6 * _bell_w.y) * dt
	_bell_a = (_bell_a + _bell_w * dt).clamp(Vector2(-1.2, -1.2), Vector2(1.2, 1.2))
	# Hanging straight down whatever the head does, plus its swing.
	_bell.rotation = Vector3(-_head_pitch - _hips.rotation.x + _bell_a.x, 0.0, _bell_a.y - _hips.rotation.z)


## A kart shaved past: a startled hop, eyes wide (and the bell rings).
func startle() -> void:
	if _react_t >= 0.0 or _hop_t >= 0.0:
		return
	_hop_t = 0.0
	_ear_kick = [1.0, 1.0]
	_bell_w += Vector2(randf_range(-5.0, 5.0), randf_range(-6.0, 6.0))


## A kart hit it: a spin (cow) or a tumble (sheep), spiral eyes and stars, then off it runs.
func knock() -> void:
	if _react_t >= 0.0:
		return
	_react_t = 0.0
	_hop_t = -1.0
	_ear_kick = [1.0, 1.0]
	_bell_w += Vector2(randf_range(8.0, 12.0) * (1.0 if randf() < 0.5 else -1.0), randf_range(-14.0, 14.0))


## Seconds since the hit (-1 before one).
func knocked_for() -> float:
	return _react_t


# ---------------------------------------------------------------- meshes (cached, merged)

## [mesh, transform, colour, patches may show] for _merge.
static func _pc(mesh: Mesh, pos: Vector3, col: Color, patch := false, rot := Vector3.ZERO, scl := Vector3.ONE) -> Array:
	return [mesh, Transform3D(Basis.from_euler(rot) * Basis.from_scale(scl), pos), col, patch]


## One mesh of pieces from _pc, coloured per vertex (alpha 1 where the patches may show).
static func _merge(pieces: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for pc in pieces:
		var arr: Array = (pc[0] as Mesh).surface_get_arrays(0)
		var xf: Transform3D = pc[1]
		var nb := xf.basis.inverse().transposed()
		var flip := xf.basis.determinant() < 0.0
		# Vertex colours reach the shader as they are: linear, unlike the albedo uniform.
		var col: Color = (pc[2] as Color).srgb_to_linear()
		col.a = 1.0 if pc[3] else 0.0
		var base := verts.size()
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i in v.size():
			verts.append(xf * v[i])
			norms.append((nb * n[i]).normalized())
			cols.append(col)
		var tri: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if tri.is_empty():
			tri = PackedInt32Array(range(v.size()))
		for t in range(0, tri.size(), 3):
			idx.append(base + tri[t])
			idx.append(base + tri[t + (2 if flip else 1)])
			idx.append(base + tri[t + (1 if flip else 2)])
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = verts
	a[Mesh.ARRAY_NORMAL] = norms
	a[Mesh.ARRAY_COLOR] = cols
	a[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return m


static func _ball(r: float, lat := 8, lon := 12) -> Mesh:
	return KitMesh.blob({"ax": r, "ay": r, "az": r}, lat, lon)


## A small blob, coarser than the kit's default (it is small on screen).
static func _lo(p: Dictionary) -> Mesh:
	return KitMesh.blob(p, 8, 12)


## A rounded rod from a to b (a coarse capsule).
static func _rod(a: Vector3, b: Vector3, r: float, sides := 8) -> Mesh:
	return KitMesh.tube(PackedVector3Array([a, b]), r, sides)


## A toy eye (white, pupil, shine; the cow's with three lashes on the outer side), +Z out.
static func _eye_mesh(r: float, side: float, lashes: bool) -> Mesh:
	return KitMesh.cached("animal:eye:%.3f:%d:%s" % [r, int(side), lashes], func() -> Mesh:
		var pr := r * 0.6
		var pcs := [
			_pc(_ball(r, 10, 14), Vector3.ZERO, P.WHITE, false, Vector3.ZERO, Vector3(1, 1.15, 0.5)),
			_pc(_ball(pr), Vector3(0, -r * 0.08, r * 0.3), EYE_DARK, false, Vector3.ZERO, Vector3(1, 1.1, 0.5)),
			_pc(_ball(pr * 0.34, 5, 8), Vector3(pr * 0.35, pr * 0.42 - r * 0.08, r * 0.3 + pr * 0.42), P.WHITE),
		]
		if lashes:
			for i in 3:
				var ang := (0.45 + 0.33 * i) * side
				var dir := Vector3(sin(ang), cos(ang), 0.0)
				var root := Vector3(dir.x * r * 0.95, dir.y * r * 1.1, 0.0)
				pcs.append(_pc(_rod(root, root + dir * r * 0.45, r * 0.1, 5), Vector3.ZERO, P.DARK))
		return _merge(pcs))


static func _spiral_mesh() -> Mesh:
	var pts := PackedVector3Array()
	for i in 24:
		var t := i / 23.0
		var a := t * TAU * 2.0
		pts.append(Vector3(cos(a), sin(a), 0) * (0.008 + t * 0.04))
	return KitMesh.tube(pts, 0.008, 5, "face_spiral")


static func _star_mesh() -> Mesh:
	return KitMesh.puffy(KitMesh.star_outline(5, 0.085, 0.04), 0.04, "animal_star")


static func _cow_torso() -> Mesh:
	return KitMesh.cached("animal:cow_torso", func() -> Mesh:
		var pcs := [_pc(KitMesh.blob({"ax": 0.43, "ay": 0.37, "az": 0.72, "n": 2.3, "flat_bottom": 0.1}, 16, 26),
			Vector3.ZERO, COW_WHITE, true)]
		# A pink udder with four teats under the back.
		pcs.append(_pc(_lo({"ax": 0.12, "ay": 0.08, "az": 0.13}), Vector3(0, -0.31, 0.32), MUZZLE))
		for x: float in [-0.05, 0.05]:
			for z: float in [0.27, 0.37]:
				pcs.append(_pc(_ball(0.026, 6, 8), Vector3(x, -0.39, z), MUZZLE, false, Vector3.ZERO, Vector3(1, 1.7, 1)))
		return _merge(pcs))


## Neck, head, muzzle, nostrils, smile, horns, a tuft, and the red bell strap with its stitching.
static func _cow_head() -> Mesh:
	return KitMesh.cached("animal:cow_head", func() -> Mesh:
		var h := COW_HEAD_AT
		var pcs := [
			_pc(KitMesh.blob({"ax": 0.25, "ay": 0.27, "az": 0.3}, 10, 16), Vector3(0, -0.06, 0.06), COW_WHITE, true),
			_pc(KitMesh.blob(COW_HEAD, 14, 22), h, COW_WHITE, true),
			_pc(KitMesh.blob({"ax": 0.28, "ay": 0.17, "az": 0.2, "n": 2.4}, 10, 18), Vector3(0, 0.0, -0.52), MUZZLE),
		]
		for x: float in [-0.1, 0.1]:
			pcs.append(_pc(_ball(0.042, 6, 10), Vector3(x, 0.04, -0.703), NOSTRIL, false, Vector3(-0.15, 0, 0), Vector3(1, 1.35, 0.45)))
		pcs.append(_pc(KitMesh.tube(PackedVector3Array([Vector3(-0.09, -0.07, -0.703), Vector3(0, -0.1, -0.705),
			Vector3(0.09, -0.07, -0.703)]), 0.013, 6), Vector3.ZERO, NOSTRIL))
		for side: float in [-1.0, 1.0]:
			var horn := PackedVector3Array()
			for p: Vector3 in [Vector3(0.15, 0.39, -0.27), Vector3(0.23, 0.45, -0.29), Vector3(0.28, 0.52, -0.32), Vector3(0.28, 0.58, -0.36)]:
				horn.append(Vector3(p.x * side, p.y, p.z))
			pcs.append(_pc(P._taper_tube(horn, 0.065), Vector3.ZERO, HORN))
		for p: Vector3 in [Vector3(0, 0.46, -0.24), Vector3(-0.065, 0.44, -0.19), Vector3(0.065, 0.44, -0.19), Vector3(0, 0.45, -0.15)]:
			pcs.append(_pc(_ball(0.065, 6, 10), p, TUFT))
		var band := Basis(Vector3.RIGHT, COLLAR_TILT) * Basis.from_scale(Vector3(1, 1, 1.2))
		pcs.append([KitMesh.cylinder(0.27, 0.285, 0.13, 20), Transform3D(band, COLLAR_AT), STRAP, false])
		for i in 12:
			var a := TAU * i / 12.0
			for y: float in [-0.042, 0.042]:
				var q := COLLAR_AT + band * Vector3(cos(a) * 0.282, y, sin(a) * 0.282)
				pcs.append(_pc(_ball(0.013, 3, 5), q, P.WHITE))
		return _merge(pcs))


static func _cow_jaw() -> Mesh:
	return KitMesh.cached("animal:cow_jaw", func() -> Mesh:
		return _merge([_pc(_lo({"ax": 0.2, "ay": 0.075, "az": 0.15}), Vector3(0, -0.02, -0.1), MUZZLE)]))


static func _cow_ear(side: float) -> Mesh:
	return KitMesh.cached("animal:cow_ear:%d" % int(side), func() -> Mesh:
		return _merge([
			_pc(_lo({"ax": 0.13, "ay": 0.08, "az": 0.04}), Vector3(0.11 * side, 0, 0), COW_WHITE, true),
			_pc(_lo({"ax": 0.085, "ay": 0.05, "az": 0.02}), Vector3(0.115 * side, -0.005, -0.03), MUZZLE),
		]))


static func _cow_leg() -> Mesh:
	return KitMesh.cached("animal:cow_leg", func() -> Mesh:
		return _merge([
			_pc(_rod(Vector3(0, 0.0, 0), Vector3(0, -0.56, 0), 0.12, 12), Vector3.ZERO, COW_WHITE),
			_pc(KitMesh.cylinder(0.118, 0.132, 0.13, 12), Vector3(0, -0.635, 0), HOOF),
		]))


## The tail in two pieces: from the rump down, then the end with its dark tuft.
static func _cow_tail(part: int) -> Mesh:
	return KitMesh.cached("animal:cow_tail:%d" % part, func() -> Mesh:
		if part == 0:
			return _merge([_pc(KitMesh.tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.06, 0.07),
				Vector3(0, -0.2, 0.11), Vector3(0, -0.34, 0.12)]), 0.032, 6), Vector3.ZERO, COW_WHITE, true)])
		return _merge([
			_pc(KitMesh.tube(PackedVector3Array([Vector3.ZERO, Vector3(0, -0.12, 0.01), Vector3(0, -0.2, 0.0)]), 0.028, 6), Vector3.ZERO, COW_WHITE),
			_pc(_lo({"ax": 0.065, "ay": 0.115, "az": 0.065}), Vector3(0, -0.28, 0), HOOF),
		]))


## A big brass cow bell hanging from its pivot: loop, crown, flared body, rim and clapper.
static func _cow_bell() -> Mesh:
	return KitMesh.cached("animal:cow_bell", func() -> Mesh:
		var loop := PackedVector3Array()
		for i in 11:
			var a := TAU * i / 10.0
			loop.append(Vector3(0, -0.035 + cos(a) * 0.03, sin(a) * 0.03))
		return _merge([
			_pc(KitMesh.tube(loop, 0.011, 5), Vector3.ZERO, HOOF),
			_pc(_lo({"ax": 0.08, "ay": 0.08, "az": 0.08, "flat_bottom": 0.96}), Vector3(0, -0.075, 0), BRASS),
			_pc(KitMesh.cylinder(0.08, 0.135, 0.2, 16), Vector3(0, -0.175, 0), BRASS),
			_pc(KitMesh.cylinder(0.148, 0.152, 0.035, 16), Vector3(0, -0.275, 0), BRASS.darkened(0.12)),
			_pc(_ball(0.045, 6, 8), Vector3(0, -0.29, 0), HOOF),
		]))


## Fluffy cream wool: a core with overlapping puffs all round (none underneath), and a tail puff.
static func _sheep_body() -> Mesh:
	return KitMesh.cached("animal:sheep_body", func() -> Mesh:
		var core := {"ax": 0.2, "ay": 0.2, "az": 0.46}
		var pcs := [_pc(KitMesh.blob({"ax": 0.21, "ay": 0.21, "az": 0.47}, 8, 12), Vector3.ZERO, WOOL[0])]
		var rng := RandomNumberGenerator.new()
		rng.seed = 1291
		var n := 42
		for i in n:
			# Spread evenly over the core (a Fibonacci sphere).
			var y := 1.0 - 2.0 * (i + 0.5) / n
			var rr := sqrt(1.0 - y * y)
			var a := i * 2.39996
			var d := Vector3(cos(a) * rr, y, sin(a) * rr)
			if d.y < -0.6:
				continue
			var r := rng.randf_range(0.12, 0.155)
			pcs.append(_pc(_ball(r, 7, 10), KitMesh.blob_point(core, d), WOOL[i % WOOL.size()]))
		pcs.append(_pc(_ball(0.1, 7, 10), Vector3(0, 0.08, 0.6), WOOL[2]))
		return _merge(pcs))


## Black face and snout, a smile, black ears, curled horns and a woolly fringe on top.
static func _sheep_head() -> Mesh:
	return KitMesh.cached("animal:sheep_head", func() -> Mesh:
		var h := SHEEP_FACE_AT
		var pcs := [
			_pc(KitMesh.blob(SHEEP_FACE, 12, 18), h, FACE),
			_pc(_lo({"ax": 0.125, "ay": 0.1, "az": 0.09}), h + Vector3(0, -0.1, -0.13), SNOUT),
			_pc(KitMesh.tube(PackedVector3Array([Vector3(-0.05, -0.13, -0.215), Vector3(0, -0.147, -0.222),
				Vector3(0.05, -0.13, -0.215)]), 0.009, 5), h, Color("#8a7f86")),
		]
		var fringe := [Vector3(0, 0.19, 0.01), Vector3(-0.09, 0.16, 0.04), Vector3(0.09, 0.16, 0.04),
				Vector3(0, 0.14, 0.11), Vector3(-0.055, 0.2, -0.06), Vector3(0.055, 0.2, -0.06)]
		for i in fringe.size():
			pcs.append(_pc(_ball(0.09, 7, 10), h + (fringe[i] as Vector3), WOOL[i % WOOL.size()]))
		for side: float in [-1.0, 1.0]:
			pcs.append(_pc(_lo({"ax": 0.11, "ay": 0.045, "az": 0.055}), h + Vector3(0.24 * side, -0.01, 0.04), FACE,
				false, Vector3(0, 0, -0.3 * side)))
			# A horn curling back, down and forward round the ear.
			var horn := PackedVector3Array()
			for i in 10:
				var t := i / 9.0
				var a := t * PI * 1.7
				var rr := 0.1 * (1.0 - 0.4 * t)
				horn.append(h + Vector3(side * (0.13 + 0.1 * t), 0.08 + cos(a) * rr, 0.05 + sin(a) * rr))
			pcs.append(_pc(P._taper_tube(horn, 0.048), Vector3.ZERO, SHEEP_HORN))
		return _merge(pcs))


## Woolly top, white shin with a black knee patch in front, black sock and hoof.
static func _sheep_leg() -> Mesh:
	return KitMesh.cached("animal:sheep_leg", func() -> Mesh:
		return _merge([
			_pc(_ball(0.1, 7, 10), Vector3(0, 0.02, 0), WOOL[1]),
			_pc(_rod(Vector3(0, -0.02, 0), Vector3(0, -0.2, 0), 0.05), Vector3.ZERO, SHIN),
			_pc(_ball(0.045, 6, 8), Vector3(0, -0.15, -0.028), FACE, false, Vector3.ZERO, Vector3(1, 1.2, 0.6)),
			_pc(_rod(Vector3(0, -0.21, 0), Vector3(0, -0.3, 0), 0.052), Vector3.ZERO, FACE),
			_pc(KitMesh.cylinder(0.056, 0.064, 0.07, 10), Vector3(0, -0.325, 0), FACE),
		]))

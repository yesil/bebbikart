class_name ToyRacer
extends Node3D
## A built toy racer (see RacerBuilder.build). Purely presentational: the sim/presentation
## layer drives it each frame with set_state() (or the fields directly) and fires one-shots
## (bump, land, fail, celebrate, wave, gesture). Moods follow the state automatically unless
## locked with set_mood(). The character's gestures, look, lean, breathing and swinging hair
## are racer_gestures.gd (`gestures`).
##
## Hierarchy: ToyRacer > Rig (lean/bounce/squash) > Model (grounded) > Ride, Character.
## Animated nodes are found by metadata: wheel_spin, leg_swing, wing_flap, spin, flicker,
## tail_wag, jiggle (see KitRideParts); ride_motion.gd (`ride`) moves them and gives every ride
## base its reactions (rearing, wing folds, squash and stretch, rocking, flares, wobbles).

signal mood_changed(mood: String)

## By path, not class name: racer.gd must load even before Godot's class cache knows the script.
const Gestures = preload("res://racer_kit/racer_gestures.gd")
const RideMotion = preload("res://racer_kit/ride_motion.gd")

var spec: Dictionary = {}
var bounciness := 1.0
## RacerSpec motion.style ("" = none) and energy: the racer's idle character.
var motion_style := ""
var motion_energy := 1.0

# Driven state
var speed := 0.0
var lean := 0.0
var airborne := false
var boost := false
var turn := 0.0           # yaw rate, rad/s (+ = turning left)
var ahead_turn := 0.0     # heading change over the road ahead, rad (+ = left): the head looks into it
var vy := 0.0             # vertical speed, m/s
var big_air := false      # airborne off a ramp (vs. a hop)
var in_water := false
var slipping := false
var rain := 0.0           # 0..1
var wind := Vector3.ZERO  # world-space wind (sim weather wind_vec(), strength 0..~1)

var rig: Node3D
var model: Node3D
var character: Node3D
var head_pivot: Node3D
var arm_l: Node3D
var arm_r: Node3D
var face: RacerFace
var name_tag: Label3D
var gestures := Gestures.new()
var ride := RideMotion.new()

var _anim := {}  # meta name -> Array[Node3D]
var _t := 0.0
var _lean_s := 0.0
var _mood := "happy"
var _mood_locked := false
var _squash := 0.0      # >0 while squashing (bump/land)
var _squash_k := 0.0
var _fail_t := 0.0
var _celebrate_t := 0.0
var _celebrate_hops := 0
var _sad_t := 0.0
var _foot := AABB()       # parts touching the ground, in Rig space (keeps a tilted rig on the ground)
# Idle personality (motion.style) offsets, written every frame by _motion().
var _mo_x := 0.0
var _mo_y := 0.0
var _mo_roll := 0.0
var _mo_char_pitch := 0.0
var _mo_head_roll := 0.0
var _mo_head_yaw := 0.0
var _mo_head_pitch := 0.0

const FAIL_TIME := 1.1
const HOP_TIME := 0.42


## Called by RacerBuilder once the node tree exists.
func setup(refs: Dictionary) -> void:
	rig = refs.rig
	model = refs.model
	character = refs.character
	head_pivot = refs.head_pivot
	arm_l = refs.arm_l
	arm_r = refs.arm_r
	face = refs.face
	name_tag = refs.get("name_tag")
	_anim.clear()
	_collect(model)
	_t = randf() * 10.0
	_foot = _footprint()
	var ok_g := gestures.setup(self)
	var ok_r := ride.setup(self)
	if not ok_g or not ok_r:
		# A builder bug (a node it always makes is missing): say so on the racer too.
		var l := Label3D.new()
		l.name = "GestureError"
		l.text = (gestures.error + "\n" + ride.error).strip_edges()
		l.modulate = Color(1.0, 0.25, 0.2)
		l.font_size = 32
		l.pixel_size = 0.006
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.position = Vector3(0, 2.4, 0)
		rig.add_child(l)


## Bounds (Rig space) of the meshes that reach the ground: wheels, feet, hull bottoms.
func _footprint() -> AABB:
	var all := RacerBuilder._aabb(rig, Transform3D.IDENTITY)
	var out := AABB()
	var first := true
	var stack: Array = [[rig, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var it: Array = stack.pop_back()
		for c in (it[0] as Node).get_children():
			if not c is Node3D or c is Label3D:
				continue
			var xf: Transform3D = it[1] * c.transform
			if c is MeshInstance3D and c.mesh:
				var b: AABB = xf * c.mesh.get_aabb()
				if b.position.y < all.position.y + 0.04:
					out = b if first else out.merge(b)
					first = false
			stack.append([c, xf])
	return out


const ANIM_KEYS := ["wheel_spin", "leg_swing", "wing_flap", "spin", "flicker", "tail_wag", "jiggle"]


func _collect(n: Node) -> void:
	if n == model:
		for key in ANIM_KEYS:
			_anim[key] = []  # every key present, so _process looks them up without allocating
	for key in ANIM_KEYS:
		if n.has_meta(key):
			_anim[key].append(n)
			n.set_meta("rest", n.transform)
	for c in n.get_children():
		_collect(c)


# --- API ---

## state keys (all optional): speed (m/s), lean (-1 left … 1 right), airborne, boost.
## Also: turn, ahead_turn, vy, big_air, in_water, slipping, rain (0..1), wind (Vector3).
func set_state(state: Dictionary) -> void:
	speed = float(state.get("speed", speed))
	lean = clampf(float(state.get("lean", lean)), -1.0, 1.0)
	airborne = bool(state.get("airborne", airborne))
	boost = bool(state.get("boost", boost))
	turn = float(state.get("turn", turn))
	ahead_turn = float(state.get("ahead_turn", ahead_turn))
	vy = float(state.get("vy", vy))
	big_air = bool(state.get("big_air", big_air))
	in_water = bool(state.get("in_water", in_water))
	slipping = bool(state.get("slipping", slipping))
	rain = float(state.get("rain", rain))
	wind = state.get("wind", wind)


## Hit by another racer: squash, a short brace and a dizzy head.
func bump() -> void:
	_squash = 0.35
	_squash_k = 1.0
	_sad_t = 0.8
	gestures.play(Gestures.G.BRACE, 0, 0.2)
	gestures.play(Gestures.G.DIZZY, 0, 1.4 if motion_style == "wobbly" else 0.0, 0.12)
	gestures.kick(Vector3(randf_range(-2.0, 2.0), 1.5, randf_range(-1.0, 1.0)))


func land() -> void:
	_squash = 0.25
	_squash_k = 0.7
	gestures.kick(Vector3(0.0, -3.0, 0.0))
	ride.land()


## Spin-out (fall off track, hit hard): dizzy, then slumps.
func fail() -> void:
	_fail_t = FAIL_TIME
	_sad_t = 0.0
	ride.fail()
	gestures.play(Gestures.G.DIZZY, 0, 0.6)
	gestures.play(Gestures.G.SLUMP, 0, 1.5, 0.4)


func celebrate(hops := 3) -> void:
	_celebrate_hops = maxi(1, hops)
	_celebrate_t = HOP_TIME * _celebrate_hops
	gestures.play(Gestures.G.CHEER, 0, _celebrate_t + 0.2)
	gestures.pant(3.5)


func wave() -> void:
	gestures.play(Gestures.G.WAVE)


## Crossed the line: the personality's finish gesture, then a wave at the camera; the ride rears
## up, flaps or bounces.
func finish() -> void:
	ride.finish()
	match gestures.win_pose:
		Gestures.G.CHEER:
			celebrate(2)
		_:
			gestures.play(gestures.win_pose, 0, 1.0)
			gestures.pant(3.5)
	gestures.play(Gestures.G.WAVE, 1, 1.2, 0.9)
	gestures.look_at_camera(2.2)


## A gesture by name (RacerGestures.NAMES): wave, cheer, fist_pump, glance_back, slump, dizzy,
## brace, wheee, tuck, flail, surprised, head_shake, rain, hat_hold. side: -1 left, 1 right arm.
func gesture(gesture_name: String, side := 0) -> void:
	gestures.play_named(gesture_name, side)


## How strongly the racer is mid-reaction (0..1): its driver's gestures (RacerGestures.REACT),
## 1 while it spins out or hops for joy. The big-screen camera holds on it (CameraDirector).
func reaction_weight() -> float:
	if _fail_t > 0.0 or _celebrate_t > 0.0:
		return 1.0
	return gestures.reaction_weight()


## What reaction_weight() comes from: "spin_out", "hops" or a gesture name; "" when none.
func reaction_name() -> String:
	if _fail_t > 0.0:
		return "spin_out"
	if _celebrate_t > 0.0:
		return "hops"
	return gestures.reaction_name()


## The head follows a node (e.g. a rival's head) or a world point for a while.
func look_at_node(n: Node3D, secs := 1.2) -> void:
	gestures.look_at(Vector3.ZERO, n, secs)


func look_at_point(p: Vector3, secs := 1.2) -> void:
	gestures.look_at(p, null, secs)


func reset_anim() -> void:
	_squash = 0.0
	_fail_t = 0.0
	_celebrate_t = 0.0
	_sad_t = 0.0
	speed = 0.0
	lean = 0.0
	airborne = false
	boost = false
	turn = 0.0
	ahead_turn = 0.0
	vy = 0.0
	big_air = false
	in_water = false
	slipping = false
	rain = 0.0
	wind = Vector3.ZERO
	_lean_s = 0.0
	_mo_x = 0.0
	_mo_y = 0.0
	_mo_roll = 0.0
	_mo_char_pitch = 0.0
	_mo_head_roll = 0.0
	_mo_head_yaw = 0.0
	_mo_head_pitch = 0.0
	if rig:
		rig.transform = Transform3D.IDENTITY
	gestures.reset()
	ride.reset()
	for key in _anim:
		for n in _anim[key]:
			n.transform = n.get_meta("rest")


## Locks a mood (happy, excited, determined, dizzy, sad, cheering) until set_auto_mood().
func set_mood(m: String, lock := true) -> void:
	_mood_locked = lock
	_apply_mood(m)


func set_auto_mood() -> void:
	_mood_locked = false


func get_mood() -> String:
	return _mood


func set_name_tag(text: String) -> void:
	if name_tag:
		name_tag.text = text


func show_name_tag(on: bool) -> void:
	if name_tag:
		name_tag.visible = on


## Neutral still pose (avatar renders, thumbnails).
func snap_pose(m := "happy") -> void:
	reset_anim()
	set_mood(m, true)
	if face:
		face._blink = 0.0
		face._blink_t = 99.0
		face.tick(0.0)


# --- animation ---

func _process(delta: float) -> void:
	if rig == null:
		return
	_t += delta
	var dt := minf(delta, 0.1)
	if not _mood_locked:
		_apply_mood(_auto_mood())
	if face:
		face.tick(dt)
	var moving := clampf(speed / 10.0, 0.0, 1.0)
	ride.update(dt)

	# Rig: lean, bounce, squash, spin-out, hops, and the ride's own pitch / roll / lift / squash.
	_lean_s = lerpf(_lean_s, lean, minf(1.0, dt * 8.0))
	var xf := Transform3D.IDENTITY
	var bounce := absf(sin(_t * (7.0 + speed * 0.5))) * 0.025 * bounciness * moving
	if airborne:
		bounce = 0.0
	var idle := (0.5 + 0.5 * sin(_t * 2.2)) * 0.012 * bounciness  # bobs up from the ground, never into it
	var hop := 0.0
	var pitch := 0.06 if boost else (0.1 if airborne else 0.0)
	if _celebrate_t > 0.0:
		_celebrate_t -= dt
		var ph := fmod(_celebrate_t, HOP_TIME) / HOP_TIME
		hop = maxf(0.0, sin(ph * PI)) * 0.28 * bounciness  # the last frame's phase is just below 0
	var yaw := 0.0
	if _fail_t > 0.0:
		_fail_t -= dt
		var k := 1.0 - _fail_t / FAIL_TIME
		yaw = ease(k, 0.4) * TAU * 2.0
		hop = sin(k * PI) * 0.2
	var sq := Vector3.ONE
	if _squash > 0.0:
		_squash -= dt
		var s := sin(clampf(_squash / 0.35, 0.0, 1.0) * PI) * 0.22 * _squash_k * bounciness * ride.rig_squash
		sq = Vector3(1.0 + s, 1.0 - s, 1.0 + s)
	_motion(moving)
	_mo_char_pitch -= ride.pitch * 0.45  # the driver leans into a rearing / diving ride
	xf.basis = Basis.from_euler(Vector3(pitch + ride.pitch, yaw + ride.yaw, -_lean_s * 0.22 + _mo_roll + ride.roll)) \
		.scaled(sq * ride.scale)
	xf.origin = Vector3(_mo_x, maxf(0.0, bounce + idle + hop + _mo_y + ride.lift) + _ground_lift(xf.basis), 0)
	rig.transform = xf
	gestures.carry = ride.carry
	gestures.update(dt)
	if _sad_t > 0.0:
		_sad_t -= dt


## How far a tilted (leaning, pitched) rig must rise so its ground parts stay above the ground.
func _ground_lift(b: Basis) -> float:
	var c := b * _foot.get_center()
	var h := _foot.size * 0.5
	var low := c.y - absf(b.x.y) * h.x - absf(b.y.y) * h.y - absf(b.z.y) * h.z
	return maxf(0.0, _foot.position.y - low)


## Idle personality from motion.style, scaled by energy and faded a bit at speed.
func _motion(moving: float) -> void:
	_mo_x = 0.0
	_mo_y = 0.0
	_mo_roll = 0.0
	_mo_char_pitch = 0.0
	_mo_head_roll = 0.0
	_mo_head_yaw = 0.0
	_mo_head_pitch = 0.0
	var k := motion_energy * (1.0 - 0.5 * moving)
	match motion_style:
		"bouncy":
			_mo_y = absf(sin(_t * 4.5)) * 0.045 * k
			_mo_head_roll = sin(_t * 4.5) * 0.06 * k
		"smooth":
			_mo_y = (0.5 + 0.5 * sin(_t * 1.2)) * 0.015 * k
			_mo_head_yaw = sin(_t * 0.6) * 0.1 * k
		"wobbly":
			_mo_roll = sin(_t * 5.0) * 0.07 * k
			_mo_head_roll = sin(_t * 5.0 + 1.2) * 0.14 * k
		"jittery":
			_mo_x = (sin(_t * 37.0) * 0.5 + sin(_t * 23.0) * 0.5) * 0.008 * k
			_mo_head_yaw = sin(_t * 11.0) * sin(_t * 2.3) * 0.25 * k
		"floaty":
			_mo_y = (sin(_t * 1.6) * 0.5 + 0.5) * 0.08 * k
			_mo_roll = sin(_t * 0.8) * 0.04 * k
		"proud":
			_mo_head_pitch = -0.16 * k
			_mo_char_pitch = -0.06 * k
			_mo_head_yaw = sin(_t * 0.5) * 0.12 * k
		"sneaky":
			_mo_char_pitch = 0.16 * k
			_mo_head_yaw = sin(_t * 0.7) * sin(_t * 0.31) * 0.4 * k


func _auto_mood() -> String:
	if _fail_t > 0.0:
		return "dizzy"
	var g := gestures.mood_hint()
	if g != "":
		return g
	if _celebrate_t > 0.0:
		return "cheering"
	if _sad_t > 0.0:
		return "sad"
	if boost or airborne:
		return "excited"
	if speed > 12.0:
		return "determined"
	return "happy"


func _apply_mood(m: String) -> void:
	if m == _mood or m not in KitCatalog.MOODS:
		return
	_mood = m
	if face:
		face.set_mood(m)
	mood_changed.emit(m)

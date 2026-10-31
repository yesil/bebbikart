class_name ToyRacer
extends Node3D
## A built toy racer (see RacerBuilder.build). Purely presentational: the sim/presentation
## layer drives it each frame with set_state() and fires one-shots (bump, land, fail,
## celebrate, wave). Moods follow the state automatically unless locked with set_mood().
##
## Hierarchy: ToyRacer > Rig (lean/bounce/squash) > Model (grounded) > Ride, Character.
## Animated nodes are found by metadata: wheel_spin, leg_swing, wing_flap, spin, flicker,
## tail_wag (see KitRideParts).

signal mood_changed(mood: String)

var spec: Dictionary = {}
var bounciness := 1.0

# Driven state
var speed := 0.0
var lean := 0.0
var airborne := false
var boost := false

var rig: Node3D
var model: Node3D
var character: Node3D
var head_pivot: Node3D
var arm_l: Node3D
var arm_r: Node3D
var face: RacerFace
var name_tag: Label3D

var _anim := {}  # meta name -> Array[Node3D]
var _arm_rest := {}
var _t := 0.0
var _lean_s := 0.0
var _mood := "happy"
var _mood_locked := false
var _squash := 0.0      # >0 while squashing (bump/land)
var _squash_k := 0.0
var _fail_t := 0.0
var _celebrate_t := 0.0
var _celebrate_hops := 0
var _wave_t := 0.0
var _sad_t := 0.0

const FAIL_TIME := 1.1
const HOP_TIME := 0.42
const WAVE_TIME := 1.6


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
	for a in [arm_l, arm_r]:
		if a:
			_arm_rest[a] = a.basis
	_anim.clear()
	_collect(model)
	_t = randf() * 10.0


func _collect(n: Node) -> void:
	for key in ["wheel_spin", "leg_swing", "wing_flap", "spin", "flicker", "tail_wag", "jiggle"]:
		if n.has_meta(key):
			if not _anim.has(key):
				_anim[key] = []
			_anim[key].append(n)
			n.set_meta("rest", n.transform)
	for c in n.get_children():
		_collect(c)


# --- API ---

## state keys (all optional): speed (m/s), lean (-1 left … 1 right), airborne, boost.
func set_state(state: Dictionary) -> void:
	speed = float(state.get("speed", speed))
	lean = clampf(float(state.get("lean", lean)), -1.0, 1.0)
	airborne = bool(state.get("airborne", airborne))
	boost = bool(state.get("boost", boost))


func bump() -> void:
	_squash = 0.35
	_squash_k = 1.0
	_sad_t = 0.8


func land() -> void:
	_squash = 0.25
	_squash_k = 0.7


## Spin-out (fall off track, hit hard).
func fail() -> void:
	_fail_t = FAIL_TIME
	_sad_t = 0.0


func celebrate(hops := 3) -> void:
	_celebrate_hops = maxi(1, hops)
	_celebrate_t = HOP_TIME * _celebrate_hops


func wave() -> void:
	_wave_t = WAVE_TIME


func reset_anim() -> void:
	_squash = 0.0
	_fail_t = 0.0
	_celebrate_t = 0.0
	_wave_t = 0.0
	_sad_t = 0.0
	speed = 0.0
	lean = 0.0
	airborne = false
	boost = false
	_lean_s = 0.0
	if rig:
		rig.transform = Transform3D.IDENTITY
	for a in _arm_rest:
		a.basis = _arm_rest[a]
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

	for n in _anim.get("wheel_spin", []):
		if not airborne:
			n.rotation.x -= speed / maxf(float(n.get_meta("wheel_spin")), 0.05) * dt
	for n in _anim.get("leg_swing", []):
		var amp := 0.12 + 0.6 * moving
		var target := sin(_t * (5.0 + speed * 0.6) + float(n.get_meta("leg_swing"))) * amp
		if airborne:
			target = 0.7
		n.rotation.x = lerpf(n.rotation.x, target, minf(1.0, dt * 20.0))
	for n in _anim.get("wing_flap", []):
		var fast := airborne or boost
		var flap := sin(_t * (14.0 if fast else 4.0 + speed * 0.4)) * (0.7 if fast else 0.15 + 0.25 * moving)
		n.rotation.z = float(n.get_meta("wing_flap")) * flap
	for n in _anim.get("spin", []):
		n.rotation.y += float(n.get_meta("spin")) * dt
	for n in _anim.get("flicker", []):
		var base := 1.6 if boost else 0.6 + moving * 0.6
		var f := base * (1.0 + 0.15 * sin(_t * 31.0) + 0.1 * sin(_t * 17.0))
		n.scale = Vector3(1.0, 1.0, f) * (0.9 + 0.1 * f)
	for n in _anim.get("tail_wag", []):
		n.rotation.y = sin(_t * (5.0 + speed * 0.5)) * (0.25 + 0.2 * moving)

	for n in _anim.get("jiggle", []):
		var j := sin(_t * (6.0 + speed * 0.4)) * (0.02 + 0.04 * moving) * bounciness
		n.scale = Vector3(1.0 + j, 1.0 - j, 1.0 + j)

	# Rig: lean, bounce, squash, spin-out, hops.
	_lean_s = lerpf(_lean_s, lean, minf(1.0, dt * 8.0))
	var xf := Transform3D.IDENTITY
	var bounce := absf(sin(_t * (7.0 + speed * 0.5))) * 0.025 * bounciness * moving
	if airborne:
		bounce = 0.0
	var idle := sin(_t * 2.2) * 0.008 * bounciness
	var hop := 0.0
	var pitch := 0.06 if boost else (0.1 if airborne else 0.0)
	if _celebrate_t > 0.0:
		_celebrate_t -= dt
		var ph := fmod(_celebrate_t, HOP_TIME) / HOP_TIME
		hop = sin(ph * PI) * 0.28 * bounciness
	var yaw := 0.0
	if _fail_t > 0.0:
		_fail_t -= dt
		var k := 1.0 - _fail_t / FAIL_TIME
		yaw = ease(k, 0.4) * TAU * 2.0
		hop = sin(k * PI) * 0.2
	var sq := Vector3.ONE
	if _squash > 0.0:
		_squash -= dt
		var s := sin(clampf(_squash / 0.35, 0.0, 1.0) * PI) * 0.22 * _squash_k * bounciness
		sq = Vector3(1.0 + s, 1.0 - s, 1.0 + s)
	xf.basis = Basis.from_euler(Vector3(pitch, yaw, -_lean_s * 0.22)).scaled(sq)
	xf.origin = Vector3(0, bounce + idle + hop, 0)
	rig.transform = xf
	if character:
		character.rotation.z = -_lean_s * 0.18
		character.rotation.x = -0.12 * moving if not boost else -0.22
	if head_pivot:
		head_pivot.rotation.z = _lean_s * 0.12 + sin(_t * 1.7) * 0.03
		head_pivot.rotation.y = sin(_t * 0.9) * 0.08 * (1.0 - moving)
	_animate_arms(dt)
	if _sad_t > 0.0:
		_sad_t -= dt


func _animate_arms(dt: float) -> void:
	if arm_l == null or arm_r == null:
		return
	if _celebrate_t > 0.0:
		for a in [arm_l, arm_r]:
			var side := -1.0 if a == arm_l else 1.0
			var up := Basis.from_euler(Vector3(0, 0, side * (2.6 + sin(_t * 12.0) * 0.25)))
			a.basis = a.basis.slerp(up, minf(1.0, dt * 14.0))
		return
	if _wave_t > 0.0:
		_wave_t -= dt
		var up2 := Basis.from_euler(Vector3(0, 0, 2.5 + sin(_t * 14.0) * 0.45))
		arm_r.basis = arm_r.basis.slerp(up2, minf(1.0, dt * 14.0))
		arm_l.basis = arm_l.basis.slerp(_arm_rest[arm_l], minf(1.0, dt * 10.0))
		return
	for a in [arm_l, arm_r]:
		a.basis = a.basis.slerp(_arm_rest[a], minf(1.0, dt * 10.0)).orthonormalized()


func _auto_mood() -> String:
	if _fail_t > 0.0:
		return "dizzy"
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

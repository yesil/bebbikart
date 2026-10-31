class_name RacerGestures
extends RefCounted
## The "alive" layer of a built ToyRacer, for any kit combination: breathing, head look-at with
## quick turns and holds, cornering lean with lag and overshoot, hands that stay on the handlebar
## (each arm is split into two bones at setup), spring-damper hair / ears / hat / cape, and
## gestures with priority and blend in/out. ToyRacer owns one, calls update() every frame after
## its rig and reset() for the built pose (snap_pose, avatar renders).
##
##   racer.gesture("wave")                  # one-shot, see NAMES
##   racer.look_at_node(rival_head, 1.2)    # head follows a node (or a point) for a while
##   rain / wind / airborne / slipping / water come from ToyRacer's driven state.
##
## Arms, body and look are solved in Character space (kit frame: -Z forward, +X right); hair,
## head extras and the hat swing in head space, a cape in Character space. update() does not
## allocate.

## Gestures in arm priority order: a later one overrides an earlier one's arm pose.
enum G { RAIN, HAT, TUCK, WHEEE, BRACE, WAVE, FIST_PUMP, CHEER, SURPRISED, FLAIL, DIZZY, SLUMP, GLANCE_BACK, HEAD_SHAKE }
const COUNT := 14
const NAMES := {
	"rain": G.RAIN, "hat_hold": G.HAT, "tuck": G.TUCK, "wheee": G.WHEEE, "brace": G.BRACE,
	"wave": G.WAVE, "fist_pump": G.FIST_PUMP, "cheer": G.CHEER, "surprised": G.SURPRISED,
	"flail": G.FLAIL, "dizzy": G.DIZZY, "slump": G.SLUMP, "glance_back": G.GLANCE_BACK,
	"head_shake": G.HEAD_SHAKE,
}
# Per gesture (index = G): arms used (0 none, 3 both, 4 one: the side passed to play()), the
# default side (-1 left, 1 right), blend in / out (s), one-shot length (s), longest reach as a
# multiple of the arm (rubber arms for the head), and the face mood while it plays.
const ARMS := [4, 4, 3, 3, 3, 4, 4, 3, 3, 3, 3, 3, 0, 0]
const SIDE := [-1, -1, 0, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0]
const BLEND_IN := [0.45, 0.4, 0.18, 0.16, 0.06, 0.2, 0.1, 0.15, 0.07, 0.1, 0.1, 0.3, 0.15, 0.06]
const BLEND_OUT := [0.55, 0.5, 0.3, 0.35, 0.25, 0.4, 0.3, 0.4, 0.45, 0.35, 0.5, 0.6, 0.35, 0.2]
const LENGTH := [3.0, 3.0, 1.2, 1.2, 0.35, 1.6, 0.9, 1.4, 0.9, 1.0, 1.1, 1.6, 0.9, 0.75]
const REACH := [1.35, 1.35, 1.0, 1.05, 1.0, 1.0, 1.05, 1.05, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
const MOOD := ["determined", "determined", "determined", "excited", "determined", "happy", "excited",
	"cheering", "excited", "dizzy", "dizzy", "sad", "", ""]

## Head limits (rad), also checked by tools/gesture_check.gd.
const YAW_MAX := 1.35
const PITCH_MIN := -0.6
const PITCH_MAX := 0.5
const ROLL_MAX := 0.45

## Personality from motion.style: look speed (rad/s spring), hold between glances (s), lean
## damping (low = more overshoot), pose on ramp jumps, at the finish and when passing someone.
## "" = spec without motion (the pose on jumps then follows bounciness).
const STYLE := {
	"": {"look": 14.0, "hold": [0.7, 2.0], "zeta": 0.45, "air": -1, "win": G.CHEER, "pass": G.FIST_PUMP},
	"bouncy": {"look": 18.0, "hold": [0.5, 1.4], "zeta": 0.32, "air": G.WHEEE, "win": G.CHEER, "pass": G.FIST_PUMP},
	"smooth": {"look": 8.0, "hold": [1.4, 3.0], "zeta": 0.75, "air": G.TUCK, "win": G.WAVE, "pass": G.WAVE},
	"wobbly": {"look": 12.0, "hold": [0.6, 1.6], "zeta": 0.22, "air": G.WHEEE, "win": G.CHEER, "pass": G.WAVE},
	"jittery": {"look": 26.0, "hold": [0.25, 0.8], "zeta": 0.4, "air": G.WHEEE, "win": G.CHEER, "pass": G.FIST_PUMP},
	"floaty": {"look": 9.0, "hold": [1.0, 2.4], "zeta": 0.4, "air": G.WHEEE, "win": G.WAVE, "pass": G.WAVE},
	"proud": {"look": 10.0, "hold": [1.2, 2.6], "zeta": 0.6, "air": G.TUCK, "win": G.WAVE, "pass": G.FIST_PUMP},
	"sneaky": {"look": 20.0, "hold": [0.4, 1.0], "zeta": 0.5, "air": G.TUCK, "win": G.FIST_PUMP, "pass": G.GLANCE_BACK},
}
## How far a hat wobbles on the head (spring gain, max rad); helmets sit tight.
const HAT_WOBBLE := {"wizard": [0.55, 0.14], "party": [0.4, 0.1], "tophat": [0.3, 0.08], "crown": [0.25, 0.06],
	"bow": [0.45, 0.12], "cap": [0.08, 0.025], "beanie": [0.1, 0.03], "helmet": [0.0, 0.0]}

# Elbow pull directions per pose (x mirrored per side), Character space.
const POLE_GRIP := Vector3(1.0, -0.6, 0.5)
const POLE_UP := Vector3(1.0, -0.5, 0.35)
const POLE_LAP := Vector3(0.8, -0.1, 0.7)
const POLE_HEAD := Vector3(1.0, -0.1, 0.1)

const GRAVITY := Vector3(0.0, -9.8, 0.0)
const WIND_ACC := 9.0      # m/s² of push per unit of sim wind strength
const AIR_K := 0.4         # head wind from driving, m/s² per m/s
const HAIR_GAIN := 0.05    # swing (rad) per m/s² of push
const SOFT_W := 5.5        # long hair: slow, swingy
const SOFT_Z := 0.22
const STIFF_W := 11.0      # short hair: quick
const STIFF_Z := 0.35
const SPRING_W := 9.0      # ears, antennae, hats: boingy
const SPRING_Z := 0.14

var ok := false
var error := ""            # why setup() failed ("" = fine)

var r: ToyRacer
var character: Node3D
var head_pivot: Node3D
var head: Node3D
var legs: Node3D           # null when the character has no legs
var grip := false          # hands hold a handle / reins (else they hang free: board, blob)

# Personality
var amp := 1.0
var look_omega := 14.0
var hold_min := 0.7
var hold_max := 2.0
var lean_zeta := 0.45
var air_pose: int = G.WHEEE
var win_pose: int = G.CHEER
var pass_pose: int = G.FIST_PUMP

# Gesture state, index = G
var _w := PackedFloat32Array()      # weight 0..1
var _left := PackedFloat32Array()   # seconds still to play
var _time := PackedFloat32Array()   # seconds since it started (oscillation phase); < 0 = idle
var _delay := PackedFloat32Array()  # seconds until it starts
var _side := PackedInt32Array()     # -1 left arm, 1 right arm
var _held := PackedByteArray()      # 1 = held on by a state (rain, wind, air, slip)
var _active := 0                    # gestures with weight or time running

# Rest pose
var _char_rest: Transform3D
var _head_rest: Transform3D
var _legs_rest: Transform3D
var _char_xf: Transform3D
var _char_inv: Transform3D
var _head_xf: Transform3D

# Arms, index 0 = left, 1 = right
var _arm: Array[Node3D] = []
var _elbow: Array[Node3D] = []
var _hand: Array[Node3D] = []
var _upper_mi: Array[Node3D] = []
var _lower_mi: Array[Node3D] = []
var _rest_q: Array[Quaternion] = []
var _shoulder := PackedVector3Array()
var _rest_dir := PackedVector3Array()
var _hand_rest := PackedVector3Array()    # Character space
var _grip_model := PackedVector3Array()   # Model space: where the hands hold on
var _len := PackedFloat32Array()
var _k := PackedFloat32Array()            # current stretch of each arm
var _p_up := PackedVector3Array()
var _p_wave := PackedVector3Array()
var _p_pump_hi := PackedVector3Array()
var _p_pump_lo := PackedVector3Array()
var _p_out := PackedVector3Array()
var _p_lap := PackedVector3Array()
var _p_rain := PackedVector3Array()
var _p_hat := PackedVector3Array()
var _p_brace := PackedVector3Array()
var _p_tuck := PackedVector3Array()
var _head_c_hp := Vector3.ZERO   # head centre, HeadPivot space
var _head_r := Vector3.ONE       # head radii + hair + hand
var _head_c_now := Vector3.ZERO  # head centre this frame, Character space
var _body_c := Vector3.ZERO
var _body_r := Vector3.ONE
var _hat_ok := false             # has a hat worth holding in the wind

# Swinging pieces (hair, head extras, hat, cape)
var _sw_node: Array[Node3D] = []
var _sw_d0 := PackedVector3Array()    # rest direction pivot -> tip
var _sw_gain := PackedFloat32Array()
var _sw_mix := PackedFloat32Array()   # 0 stiff … 1 soft; -1 springy (ears, hat); -2 cape
var _sw_max := PackedFloat32Array()
var _sw_in := PackedVector3Array()    # direction into the head (tips are kept out of it)
var _sw_lim := PackedFloat32Array()
var _sw_phase := PackedFloat32Array()
var _sw_chain := PackedByteArray()    # 1 = lower half of a chain (swings relative to the top)
var _has_cape := false

# Springs and motion history
var _d_soft := Vector3.ZERO
var _v_soft := Vector3.ZERO
var _d_stiff := Vector3.ZERO
var _v_stiff := Vector3.ZERO
var _d_spring := Vector3.ZERO
var _v_spring := Vector3.ZERO
var _d_cape := Vector3.ZERO
var _v_cape := Vector3.ZERO
var _pr_prev := Vector3.ZERO
var _vr_prev := Vector3.ZERO
var _a_rig := Vector3.ZERO
var _have_prev := false
var _speed_prev := 0.0
var _vy_prev := 0.0
var _a_long := 0.0
var _a_vert := 0.0
var _roll := 0.0
var _roll_v := 0.0
var _pitch := 0.0
var _pitch_v := 0.0
var _breath := 0.0
var _pant_t := 0.0

# Look
var _yaw := 0.0
var _yaw_v := 0.0
var _pit := 0.0
var _pit_v := 0.0
var _look_ty := 0.0
var _look_tp := 0.0
var _sacc := 0.0
var _look_hold := 0.0
var _look_t := 0.0
var _look_pos := Vector3.ZERO
var _look_node: Node3D = null
var _glance_side := 1.0

# Edges of the driven state
var _was_rain := false
var _was_water := false
var _was_boost := false
var _was_slip := false
var _was_hat := false
var _air_held := -1          # the jump pose being held while airborne, or -1

var _t := 0.0
var _rng := RandomNumberGenerator.new()


# --- setup ---

## Finds the nodes the builder always makes, splits each arm at the elbow and puts swing pivots
## under hanging hair and dangly extras. False (with `error` set and pushed) on a missing node.
func setup(racer: ToyRacer) -> bool:
	r = racer
	_rng.seed = hash(str(r.spec.get("title", ""))) ^ randi()
	var title := str(r.spec.get("title", "?"))
	character = r.character
	head_pivot = r.head_pivot
	head = head_pivot.get_node_or_null("Head") as Node3D if head_pivot else null
	var head_mesh := head.get_node_or_null("HeadMesh") as MeshInstance3D if head else null
	var body := character.get_node_or_null("Body") as Node3D if character else null
	if character == null or head_pivot == null or head == null or head_mesh == null or body == null \
			or r.arm_l == null or r.arm_r == null:
		return _fail("%s: the built racer lacks Character, Body, HeadPivot/Head/HeadMesh or ArmL/ArmR" % title)
	var st := r.motion_style
	if not STYLE.has(st):
		return _fail("%s: no gesture tuning for motion style \"%s\" (add it to RacerGestures.STYLE)" % [title, st])
	var sty: Dictionary = STYLE[st]
	look_omega = sty.look
	hold_min = sty.hold[0]
	hold_max = sty.hold[1]
	lean_zeta = sty.zeta
	air_pose = sty.air if sty.air >= 0 else (G.WHEEE if r.bounciness > 1.05 else G.TUCK)
	win_pose = sty.win
	pass_pose = sty.pass
	amp = clampf(r.bounciness, 0.6, 1.6)
	_w.resize(COUNT)
	_left.resize(COUNT)
	_time.resize(COUNT)
	_delay.resize(COUNT)
	_side.resize(COUNT)
	_held.resize(COUNT)
	legs = character.get_node_or_null("Legs") as Node3D
	_char_rest = character.transform
	_head_rest = head_pivot.transform
	_legs_rest = legs.transform if legs else Transform3D.IDENTITY

	# Head and body as ellipsoids (Character space) to keep hands out of them.
	var hb := head_mesh.mesh.get_aabb()
	var hxf := head.transform * head_mesh.transform
	_head_c_hp = hxf * hb.get_center()
	_head_r = (hxf.basis * (hb.size * 0.5)).abs() * 1.08 + Vector3.ONE * 0.065
	var bb := RacerBuilder._aabb(body, body.transform)
	_body_c = bb.get_center()
	_body_r = bb.size * 0.5 + Vector3.ONE * 0.05
	if not _setup_arms(title):
		return false
	_setup_poses(bb)
	_setup_swing(head_mesh, title)
	if not error.is_empty():
		return false
	ok = true
	reset()
	return true


func _fail(msg: String) -> bool:
	error = "RacerGestures: " + msg
	push_error(error)
	ok = false
	return false


func _setup_arms(title: String) -> bool:
	for i in 2:
		var arm: Node3D = r.arm_l if i == 0 else r.arm_r
		var hand := arm.get_node_or_null("Hand") as Node3D
		var cap: MeshInstance3D = null
		for c in arm.get_children():
			if c is MeshInstance3D:
				cap = c
				break
		if hand == null or cap == null or cap.mesh == null:
			return _fail("%s: %s has no Hand or arm mesh" % [title, arm.name])
		var L := -hand.position.y
		var s := arm.position
		var hr := arm.transform * hand.position
		_arm.append(arm)
		_hand.append(hand)
		_shoulder.append(s)
		_len.append(L)
		_k.append(1.0)
		_rest_q.append(arm.quaternion)
		_hand_rest.append(hr)
		_rest_dir.append((hr - s).normalized())
		_grip_model.append(_char_rest * hr)
		# Two bones: the arm capsule becomes the upper half, an Elbow node carries the lower half
		# and the hand. Straight at rest, so the silhouette is the builder's.
		var box := cap.mesh.get_aabb()
		var half := KitMesh.capsule(box.size.x * 0.5, L * 0.5 + (box.size.y - L))
		cap.mesh = half
		cap.position = Vector3(0, -L * 0.25, 0)
		var elbow := Node3D.new()
		elbow.name = "Elbow"
		elbow.position = Vector3(0, -L * 0.5, 0)
		arm.add_child(elbow)
		var low := _copy_mesh(cap)
		low.name = "Forearm"
		low.position = Vector3(0, -L * 0.25, 0)
		elbow.add_child(low)
		arm.remove_child(hand)
		elbow.add_child(hand)
		hand.position = Vector3(0, -L * 0.5, 0)
		_elbow.append(elbow)
		_upper_mi.append(cap)
		_lower_mi.append(low)
	# Hands far in front of the shoulders hold a handle (the builder puts free hands just below
	# and beside the shoulder).
	grip = (_hand_rest[0] - _shoulder[0]).z < -0.12 and (_hand_rest[1] - _shoulder[1]).z < -0.12
	return true


static func _copy_mesh(src: MeshInstance3D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = src.mesh
	m.material_override = src.material_override
	m.cast_shadow = src.cast_shadow
	for p in src.get_property_list():
		var n: String = p.name
		if n.begins_with("instance_shader_parameters/"):
			m.set(n, src.get(n))
	return m


## Hand targets per pose (Character space), each kept reachable and clear of the head.
func _setup_poses(body_box: AABB) -> void:
	var hc := _head_rest * _head_c_hp
	var hat := head.get_node_or_null("Hat") as Node3D
	var hat_box := AABB()
	if hat:
		hat_box = _head_rest * (head.transform * (hat.transform * RacerBuilder._aabb(hat, Transform3D.IDENTITY)))
	var front := body_box.get_center().z - body_box.size.z * 0.5 - 0.06
	var lap_y := maxf(0.05, body_box.get_center().y * 0.55)
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var S := _shoulder[i]
		var L := _len[i]
		_p_up.append(_reach(i, S + Vector3(s * 0.5, 1.0, -0.12).normalized() * L * 1.05, 1.05, true))
		_p_wave.append(_reach(i, S + Vector3(s * 0.75, 0.8, -0.3).normalized() * L * 0.9, 1.0, true))
		_p_pump_hi.append(_reach(i, S + Vector3(s * 0.3, 1.0, -0.4).normalized() * L, 1.0, true))
		_p_pump_lo.append(_reach(i, S + Vector3(s * 0.5, 0.55, -0.65).normalized() * L * 0.6, 1.0, true))
		_p_out.append(_reach(i, S + Vector3(s * 1.0, 0.5, -0.4).normalized() * L * 0.95, 1.0, true))
		# Rain: a hand shields the forehead (kid-drawing arms rarely reach over a big head).
		var brow := hc + Vector3(s * _head_r.x * 0.3, _head_r.y * 0.45, -_head_r.z)
		_p_rain.append(_reach(i, _push_out(brow, hc, _head_r), 1.35, false))
		if hat:
			# Wind: the hand holds the hat down by the front of its brim.
			var brim := Vector3(hat_box.get_center().x + s * hat_box.size.x * 0.25, hat_box.position.y + 0.02,
				hat_box.get_center().z - hat_box.size.z * 0.45)
			_p_hat.append(_reach(i, _push_out(brim, hc, _head_r), 1.35, false))
		else:
			_p_hat.append(_p_rain[i])
		if grip:
			_p_lap.append(_reach(i, Vector3(s * maxf(absf(S.x) * 0.7, 0.07), lap_y, front), 1.0, false))
		else:
			_p_lap.append(_reach(i, S + Vector3(s * 0.04, -L, 0.03), 1.0, false))
		_p_brace.append(_reach(i, S + Vector3(s * 0.2, -0.1, -0.85).normalized() * L * 0.9, 1.0, false))
		_p_tuck.append(_reach(i, S + Vector3(s * 0.05, -0.7, -0.6).normalized() * L * 0.75, 1.0, false))
	var hat_type := str(r.spec.get("character", {}).get("hat", {}).get("type", ""))
	_hat_ok = hat != null and hat_type != "helmet"


## A reachable hand target toward `want` (at most kmax arm lengths from the shoulder). With
## clear, a straight arm toward it is swung outward until it misses the head and body.
func _reach(i: int, want: Vector3, kmax: float, clear: bool) -> Vector3:
	var S := _shoulder[i]
	var to := want - S
	var d := to.length()
	if d < 1e-4:
		return S
	var dir := to / d
	var dist := minf(d, _len[i] * kmax)
	if clear:
		var hc := _head_rest * _head_c_hp
		var s := -1.0 if i == 0 else 1.0
		for _it in 16:
			var hit := false
			for t in [0.35, 0.55, 0.75, 1.0]:
				var p: Vector3 = S + dir * dist * t
				if _inside(p, hc, _head_r) or (t > 0.5 and _inside(p, _body_c, _body_r)):
					hit = true
					break
			if not hit:
				break
			dir = (dir + Vector3(s * 0.12, 0.02, 0.0)).normalized()
	return S + dir * dist


static func _inside(p: Vector3, c: Vector3, rad: Vector3) -> bool:
	return ((p - c) / rad).length_squared() < 1.0


static func _push_out(p: Vector3, c: Vector3, rad: Vector3) -> Vector3:
	var q := (p - c) / rad
	var l := q.length()
	if l >= 1.0 or l < 1e-4:
		return p
	return c + q / l * rad


## Swing pivots for hair pieces, head-socket extras, the hat and a cape.
func _setup_swing(head_mesh: MeshInstance3D, title: String) -> void:
	var ay := head_mesh.mesh.get_aabb().size.y * 0.5
	var hair := head.get_node_or_null("Hair") as Node3D
	if hair:
		var dangle: Array[Node3D] = []
		for c in hair.get_children():
			if c is Node3D:
				_classify_hair(c, ay, dangle)
		if not dangle.is_empty():
			_dangle_group(hair, dangle)
	for sock in ["Socket_head_top", "Socket_head_side", "Socket_head_side_r"]:
		var m := head.get_node_or_null(sock) as Node3D
		if m == null:
			_fail("%s: head socket %s is missing" % [title, sock])
			return
		if m.get_child_count() == 0:
			continue
		var floppy := false
		for e in m.get_children():
			var nm := String(e.name)
			if nm.contains("capsule") or nm.contains("cylinder"):
				floppy = true
		var out := m.position.normalized() if m.position.length() > 1e-4 else Vector3.UP
		_add_swing(m, out, 0.55 if floppy else 0.12, -1.0, 0.4 if floppy else 0.07, Vector3.ZERO, 1.0, 0)
	var hat := head.get_node_or_null("Hat") as Node3D
	if hat:
		var type := str(r.spec.get("character", {}).get("hat", {}).get("type", ""))
		if not HAT_WOBBLE.has(type):
			_fail("%s: no wobble tuning for hat type \"%s\" (add it to RacerGestures.HAT_WOBBLE)" % [title, type])
			return
		var hw: Array = HAT_WOBBLE[type]
		if float(hw[0]) > 0.0:
			_add_swing(_pivot_at(hat, hat.position), Vector3.UP, hw[0], -1.0, hw[1], Vector3.ZERO, 1.0, 0)
	var back := character.get_node_or_null("Socket_body_back") as Node3D
	if back == null:
		_fail("%s: body socket Socket_body_back is missing" % title)
		return
	for e in back.get_children():
		if String(e.name).contains("Extra_cape"):
			_has_cape = true
			_add_swing(_pivot_at(e, e.position), Vector3.DOWN, 1.0, -2.0, 0.9, Vector3(0, 0, -1), 0.05, 0)


func _add_swing(n: Node3D, d0: Vector3, gain: float, mix: float, mx: float, into: Vector3, lim: float, chain: int) -> void:
	_sw_node.append(n)
	_sw_d0.append(d0.normalized())
	_sw_gain.append(gain)
	_sw_mix.append(mix)
	_sw_max.append(mx)
	_sw_in.append(into)
	_sw_lim.append(lim)
	_sw_phase.append(_rng.randf_range(0.0, TAU))
	_sw_chain.append(chain)


## Hair piece -> swing (hangs or sticks out), jiggle (points up) or static. Small pieces well
## below the head (braid beads, ties) are collected into `dangle`.
func _classify_hair(c: Node3D, ay: float, dangle: Array[Node3D]) -> void:
	var box := _own_box(c)
	var sz := box.size
	if sz == Vector3.ZERO:
		return
	var order := [0, 1, 2]
	order.sort_custom(func(a, b): return sz[a] > sz[b])
	var big: int = order[0]
	var mid: int = order[1]
	var small: int = order[2]
	var flat: bool = sz[small] < 0.35 * sz[mid]
	var axis := big
	if flat:
		# A flat panel hangs along whichever of its two long sides runs most up-down.
		axis = big if absf(c.basis[big].normalized().y) >= absf(c.basis[mid].normalized().y) else mid
	var others := 0.0
	for k in 3:
		if k != axis:
			others = maxf(others, sz[k])
	var elong: float = sz[axis] / maxf(others, 1e-4)
	var e := Vector3.ZERO
	e[axis] = sz[axis] * 0.5
	var p1 := c.transform * (box.get_center() + e)
	var p2 := c.transform * (box.get_center() - e)
	var near := p1 if p1.length() <= p2.length() else p2
	var far := p2 if near == p1 else p1
	var length := near.distance_to(far)
	var d0 := (far - near) / maxf(length, 1e-4)
	var hangs := d0.y < -0.35
	var sticks_out := far.length() - near.length() > 0.4 * length
	var into := -Vector3(near.x, 0.0, near.z).normalized() if Vector2(near.x, near.z).length() > 1e-3 else Vector3.ZERO
	if (elong >= 1.5 or flat) and (hangs or sticks_out):
		var mix := clampf(length / (ay * 3.0), 0.25, 1.0)
		_add_swing(_pivot_at(c, near), d0, 1.0, mix, 0.75 if hangs else 0.5, into, 0.12, 0)
	elif elong >= 1.3 and d0.y > 0.35:
		_add_swing(_pivot_at(c, near), d0, 0.3, -1.0, 0.22, Vector3.ZERO, 1.0, 0)
	elif (c.transform * box.get_center()).y < -0.9 * ay:
		dangle.append(c)


## Pieces that hang below the head (braid beads and its tie) swing together from their top; a
## long group swings as a two-link chain.
func _dangle_group(hair: Node3D, pieces: Array[Node3D]) -> void:
	var box := AABB()
	for i in pieces.size():
		var b := pieces[i].transform * _own_box(pieces[i])
		box = b if i == 0 else box.merge(b)
	var top := Vector3(box.get_center().x, box.end.y, box.get_center().z)
	var into := -Vector3(top.x, 0.0, top.z).normalized() if Vector2(top.x, top.z).length() > 1e-3 else Vector3.ZERO
	var a := Node3D.new()
	a.name = "Swing"
	a.position = top
	hair.add_child(a)
	var split := top.y - box.size.y * 0.5
	var b2: Node3D = null
	if box.size.y > 0.4:
		b2 = Node3D.new()
		b2.name = "Swing"
		b2.position = Vector3(0, split - top.y, 0)
		a.add_child(b2)
	for p in pieces:
		var xf := p.transform
		hair.remove_child(p)
		if b2 != null and (xf * _own_box(p).get_center()).y < split:
			b2.add_child(p)
			p.transform = Transform3D(xf.basis, xf.origin - top - b2.position)
		else:
			a.add_child(p)
			p.transform = Transform3D(xf.basis, xf.origin - top)
	_add_swing(a, Vector3.DOWN, 1.0, 0.45, 0.7, into, 0.12, 0)
	if b2 != null:
		_add_swing(b2, Vector3.DOWN, 1.0, 0.0, 0.5, into, 0.1, 1)


## Bounds of a node's own mesh and its children, in its own space.
static func _own_box(n: Node3D) -> AABB:
	var box := RacerBuilder._aabb(n, Transform3D.IDENTITY)
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mb := (n as MeshInstance3D).mesh.get_aabb()
		box = mb if box.size == Vector3.ZERO else box.merge(mb)
	return box


## Puts a new pivot at p (parent space) above n, so rotating the pivot swings n about p.
static func _pivot_at(n: Node3D, p: Vector3) -> Node3D:
	var parent := n.get_parent() as Node3D
	var piv := Node3D.new()
	piv.name = "Swing"
	piv.position = p
	var idx := n.get_index()
	var xf := n.transform
	parent.add_child(piv)
	parent.move_child(piv, idx)
	parent.remove_child(n)
	piv.add_child(n)
	n.transform = Transform3D(xf.basis, xf.origin - p)
	return piv


# --- API ---

## Plays a gesture by name (see NAMES). side: -1 left arm, 1 right arm, 0 = its default.
## length 0 = its default; delay in seconds.
func play_named(gesture_name: String, side := 0, length := 0.0, delay := 0.0) -> void:
	if not NAMES.has(gesture_name):
		push_error("RacerGestures: unknown gesture \"%s\" (known: %s)" % [gesture_name, ", ".join(NAMES.keys())])
		return
	play(NAMES[gesture_name], side, length, delay)


func play(g: int, side := 0, length := 0.0, delay := 0.0) -> void:
	if not ok:
		return
	_side[g] = side if side != 0 else int(SIDE[g])
	_left[g] = length if length > 0.0 else float(LENGTH[g])
	if g == G.GLANCE_BACK:
		_glance_side = float(_side[g])
	if delay > 0.0:
		_delay[g] = delay
	elif _time[g] < 0.0:
		_time[g] = 0.0
	_active = maxi(_active, 1)


func hold(g: int, on: bool) -> void:
	if not ok:
		return
	_held[g] = 1 if on else 0
	if on and _time[g] < 0.0 and _delay[g] <= 0.0:
		_time[g] = 0.0
		if _side[g] == 0:
			_side[g] = int(SIDE[g])
		_active = maxi(_active, 1)


## Head follows a node (or a world point when n is null) for secs.
func look_at(p: Vector3, n: Node3D, secs: float) -> void:
	_look_pos = p
	_look_node = n
	_look_t = secs


func look_at_camera(secs: float) -> void:
	var cam := r.get_viewport().get_camera_3d() if r.is_inside_tree() else null
	if cam:
		look_at(Vector3.ZERO, cam, secs)


## Weight of a gesture (0..1), for tools and the viewer.
func weight(g: int) -> float:
	return _w[g]


func is_idle() -> bool:
	return _active == 0


## Face mood of the strongest playing gesture, or "".
func mood_hint() -> String:
	if _active == 0:
		return ""
	for g in range(COUNT - 1, -1, -1):
		if _w[g] > 0.3 and MOOD[g] != "":
			return MOOD[g]
	return ""


func kick(v: Vector3) -> void:
	_v_soft += v
	_v_stiff += v * 0.7
	_v_spring += v * 1.2
	_v_cape += v


func pant(secs: float) -> void:
	_pant_t = maxf(_pant_t, secs)


## Back to the built pose: no gestures, springs at rest, every touched node at its rest transform.
func reset() -> void:
	if not ok:
		return
	for g in COUNT:
		_w[g] = 0.0
		_left[g] = 0.0
		_time[g] = -1.0
		_delay[g] = 0.0
		_held[g] = 0
		_side[g] = int(SIDE[g])
	_active = 0
	for v in ["_d_soft", "_v_soft", "_d_stiff", "_v_stiff", "_d_spring", "_v_spring", "_d_cape", "_v_cape", "_a_rig"]:
		set(v, Vector3.ZERO)
	_have_prev = false
	_a_long = 0.0
	_a_vert = 0.0
	_speed_prev = 0.0
	_vy_prev = 0.0
	_roll = 0.0
	_roll_v = 0.0
	_pitch = 0.0
	_pitch_v = 0.0
	_breath = 0.0
	_pant_t = 0.0
	_yaw = 0.0
	_yaw_v = 0.0
	_pit = 0.0
	_pit_v = 0.0
	_look_ty = 0.0
	_look_tp = 0.0
	_sacc = 0.0
	_look_hold = 0.0
	_look_t = 0.0
	_look_node = null
	_was_rain = false
	_was_water = false
	_was_boost = false
	_was_slip = false
	_was_hat = false
	_air_held = -1
	_char_xf = _char_rest
	_char_inv = _char_rest.affine_inverse()
	_head_xf = _head_rest
	_head_c_now = _head_rest * _head_c_hp
	character.transform = _char_rest
	head_pivot.transform = _head_rest
	if legs:
		legs.transform = _legs_rest
	for i in 2:
		_arm[i].quaternion = _rest_q[i]
		_elbow[i].quaternion = Quaternion.IDENTITY
		_set_stretch(i, 1.0)
	for n in _sw_node:
		n.rotation = Vector3.ZERO


# --- per frame ---

func update(dt: float) -> void:
	if not ok or dt <= 0.0:
		return
	_t += dt
	var sdt := minf(dt, 1.0 / 30.0)  # springs: slow frames play in slow motion instead of blowing up
	_states()
	if _active > 0 or _held.count(1) > 0:
		_tick(dt)
	var moving := clampf(r.speed / 10.0, 0.0, 1.0)
	_a_long = lerpf(_a_long, clampf((r.speed - _speed_prev) / dt, -30.0, 30.0), minf(1.0, dt * 8.0))
	_speed_prev = r.speed
	_a_vert = lerpf(_a_vert, clampf((r.vy - _vy_prev) / dt, -40.0, 60.0), minf(1.0, dt * 20.0))
	_vy_prev = r.vy

	# Gesture contributions to body and head.
	var gp := 0.0
	var gr := 0.0
	var gt := 0.0
	var gl := 0.0
	var hy := 0.0
	var hp := 0.0
	var hr := 0.0
	var hdrop := 0.0
	var glance := 0.0
	var hat_w := 0.0
	if _active > 0:
		for g in COUNT:
			var w := _w[g]
			if w <= 0.0:
				continue
			var ws := w * w * (3.0 - 2.0 * w)
			var tt := _time[g]
			match g:
				G.RAIN:
					gp -= 0.12 * ws
					hp -= 0.15 * ws
					hdrop -= 0.025 * ws
				G.HAT:
					gp -= 0.05 * ws
					hp -= 0.06 * ws
					hat_w = ws
				G.TUCK:
					gp -= 0.3 * ws
					hp += 0.22 * ws
					gl -= 0.03 * ws
				G.WHEEE:
					gp += 0.12 * ws
					hp += 0.3 * ws
				G.BRACE:
					gp += 0.16 * ws
					hp -= 0.12 * ws
					gl -= 0.025 * ws
				G.WAVE:
					gt += _yaw * 0.3 * ws
					hr += 0.06 * float(_side[g]) * ws
				G.FIST_PUMP:
					gp += 0.06 * ws
					hp += 0.12 * ws
				G.CHEER:
					gp += 0.1 * ws
					gl += 0.02 * ws * (0.5 + 0.5 * sin(tt * 12.0)) * amp
					hp += 0.22 * ws
				G.SURPRISED:
					gp += 0.12 * ws
					gl += 0.035 * ws
					hp += 0.25 * ws
				G.FLAIL:
					gr += sin(tt * 13.0) * 0.1 * ws * amp
					hr += sin(tt * 11.0 + 1.0) * 0.15 * ws * amp
					hp += 0.1 * ws
				G.DIZZY:
					var dz := ws * (1.0 - 0.6 * clampf(tt / float(LENGTH[g]), 0.0, 1.0)) * amp
					hr += sin(tt * 7.5) * 0.25 * dz
					hp += cos(tt * 7.5) * 0.15 * dz
					gr += sin(tt * 7.5 + 1.0) * 0.05 * dz
				G.SLUMP:
					gp -= 0.3 * ws
					hp -= 0.5 * ws
					gl -= 0.03 * ws
					hr += 0.12 * ws
				G.GLANCE_BACK:
					glance = ws
				G.HEAD_SHAKE:
					hy += sin(tt * 21.0) * 0.38 * ws * amp
					hr += sin(tt * 21.0 + 0.6) * 0.08 * ws * amp

	# Lean with lag and overshoot (spring), into the turn and the side slide.
	var lk := 49.0
	var lc := 2.0 * lean_zeta * 7.0
	var lean_t := clampf(-r.lean * 0.18 + r.turn * 0.09, -0.32, 0.32)
	_roll_v += (lk * (lean_t - _roll) - lc * _roll_v) * sdt
	_roll += _roll_v * sdt
	var pitch_t := (-0.22 if r.boost else -0.12 * moving) + clampf(_a_long * 0.01, -0.12, 0.15) + r._mo_char_pitch
	_pitch_v += (36.0 * (pitch_t - _pitch) - 2.0 * 0.5 * 6.0 * _pitch_v) * sdt
	_pitch += _pitch_v * sdt
	if glance > 0.0:
		gt += signf(_yaw if _look_t > 0.0 else -_glance_side) * 0.28 * glance

	# Breathing: slow at rest, panting after a boost or the finish.
	_pant_t = maxf(0.0, _pant_t - dt)
	var pant_k := clampf(_pant_t / 1.5, 0.0, 1.0)
	_breath += dt * lerpf(2.4, 10.0, pant_k)
	var b := sin(_breath) * lerpf(0.012, 0.03, pant_k)
	var basis := Basis.from_euler(Vector3(_pitch + gp + b * 0.5, gt, _roll + gr)) * _char_rest.basis \
		* Basis.from_scale(Vector3(1.0 + 0.5 * b, 1.0 + b, 1.0 + 0.5 * b))
	_char_xf = Transform3D(basis, _char_rest.origin + Vector3(0.0, gl, 0.0))
	character.transform = _char_xf
	_char_inv = _char_xf.affine_inverse()
	if legs:
		legs.transform = _char_inv * _char_rest * _legs_rest

	# Head: look target (spring with quick turns), personality, gestures; clamped.
	_look(dt, sdt, moving)
	var yaw := _yaw * (1.0 - 0.7 * hat_w) + r._mo_head_yaw + hy
	if glance > 0.0 and _look_t <= 0.0:
		yaw = lerpf(yaw, -_glance_side * 1.25, glance)
	var pitch := _pit * (1.0 - 0.7 * hat_w) + r._mo_head_pitch + hp
	var roll := r._lean_s * 0.12 + sin(_t * 1.7) * 0.03 + r._mo_head_roll + hr - _roll * 0.5
	var hb := Basis.from_euler(Vector3(clampf(pitch, PITCH_MIN, PITCH_MAX), clampf(yaw, -YAW_MAX, YAW_MAX), clampf(roll, -ROLL_MAX, ROLL_MAX)))
	_head_xf = Transform3D(hb, _head_rest.origin + Vector3(0.0, hdrop, 0.0))
	head_pivot.transform = _head_xf
	_head_c_now = _head_xf * _head_c_hp

	_arms()
	_swing(dt, sdt)


## Holds driven by the racer's state, and one-shots on its edges.
## Edge-triggered, so a hold set by hand (viewer, tools) stays until the state changes.
func _states() -> void:
	var raining := r.rain > 0.35
	if raining != _was_rain and (raining or r.rain < 0.1):
		hold(G.RAIN, raining)
		if not raining:
			play(G.HEAD_SHAKE, 0, 0.0, _rng.randf_range(0.05, 0.6))
		_was_rain = raining
	var windy := _hat_ok and r.wind.length_squared() > 0.2
	if windy != _was_hat:
		hold(G.HAT, windy)
		_was_hat = windy
	var pose := air_pose if r.airborne and r.big_air else -1
	if pose != _air_held:
		if _air_held >= 0:
			hold(_air_held, false)
		if pose >= 0:
			hold(pose, true)
		_air_held = pose
	if r.slipping != _was_slip:
		if r.slipping:
			play(G.FLAIL, 0, 0.5)
		hold(G.FLAIL, r.slipping)
		_was_slip = r.slipping
	if r.in_water and not _was_water:
		play(G.SURPRISED)
	_was_water = r.in_water
	if _was_boost and not r.boost:
		pant(3.5)
	_was_boost = r.boost


func _tick(dt: float) -> void:
	_active = 0
	for g in COUNT:
		if _delay[g] > 0.0:
			_delay[g] -= dt
			_active += 1
			if _delay[g] > 0.0:
				continue
			_time[g] = 0.0
		if _time[g] < 0.0:
			continue
		_time[g] += dt
		var on := _left[g] > 0.0 or _held[g] == 1
		_left[g] = maxf(0.0, _left[g] - dt)
		var w := _w[g]
		if on:
			w = minf(1.0, w + dt / float(BLEND_IN[g]))
		else:
			w = maxf(0.0, w - dt / float(BLEND_OUT[g]))
			if w <= 0.0:
				_time[g] = -1.0
		_w[g] = w
		_active += 1


func _look(dt: float, sdt: float, moving: float) -> void:
	if _look_t > 0.0:
		_look_t -= dt
		var p := _look_pos
		if _look_node != null:
			if is_instance_valid(_look_node) and _look_node.is_inside_tree():
				p = _look_node.global_position
			else:
				_look_t = 0.0
		if _look_t > 0.0 and r.is_inside_tree():
			var cg := character.global_transform
			var dir := cg.basis.inverse() * (p - cg * _head_rest.origin)
			_look_ty = clampf(atan2(-dir.x, -dir.z), -YAW_MAX, YAW_MAX)
			_look_tp = clampf(atan2(dir.y, Vector2(dir.x, dir.z).length()) * 0.7, PITCH_MIN, PITCH_MAX)
		if _look_t <= 0.0:
			_look_node = null
			_look_hold = 0.3
	else:
		_look_hold -= dt
		if _look_hold <= 0.0:
			_pick_look(moving)
		if moving > 0.3 and _look_t <= 0.0:
			_look_ty = clampf(r.ahead_turn * 0.8, -0.7, 0.7) + _sacc
	var k := look_omega * look_omega
	var c := 2.0 * 0.8 * look_omega
	_yaw_v += (k * (_look_ty - _yaw) - c * _yaw_v) * sdt
	_yaw += _yaw_v * sdt
	_pit_v += (k * (_look_tp - _pit) - c * _pit_v) * sdt
	_pit += _pit_v * sdt


## Next glance: driving = small saccades around the corner look; idle = look around, now and
## then at the camera.
func _pick_look(moving: float) -> void:
	_look_hold = _rng.randf_range(hold_min, hold_max)
	if moving > 0.3:
		_sacc = _rng.randf_range(-0.18, 0.18)
		_look_tp = _rng.randf_range(-0.08, 0.05)
		return
	_sacc = 0.0
	if _rng.randf() < 0.3 and r.is_inside_tree():
		var cam := r.get_viewport().get_camera_3d()
		if cam:
			look_at(Vector3.ZERO, cam, _look_hold)
			return
	_look_ty = _rng.randf_range(-0.75, 0.75)
	_look_tp = _rng.randf_range(-0.15, 0.2)


func _arms() -> void:
	var lean_out := clampf(absf(_roll) * 2.5, 0.0, 1.0)
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var t: Vector3
		if grip:
			t = _char_inv * _grip_model[i]
		else:
			t = _hand_rest[i] + Vector3(s * 0.06, 0.1, 0.0) * lean_out
		var pole := Vector3(s * POLE_GRIP.x, POLE_GRIP.y, POLE_GRIP.z)
		var kmax := 1.15 if grip else 1.0
		var posed := 0.0
		if _active > 0:
			for g in COUNT:
				var w := _w[g]
				if w <= 0.0:
					continue
				var mask: int = ARMS[g]
				if mask == 0 or (mask == 4 and _side[g] != i * 2 - 1):
					continue
				if grip and (g == G.TUCK or g == G.BRACE):
					continue
				var ws := w * w * (3.0 - 2.0 * w)
				if g == G.DIZZY:
					ws *= 0.35
				t = t.lerp(_pose(g, i, s), ws) + Vector3(s * 0.07, 0.03, 0.0) * sin(ws * PI)
				pole = pole.lerp(_pole(g, s), ws)
				kmax = lerpf(kmax, float(REACH[g]), ws)
				posed = maxf(posed, ws)
		if posed > 0.0:
			t = _push_out(t, _head_c_now, _head_r)
			t = _push_out(t, _body_c, _body_r)
		_solve(i, t, pole, kmax)


func _pose(g: int, i: int, s: float) -> Vector3:
	var tt := _time[g]
	match g:
		G.RAIN:
			return _p_rain[i]
		G.HAT:
			return _p_hat[i]
		G.TUCK:
			return _p_tuck[i]
		G.WHEEE:
			return _p_up[i] + Vector3(s * 0.03 * sin(tt * 9.0), 0.04 * sin(tt * 7.0 + i), 0.0) * amp
		G.BRACE:
			return _p_brace[i]
		G.WAVE:
			return _p_wave[i] + Vector3(s * 0.09 * sin(tt * 13.0), 0.02 * sin(tt * 26.0), 0.0) * amp
		G.FIST_PUMP:
			return _p_pump_lo[i].lerp(_p_pump_hi[i], 0.5 + 0.5 * sin(tt * 13.0 - 1.5))
		G.CHEER:
			return _p_up[i] + Vector3(0.0, 0.07 * sin(tt * 12.0 + i * 1.3), 0.0) * amp
		G.SURPRISED:
			return _p_out[i] + Vector3(0.0, 0.02 * sin(tt * 30.0), 0.0)
		G.FLAIL:
			var ph := tt * 15.0 + i * PI
			return _shoulder[i] + Vector3(s * 0.18, 0.12 + sin(ph) * 0.5 * _len[i], -0.05 - cos(ph) * 0.5 * _len[i])
		G.DIZZY, G.SLUMP:
			return _p_lap[i] + Vector3(0.0, 0.0, 0.015 * sin(tt * 3.0 + i))
	return _hand_rest[i]


func _pole(g: int, s: float) -> Vector3:
	var p := POLE_UP
	match g:
		G.RAIN, G.HAT:
			p = POLE_HEAD
		G.TUCK, G.BRACE:
			p = POLE_GRIP
		G.DIZZY, G.SLUMP:
			p = POLE_LAP
	return Vector3(s * p.x, p.y, p.z)


## Two equal bones from the shoulder to target t (Character space), elbow pulled toward pole.
## Within 8 % shorter .. kmax longer the arm squashes / stretches instead of bending, so it is
## exactly straight (the built pose) at rest.
func _solve(i: int, t: Vector3, pole: Vector3, kmax: float) -> void:
	var S := _shoulder[i]
	var L := _len[i]
	var to := t - S
	var d := to.length()
	if d < 1e-4:
		return
	var dir := to / d
	var k := clampf(d / L, 0.92, kmax)
	if absf(k - 1.0) < 0.004:
		k = 1.0
	if absf(k - _k[i]) > 0.003 or (k == 1.0 and _k[i] != 1.0):
		_set_stretch(i, k)
	var span := L * k
	var upper := dir
	var lower := dir
	if d < span:
		var ca := d / span
		var sa := sqrt(1.0 - ca * ca)
		var pn := pole - dir * pole.dot(dir)
		var pl := pn.length()
		if pl > 1e-4:
			pn /= pl
			upper = dir * ca + pn * sa
			lower = dir * ca - pn * sa
	var qu := Quaternion(_rest_dir[i], upper) * _rest_q[i]
	_arm[i].quaternion = qu
	_elbow[i].quaternion = qu.inverse() * Quaternion(upper, lower) * qu


func _set_stretch(i: int, k: float) -> void:
	var y := -_len[i] * 0.25 * k
	_upper_mi[i].position = Vector3(0.0, y, 0.0)
	_upper_mi[i].scale = Vector3(1.0, k, 1.0)
	_lower_mi[i].position = Vector3(0.0, y, 0.0)
	_lower_mi[i].scale = Vector3(1.0, k, 1.0)
	_elbow[i].position = Vector3(0.0, y * 2.0, 0.0)
	_hand[i].position = Vector3(0.0, y * 2.0, 0.0)
	_k[i] = k


## Hair, ears, hat and cape: springs driven by the push on the head (inertia, gravity when the
## head tilts, head wind from driving and falling, weather wind), shared by all pieces.
func _swing(dt: float, sdt: float) -> void:
	if _sw_node.is_empty():
		return
	# Head motion inside the racer (hops, bounce, lean): second difference of its position.
	var pr := r.rig.transform * (r.model.transform * (_char_xf * _head_xf.origin))
	if _have_prev:
		var vr := (pr - _pr_prev) / dt
		_a_rig = _a_rig.lerp(((vr - _vr_prev) / dt).limit_length(40.0) * 0.6, minf(1.0, dt * 25.0))
		_vr_prev = vr
	_pr_prev = pr
	_have_prev = true
	var a_toy := Vector3(-r.speed * r.turn, _a_vert, -_a_long) + _a_rig
	var toy_q := r.global_basis.get_rotation_quaternion() if r.is_inside_tree() else Quaternion.IDENTITY
	var push := toy_q.inverse() * (GRAVITY + r.wind * WIND_ACC) - a_toy + Vector3(0.0, -r.vy * 0.4, r.speed * AIR_K)
	var to_char := r.rig.basis * r.model.basis * _char_xf.basis
	var hq := (to_char * _head_xf.basis).get_rotation_quaternion()
	var df := (hq.inverse() * push - GRAVITY) * HAIR_GAIN
	_v_soft += (df - _d_soft) * (SOFT_W * SOFT_W * sdt) - _v_soft * (2.0 * SOFT_Z * SOFT_W * sdt)
	_d_soft += _v_soft * sdt
	_v_stiff += (df - _d_stiff) * (STIFF_W * STIFF_W * sdt) - _v_stiff * (2.0 * STIFF_Z * STIFF_W * sdt)
	_d_stiff += _v_stiff * sdt
	_v_spring += (df - _d_spring) * (SPRING_W * SPRING_W * sdt) - _v_spring * (2.0 * SPRING_Z * SPRING_W * sdt)
	_d_spring += _v_spring * sdt
	if _has_cape:
		var dc := (to_char.get_rotation_quaternion().inverse() * push - GRAVITY) * HAIR_GAIN
		_v_cape += (dc - _d_cape) * (SOFT_W * SOFT_W * sdt) - _v_cape * (2.0 * SOFT_Z * SOFT_W * sdt)
		_d_cape += _v_cape * sdt
	var wind := r.wind.length()
	for j in _sw_node.size():
		var mix := _sw_mix[j]
		var d: Vector3
		if _sw_chain[j] == 1:
			d = (_d_soft - _d_stiff) * 0.9
		elif mix == -1.0:
			d = _d_spring
		elif mix == -2.0:
			d = _d_cape
		else:
			d = _d_stiff.lerp(_d_soft, mix)
		if wind > 0.02:
			var ph := _sw_phase[j]
			d += Vector3(sin(_t * 7.0 + ph), 0.3 * sin(_t * 5.3 + ph * 2.0), cos(_t * 8.3 + ph)) * (0.1 * wind)
		var n := _sw_in[j]
		var into := d.dot(n) - _sw_lim[j]
		if into > 0.0:
			d -= n * into
		var th := _sw_d0[j].cross(d) * _sw_gain[j]
		var mx := _sw_max[j]
		var l2 := th.length_squared()
		if l2 > mx * mx:
			th *= mx / sqrt(l2)
		_sw_node[j].rotation = th

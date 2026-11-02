extends RefCounted
## The ride's half of a built ToyRacer coming alive, per ride base, on the nodes and anim metas the
## builder already makes (kit_rides.gd / kit_ride_parts.gd stay as they are):
##   - wheels spin, legs walk, wings flap, flames flicker, tails wag, jellies jiggle (the metas);
##   - karts and cars roll into bends on their wheels and squash and stretch on landing: the body
##     and the driver sit on a "Sway" pivot above the axles (`carry` moves the driver with it);
##     bikes and boards carve into bends and squash and stretch as a whole;
##   - four-legged animals nod with their stride, buck a little on landing, rear up at the finish;
##   - wings (birds, or drawn on any ride) flap hard on jumps and fold on landing;
##   - boats rock and bob; rockets wobble, and their flame flares on boost;
##   - blobs wobble far more (landing, bends, boost), the rider bouncing on top;
##   - ride extras (antennae, flags, horns), tails and the boat's pennant swing on hair springs;
##   - idles and weather: tails swish now and then, animals flick their ears, a sailboat's sail
##     swings out to the wind and the boat heels, rockets sputter when slow, water splashes up on
##     entering the pond, rain drops splash on the ride.
## Start grid (race_reactions.gd): crouch() while the lights count down, go() on green, fidget().
## ToyRacer owns one (`ride`): update() each frame before it builds its rig transform from
## pitch / roll / yaw / lift / scale; land(), finish(), fail() on those events; reset() for the
## built pose. update() does not allocate.

const Gestures = preload("res://racer_kit/racer_gestures.gd")

const WHEELED := ["kart", "car", "chassis"]  # body on a suspension above the wheels (Sway pivot)
const CARVERS := ["bike", "board"]    # lean into bends as a whole
const REAR_S := 1.5                   # finish: rear up, big flaps, happy bounce
const BUCK_S := 0.5                   # landing buck (animals)
const FOLD_S := 1.0                   # wings folded after landing
const GO_S := 0.6                     # leaving the grid
const FIDGET_S := 0.9
## Ride extras: swing gain and largest swing (rad) by shape; anything else sits nearly still.
const EXTRA_SWING := {"capsule": [0.6, 0.45], "cylinder": [0.6, 0.45], "cone": [0.2, 0.1],
	"box": [0.3, 0.2], "leaf": [0.35, 0.22], "heart": [0.3, 0.18], "star": [0.3, 0.18], "flower": [0.35, 0.22],
	"flame": [0.3, 0.2], "lightning": [0.3, 0.18], "moon": [0.3, 0.18], "cloud": [0.25, 0.15],
	"diamond": [0.25, 0.15], "drop": [0.3, 0.18], "bowtie": [0.3, 0.18], "cape": [0.5, 0.35]}
const BOAT_FLAG_AT := Vector3(0, 0.94, 0.62)  # kit_rides.gd _boat(): the pennant on its little pole
const SAIL_AT := Vector3(0, 0.5, 0.45)        # kit_rides.gd _sailboat(): the sail beside the mast
const MAST_Z := 0.42
const EAR_AT := Vector3(0.12, 0.18, 0.02)     # kit_rides.gd _animal4(): the ears on RideHead (x mirrored)
const EAR_HALF := 0.08                        # half the ear capsule: its root is this far down
const SWISH_S := 0.6
const FLICK_S := 0.25
const SPUTTER_S := 0.12
const WATER := Color(0.75, 0.9, 1.0, 0.75)

var ok := false
var error := ""
var r: ToyRacer
var base := ""

# Rig offsets for ToyRacer, written by update().
var pitch := 0.0                  # rad, + = nose up
var roll := 0.0                   # rad, + = left side down (into a left bend)
var yaw := 0.0
var lift := 0.0                   # m, never below the ground
var scale := Vector3.ONE
## Model-space transform the driver rides on (a kart's Sway, a blob's bouncing top); RacerGestures.
var carry := Transform3D.IDENTITY
## How much of ToyRacer's whole-rig squash (bumps, landings) to keep: karts and cars squash their
## body on the Sway instead, so the wheels stay round.
var rig_squash := 1.0

var _ride: Node3D
var _sway: Node3D = null
var _sway_p := Vector3.ZERO       # pivot (Ride space): axle height, middle of the ride
var _axle_front := 0.0            # z of the front / rear axles (Ride space): a wheelie turns on the
var _axle_back := 0.0             # rear one, a dive on the front one
var _head: Node3D = null          # RideHead of animals and birds
var _head_rest := Transform3D.IDENTITY
var _jelly: Node3D = null
var _jelly_rest := Transform3D.IDENTITY
var _jelly_lo := 0.0              # jelly bottom / height below / above its origin (Jelly space)
var _jelly_h := 0.0
var _legs: Array = []             # leg_swing pivots
var _leg_front := PackedByteArray()
var _wings: Array = []
var _tails: Array = []            # tail roots (wag + swing)
var _flames: Array = []
var _ext: Array[Node3D] = []      # swinging extras: socket markers, the boat's pennant
var _ext_d0 := PackedVector3Array()
var _ext_gain := PackedFloat32Array()
var _ext_max := PackedFloat32Array()
var _ext_flag := PackedByteArray()  # 1 = flutters in the wind like a flag
var _ext_phase := PackedFloat32Array()
var _ext_base := []               # rest rotation per extra (the pennant is turned on its pole)
var _rear_max := 0.5              # rad: rearing / bucking as far as no part dips into the ground
var _buck_max := 0.18

var _t := 0.0
var _stride := 0.0
var _turn_s := 0.0
var _a_long := 0.0
var _a_vert := 0.0
var _speed_prev := 0.0
var _vy_prev := 0.0
var _was_boost := false
var _roll_s := 0.0
var _roll_v := 0.0
var _pitch_s := 0.0
var _pitch_v := 0.0
var _sq := 0.0                    # squash (-) / stretch (+)
var _sq_v := 0.0
var _jx := 0.0                    # blob lean in bends
var _jx_v := 0.0
var _flare := 1.0
var _flare_v := 0.0
var _kick := 0.0                  # boost start (1 -> 0)
var _rear_t := 0.0
var _buck_t := 0.0
var _fold_t := 0.0
var _go_t := 0.0
var _crouch := 0.0                # 0..1 while the start lights count down
var _crouch_s := 0.0
var _fidget_t := 0.0
var _fidget_k := 0
var _rock_k := 0.0                # extra boat rocking after a splash
var _ears: Array[Node3D] = []     # ear pivots (animals)
var _ear_side := PackedFloat32Array()
var _sail: Node3D = null          # sail pivot on the mast (sailboat)
var _sail_s := 0.0                # sail swing (rad) and its speed
var _sail_v := 0.0
var _heel := 0.0                  # the sailboat heeling away from the wind (rad, added to roll)
var _swish_t := 0.0               # tail swish left (s), time to the next one
var _swish_next := 2.0
var _flick_t := 0.0               # ear flick left, which ear, time to the next one
var _flick_i := 0
var _flick_next := 1.5
var _sputter_t := 0.0             # rocket sputter left, time to the next one
var _sputter_next := 1.0
var _was_water := false
var _splash: CPUParticles3D = null  # water thrown up entering the pond
var _drops: CPUParticles3D = null   # rain drops bursting on the ride
var _rng := RandomNumberGenerator.new()
var _d_spring := Vector3.ZERO
var _v_spring := Vector3.ZERO
var _d_soft := Vector3.ZERO
var _v_soft := Vector3.ZERO


# --- setup ---

func setup(racer: ToyRacer) -> bool:
	r = racer
	var title := str(r.spec.get("title", "?"))
	base = str(r.spec.get("ride", {}).get("base", ""))
	_ride = r.model.get_node_or_null("Ride") as Node3D
	var body := _ride.get_node_or_null("RideBody") as Node3D if _ride else null
	if body == null:
		return _fail("%s: the built racer has no Model/Ride/RideBody" % title)
	_t = randf() * 10.0
	_head = body.get_node_or_null("RideHead") as Node3D
	if _head:
		_head_rest = _head.transform
	_jelly = body.get_node_or_null("Jelly") as Node3D
	if base == "blob" and _jelly == null:
		return _fail("%s: a blob ride without its Jelly node" % title)
	if _jelly:
		_jelly_rest = _jelly.transform
		var jb := RacerBuilder._aabb(_jelly, Transform3D.IDENTITY)
		_jelly_lo = -jb.position.y
		_jelly_h = jb.size.y
	_legs = r._anim["leg_swing"]
	for l in _legs:
		_leg_front.append(1 if (l as Node3D).position.z < -0.05 else 0)
	_wings = r._anim["wing_flap"]
	_tails = r._anim["tail_wag"]
	_flames = r._anim["flicker"]
	for sock in _ride.get_children():
		# ride_center holds a chassis's built body: it rides rigid, only the parts on the edges swing.
		if sock is Marker3D and String(sock.name).begins_with("Socket_ride_") and sock.get_child_count() > 0 \
				and sock.name != "Socket_ride_center":
			_add_extra(sock)
	if base in ["boat", "sailboat"]:
		var flag: Node3D = null
		for c in body.get_children():
			if c is MeshInstance3D and (c as Node3D).position.is_equal_approx(BOAT_FLAG_AT):
				flag = c
		if flag == null:
			return _fail("%s: the boat's pennant is not at %s on RideBody (kit_rides.gd _boat changed?)" % [title, BOAT_FLAG_AT])
		var piv := Gestures._pivot_at(flag, flag.position)
		_add_swing(piv, Vector3(0, 0, 1), 0.9, 0.6, true)  # it points back from the pole
	if base == "sailboat":
		var sail: Node3D = null
		for c in body.get_children():
			if c is MeshInstance3D and (c as Node3D).position.is_equal_approx(SAIL_AT):
				sail = c
		if sail == null:
			return _fail("%s: the sail is not at %s on RideBody (kit_rides.gd _sailboat changed?)" % [title, SAIL_AT])
		_sail = Gestures._pivot_at(sail, Vector3(0.0, SAIL_AT.y, MAST_Z))
	if base == "animal4":
		if _head == null:
			return _fail("%s: an animal ride without its RideHead" % title)
		for s in [-1.0, 1.0]:
			var ear: Node3D = null
			for c in _head.get_children():
				if c is MeshInstance3D and (c as Node3D).position.is_equal_approx(Vector3(EAR_AT.x * s, EAR_AT.y, EAR_AT.z)):
					ear = c
			if ear == null:
				return _fail("%s: no ear at %s on RideHead (kit_rides.gd _animal4 changed?)" % [title, EAR_AT])
			_ears.append(Gestures._pivot_at(ear, ear.position + ear.basis * Vector3(0.0, -EAR_HALF, 0.0)))
			_ear_side.append(s)
	_rng.seed = hash(title) ^ randi()
	_splash = _particles(40, 0.85, 0.075)
	_splash.one_shot = true
	_splash.explosiveness = 0.95
	_splash.direction = Vector3.UP
	_splash.spread = 40.0
	_splash.initial_velocity_min = 3.0
	_splash.initial_velocity_max = 6.0
	_splash.emission_box_extents = Vector3(0.6, 0.05, 0.8)
	_drops = _particles(20, 0.3, 0.04)
	_drops.direction = Vector3.UP
	_drops.spread = 70.0
	_drops.initial_velocity_min = 0.8
	_drops.initial_velocity_max = 1.6
	var box := RacerBuilder._aabb(r.model, Transform3D.IDENTITY)
	_drops.position = box.get_center() + Vector3(0.0, box.size.y * 0.3, 0.0)
	_drops.emission_box_extents = box.size * Vector3(0.4, 0.2, 0.4)
	if base in WHEELED:
		_setup_sway(body)
		rig_squash = 0.3
	if base == "animal4":
		var pts := PackedVector3Array()
		_low_points(r.model, r.model.transform, pts)
		_rear_max = _max_pitch(pts, 0.5)
		_buck_max = -_max_pitch(pts, -0.18)
	ok = true
	reset()
	return true


## Water droplets (small light-blue balls under gravity), not emitting; parented to the Model.
func _particles(n: int, life: float, size: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.name = "Water"
	p.amount = n
	p.lifetime = life
	p.emitting = false
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.gravity = Vector3(0.0, -9.8, 0.0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var m := SphereMesh.new()
	m.radius = size
	m.height = size * 2.0
	m.radial_segments = 6
	m.rings = 3
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WATER
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = mat
	p.mesh = m
	r.model.add_child(p)
	return p


func _fail(msg: String) -> bool:
	error = "RideMotion: " + msg
	push_error(error)
	ok = false
	return false


## Everything on the ride but its wheels and legs goes under a Sway pivot (identity at rest, so the
## built pose is unchanged), which rolls and squashes about the axles.
func _setup_sway(body: Node3D) -> void:
	var keep: Array = []
	for c in _ride.get_children():
		var grounded := false
		for w in r._anim["wheel_spin"]:
			if c.is_ancestor_of(w):
				grounded = true
		if c in _legs:
			grounded = true
		if not grounded:
			keep.append(c)
	_sway = Node3D.new()
	_sway.name = "Sway"
	_ride.add_child(_sway)
	_ride.move_child(_sway, 0)
	for c in keep:
		var xf: Transform3D = c.transform
		_ride.remove_child(c)
		_sway.add_child(c)
		c.transform = xf
	var axle := 0.18
	_axle_front = INF
	_axle_back = -INF
	for w in r._anim["wheel_spin"]:
		var at: Vector3 = (w as Node3D).get_parent().position
		axle = at.y
		_axle_front = minf(_axle_front, at.z)
		_axle_back = maxf(_axle_back, at.z)
	if _axle_front == INF:
		_axle_front = -0.4  # legs instead of wheels: the spec drew it so
		_axle_back = 0.4
	_sway_p = Vector3(0, axle, body.position.z)


## Mesh box corners low on the ride (Rig space, at rest); wheels and legs are left out, the rig's
## ground lift keeps those on the ground.
func _low_points(n: Node, xf: Transform3D, pts: PackedVector3Array) -> void:
	for c in n.get_children():
		if not c is Node3D or c is Label3D or c.has_meta("leg_swing") or c.has_meta("wheel_spin"):
			continue
		var cx: Transform3D = xf * c.transform
		if c is MeshInstance3D and c.mesh:
			var b: AABB = c.mesh.get_aabb()
			for k in 8:
				var p: Vector3 = cx * b.get_endpoint(k)
				if p.y < 0.7:
					pts.append(p)
		_low_points(c, cx, pts)


## The largest pitch toward `want` (rad) at which none of `pts` goes below the ground.
func _max_pitch(pts: PackedVector3Array, want: float) -> float:
	var a := want
	for _i in 12:
		var b := Basis.from_euler(Vector3(a, 0.0, 0.0))
		var low := INF
		for p in pts:
			low = minf(low, (b * p).y)
		if low + r._ground_lift(b) >= 0.02:
			return a
		a *= 0.8
	return 0.0


func _add_extra(sock: Node3D) -> void:
	var gain := 0.1
	var mx := 0.05
	var flag := false
	for e in sock.get_children():
		var shape := String(e.name).trim_prefix("Extra_")
		if EXTRA_SWING.has(shape):
			var sw: Array = EXTRA_SWING[shape]
			if float(sw[0]) > gain:
				gain = sw[0]
				mx = sw[1]
				flag = shape not in ["capsule", "cylinder", "cone"]
	# Rest direction socket -> the middle of what hangs on it (an antenna points up its length).
	var box := RacerBuilder._aabb(sock, Transform3D.IDENTITY)
	var c := box.get_center()
	# A long piece low on the ride swings no further than its tip can drop above the ground.
	var to_rig := r.model.transform * _ride.transform * sock.transform
	var low := INF
	var reach := 0.0
	for k in 8:
		var p := box.get_endpoint(k)
		low = minf(low, (to_rig * p).y)
		reach = maxf(reach, (to_rig.basis * p).length())
	if reach > 1e-3:
		mx = minf(mx, asin(clampf((low - 0.04) / reach, 0.0, 1.0)) * 0.8)
	_add_swing(sock, c if c.length() > 0.02 else Vector3.UP, gain, mx, flag)


func _add_swing(n: Node3D, d0: Vector3, gain: float, mx: float, flag: bool) -> void:
	_ext.append(n)
	_ext_d0.append(d0.normalized())
	_ext_gain.append(gain)
	_ext_max.append(mx)
	_ext_flag.append(1 if flag else 0)
	_ext_phase.append(randf() * TAU)
	_ext_base.append(n.rotation)


# --- events ---

func land() -> void:
	_sq_v -= 3.0 if base != "blob" else 4.2
	_buck_t = BUCK_S
	if not _wings.is_empty():
		_fold_t = FOLD_S
	_rock_k = 1.0


func finish() -> void:
	_rear_t = REAR_S


func fail() -> void:
	_sq_v -= 1.6
	_rock_k = 1.0


## Start lights counting down (0 = waiting, 1 = about to go): the ride gets ready to leap.
func crouch(k: float) -> void:
	_crouch = clampf(k, 0.0, 1.0)


func go() -> void:
	_crouch = 0.0
	_go_t = GO_S
	_sq_v += 1.4
	_kick = 1.0


## A little idle thing on the grid (an animal stomps and shakes its head, a bird stretches its
## wings, a blob wobbles, a kart revs, a rocket puffs, a boat rocks).
func fidget() -> void:
	_fidget_t = FIDGET_S
	_fidget_k = randi() % 2


## Every node the ride layer moves (gesture_check checks they stay finite and come back).
func nodes() -> Array:
	var out: Array = []
	if _sway:
		out.append(_sway)
	if _head:
		out.append(_head)
	if _jelly:
		out.append(_jelly)
	out.append_array(_legs)
	out.append_array(_wings)
	out.append_array(_tails)
	out.append_array(_flames)
	out.append_array(_ext)
	out.append_array(_ears)
	if _sail:
		out.append(_sail)
	return out


func reset() -> void:
	if not ok:
		return
	pitch = 0.0
	roll = 0.0
	yaw = 0.0
	lift = 0.0
	scale = Vector3.ONE
	carry = Transform3D.IDENTITY
	for v in ["_roll_s", "_roll_v", "_pitch_s", "_pitch_v", "_sq", "_sq_v", "_jx", "_jx_v", "_flare_v", "_kick",
			"_rear_t", "_buck_t", "_fold_t", "_go_t", "_crouch", "_crouch_s", "_fidget_t", "_rock_k",
			"_turn_s", "_a_long", "_a_vert", "_speed_prev", "_vy_prev"]:
		set(v, 0.0)
	_flare = 1.0
	_was_boost = false
	for v in ["_d_spring", "_v_spring", "_d_soft", "_v_soft"]:
		set(v, Vector3.ZERO)
	if _sway:
		_sway.transform = Transform3D.IDENTITY
	if _head:
		_head.transform = _head_rest
	if _jelly:
		_jelly.transform = _jelly_rest
	for j in _ext.size():
		_ext[j].rotation = _ext_base[j]
	for e in _ears:
		e.rotation = Vector3.ZERO
	if _sail:
		_sail.rotation = Vector3.ZERO
	for v in ["_sail_s", "_sail_v", "_heel", "_swish_t", "_flick_t", "_sputter_t"]:
		set(v, 0.0)
	_swish_next = 1.0  # the first idle swish, flick and sputter come soon after the built pose
	_flick_next = 0.8
	_sputter_next = 0.6
	_was_water = false
	if _splash:
		_splash.emitting = false
		_drops.emitting = false


# --- per frame ---

func update(dt: float) -> void:
	if not ok or dt <= 0.0:
		return
	_t += dt
	var sdt := minf(dt, 1.0 / 30.0)
	var moving := clampf(r.speed / 10.0, 0.0, 1.0)
	_turn_s = lerpf(_turn_s, r.turn, minf(1.0, dt * 6.0))
	_a_long = lerpf(_a_long, clampf((r.speed - _speed_prev) / dt, -30.0, 30.0), minf(1.0, dt * 8.0))
	_speed_prev = r.speed
	_a_vert = lerpf(_a_vert, clampf((r.vy - _vy_prev) / dt, -40.0, 60.0), minf(1.0, dt * 20.0))
	_vy_prev = r.vy
	if r.boost and not _was_boost:
		_kick = 1.0
		_flare_v += 14.0
	_was_boost = r.boost
	_kick = maxf(0.0, _kick - dt * 2.0)
	_rear_t = maxf(0.0, _rear_t - dt)
	_buck_t = maxf(0.0, _buck_t - dt)
	_fold_t = maxf(0.0, _fold_t - dt)
	_go_t = maxf(0.0, _go_t - dt)
	_fidget_t = maxf(0.0, _fidget_t - dt)
	_rock_k = maxf(0.0, _rock_k - dt * 0.7)
	_idles(dt, sdt)
	_crouch_s = lerpf(_crouch_s, _crouch, minf(1.0, dt * 6.0))
	pitch = 0.0
	roll = 0.0
	yaw = 0.0
	lift = 0.0
	scale = Vector3.ONE
	carry = Transform3D.IDENTITY
	_stride += dt * (5.0 + r.speed * 0.6)

	# Squash and stretch: stretched while falling, a squash with overshoot on landing.
	var sq_t := 0.07 if r.airborne and r.vy < -1.0 else 0.0
	sq_t -= 0.08 * _crouch_s
	var sq_w := 11.0 if base != "blob" else 8.0
	var sq_z := 0.22 if base != "blob" else 0.1
	_sq_v += (sq_w * sq_w * (sq_t - _sq) - 2.0 * sq_z * sq_w * _sq_v) * sdt
	_sq += _sq_v * sdt
	_sq = clampf(_sq, -0.35, 0.3)
	var go := sin(clampf(1.0 - _go_t / GO_S, 0.0, 1.0) * PI) if _go_t > 0.0 else 0.0
	var rear := _envelope(_rear_t, REAR_S, 0.3, 0.45)

	# Bends: wheeled bodies roll on their springs, carvers lean as a whole, boats bank a little.
	var gain := 0.016 if base in WHEELED else (0.024 if base in CARVERS else 0.006)
	var roll_t := clampf(_turn_s * r.speed * gain, -0.32, 0.32)
	_roll_v += (90.0 * (roll_t - _roll_s) - 2.0 * 0.3 * 9.5 * _roll_v) * sdt
	_roll_s += _roll_v * sdt
	var pitch_t := clampf(_a_long * 0.006, -0.07, 0.08) - 0.09 * _crouch_s + 0.12 * go
	_pitch_v += (70.0 * (pitch_t - _pitch_s) - 2.0 * 0.35 * 8.4 * _pitch_v) * sdt
	_pitch_s += _pitch_v * sdt

	if base in WHEELED:
		var rev := sin(_t * 38.0) * 0.012 * (_fidget_t / FIDGET_S + 0.7 * _crouch_s)  # revving on the grid
		var s := _sq + rev
		var b := Basis.from_euler(Vector3(_pitch_s, 0.0, _roll_s)).scaled(Vector3(1.0 - 0.5 * s, 1.0 + s, 1.0 - 0.5 * s))
		var piv := Vector3(_sway_p.x, _sway_p.y, _axle_back if _pitch_s > 0.0 else _axle_front)
		var sway := Transform3D(b, piv - b * piv)
		_sway.transform = sway
		var rx := _ride.transform
		carry = rx * sway * rx.affine_inverse()
	elif base in CARVERS:
		roll = _roll_s
		pitch = _pitch_s * 0.6
		scale = Vector3(1.0 - 0.5 * _sq, 1.0 + _sq, 1.0 - 0.5 * _sq)
	elif base == "animal4":
		_animal(rear, go, moving)
	elif base == "bird":
		_bird(rear, go, moving)
	elif base in ["boat", "sailboat"]:
		_boat(rear, moving)
	elif base == "rocket":
		_rocket(rear, go, moving)
	elif base == "blob":
		_blob(rear, go, moving, sdt)
	if base not in WHEELED and base not in CARVERS and base != "blob":
		scale = Vector3(1.0 - 0.25 * _sq, 1.0 + 0.5 * _sq, 1.0 - 0.25 * _sq)
	_parts(dt, moving, rear)
	_swing(dt, sdt)


## 0 -> 1 over `rise` s, held, 1 -> 0 over the last `fall` s of a timer counting down from `total`.
static func _envelope(left: float, total: float, rise: float, fall: float) -> float:
	if left <= 0.0:
		return 0.0
	var k := minf((total - left) / rise, left / fall)
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


func _animal(rear: float, go: float, moving: float) -> void:
	var buck := sin(clampf(1.0 - _buck_t / BUCK_S, 0.0, 1.0) * PI) if _buck_t > 0.0 else 0.0
	pitch = _rear_max * rear + 0.4 * _rear_max * go - _buck_max * buck - 0.1 * _crouch_s + _pitch_s * 0.4
	roll = _roll_s * 0.6
	if _head:
		var stomp := _fidget_t / FIDGET_S if _fidget_k == 0 else 0.0
		var shake := sin(_t * 26.0) * 0.35 * (_fidget_t / FIDGET_S) if _fidget_k == 1 else 0.0
		var hp := sin(_stride * 2.0) * 0.07 * moving + 0.4 * rear * (0.8 + 0.2 * sin(_t * 9.0)) - 0.2 * buck \
			- 0.22 * _crouch_s - 0.1 * stomp
		var hy := clampf(r.ahead_turn * 0.4, -0.35, 0.35) + shake
		_head.transform = Transform3D(Basis.from_euler(Vector3(hp, hy, shake * 0.3)), _head_rest.origin
			+ Vector3(0.0, sin(_stride * 2.0) * 0.02 * moving, 0.0))


func _bird(rear: float, go: float, moving: float) -> void:
	pitch = 0.12 * rear + 0.1 * go - 0.05 * _crouch_s
	roll = _roll_s * 0.8
	lift = 0.08 * rear * (0.5 + 0.5 * sin(_t * 8.0))
	if _head:
		# Pigeon bob while walking, looks into bends, head up at the finish.
		var bob := sin(_stride * 2.0) * 0.04 * moving
		var hp := 0.3 * rear - 0.12 * _crouch_s + sin(_stride * 2.0 + 1.0) * 0.06 * moving
		_head.transform = Transform3D(Basis.from_euler(Vector3(hp, clampf(r.ahead_turn * 0.5, -0.45, 0.45), 0.0)),
			_head_rest.origin + Vector3(0.0, 0.0, -bob))


func _boat(rear: float, moving: float) -> void:
	var rock := (0.04 + 0.03 * moving) * (1.0 + 2.0 * _rock_k + 2.5 * rear)
	if r.in_water:
		rock *= 1.4
	roll = sin(_t * 1.6) * rock + sin(_t * 2.7 + 1.3) * rock * 0.4 + _roll_s + _heel
	roll += 0.09 * rear * sin((REAR_S - _rear_t) * 6.0)  # a happy rock side to side at the finish
	pitch = sin(_t * 1.2 + 0.7) * 0.03 + 0.05 * moving - 0.12 * _rock_k * sin(_rock_k * PI) + _pitch_s * 0.5
	lift = (0.5 + 0.5 * sin(_t * 2.2)) * (0.03 + 0.05 * rear)


func _rocket(rear: float, go: float, moving: float) -> void:
	var wob := 0.015 + (0.04 if r.boost else 0.0) + 0.05 * _kick + 0.03 * _crouch_s + 0.02 * rear
	roll = sin(_t * 9.3) * wob + sin(_t * 14.1 + 0.7) * wob * 0.6 + _roll_s
	yaw = sin(_t * 7.7 + 1.1) * wob * 0.5
	pitch = sin(_t * 11.0) * wob * 0.4 + 0.12 * _kick + 0.1 * go + 0.15 * rear
	lift = (0.5 + 0.5 * sin(_t * 2.1)) * 0.04 + 0.1 * rear * (0.5 + 0.5 * sin(_t * 5.0))


## The jelly squashes about its bottom and leans out of bends; the rider rides its top.
func _blob(rear: float, go: float, moving: float, sdt: float) -> void:
	if rear > 0.0 and fmod(_rear_t, 0.5) < sdt:
		_sq_v -= 2.5  # happy bounces at the finish
	var jig := sin(_t * (6.0 + r.speed * 0.4)) * (0.03 + 0.06 * moving + 0.05 * _fidget_t / FIDGET_S) * r.bounciness
	var s := clampf(_sq + jig + 0.08 * go, -0.4, 0.35)
	var jt := clampf(-_turn_s * r.speed * 0.012, -0.16, 0.16)
	_jx_v += (64.0 * (jt - _jx) - 2.0 * 0.15 * 8.0 * _jx_v) * sdt
	_jx += _jx_v * sdt
	var sy := 1.0 + s
	var b := Basis.from_euler(Vector3(0.0, 0.0, _jx)).scaled(Vector3(1.0 - 0.5 * s, sy, 1.0 - 0.5 * s))
	var bottom := _jelly_rest.origin - Vector3(0.0, _jelly_lo, 0.0)
	_jelly.transform = Transform3D(b * _jelly_rest.basis, bottom + b * Vector3(0.0, _jelly_lo, 0.0))
	var top_rest := bottom + Vector3(0.0, _jelly_h, 0.0)
	var top_now := bottom + b * Vector3(0.0, _jelly_h, 0.0)
	var rx := _ride.transform
	carry = Transform3D(Basis.IDENTITY, rx.basis * (top_now - top_rest) * 0.9)
	roll = _roll_s * 0.5


## Legs, wings, flames, tails, wheels (the anim metas), with the reactions on top.
func _parts(dt: float, moving: float, rear: float) -> void:
	for n in r._anim["wheel_spin"]:
		if not r.airborne:
			n.rotation.x -= r.speed / maxf(float(n.get_meta("wheel_spin")), 0.05) * dt
	var buck := sin(clampf(1.0 - _buck_t / BUCK_S, 0.0, 1.0) * PI) if _buck_t > 0.0 else 0.0
	var stomp := sin(clampf(1.0 - _fidget_t / FIDGET_S, 0.0, 1.0) * PI) if _fidget_t > 0.0 and _fidget_k == 0 else 0.0
	for i in _legs.size():
		var n: Node3D = _legs[i]
		var amp := 0.12 + 0.6 * moving
		var target := sin(_t * (5.0 + r.speed * 0.6) + float(n.get_meta("leg_swing"))) * amp
		if r.airborne:
			target = 0.7
		if _leg_front[i] == 1:
			# Rearing: the front legs paw the air; a stomp on the grid; reaching out on 3-2-1.
			target = lerpf(target, 0.55 + sin(_t * 13.0 + float(n.get_meta("leg_swing"))) * 0.55, rear)
			target = lerpf(target, 0.7 * sin(_t * 18.0), stomp * (1.0 if i % 2 == 0 else 0.0))
			target += 0.25 * _crouch_s
		else:
			target = lerpf(target, -0.15, rear)
			target = lerpf(target, -0.9, buck)  # kick back on landing
			target -= 0.2 * _crouch_s
		n.rotation.x = lerpf(n.rotation.x, target, minf(1.0, dt * 20.0))
	var fold := _envelope(_fold_t, FOLD_S, 0.1, 0.35)
	var stretch := _fidget_t / FIDGET_S if _fidget_k == 1 else 0.0
	for n in _wings:
		var side := float(n.get_meta("wing_flap"))
		var flap: float
		if r.airborne and r.big_air:
			flap = sin(_t * 19.0) * 1.05  # flapping hard on a jump
		elif r.airborne or r.boost or rear > 0.0:
			flap = sin(_t * 15.0) * lerpf(0.7, 0.95, rear)
		else:
			flap = sin(_t * (4.0 + r.speed * 0.4)) * (0.15 + 0.25 * moving)
		flap = lerpf(flap, 0.9 + 0.15 * sin(_t * 5.0), stretch) + 0.25 * _crouch_s
		n.rotation = Vector3(0.0, -side * 0.85 * fold, side * (flap * (1.0 - fold) - 0.35 * fold))
	for n in r._anim["spin"]:
		n.rotation.y += float(n.get_meta("spin")) * dt
	if not _flames.is_empty():
		var want := 1.6 if r.boost else 0.6 + moving * 0.6 + 0.4 * _crouch_s
		_flare_v += (120.0 * (want - _flare) - 2.0 * 0.25 * 11.0 * _flare_v) * minf(dt, 1.0 / 30.0)
		_flare += _flare_v * minf(dt, 1.0 / 30.0)
		_flare = clampf(_flare, 0.2, 3.0)
		var puff := 0.8 * (_fidget_t / FIDGET_S) if base == "rocket" else 0.0
		var sputter := 1.0 - 0.75 * sin(_sputter_t / SPUTTER_S * PI) if _sputter_t > 0.0 else 1.0
		var f := (_flare + puff) * sputter * (1.0 + 0.15 * sin(_t * 31.0) + 0.1 * sin(_t * 17.0))
		for n in _flames:
			n.scale = Vector3(1.0, 1.0, f) * (0.9 + 0.1 * f)


## Idles and weather: tail swishes, ear flicks, sputters (timed at random per racer), the sail to
## the wind, splashes entering water, raindrops bursting on the ride.
func _idles(dt: float, sdt: float) -> void:
	var slow := r.speed < 6.0
	if not _tails.is_empty():
		_swish_t = maxf(0.0, _swish_t - dt)
		_swish_next -= dt
		if _swish_next <= 0.0:
			_swish_next = _rng.randf_range(1.5, 4.0) if slow else _rng.randf_range(4.0, 8.0)
			_swish_t = SWISH_S
	if not _ears.is_empty():
		_flick_t = maxf(0.0, _flick_t - dt)
		_flick_next -= dt
		if _flick_next <= 0.0:
			_flick_next = _rng.randf_range(0.8, 2.6)
			_flick_t = FLICK_S
			_flick_i = _rng.randi() % _ears.size()
		for i in _ears.size():
			var k := sin(_flick_t / FLICK_S * PI) if _flick_t > 0.0 and i == _flick_i else 0.0
			# Back and out, then home; pinned back while galloping fast.
			_ears[i].rotation = Vector3(-0.6 * k - 0.35 * clampf(r.speed / 15.0, 0.0, 1.0), 0.0, -_ear_side[i] * 0.5 * k)
	if not _flames.is_empty():
		_sputter_t = maxf(0.0, _sputter_t - dt)
		_sputter_next -= dt
		if _sputter_next <= 0.0:
			_sputter_next = _rng.randf_range(0.6, 2.2) if slow else _rng.randf_range(3.0, 6.0)
			_sputter_t = SPUTTER_S
			if base == "rocket":
				_kick = maxf(_kick, 0.25)  # a cough shakes it
	if _sail:
		# The boom swings out to leeward with the wind across the boat; more wind, more heel.
		var w_local := r.global_basis.inverse() * r.wind if r.is_inside_tree() else r.wind
		var want := clampf(w_local.x * 1.1, -0.9, 0.9)
		_sail_v += (16.0 * (want - _sail_s) - 2.0 * 0.3 * 4.0 * _sail_v) * sdt
		_sail_s += _sail_v * sdt
		_sail.rotation = Vector3(0.0, _sail_s, 0.0)
		_heel = -clampf(w_local.x * 0.12, -0.12, 0.12)
	if _splash:
		if r.in_water and not _was_water:
			_splash.restart()
			_splash.emitting = true
			_rock_k = 1.0
		_was_water = r.in_water
		_drops.emitting = r.rain > 0.35


## Extras, tails and the boat's pennant: springs in ride space driven like the hair's
## (RacerGestures constants): inertia, gravity on a tilted ride, head wind, weather wind.
func _swing(dt: float, sdt: float) -> void:
	if _ext.is_empty() and _tails.is_empty():
		return
	var a_toy := Vector3(-r.speed * r.turn, _a_vert, -_a_long)
	var toy_q := r.global_basis.get_rotation_quaternion() if r.is_inside_tree() else Quaternion.IDENTITY
	var push := toy_q.inverse() * (Gestures.GRAVITY + r.wind * Gestures.WIND_ACC) - a_toy \
		+ Vector3(0.0, -r.vy * 0.4, r.speed * Gestures.AIR_K)
	var rq := (r.rig.basis * r.model.basis).get_rotation_quaternion()
	var df := (rq.inverse() * push - Gestures.GRAVITY) * Gestures.HAIR_GAIN
	var w := Gestures.SPRING_W
	_v_spring += (df - _d_spring) * (w * w * sdt) - _v_spring * (2.0 * Gestures.SPRING_Z * w * sdt)
	_d_spring += _v_spring * sdt
	w = Gestures.SOFT_W
	_v_soft += (df - _d_soft) * (w * w * sdt) - _v_soft * (2.0 * Gestures.SOFT_Z * w * sdt)
	_d_soft += _v_soft * sdt
	var wind := r.wind.length()
	var flutter := 0.1 * wind + 0.012 * r.speed
	for j in _ext.size():
		var d := _d_spring if _ext_flag[j] == 0 else _d_soft
		if _ext_flag[j] == 1:
			var ph := _ext_phase[j]
			d += Vector3(sin(_t * 9.0 + ph), 0.3 * sin(_t * 6.3 + ph * 2.0), cos(_t * 10.3 + ph)) * flutter
		var th := _ext_d0[j].cross(d) * _ext_gain[j]
		var mx := _ext_max[j]
		var l2 := th.length_squared()
		if l2 > mx * mx:
			th *= mx / sqrt(l2)
		_ext[j].rotation = _ext_base[j] + th
	var moving := clampf(r.speed / 10.0, 0.0, 1.0)
	var wag := sin(_t * (5.0 + r.speed * 0.5)) * (0.25 + 0.2 * moving + 0.3 * _rear_t / REAR_S)
	if _swish_t > 0.0:
		# A big swish: one and a half sweeps, peaking mid-way.
		wag = lerpf(wag, sin((SWISH_S - _swish_t) / SWISH_S * TAU * 1.5) * 0.8, sin(_swish_t / SWISH_S * PI))
	var th2 := Vector3(0, 0, 1).cross(_d_soft) * 1.0
	th2 = th2.limit_length(0.5)
	for n in _tails:
		n.rotation = Vector3(th2.x, wag + th2.y, th2.z)

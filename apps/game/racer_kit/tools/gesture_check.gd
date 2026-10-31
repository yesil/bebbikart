extends SceneTree
## Headless check of the gesture and ride layers (racer_gestures.gd, ride_motion.gd) on every
## racer we have: the samples, data/pkg_default and every spec the designer wrote under
## packages/asset-pipeline/out*/. Each racer gets every gesture and driven event, stepped 4 s at
## 60 Hz, and fails on:
##   - a NaN / infinite transform on a node the layers move
##   - a ride reaction that does not show (RIDE_EXPECT: a pony that does not rear at the finish,
##     wings that do not fold on landing, a kart body that does not roll in a bend ...), or a ride
##     not back at rest once it is over
##   - hands not back at rest (on the handle, or hanging) once the gesture is over
##   - the head turned past RacerGestures' limits
##   - an elbow or forearm deep inside the head or body (ARM_FAIL; ARM_BURY counts the shallow ones)
##   - any part of the racer below the ground
##   - snap_pose() not giving back the exact built pose
##   - both layers together costing more than MAX_US per racer per frame (busiest state, mean)
## Exit code 1 on any failure.
##
##   godot --headless --path apps/game --script res://racer_kit/tools/gesture_check.gd

const Gestures = preload("res://racer_kit/racer_gestures.gd")
const DT := 1.0 / 60.0
const EVENT_S := 3.0
const SETTLE_S := 1.0
const HAND_TOL := 0.01       # m (Model space) / Character units for hanging hands
const GROUND_TOL := 0.02
const MAX_US := 50.0
const EVENTS := ["wave", "cheer", "fist_pump", "glance_back", "slump", "dizzy", "brace", "surprised",
	"head_shake", "flail", "wheee", "tuck", "rain", "hat_hold",
	"ready", "tap", "scratch", "stretch", "salute", "clap", "bow", "spin", "peek", "twirl", "jive",
	"taunt", "whoop", "flinch", "high_five", "shake_fist", "fist_bump",
	"state:rain", "state:wind", "state:air", "state:slip", "state:water", "state:boost",
	"bump", "land", "fail", "celebrate", "finish", "look", "drive", "grid", "signature",
	"mood:grumpy", "mood:cocky", "idle"]
## In-game face expressions each event must show at some point (RacerFace.EXPRESSIONS).
const FACE := {"flinch": "eek", "surprised": "eek", "taunt": "smug", "shake_fist": "smug",
	"mood:grumpy": "grumpy", "mood:cocky": "smug"}
## Arm points (elbow, mid upper arm, forearm) deeper than this inside the head or body (0 at the
## surface, 1 at the centre) count as an arm through them.
const ARM_BURY := 0.12
const ARM_FAIL := 0.3        # this deep fails the check

var failures := 0
var arm_events := 0
var arm_buried := 0
var verbose_arms := "--arms" in OS.get_cmdline_user_args()
var total_us := 0.0
var total_frames := 0
var worst_us := 0.0
var worst_name := ""


var _started := false


## Runs on the first frame: in _initialize the root is not in the tree yet (no global transforms).
func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_run()
	return false


func _run() -> void:
	var files := _spec_files()
	var t0 := Time.get_ticks_msec()
	for f in files:
		_check(f)
	print("%d racers x %d events, %d failures, gesture + ride layers %.1f us/racer/frame (worst %s %.1f us), %.1f s" % [
		files.size(), EVENTS.size(), failures, total_us / maxi(1, total_frames), worst_name, worst_us,
		(Time.get_ticks_msec() - t0) / 1000.0])
	print("arms through the head or body (deeper than %.2f): %d of %d racer events" % [ARM_BURY, arm_buried, arm_events])
	quit(1 if failures > 0 else 0)


func _spec_files() -> PackedStringArray:
	var dirs := SpecFolders.dirs(OS.get_cmdline_user_args())
	var pipeline := SpecFolders.ws5_dir().get_base_dir()
	var da := DirAccess.open(pipeline)
	if da == null:
		_fail("-", "setup", "cannot open " + pipeline)
	else:
		for d in da.get_directories():
			if d.begins_with("out") and pipeline.path_join(d) not in dirs:
				dirs.append(pipeline.path_join(d))
	var out := PackedStringArray()
	for d in dirs:
		out.append_array(SpecFolders.list(d))
	out.append(KitCatalog.PKG_DEFAULT_PATH)
	return out


func _fail(who: String, event: String, why: String) -> void:
	failures += 1
	print("FAIL  %-44s %-12s %s" % [who, event, why])


func _check(path: String) -> void:
	var who := path.get_base_dir().get_file() + "/" + path.get_file()
	var raw := RacerSpec.load_file(path)
	var r := RacerBuilder.build(raw) if not raw.is_empty() else null
	if r == null:
		_fail(who, "build", "does not build: " + ", ".join(RacerBuilder.last_errors))
		return
	root.add_child(r)
	var g: Gestures = r.gestures
	if not g.ok or not r.ride.ok:
		_fail(who, "setup", (g.error + " " + r.ride.error).strip_edges())
		r.free()
		return
	var rest := _snapshot(r)
	var bad := 0
	for ev in EVENTS:
		r.snap_pose()
		r.set_auto_mood()
		_fire(r, ev, true)
		var steps := int((EVENT_S + SETTLE_S) / DT)
		var broke := false
		var ext := {}
		for i in steps:
			if i == int(1.5 / DT):
				_fire(r, ev, false)  # held states end
			r._process(DT)
			_ride_extremes(r, ext)
			_arm_bury(r, ext)
			if r.face and r.face.expression != "":
				ext["face:" + r.face.expression] = 1.0
			var why := _frame_problem(r, i % 15 == 0)
			if why != "":
				_fail(who, ev, "t=%.2f s: %s" % [i * DT, why])
				bad += 1
				broke = true
				break
		if bad > 3:
			break
		if broke:
			continue
		var why2 := _hands_problem(r)
		if why2 == "":
			why2 = _ride_problem(r, ev, ext)
		if why2 != "":
			_fail(who, ev, why2)
			bad += 1
	r.snap_pose()
	var why3 := _pose_diff(r, rest)
	if why3 != "":
		_fail(who, "snap_pose", why3)
	_time(r, who)
	if bad == 0 and why3 == "":
		print("ok    %-44s %-8s grip=%-5s swings=%d" % [who, r.spec.ride.base, g.grip, g._sw_node.size()])
	r.free()


func _fire(r: ToyRacer, ev: String, on: bool) -> void:
	if ev.begins_with("mood:"):
		r.gestures.mood_mem = (-1.0 if ev == "mood:grumpy" else 1.0) if on else 0.0
		return
	if ev == "idle":
		return  # standing still: the ride's idles (swishes, flicks, sputters)
	if ev.begins_with("state:") or ev == "drive" or ev == "grid":
		match ev:
			"state:rain": r.rain = 1.0 if on else 0.0
			"state:wind": r.wind = Vector3(0.7, 0.0, -0.5) if on else Vector3.ZERO
			"state:air":
				r.airborne = on
				r.big_air = on
				r.vy = 2.0 if on else 0.0
			"state:slip": r.slipping = on
			"state:water": r.in_water = on
			"state:boost":
				r.boost = on
				r.speed = 18.0 if on else 0.0
			"grid":
				# Waiting on the grid: crouch as the lights count down, then green.
				r.gestures.hold(Gestures.G.READY, on)
				r.ride.crouch(1.0 if on else 0.0)
				if not on:
					r.gestures.play(Gestures.G.WHOOP)
					r.ride.go()
			"drive":
				r.speed = 15.0 if on else 0.0
				r.turn = 0.9 if on else 0.0
				r.ahead_turn = 0.6 if on else 0.0
				r.lean = 0.6 if on else 0.0
		return
	if not on:
		return
	match ev:
		"bump": r.bump()
		"land": r.land()
		"fail": r.fail()
		"celebrate": r.celebrate(3)
		"finish": r.finish()
		"signature": r.signature()
		"high_five": r.gestures.high_five(r.global_position + r.global_basis.x * 0.9 + Vector3.UP * 1.1, 1)
		"fist_bump": r.gestures.fist_bump(r.global_position + r.global_basis.x * 0.9 + Vector3.UP * 0.9, 1)
		"look": r.look_at_point(r.global_position + Vector3(-3.0, 1.5, 2.0), 2.0)
		_: r.gesture(ev)


func _nodes(r: ToyRacer) -> Array:
	var g: Gestures = r.gestures
	var out: Array = [r.rig, r.character, r.head_pivot]
	out.append_array(g._arm)
	out.append_array(g._elbow)
	out.append_array(g._hand)
	out.append_array(g._sw_node)
	out.append_array(g._palm)
	out.append_array(r.ride.nodes())
	if r.face:
		out.append_array(r.face._eyes)
		out.append_array(r.face._brows)
		out.append_array(r.face._pupil_all.filter(func(pu): return pu not in r.face._pupils))  # googly ones wobble
		out.append_array(r.face._mouths.values())
	return out


func _frame_problem(r: ToyRacer, ground: bool) -> String:
	for n in _nodes(r):
		var xf: Transform3D = n.transform
		if not xf.is_finite():
			return "non-finite transform on " + str(n.name)
	var hr := r.head_pivot.rotation
	if absf(hr.y) > Gestures.YAW_MAX + 1e-3 or hr.x < Gestures.PITCH_MIN - 1e-3 or hr.x > Gestures.PITCH_MAX + 1e-3 \
			or absf(hr.z) > Gestures.ROLL_MAX + 1e-3:
		return "head beyond limits: " + str(hr)
	if ground:
		_low = INF
		_low_name = ""
		_lowest(r, Transform3D.IDENTITY)
		if _low < -GROUND_TOL:
			return "part below the ground: y %.3f (%s)" % [_low, _low_name]
	return ""


var _low := INF
var _low_name := ""


## Lowest mesh point under n, in the racer's space. Spinning wheels and swinging legs count at
## their rest transform: a turned box around a round wheel is not the wheel.
func _lowest(n: Node, xf: Transform3D) -> void:
	for c in n.get_children():
		if not c is Node3D or c is Label3D:
			continue
		var cx: Transform3D = xf * (c.get_meta("rest") as Transform3D if c.has_meta("rest") else c.transform)
		if c is MeshInstance3D and c.mesh and c.visible:
			var y: float = (cx * c.mesh.get_aabb()).position.y
			if y < _low:
				_low = y
				_low_name = str(c.get_parent().name) + "/" + str(c.name)
		_lowest(c, cx)


## Largest ride motions seen during an event (rig pitch / roll / squash, the Sway, wings, jelly, flames).
func _ride_extremes(r: ToyRacer, e: Dictionary) -> void:
	var rb := r.rig.basis
	var eu := rb.get_euler()
	_mx(e, "pitch", eu.x)
	_mx(e, "-pitch", -eu.x)
	_mx(e, "roll", absf(eu.z))
	_mx(e, "-sy", -rb.get_scale().y)
	var m = r.ride
	if m._sway:
		_mx(e, "sway_roll", absf(m._sway.basis.get_euler().z))
		_mx(e, "-sway_sy", -m._sway.basis.get_scale().y)
	if m._jelly:
		_mx(e, "-jelly_sy", -m._jelly.basis.get_scale().y)
		_mx(e, "jelly_lean", absf(m._jelly.basis.get_euler().z))
	for w in m._wings:
		_mx(e, "wing_fold", absf(w.rotation.y))
		_mx(e, "wing_flap", absf(w.rotation.z))
	for f in m._flames:
		_mx(e, "flame", f.scale.z)
		_mx(e, "-flame", -f.scale.z)
	for n in m._tails:
		_mx(e, "swish", absf(n.rotation.y))
	for n in m._ears:
		_mx(e, "flick", absf(n.rotation.x))
	if m._sail:
		_mx(e, "sail", absf(m._sail.rotation.y))
	if m._splash and m._splash.emitting:
		_mx(e, "splash", 1.0)
	if m._drops and m._drops.emitting:
		_mx(e, "drops", 1.0)


static func _mx(e: Dictionary, k: String, v: float) -> void:
	e[k] = maxf(float(e.get(k, -INF)), v)


## Per event and ride: [extreme, at least, what it shows]. "-x" keys are negated minima.
func _ride_expect(r: ToyRacer, ev: String) -> Array:
	var m = r.ride
	var out: Array = []
	var wheeled: bool = m.base in m.WHEELED
	var carver: bool = m.base in m.CARVERS
	match ev:
		"finish":
			if m.base == "animal4" and m._rear_max > 0.15:
				out.append(["pitch", m._rear_max * 0.7, "rears up"])
			if m.base == "blob":
				out.append(["-jelly_sy", -0.9, "bounces"])
			if m.base in ["boat", "sailboat"]:
				out.append(["roll", 0.06, "rocks"])
			if not m._wings.is_empty():
				out.append(["wing_flap", 0.6, "flaps"])
		"land":
			if wheeled:
				out.append(["-sway_sy", -0.93, "squashes its body"])
			if carver:
				out.append(["-sy", -0.95, "squashes"])
			if m.base == "animal4" and m._buck_max > 0.05:
				out.append(["-pitch", m._buck_max * 0.6, "bucks"])
			if m.base == "blob":
				out.append(["-jelly_sy", -0.85, "wobbles"])
			if not m._wings.is_empty():
				out.append(["wing_fold", 0.5, "folds its wings"])
		"drive":
			if wheeled:
				out.append(["sway_roll", 0.08, "rolls into the bend"])
			if carver:
				out.append(["roll", 0.15, "carves into the bend"])
			if m.base == "blob":
				out.append(["jelly_lean", 0.06, "leans out of the bend"])
		"grid":
			if wheeled:
				out.append(["-sway_sy", -0.96, "crouches on its wheels"])
			if m.base == "animal4":
				out.append(["-pitch", 0.05, "crouches"])
		"idle":
			if not m._tails.is_empty() and m._tails[0].has_meta("tail_wag"):
				out.append(["swish", 0.6, "swishes its tail"])
			if not m._ears.is_empty():
				out.append(["flick", 0.3, "flicks an ear"])
			if not m._flames.is_empty():
				out.append(["-flame", -0.45, "sputters"])
		"state:wind":
			if m._sail:
				out.append(["sail", 0.2, "swings its sail out to the wind"])
		"state:water":
			out.append(["splash", 1.0, "splashes"])
		"state:rain":
			out.append(["drops", 1.0, "gets rain drops bursting on it"])
		"state:air":
			if not m._wings.is_empty():
				out.append(["wing_flap", 0.9, "flaps hard"])
		"state:boost":
			if not m._flames.is_empty():
				out.append(["flame", 1.8, "flares"])
	return out


## Deepest an elbow, upper arm or forearm went into the head (padded as the layer pads it, less
## the arm's own thickness) or an elbow / forearm into the body, while a gesture moved the arm.
func _arm_bury(r: ToyRacer, e: Dictionary) -> void:
	var g: Gestures = r.gestures
	if g.is_idle():
		return
	var ci := r.character.global_transform.affine_inverse()
	var hr: Vector3 = g._head_r - Vector3.ONE * 0.04
	for i in 2:
		var s: Vector3 = g._shoulder[i]
		var el: Vector3 = ci * g._elbow[i].global_position
		var ha: Vector3 = ci * g._hand[i].global_position
		var d := 0.0
		for p in [s.lerp(el, 0.6), el, el.lerp(ha, 0.5), el.lerp(ha, 0.75)]:
			d = maxf(d, Gestures._buried(p, g._head_c_now, hr))
		for p in [el, el.lerp(ha, 0.4)]:
			d = maxf(d, Gestures._buried(p, g._body_c, g._body_r - Vector3.ONE * 0.04))
		_mx(e, "arm_bury", d)


func _ride_problem(r: ToyRacer, ev: String, ext: Dictionary) -> String:
	arm_events += 1
	var bury := float(ext.get("arm_bury", 0.0))
	if bury > ARM_BURY:
		arm_buried += 1
		if verbose_arms:
			print("arm   %-44s %-12s %.2f" % [r.spec.get("title", "?"), ev, bury])
	if bury > ARM_FAIL:
		return "arm through the head or body: %.2f deep (limit %.2f)" % [bury, ARM_FAIL]
	if FACE.has(ev) and not ext.has("face:" + str(FACE[ev])) and r.face:
		return "face never showed \"%s\" (expressions seen: %s)" % [FACE[ev], ", ".join(ext.keys().filter(func(k): return str(k).begins_with("face:")))]
	for x in _ride_expect(r, ev):
		var got := float(ext.get(x[0], -INF))
		if got < float(x[1]):
			return "ride reaction missing: %s %s (%s %.3f, want >= %.3f)" % [r.ride.base, x[2], x[0], got, x[1]]
	var m = r.ride
	if m._sway and absf(m._sway.basis.get_euler().z) > 0.02:
		return "ride not back at rest: Sway still rolled %.3f" % m._sway.basis.get_euler().z
	for w in m._wings:
		if absf(w.rotation.y) > 0.02:
			return "ride not back at rest: wings still folded %.3f" % w.rotation.y
	return ""


func _hands_problem(r: ToyRacer) -> String:
	var g: Gestures = r.gestures
	if not g.is_idle():
		var on := PackedStringArray()
		for k in Gestures.NAMES:
			if g.weight(Gestures.NAMES[k]) > 0.0:
				on.append(k)
		return "gestures still playing after %.1f s: %s" % [EVENT_S + SETTLE_S, ", ".join(on)]
	var minv := r.model.global_transform.affine_inverse()
	var cinv := r.character.global_transform.affine_inverse()
	for i in 2:
		var hand: Vector3 = g._hand[i].global_position
		var err: float
		if g.grip:
			err = (minv * hand).distance_to(g._grip_model[i])
		else:
			err = (cinv * hand).distance_to(g._hand_rest[i])
		if err > HAND_TOL:
			return "%s hand %.3f off its rest place" % ["left" if i == 0 else "right", err]
	return ""


func _snapshot(r: ToyRacer) -> Array:
	var out: Array = []
	for n in _nodes(r):
		out.append(n.transform)
	return out


func _pose_diff(r: ToyRacer, rest: Array) -> String:
	var nodes := _nodes(r)
	for i in nodes.size():
		var a: Transform3D = nodes[i].transform
		var b: Transform3D = rest[i]
		if not a.is_equal_approx(b):
			return "%s not at its built transform" % nodes[i].name
	return ""


## Mean cost of one gesture update in a busy state: driving into a bend in rain and wind while
## cheering (arms, look, lean, every swing piece working).
func _time(r: ToyRacer, who: String) -> void:
	r.snap_pose()
	r.set_auto_mood()
	r.speed = 14.0
	r.turn = 0.8
	r.ahead_turn = 0.5
	r.rain = 1.0
	r.wind = Vector3(0.6, 0.0, 0.3)
	r.celebrate(3)
	for i in 30:
		r._process(DT)
	var g: Gestures = r.gestures
	var n := 240
	var t0 := Time.get_ticks_usec()
	for i in n:
		r.ride.update(DT)
		g.update(DT)
	var us := float(Time.get_ticks_usec() - t0) / n
	total_us += us * n
	total_frames += n
	if us > worst_us:
		worst_us = us
		worst_name = who
	if us > MAX_US:
		_fail(who, "cpu", "%.1f us per update (limit %.0f)" % [us, MAX_US])

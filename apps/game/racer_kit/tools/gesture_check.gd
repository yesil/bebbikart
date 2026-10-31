extends SceneTree
## Headless check of the gesture layer (racer_gestures.gd) on every racer we have: the samples,
## data/pkg_default and every spec the designer wrote under packages/asset-pipeline/out*/. Each
## racer gets every gesture and driven event, stepped 4 s at 60 Hz, and fails on:
##   - a NaN / infinite transform on a node the layer moves
##   - hands not back at rest (on the handle, or hanging) once the gesture is over
##   - the head turned past RacerGestures' limits
##   - any part of the racer below the ground
##   - snap_pose() not giving back the exact built pose
##   - the layer costing more than MAX_US per racer per frame (busiest state, mean)
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
	"state:rain", "state:wind", "state:air", "state:slip", "state:water", "state:boost",
	"bump", "land", "fail", "celebrate", "finish", "look", "drive"]

var failures := 0
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
	print("%d racers x %d events, %d failures, gesture layer %.1f us/racer/frame (worst %s %.1f us), %.1f s" % [
		files.size(), EVENTS.size(), failures, total_us / maxi(1, total_frames), worst_name, worst_us,
		(Time.get_ticks_msec() - t0) / 1000.0])
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
	if not g.ok:
		_fail(who, "setup", g.error)
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
		for i in steps:
			if i == int(1.5 / DT):
				_fire(r, ev, false)  # held states end
			r._process(DT)
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
	if ev.begins_with("state:") or ev == "drive":
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
		"look": r.look_at_point(r.global_position + Vector3(-3.0, 1.5, 2.0), 2.0)
		_: r.gesture(ev)


func _nodes(r: ToyRacer) -> Array:
	var g: Gestures = r.gestures
	var out: Array = [r.rig, r.character, r.head_pivot]
	out.append_array(g._arm)
	out.append_array(g._elbow)
	out.append_array(g._hand)
	out.append_array(g._sw_node)
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
		g.update(DT)
	var us := float(Time.get_ticks_usec() - t0) / n
	total_us += us * n
	total_frames += n
	if us > worst_us:
		worst_us = us
		worst_name = who
	if us > MAX_US:
		_fail(who, "cpu", "%.1f us per update (limit %.0f)" % [us, MAX_US])

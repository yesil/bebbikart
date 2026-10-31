extends SceneTree
## Headless check of world/camera_director.gd, the big screen's racer switching:
##   godot --headless --path apps/game --script res://tools/camera_check.gd
## Prints every broken expectation and exits 1 if there is one.

const CameraDirector = preload("res://world/camera_director.gd")
const DT := 0.125  # exact in binary, so the sums of steps are too


class FakeRacer:
	var run_id := ""
	var airborne := false
	var looping := false
	var p := 0.3

	func _init(id: String) -> void:
		run_id = id

	func progress() -> float:
		return p


var fails: PackedStringArray = []


func _initialize() -> void:
	_one_racer_stays()
	_two_racers_alternate()
	_new_racer_waits_its_turn()
	_never_mid_jump()
	_never_to_a_finishing_racer()
	_leaving_racer_cuts_at_once()
	_phone_requests_queue()
	_keys_and_lock()
	_interval_zero_never_switches()
	if fails.is_empty():
		print("camera_check: all good")
		quit(0)
		return
	for f in fails:
		printerr("camera_check: " + f)
	quit(1)


func _expect(ok: bool, what: String) -> void:
	if not ok:
		fails.append(what)


## Runs the director for `seconds`; returns [[time, run_id, reason], ...] for every cut.
func _run(d: CameraDirector, racers: Array, seconds: float, t0 := 0.0) -> Array:
	var cuts: Array = []
	var t := t0
	for i in int(round(seconds / DT)):
		t += DT
		d.update(DT, racers)
		if d.changed:
			cuts.append([t, d.run_id, d.reason])
	return cuts


func _ids(cuts: Array) -> Array:
	return cuts.map(func(c): return c[1])


func _one_racer_stays() -> void:
	var d := CameraDirector.new()
	var cuts := _run(d, [FakeRacer.new("a")], 30.0)
	_expect(_ids(cuts) == ["a"], "one racer: expected one cut to a, got %s" % [cuts])
	_expect(d.next_in() < 0.0, "one racer: no switch should be coming")


func _two_racers_alternate() -> void:
	var d := CameraDirector.new()
	var a := FakeRacer.new("a")
	var b := FakeRacer.new("b")
	var cuts := _run(d, [a, b], 25.0)
	_expect(_ids(cuts) == ["a", "b", "a", "b"], "two racers: expected a b a b, got %s" % [cuts])
	if cuts.size() >= 3:
		_expect(is_equal_approx(cuts[1][0], 8.125) and is_equal_approx(cuts[2][0], 16.125),
			"two racers: cuts should be 8 s apart, got %s" % [cuts])


func _new_racer_waits_its_turn() -> void:
	var d := CameraDirector.new()
	var racers: Array = [FakeRacer.new("a"), FakeRacer.new("b")]
	var cuts := _run(d, racers, 5.0)
	racers.append(FakeRacer.new("c"))  # starts at 5 s: b (waiting since 0 s) goes first
	cuts += _run(d, racers, 15.0, 5.0)
	_expect(_ids(cuts) == ["a", "b", "c"], "new racer: expected a b c, got %s" % [cuts])


func _never_mid_jump() -> void:
	var d := CameraDirector.new()
	var a := FakeRacer.new("a")
	var b := FakeRacer.new("b")
	_run(d, [a, b], 7.0)
	a.airborne = true
	var cuts := _run(d, [a, b], 1.5, 7.0)
	_expect(cuts.is_empty(), "jump: cut while airborne at %s" % [cuts])
	a.airborne = false
	cuts = _run(d, [a, b], 0.3, 8.5)
	_expect(_ids(cuts) == ["b"], "jump: expected the cut right after landing, got %s" % [cuts])
	# A jump that never lands (stuck flag) still gets cut after MAX_AIR_WAIT_S.
	b.airborne = true
	cuts = _run(d, [a, b], CameraDirector.DEFAULT_CYCLE_S + CameraDirector.MAX_AIR_WAIT_S + 0.5)
	_expect(_ids(cuts) == ["a"], "long jump: expected a cut after the wait, got %s" % [cuts])


func _never_to_a_finishing_racer() -> void:
	var d := CameraDirector.new()
	var a := FakeRacer.new("a")
	var b := FakeRacer.new("b")
	b.p = 0.97
	var cuts := _run(d, [a, b], 20.0)
	_expect(_ids(cuts) == ["a"], "finishing: b is about to finish and should get no shot, got %s" % [cuts])
	var c := FakeRacer.new("c")
	c.looping = true
	c.p = 0.99  # a loop racer near the line is mid-run, not finishing
	cuts = _run(d, [a, c], 5.0)
	_expect(_ids(cuts) == ["c"], "loop: c should get a shot, got %s" % [cuts])


func _leaving_racer_cuts_at_once() -> void:
	var d := CameraDirector.new()
	var a := FakeRacer.new("a")
	var b := FakeRacer.new("b")
	_run(d, [a, b], 2.0)
	var cuts := _run(d, [b], 0.1, 2.0)
	_expect(cuts.size() == 1 and cuts[0][1] == "b" and cuts[0][2] == "left",
		"leaving: expected an immediate cut to b, got %s" % [cuts])
	cuts = _run(d, [], 0.1, 2.1)
	_expect(cuts.size() == 1 and cuts[0][1] == "", "empty course: expected a cut to nobody, got %s" % [cuts])


func _phone_requests_queue() -> void:
	var d := CameraDirector.new()
	var racers: Array = [FakeRacer.new("a"), FakeRacer.new("b"), FakeRacer.new("c"), FakeRacer.new("d")]
	_run(d, racers, 1.0)
	_expect(d.request("d"), "phone: d's request should be taken")
	_expect(d.request("c"), "phone: c's request should be taken")
	_expect(not d.request("c"), "phone: a second request from c is not queued twice")
	_expect(not d.request("a"), "phone: a is on camera already")
	var cuts := _run(d, racers, 9.0, 1.0)
	# a's shot began at 0.125 s: d once it is MIN_SHOT_S old, c 3 s later, then c keeps the
	# camera for a full interval.
	_expect(cuts.size() >= 2 and cuts[0][1] == "d" and cuts[0][2] == "phone" and is_equal_approx(cuts[0][0], 3.125),
		"phone: expected d at 3.125 s, got %s" % [cuts])
	_expect(cuts.size() >= 2 and cuts[1][1] == "c" and is_equal_approx(cuts[1][0], 6.125),
		"phone: expected c at 6.125 s, got %s" % [cuts])
	_expect(cuts.size() == 2, "phone: c should keep the camera a full interval, got %s" % [cuts])


func _keys_and_lock() -> void:
	var d := CameraDirector.new()
	var racers: Array = [FakeRacer.new("a"), FakeRacer.new("b"), FakeRacer.new("c")]
	_run(d, racers, 1.0)
	d.step(1, racers)
	_expect(d.run_id == "b" and d.reason == "key", "Tab: expected b, got %s" % d.run_id)
	d.step(-1, racers)
	d.step(-1, racers)
	_expect(d.run_id == "c", "Shift+Tab twice from b: expected c, got %s" % d.run_id)
	d.auto = false
	var cuts := _run(d, racers, 30.0, 1.0)
	_expect(cuts.is_empty(), "A (locked): expected no cuts, got %s" % [cuts])
	_expect(d.next_in() < 0.0, "A (locked): no switch should be coming")
	d.auto = true
	cuts = _run(d, racers, 0.2, 31.0)
	_expect(cuts.size() == 1, "A (unlocked): an overdue switch should happen at once, got %s" % [cuts])


func _interval_zero_never_switches() -> void:
	var d := CameraDirector.new()
	d.cycle_s = 0.0
	var cuts := _run(d, [FakeRacer.new("a"), FakeRacer.new("b")], 30.0)
	_expect(_ids(cuts) == ["a"], "interval 0: expected only the first cut, got %s" % [cuts])

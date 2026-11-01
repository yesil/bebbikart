extends SceneTree
## Headless check of the duel's verdicts (main.gd _duel_verdict, DuelHud.result) in the real mock
## race: while a half shows a lap's verdict ("NEW CHAMPION!", the time, OOPS!), the racer that
## drove that lap is still in its shot (KitRacerView.leave keeps it for the verdict's time).
## Fails if a verdict stands over an empty half for more than MAX_EMPTY_S, or if no verdict
## showed at all. main.gd reads the same user args (pass --kit).
##   godot --headless --fixed-fps 60 --path apps/game --script res://tools/verdict_check.gd \
##     -- --kit --racers=4 [--secs=240]

const MAX_EMPTY_S := 0.2

var _main: Node
var _secs := 240.0
var _t := 0.0
var _done := false
var _on := {"left": false, "right": false}       # side -> its verdict shows
var _empty := {"left": 0.0, "right": 0.0}        # side -> seconds of this verdict without the racer
var _verdicts := 0
var _empty_total := 0.0
var _worst := 0.0
var problems: PackedStringArray = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			_secs = float(a.trim_prefix("--secs="))
	_main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main


func _process(delta: float) -> bool:
	if _done or _main.get("duel_hud") == null:
		return false
	_t += delta
	for side in ["left", "right"]:
		var h: Dictionary = _main.duel_hud._halves[side]
		var shows: bool = h["verdict"].is_visible_in_tree() and h["verdict_big"].text != ""
		if shows:
			if not _on[side]:
				_verdicts += 1
				_empty[side] = 0.0
			if not _racer_in(side):
				_empty[side] += delta
		elif _on[side]:
			_verdict_over(side)
		_on[side] = shows
	if _t >= _secs:
		_done = true
		_report()
	return false


## Some run of this half (main.gd's duel_sides; full screen: all on the left) still has its view.
func _racer_in(side: String) -> bool:
	for rid in _main.duel_sides:
		var s: String = _main.duel_sides[rid] if _main.duel_screen.split else "left"
		if s == side and _main._view_of(rid) != null:
			return true
	return false


func _verdict_over(side: String) -> void:
	var e: float = _empty[side]
	print("%s half verdict over, %.2f s of it without the racer" % [side, e])
	_empty_total += e
	_worst = maxf(_worst, e)
	if e > MAX_EMPTY_S:
		problems.append("verdict over an empty %s half for %.2f s (limit %.1f s)" % [side, e, MAX_EMPTY_S])


func _report() -> void:
	for side in _on:
		if _on[side]:
			_verdict_over(side)  # still showing as the check ends
	print("verdicts in %.0f s: %d, %.2f s of them over an empty half in all, worst %.2f s" % [_secs, _verdicts, _empty_total, _worst])
	if _verdicts == 0:
		problems.append("no verdict showed in %.0f s" % _secs)
	if problems.is_empty():
		print("VERDICT CHECK PASSED")
	else:
		for p in problems:
			print("FAIL ", p)
		print("VERDICT CHECK FAILED (%d problems)" % problems.size())
	# The game goes first, and the audio thread drops its stopped music and engines on its next mix:
	# quitting at once leaks their streams. Real time: with --fixed-fps a game-time timer runs out
	# before the audio thread mixes again.
	_main.free()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300:
		await process_frame
	quit(0 if problems.is_empty() else 1)

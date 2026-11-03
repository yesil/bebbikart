extends SceneTree
## Headless check of the race-end sounds (audio/audio_director.gd) in the real mock race: every
## lap that ends gets its verdict's cue (main.gd _verdict -> AudioDirector.VERDICT_CUE), cues never
## stack (a smaller one never starts while a bigger or equal one sounds), the music dips under a
## cue to its depth and comes back after it, the crowd cheers come at their times, and the podium
## at a session's end gets its fanfare. main.gd reads the same user args (pass --kit).
##   godot --headless --fixed-fps 60 --path apps/game --script res://tools/end_sound_check.gd \
##     -- --kit --racers=4 [--secs=240]
## Exits 1 if a rule is broken or no lap ended. Game time throughout (the director's _now).

const AudioDirector = preload("res://audio/audio_director.gd")

const DIP_SLACK_DB := 0.6       # the dip reaches its depth within this
const DIP_IN_S := 0.3           # ... this long after the cue starts
const BACK_S := 2.5             # after a cue (and a pending music switch) the music is back within

var _main: Node
var _secs := 240.0
var _t := 0.0
var _done := false
var _dips: Array = []           # [t, dip dB] per frame (director time)
var problems: PackedStringArray = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--secs="):
			_secs = float(a.trim_prefix("--secs="))
	_main = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	current_scene = _main


func _process(delta: float) -> bool:
	if _done or _main.get("audio") == null or _main.audio.get("_dip") == null:
		return false
	_t += delta
	_dips.append([_main.audio._now, _main.audio._dip.volume_db])
	if _t >= _secs:
		_done = true
		_finish()
	return false


func _finish() -> void:
	var audio = _main.audio
	# The session ends: the podium (mock mode keeps its own bests) and its fanfare.
	_main.hud.set_session("running")
	_main.hud.set_session("ended")
	var podium := false
	for e in audio.cue_log:
		if e["what"] == "cue" and e["kind"] == "podium":
			podium = true
	if _main.hud._podium == null:
		problems.append("no podium showed at the session's end (did no lap finish?)")
	elif not podium:
		problems.append("the podium showed without its fanfare")
	_check_log(audio.cue_log)
	_report()


func _check_log(entries: Array) -> void:
	var counts := {}
	var last_cue := {}              # the cue playing (or last played)
	var cues := {}                  # id -> its cue entry
	var cut := {}                   # id -> true if a bigger cue cut it off
	var ends := 0
	for i in entries.size():
		var e: Dictionary = entries[i]
		match String(e["what"]):
			"run_end":
				ends += 1
				var want: String = AudioDirector.VERDICT_CUE[e["verdict"]]
				var next: Dictionary = entries[i + 1] if i + 1 < entries.size() else {}
				if next.is_empty() or not String(next["what"]) in ["cue", "left_out"] or next["kind"] != want \
						or absf(float(next["t"]) - float(e["t"])) > 0.001:
					problems.append("run %s ended %s at %.2f s but its %s cue neither played nor was left out (next: %s)" % [e["run"], e["verdict"], e["t"], want, JSON.stringify(next)])
			"cue":
				counts[e["kind"]] = int(counts.get(e["kind"], 0)) + 1
				if not last_cue.is_empty() and float(e["t"]) < float(last_cue["t"]) + float(last_cue["len"]):
					if int(e["rank"]) <= int(last_cue["rank"]):
						problems.append("%s cue at %.2f s started over a playing %s cue" % [e["kind"], e["t"], last_cue["kind"]])
					cut[int(last_cue["id"])] = true
				last_cue = e
				cues[int(e["id"])] = e
			"left_out":
				counts[e["kind"] + " (left out)"] = int(counts.get(e["kind"] + " (left out)", 0)) + 1
				if last_cue.is_empty() or float(e["t"]) >= float(last_cue["t"]) + float(last_cue["len"]) \
						or int(e["rank"]) > int(last_cue["rank"]):
					problems.append("%s cue at %.2f s was left out with no bigger cue playing" % [e["kind"], e["t"]])
	if ends == 0:
		problems.append("no lap ended in %.0f s" % _secs)
	# Crowd cheers at their planned times, for the cues nothing cut off.
	for id in cues:
		var c: Dictionary = cues[id]
		if cut.has(id):
			continue
		var plan: Array = AudioDirector.END_CUES[c["kind"]]["cheer"]
		var got: Array = entries.filter(func(e): return e["what"] == "cheer" and int(e["id"]) == id)
		if got.size() != plan.size() and float(c["t"]) + 5.0 < _dips[-1][0]:
			problems.append("%s cue at %.2f s: %d crowd cheers, planned %d" % [c["kind"], c["t"], got.size(), plan.size()])
		for k in mini(got.size(), plan.size()):
			var late: float = float(got[k]["t"]) - float(c["t"]) - float(plan[k][0])
			if absf(late) > 0.05:
				problems.append("%s cue at %.2f s: cheer %d came %.2f s off its time" % [c["kind"], c["t"], k + 1, late])
		_check_dip(c)
	var parts: PackedStringArray = []
	for k in counts:
		parts.append("%s %d" % [k, counts[k]])
	print("laps ended: %d; cues: %s" % [ends, ", ".join(parts)])


## The music is down to the cue's dip shortly after it starts, and back up some time after it.
func _check_dip(c: Dictionary) -> void:
	var depth: float = AudioDirector.END_CUES[c["kind"]]["dip"]
	var t0: float = float(c["t"])
	var t_in := t0 + DIP_IN_S
	var lowest := 0.0
	for s in _dips:
		if s[0] >= t0 and s[0] <= t_in:
			lowest = minf(lowest, s[1])
	if t_in < _dips[-1][0] and lowest > depth + DIP_SLACK_DB:
		problems.append("%s cue at %.2f s: the music only dipped to %.1f dB (wanted %.0f)" % [c["kind"], t0, lowest, depth])
	# Back up: some time after the cue, unless another cue (or the run's end) came first.
	var back_by: float = t0 + float(c["len"]) + AudioDirector.HOLD_S + BACK_S
	if back_by > _dips[-1][0]:
		return
	for e in _main.audio.cue_log:
		if e["what"] == "cue" and float(e["t"]) > t0 and float(e["t"]) < back_by:
			return  # the next cue holds it down
	for s in _dips:
		if s[0] >= t0 + float(c["len"]) and s[0] <= back_by and s[1] > -0.5:
			return
	problems.append("%s cue at %.2f s: the music was still dipped %.1f s after it" % [c["kind"], t0, back_by - t0 - float(c["len"])])


func _report() -> void:
	if problems.is_empty():
		print("END SOUND CHECK PASSED")
	else:
		for p in problems:
			print("FAIL ", p)
		print("END SOUND CHECK FAILED (%d problems)" % problems.size())
	# As tools/verdict_check.gd: let the audio thread drop its streams before quitting.
	_main.free()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 300:
		await process_frame
	quit(0 if problems.is_empty() else 1)

extends RefCounted
## Picks the racer the big-screen camera follows (game.md "Camera director").
##
## With two or more racers on the course it cuts to another one every `cycle_s` seconds
## (default 8; options menu or --cam-cycle; 0 = never): the racer who has been off camera the
## longest goes next (a new racer counts from its start), so everyone gets a moment. A cut never
## happens mid-jump (it waits up to MAX_AIR_WAIT_S for the landing) and never goes to a racer
## about to finish. When the followed racer leaves the course the camera cuts at once, unless it
## is still cheering or slumping (its finish or crash reaction): then it stays up to MAX_AIR_WAIT_S.
## No automatic cut (interval, phone queue) lands mid-reaction either: a racer reacting at least
## HOLD_W (`reaction`, e.g. an overtake's fist pump) keeps the shot for up to MAX_AIR_WAIT_S more.
##
## The picture-in-picture inset (`inset_run`, pick_inset) shows the racer on camera, or for a few
## seconds another racer mid-reaction while the one on camera is not reacting.
##
## By hand: Tab / Shift+Tab (`step`) cut to the next / previous racer straight away, and A turns
## automatic switching off and on (`auto`). A phone's "Show me on the big screen" (`request`,
## run.watch) queues its racer; queued racers get the next cuts, in order, each once the shot
## before it has had MIN_SHOT_S, so a row of phone taps can't make the camera flicker.
##
## Pure logic, no nodes: racers are duck-typed (run_id, airborne, looping, progress()) and
## reactions come from the `reaction` lookup, so tools/camera_check.gd can test it headless with fakes.

const DEFAULT_CYCLE_S := 8.0
## Choices in the options menu, seconds; 0 = never switch automatically.
const CYCLE_CHOICES := [0.0, 5.0, 8.0, 10.0, 15.0]
const MIN_SHOT_S := 3.0       # a phone's racer waits until the current shot is this old
const MAX_AIR_WAIT_S := 2.0   # an automatic cut waits at most this long for a jump to land (or a reaction)
const HOLD_W := 0.35          # reaction weight from which a racer is mid-reaction (held, inset)
const INSET_MIN_S := 1.2      # the inset stays at least this long on another racer's reaction
const NEAR_FINISH := 0.95     # point-to-point racers past this progress get no new shot

var cycle_s := DEFAULT_CYCLE_S
var auto := true              # false: stay on the current racer (A)
var run_id := ""              # followed run; "" while nobody is on the course
var shot_s := 0.0             # seconds since the last cut
var reason := ""              # why the last cut happened: auto | key | phone | left
var changed := false          # the last update() or step() cut to another racer
var requests: Array = []      # run ids queued by phones, oldest first
var _count := 0               # racers on the course at the last update()
var _clock := 0.0
var _last_seen := {}          # runId -> clock when it was last on camera (or first seen)
var _gone_s := 0.0            # seconds the followed racer has been off the course (held on its reaction)
## run_id -> how strongly that racer is mid-reaction right now (0..1: a finish cheer, crash slump,
## overtake). main.gd reads it from the racer views, tools/camera_check.gd from its fakes.
var reaction: Callable
## Run the inset shows (pick_inset); "" while nobody is on camera.
var inset_run := ""
var _inset_s := 0.0
var _inset_spent := ""        # had the inset for MIN_SHOT_S; skipped until its reaction is over


func _init(p_reaction: Callable) -> void:
	if not p_reaction.is_valid():
		push_error("CameraDirector: needs a reaction lookup (run_id -> 0..1), got an invalid Callable")
	reaction = p_reaction


## Advances by `delta` seconds. `racers`: the sim racers on the course, in release order.
## Sets `changed` (and `reason`) when it cut to another racer or to nobody.
func update(delta: float, racers: Array) -> void:
	_clock += delta
	shot_s += delta
	changed = false
	_count = racers.size()
	var by_id := {}
	for r in racers:
		by_id[r.run_id] = r
		if not _last_seen.has(r.run_id):
			_last_seen[r.run_id] = _clock
	for id in _last_seen.keys():
		if not by_id.has(id):
			_last_seen.erase(id)
	requests = requests.filter(func(id): return by_id.has(id) and id != run_id)
	var left := run_id != "" and not by_id.has(run_id)
	if left:
		_gone_s += delta
		if _gone_s < MAX_AIR_WAIT_S and _reacting(run_id):
			return  # still cheering or slumping on screen after its run
		_cut("", "left")
	if run_id == "":
		if not requests.is_empty():
			_cut(requests.pop_front(), "phone")
		elif not racers.is_empty():
			_cut(_longest_unseen(racers, "", true), "left" if left else "auto")
		return
	_last_seen[run_id] = _clock
	var reacting := _reacting(run_id)
	if not requests.is_empty() and shot_s >= MIN_SHOT_S and not (reacting and shot_s < MIN_SHOT_S + MAX_AIR_WAIT_S):
		_cut(requests.pop_front(), "phone")
		return
	if not auto or cycle_s <= 0.0 or racers.size() < 2 or shot_s < cycle_s:
		return
	if (by_id[run_id].airborne or reacting) and shot_s < cycle_s + MAX_AIR_WAIT_S:
		return
	var next := _longest_unseen(racers, run_id, false)
	if next != "":
		_cut(next, "auto")


## Tab (+1) / Shift+Tab (-1): the next or previous racer in release order, straight away.
func step(dir: int, racers: Array) -> void:
	changed = false
	if racers.is_empty():
		return
	var ids: Array = racers.map(func(r): return r.run_id)
	var i := ids.find(run_id)
	var j: int = posmod(i + dir, ids.size()) if i >= 0 else (0 if dir > 0 else ids.size() - 1)
	_cut(ids[j], "key")


## A phone asked to see its racer (run.watch). Returns false if it is already on camera or queued.
func request(id: String) -> bool:
	if id == run_id or requests.has(id):
		return false
	requests.append(id)
	return true


## Seconds left until the next automatic cut, or -1 when none is coming (auto off, interval 0,
## fewer than two racers).
func next_in() -> float:
	if not auto or cycle_s <= 0.0 or _count < 2 or run_id == "":
		return -1.0
	return maxf(0.0, cycle_s - shot_s)


## Picks inset_run among `ids` (racers that can be shown: on the course, on the grid, or still on
## screen after their run). Call after update(). Another racer's reaction gets the inset while the
## racer on camera is not reacting: at least INSET_MIN_S, at most MIN_SHOT_S, then back.
func pick_inset(delta: float, ids: Array) -> void:
	_inset_s += delta
	if _inset_spent != "" and not _reacting(_inset_spent):
		_inset_spent = ""
	var other := inset_run != run_id and ids.has(inset_run)
	if other and _inset_s < INSET_MIN_S:
		return
	if other and _inset_s >= MIN_SHOT_S:
		_inset_spent = inset_run  # had its turn: not again for this reaction
	elif other and _reacting(inset_run) and not _reacting(run_id):
		return
	var best := run_id
	if run_id != "" and not _reacting(run_id):
		var best_w := HOLD_W
		for id in ids:
			if id == run_id or id == _inset_spent:
				continue
			var w := float(reaction.call(id))
			if w > best_w or (w == best_w and id == inset_run):
				best_w = w
				best = id
	if best != inset_run:
		inset_run = best
		_inset_s = 0.0


func _reacting(id: String) -> bool:
	return id != "" and float(reaction.call(id)) >= HOLD_W


func _cut(id: String, why: String) -> void:
	shot_s = 0.0
	_gone_s = 0.0
	if id == run_id:
		return
	run_id = id
	reason = why
	changed = true
	if id != "":
		_last_seen[id] = _clock


## The racer off camera the longest (ties: released first), other than `exclude`. Racers about to
## finish a point-to-point run only if `allow_finishing`; "" if there is nobody to cut to.
func _longest_unseen(racers: Array, exclude: String, allow_finishing: bool) -> String:
	var best := ""
	var best_t := INF
	var finishing := ""
	for r in racers:
		if r.run_id == exclude:
			continue
		if not r.looping and r.progress() >= NEAR_FINISH:
			if finishing == "":
				finishing = r.run_id
			continue
		var t: float = _last_seen.get(r.run_id, _clock)
		if t < best_t:
			best_t = t
			best = r.run_id
	if best == "" and allow_finishing:
		return finishing
	return best

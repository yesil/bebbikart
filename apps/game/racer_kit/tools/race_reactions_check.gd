extends SceneTree
## Headless check of the race-wide reactions (race_reactions.gd) in the real mock race with kit
## racers. The game races duels (main.gd sets sim.solo): one racer per half, two at most on the
## track, passing through each other. Counts every reaction event and fails if the start grid
## (lean in, a fist bump, whoop on green), overtakes or two racers finishing together never
## happened (MUST: seed 4 has them all), if a finisher misses its finish (its signature cheer, a
## wave, a look into the camera), if no half ever showed its racer from the front on the grid and
## after its lap (main.gd turns the racer's head to that camera), if on the grid anything took the
## head off that camera before the look ended (after a lap a joint cheer may: what took it is
## reported), if a racer coasting after its finish leaves the road, if two finishers stand inside
## each other (after SETTLE_S), if a rival moment fires while a group leaves the grid or a finisher
## cheers together twice. Crashes and failed runs are rare, so flinches and slumps are only counted.
## It races the countryside unless --track says otherwise: seed 4's MUST list was set there (the
## village, the game's default track, has no overtake on seed 4).
## Alongside (a wave or taunt at a rival side by side at the same speed for SIDE_S) needs two
## karts in different lines: duel karts keep their own lines through each other and it never came
## up (0 in 1080 s of duels over five seeds; two racers seldom even hold the same speed for a
## second). The check stages it: once two racers are well clear of the grid, a Stager holds one
## beside the other at the other's speed as race_reactions.gd reads them, and the check fails
## unless the reaction fires for that pair and the two look at each other. The sim never sees it:
## main.gd's next sync puts the racer back on its line, and its speed is put back before the sim's
## next tick (the reaction keeps its own cooldown and rivalry memory). Alongside in the race
## itself is counted and reported.
## A grid fist bump needs two racers waiting for green at once in neighbouring slots, within reach
## and with time left; duel racers wait in slots of their own and that seldom comes up. The check
## stages it too: the first time two racers wait with time to green, a GridStager holds the later
## one in the slot next to the other (closer if their fists can't reach across), and the check
## fails unless the two bump within BUMP_STAGE_MAX_S (the fists must meet, as for every fist bump).
## main.gd reads the same user args (pass --kit).
##
## High fives must bring the two hands together (HF_TOUCH); every pair of a high five is listed.
##   godot --headless --path apps/game --script res://racer_kit/tools/race_reactions_check.gd \
##     -- --kit --racers=16 --seed=4 --speed=2 [--limit=120] [--verbose]

const KitRacerView = preload("res://racer_kit/kit_racer_view.gd")
const RaceReactions = preload("res://racer_kit/race_reactions.gd")
const Gestures = preload("res://racer_kit/racer_gestures.gd")
const Tuning = preload("res://sim/tuning.gd")
const MUST := ["go", "overtake", "finish_together", "fist_bump"]
const SETTLE_S := 0.5
const MAX_PAIR_FRAMES := 15
const HF_TOUCH := 0.2        # m: the two slapping hands (centres) must come this close
const STAGE_LAT := 2.0       # m: the staged racer drives this far beside the other (in RaceReactions.SIDE_LANE, past BRACE_DIST)
const STAGE_MAX_S := 3.0     # s: the staged pair must react within this
const BUMP_STAGE_MAX_S := 1.5  # s: the staged grid pair must fist-bump within this
const BUMP_A_GO_S := 1.2     # s to green the earlier racer of the grid pair needs left (bump, then the fists meet)
const BUMP_B_GO_S := 2.3     # s to green the later one needs left (RaceReactions bumps above GRID_CALM_S + 0.5)
const BUMP_HOLD_S := 0.6     # s the staged pair stays together after the bump (the fists meet 0.28-0.5 s in)
const BUMP_REACH_K := 0.9    # of the two arms' fist-bump reach: the staged pair waits a little inside what RaceReactions bumps at (0.97)


## Holds `b` beside `a` as race_reactions.gd sees them: the same heading, STAGE_LAT to its left, at
## a's speed. It sits under main.gd just before RaceReactions, so it runs after main.gd has synced
## the views; main.gd's next sync puts `b` back on its own line, and a Restorer just after
## RaceReactions gives it its own speed back before the sim's next tick (_physics_process).
class Stager extends Node:
	var a = null
	var b = null
	var own_v := 0.0         # b's own speed while staged

	func _process(_delta: float) -> void:
		if not staging():
			return
		var fwd: Vector3 = a.forward()
		b.global_position = a.global_position + Vector3(fwd.z, 0.0, -fwd.x).normalized() * STAGE_LAT
		b._body.rotation = a._body.rotation
		own_v = b.racer.v
		b.racer.v = a.racer.v

	func staging() -> bool:
		return a != null and is_instance_valid(a) and is_instance_valid(b)


class Restorer extends Node:
	var stager: Stager

	func _process(_delta: float) -> void:
		if stager.staging():
			stager.b.racer.v = stager.own_v


## Holds `b` (the later of two racers waiting for green) `lat` metres across the road from `a`
## (+: a's +d side, Route.normal_at), facing the same way, as race_reactions.gd reads them. It sits
## under main.gd just before RaceReactions like Stager; main.gd's next sync puts `b` back in its
## own slot.
class GridStager extends Node:
	var a = null
	var b = null
	var lat := 0.0

	func _process(_delta: float) -> void:
		if not staging():
			return
		var fwd: Vector3 = a.forward()
		fwd.y = 0.0
		fwd = fwd.normalized()
		b.global_position = a.global_position + Vector3(-fwd.z, 0.0, fwd.x) * lat
		b._body.rotation = a._body.rotation

	func staging() -> bool:
		return a != null and is_instance_valid(a) and is_instance_valid(b)

var main: Node
var limit := 120.0
var done := false
var t := 0.0
var counts := {"go": 0, "overtake": 0, "alongside": 0, "flinch": 0, "finish_together": 0, "revenge": 0, "high_five": 0, "fist_bump": 0}
var fb_pairs := {}     # [a, b] of each grid fist bump -> [time it started, closest the two fists came (m)]
var hf_pairs := {}     # [a, b] of each high five -> closest the two slapping hands came (m)
var ready_seen := {}   # views seen leaning in on the grid
var off_road := 0      # frames a coasting finisher was off its road
var coast_frames := 0
var early_rivals := 0  # rival moments right after the grid (a group leaving together)
var together := {}     # finisher -> joint cheers
var overlaps := 0      # frames two finishers standing after their run were inside each other
var pair_frames := {}  # pair -> those frames
var arrived := {}      # finisher -> seen
var arrived_inside := 0  # finishers already inside another racer on their first frame after the line
var finishes := {}     # finisher instance id -> {sig, wave, joint, cam: seen its signature, wave, joint cheer, camera look; left: _leave_t}
var slumps := {}       # failed racer instance id -> slumped (Gestures.G.SLUMP seen)
var front_was := {}    # side -> instance id of the view main.gd showed from the front in that half last frame (0: none)
var front_looks := {}  # view instance id -> {view, cam, kind, left}: a front look under way
var front_count := {"grid": 0, "finish": 0}  # front looks main.gd started
var front_lost := {"grid": 0, "finish": 0}   # of those, the head turned elsewhere before the look ended
var front_lost_to := {}  # what took the head -> times
var stager: Stager = null
var stage_t := 0.0
var stage_tries := 0   # staged pairs that stopped racing before the reaction
var staged = null      # the staged alongside reaction once it fired: {by, to, gesture, after}
var staged_looks := false  # and the two looked at each other
var staged_late := false   # the pair held side by side STAGE_MAX_S without a reaction
var grid_stager: GridStager = null
var bump_t := 0.0
var bump_go := -1.0    # bump_t the staged fist bump fired at, -1 before
var bump_tries := 0    # staged grid pairs that left the grid before the bump
var bump_skip := {}    # "id-id" -> true: grid pairs whose fists can't reach across without sitting inside each other
var bump_staged = null # the staged fist bump once it fired: {a, b, lat, after}
var bump_late := false # the pair held in reach BUMP_STAGE_MAX_S without a bump


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--limit="):
			limit = float(a.trim_prefix("--limit="))
	if not "--kit" in OS.get_cmdline_user_args():
		push_error("race_reactions_check: pass --kit (placeholder racers have no drivers)")
		quit(1)
		return
	main = (load("res://main.tscn") as PackedScene).instantiate()
	main.args["track"] = "countryside"  # main.gd's _ready adds the user args on top: --track wins
	root.add_child(main)


func _process(delta: float) -> bool:
	if done:
		return false
	t += delta
	var rr = main.get_node_or_null("RaceReactions")
	if rr != null and stager == null:
		stager = Stager.new()
		main.add_child(stager)
		main.move_child(stager, rr.get_index())
		var restorer := Restorer.new()
		restorer.stager = stager
		main.add_child(restorer)
		main.move_child(restorer, rr.get_index() + 1)
		grid_stager = GridStager.new()
		main.add_child(grid_stager)
		main.move_child(grid_stager, rr.get_index())
	if rr != null:
		for e in rr.events:
			if e.type == "alongside" and stager.a != null and [e.by, e.to].has(stager.a) and [e.by, e.to].has(stager.b):
				staged = {"by": e.by.nickname, "to": e.to.nickname, "gesture": e.gesture, "after": stage_t}
				staged_looks = e.by.toy.gestures._look_node == e.to.toy.head_pivot and e.to.toy.gestures._look_node == e.by.toy.head_pivot
				stager.a = null
				continue
			counts[e.type] = int(counts.get(e.type, 0)) + 1
			if e.type == "alongside" and (e.by.race_t < 5.0 or e.to.race_t < 5.0):
				early_rivals += 1
			if e.type == "finish_together" or e.type == "high_five":
				for v in e.views:
					together[v] = int(together.get(v, 0)) + 1
			if e.type == "high_five":
				hf_pairs[e.views] = INF
			if e.type == "fist_bump":
				fb_pairs[e.views] = [t, INF]
				if grid_stager.a != null and bump_go < 0.0 and [grid_stager.a, grid_stager.b].all(func(v): return e.views.has(v)):
					bump_go = bump_t
					bump_staged = {"a": grid_stager.a.nickname, "b": grid_stager.b.nickname, "lat": absf(grid_stager.lat), "after": bump_t}
	for pair in fb_pairs:
		var fa = pair[0]
		var fb = pair[1]
		var since: float = t - float(fb_pairs[pair][0])
		if is_instance_valid(fa) and is_instance_valid(fb) and since > 0.28 and since < 0.5:
			var fd: float = fa.toy.gestures.hand_world(_toward(fa, fb)).distance_to(fb.toy.gestures.hand_world(_toward(fb, fa)))
			fb_pairs[pair][1] = minf(float(fb_pairs[pair][1]), fd)
	for pair in hf_pairs:
		var a = pair[0]
		var b = pair[1]
		if is_instance_valid(a) and is_instance_valid(b) and a.hf_with == b and a.hf_go >= 0.0 \
				and a.hf_t - a.hf_go > 0.36 and a.hf_t - a.hf_go < 0.6:
			var d: float = a.toy.gestures.hand_world(_toward(a, b)).distance_to(b.toy.gestures.hand_world(_toward(b, a)))
			hf_pairs[pair] = minf(hf_pairs[pair], d)
			if "--verbose" in OS.get_cmdline_user_args() and absf(a.hf_t - a.hf_go - 0.43) < 0.01:
				var ga = a.toy.gestures
				var gb = b.toy.gestures
				print("hf %s-%s t %.2f hands %.2f gap %.2f reach %.2f+%.2f hand_a->meet %.2f hand_b->meet %.2f meet_y %.2f" % [a.nickname, b.nickname, a.hf_t, d,
					a.global_position.distance_to(b.global_position), ga.high_five_reach(_toward(a, b)), gb.high_five_reach(_toward(b, a)),
					ga.hand_world(_toward(a, b)).distance_to(ga._hf_point), gb.hand_world(_toward(b, a)).distance_to(gb._hf_point), ga._hf_point.y - a.global_position.y])
	_stage(delta)
	_stage_bump(delta)
	_front_looks()
	_finishes()
	for k in main.views:
		var v = main.views[k]
		if v.get_script() == KitRacerView and v.grid_ready:
			ready_seen[v] = true
	var lv: Array = []
	for id in main.leaving:
		var v = main.leaving[id]
		if is_instance_valid(v) and v.leaving != "":
			lv.append(v)
	# Finishers that cross the line already inside another racer (the race's own overlap).
	for v in lv:
		if not arrived.has(v):
			arrived[v] = true
			for o in lv + main.views.values():
				if o != v and o.get("toy") != null and is_instance_valid(o) and _overlap(v, o):
					arrived_inside += 1
					break
	for i in lv.size():
		for j in range(i + 1, lv.size()):
			# Two racers can cross the line already touching (the sim keeps a smaller circle than a
			# toy's footprint): they have SETTLE_S to slide apart. Popping away does not count.
			if _settled(lv[i]) and _settled(lv[j]) and _overlap(lv[i], lv[j]):
				overlaps += 1
				var key := "%d-%d" % [mini(lv[i].get_instance_id(), lv[j].get_instance_id()), maxi(lv[i].get_instance_id(), lv[j].get_instance_id())]
				pair_frames[key] = int(pair_frames.get(key, 0)) + 1
				if "--verbose" in OS.get_cmdline_user_args():
					print("overlap %s %.2f / %s %.2f, %s %s, gap %.2f, high five %s go %.2f, sizes %s %s, v %.1f %.1f" % [lv[i].nickname, lv[i]._leave_t, lv[j].nickname, lv[j]._leave_t,
						lv[i].leaving, lv[j].leaving, lv[i].global_position.distance_to(lv[j].global_position),
						lv[i].hf_with == lv[j], lv[i].hf_go, lv[i].half_size(), lv[j].half_size(), lv[i]._leave_v, lv[j]._leave_v])
	for id in main.leaving:
		var v = main.leaving[id]
		if is_instance_valid(v) and v.leaving == "finished":
			coast_frames += 1
			var rt = v._leave_seg["route"]
			var s: float = minf(v._leave_ls, rt.length)
			var off: float = (v.global_position - rt.world_at(s, 0.0)).length()
			if v._leave_ls <= rt.length and off > float(v._leave_seg["half_width"]) + 0.5:
				off_road += 1
	if t >= limit:
		done = true
		_report()
	return false


## Staging alongside: picks two racers well clear of the grid and holds one beside the other until
## the reaction fires (or one of them stops racing: try again with the next pair).
func _stage(delta: float) -> void:
	if staged != null or staged_late or stager == null:
		return
	if stager.a != null:
		stage_t += delta
		if not _racing(stager.a) or not _racing(stager.b):
			stager.a = null
			stage_tries += 1
		elif stage_t > STAGE_MAX_S:
			stager.a = null
			staged_late = true
		return
	var kits: Array = main.views.values().filter(func(v): return _racing(v) and v.race_t > RaceReactions.SIDE_AFTER_S + 0.5 \
		and v.react_cool <= 0.0)
	if kits.size() >= 2 and kits[0].racer.v > 5.0:
		stager.a = kits[0]
		stager.b = kits[1]
		stage_t = 0.0


## Staging a grid fist bump: the first two racers waiting for green at once with time left (the
## earlier one BUMP_A_GO_S, the later BUMP_B_GO_S), neither bumped yet: the later one waits in
## the slot next to the earlier one, or closer if their fists can't reach that far, until they
## bump and their fists have met (or one leaves the grid first: try again with the next pair).
func _stage_bump(delta: float) -> void:
	if grid_stager == null or (bump_staged != null and grid_stager.a == null) or bump_late:
		return
	if grid_stager.a != null:
		bump_t += delta
		var gone: bool = not _waiting(grid_stager.a) or not _waiting(grid_stager.b)
		if bump_go >= 0.0:
			if gone or bump_t - bump_go > BUMP_HOLD_S:
				grid_stager.a = null
		elif gone:
			grid_stager.a = null
			bump_tries += 1
		elif bump_t > BUMP_STAGE_MAX_S:
			grid_stager.a = null
			bump_late = true
		return
	var waiting: Array = main.views.values().filter(func(v): return _waiting(v) and not v.grid_bumped)
	if waiting.size() < 2:
		return
	waiting.sort_custom(func(x, y): return x.grid_t > y.grid_t)  # longest waiting first
	var a = waiting[0]
	var b = waiting[1]
	var key := "%d-%d" % [a.get_instance_id(), b.get_instance_id()]
	if bump_skip.has(key) or _go_in(a) < BUMP_A_GO_S or _go_in(b) < BUMP_B_GO_S:
		return
	# Toward b's own slot; the slot next to a, closer if the two fists can't reach across.
	var sa: float = main.sim.grid_slot[a.racer.run_id]
	var dir := signf(float(main.sim.grid_slot[b.racer.run_id]) - sa)
	var gap: float = Tuning.START_LANES[1] - Tuning.START_LANES[0]
	var fwd: Vector3 = a.forward()
	fwd.y = 0.0
	var n := Vector3(-fwd.normalized().z, 0.0, fwd.normalized().x) * dir
	var side := 1 if (a.toy.global_transform.affine_inverse() * (a.global_position + n)).x > 0.0 else -1
	var reach: float = a.toy.gestures.high_five_reach(side, Gestures.FB_REACH) + b.toy.gestures.high_five_reach(-side, Gestures.FB_REACH)
	var lat := minf(gap, reach * BUMP_REACH_K)
	if lat < a.half_size().x + b.half_size().x + RaceReactions.LINGER_GAP:
		bump_skip[key] = true  # this pair would have to sit inside each other
		return
	grid_stager.a = a
	grid_stager.b = b
	grid_stager.lat = lat * dir
	bump_t = 0.0
	bump_go = -1.0


## Waiting on the start grid for green (a kit racer).
func _waiting(v) -> bool:
	return is_instance_valid(v) and v.get("toy") != null and v.racer != null and v.parked and v.leaving == "" \
		and main.sim.on_grid(v.racer.run_id)


## Seconds until this waiting racer's lights go green.
func _go_in(v) -> float:
	var sim = main.sim
	return float(int(sim.go_tick.get(v.racer.run_id, sim.tick)) - sim.tick) / Tuning.HZ


func _racing(v) -> bool:
	return is_instance_valid(v) and v.get("toy") != null and v.racer != null and v.racer.state == "racing" \
		and not v.parked and v.leaving == ""


## main.gd turns a racer's head to its half's camera as that camera comes round to the front (on
## the grid, after the lap), or as a new racer comes into a front shot (the next one on the grid
## while the last one stands after its lap; main.gd _update_duel): follows each such look until it
## ends and notes whether something else took the head first.
func _front_looks() -> void:
	var fw: Dictionary = main._front_was
	for side in fw:
		if int(fw[side]) != 0 and int(fw[side]) != int(front_was.get(side, 0)):
			var v = instance_from_id(int(fw[side]))
			if v != null and v.get("toy") != null:
				var kind := "finish" if String(v.leaving) != "" else "grid"
				front_count[kind] += 1
				front_looks[v.get_instance_id()] = {"view": v, "cam": main.duel_screen.camera_of(side), "kind": kind,
					"left": main.FRONT_LOOK_S}
	front_was = fw.duplicate()
	for id in front_looks.keys():
		var f: Dictionary = front_looks[id]
		if not is_instance_id_valid(id):
			front_looks.erase(id)
			continue
		var g = f.view.toy.gestures
		if g._look_t > 0.0 and g._look_node == f.cam:
			f.left = g._look_t
			continue
		# A new look as this one runs out (its last frame) is the look ending, not a theft.
		if g._look_t > 0.0 and float(f.left) > 0.1:
			front_lost[f.kind] += 1
			var what := _look_name(g._look_node)
			front_lost_to[what] = int(front_lost_to.get(what, 0)) + 1
			if "--verbose" in OS.get_cmdline_user_args():
				print("front look (%s) of %s lost to %s with %.2f s left" % [f.kind, f.view.nickname, what, f.left])
		front_looks.erase(id)


func _look_name(n) -> String:
	if n == null:
		return "a point (the road ahead)"
	if not is_instance_valid(n):
		return "a node gone"
	if n is Camera3D:
		return "another camera"
	if String(n.name).begins_with("Lamp"):
		return "the start lights"
	return "another racer"


## Finishers: the signature cheer, then the wave (or a joint cheer or high five with another
## finisher, which takes its place: race_reactions.gd _cheer_together) and a look into a camera
## (KitRacerView.leave -> ToyRacer.finish, main.gd's front shot); failed runs: the slump.
func _finishes() -> void:
	for id in main.leaving:
		var v = main.leaving[id]
		if not is_instance_valid(v) or v.get("toy") == null:
			continue
		var g = v.toy.gestures
		var key: int = v.get_instance_id()
		if v.leaving == "finished":
			if not finishes.has(key):
				finishes[key] = {"name": v.nickname, "sig": false, "wave": false, "joint": false, "cam": false, "left": v._leave_t}
			var f: Dictionary = finishes[key]
			f.sig = f.sig or g.weight(g.sig_pose) > 0.0
			f.wave = f.wave or g.weight(Gestures.G.WAVE) > 0.0
			f.joint = f.joint or together.has(v)
			f.cam = f.cam or (g._look_t > 0.0 and is_instance_valid(g._look_node) and g._look_node is Camera3D)
			f.left = v._leave_t
		elif v.leaving == "failed":
			slumps[key] = bool(slumps.get(key, false)) or g.weight(Gestures.G.SLUMP) > 0.0


func _toward(v, other) -> int:
	return 1 if (v.toy.global_transform.affine_inverse() * other.global_position).x > 0.0 else -1


func _settled(v) -> bool:
	return v.leave_stay - v._leave_t > SETTLE_S and v._leave_t > v.POP


## Footprints (KitRacerView.half_size, in the first one's road frame) overlapping by more than 5 cm.
func _overlap(a, b) -> bool:
	var fwd: Vector3 = a.forward()
	fwd.y = 0.0
	fwd = fwd.normalized()
	var d: Vector3 = b.global_position - a.global_position
	var along := absf(d.dot(fwd))
	var lat := absf(d.dot(Vector3(-fwd.z, 0.0, fwd.x)))
	var ha: Vector2 = a.half_size()
	var hb: Vector2 = b.half_size()
	return along < ha.y + hb.y - 0.05 and lat < ha.x + hb.x - 0.05


func _report() -> void:
	var bad := PackedStringArray()
	for k in MUST:
		if int(counts.get(k, 0)) == 0:
			bad.append("no %s" % k)
	if ready_seen.is_empty():
		bad.append("nobody leaned in on the grid")
	var missed := 0
	var closest := INF
	for pair in hf_pairs:
		closest = minf(closest, hf_pairs[pair])
		if hf_pairs[pair] > HF_TOUCH:
			missed += 1
			if "--verbose" in OS.get_cmdline_user_args():
				print("missed high five %s: closest %.2f m" % [pair.map(func(v): return v.nickname if is_instance_valid(v) else "(gone)"), hf_pairs[pair]])
	if missed > 0:
		bad.append("%d of %d high fives where the hands did not meet (closest %.2f m, limit %.2f)" % [missed, hf_pairs.size(), closest, HF_TOUCH])
	var fb_missed := 0
	var fb_closest := INF
	for pair in fb_pairs:
		fb_closest = minf(fb_closest, float(fb_pairs[pair][1]))
		if float(fb_pairs[pair][1]) > HF_TOUCH + 0.04:  # two round fists
			fb_missed += 1
	if fb_missed > 0:
		bad.append("%d of %d fist bumps where the fists did not meet (closest %.2f m, limit %.2f)" % [fb_missed, fb_pairs.size(), fb_closest, HF_TOUCH + 0.04])
	if early_rivals > 0:
		bad.append("%d rival moments while a group was still leaving the grid" % early_rivals)
	var twice := together.values().filter(func(n): return n > 1).size()
	if twice > 0:
		bad.append("%d finishers cheered together more than once" % twice)
	# In a crowd at the line (three or more finishing within a second) a pair may need a moment to
	# slide apart; one pair inside each other for longer than MAX_PAIR_FRAMES fails.
	var worst := 0
	for k in pair_frames:
		worst = maxi(worst, int(pair_frames[k]))
	if worst > MAX_PAIR_FRAMES:
		bad.append("two finishers inside each other for %d frames (limit %d)" % [worst, MAX_PAIR_FRAMES])
	if off_road > 0:
		bad.append("coasting finishers off the road for %d of %d frames" % [off_road, coast_frames])
	# Finishers seen through their stay (not cut off by the end of the check).
	var judged := 0
	var missed_fin := PackedStringArray()
	for k in finishes:
		var f: Dictionary = finishes[k]
		if float(f.left) > 0.5:
			continue
		judged += 1
		var miss := PackedStringArray()
		if not f.sig:
			miss.append("signature cheer")
		if not f.wave and not f.joint:
			miss.append("wave or joint cheer")
		if not f.cam:
			miss.append("camera look")
		if not miss.is_empty():
			missed_fin.append("%s (%s)" % [f.name, ", ".join(miss)])
	if judged == 0:
		bad.append("no finisher stayed through its finish")
	if not missed_fin.is_empty():
		bad.append("finishers without their finish: " + "; ".join(missed_fin))
	for kind in front_count:
		if front_count[kind] == 0:
			bad.append("no front look %s" % ("on the grid" if kind == "grid" else "after a lap"))
	if front_lost.grid > 0:
		bad.append("%d of %d front looks on the grid lost the head before they ended" % [front_lost.grid, front_count.grid])
	if staged == null:
		bad.append("staged alongside never fired (%s)" % ("held side by side %.0f s without a reaction" % STAGE_MAX_S if staged_late
			else "no two racers on the track to stage it with, %d pairs stopped racing first" % stage_tries))
	elif not staged_looks:
		bad.append("staged alongside fired but the two did not look at each other")
	if bump_staged == null:
		bad.append("staged fist bump never fired (%s)" % ("held in reach %.1f s without a bump" % BUMP_STAGE_MAX_S if bump_late
			else "no two racers waited on the grid with time to green to stage it with, %d pairs left the grid first, %d could not reach each other" % [bump_tries, bump_skip.size()]))
	print("race reactions in %.0f s: %s, leaning in on the grid: %d racers, coasting finishers on the road: %d frames, finishers inside each other: %d frames (%d pairs), crossed the line inside another: %d of %d%s" % [
		limit, JSON.stringify(counts), ready_seen.size(), coast_frames, overlaps, pair_frames.size(), arrived_inside, arrived.size(),
		"" if counts.flinch > 0 else " (no crash near a racer this run)"])
	print("finishes: %d finishers seen through their stay, %d with signature cheer, wave (or joint cheer) and camera look; failed runs: %d, slumped: %d%s" % [
		judged, judged - missed_fin.size(), slumps.size(), slumps.values().count(true), "" if slumps.size() > 0 else " (no failed run this time)"])
	print("front looks into the half's camera: %d on the grid (head taken elsewhere in %d), %d after a lap (in %d)%s" % [
		front_count.grid, front_lost.grid, front_count.finish, front_lost.finish,
		"" if front_lost_to.is_empty() else ", taken by: " + JSON.stringify(front_lost_to)])
	if staged != null:
		print("alongside: %d in the race itself%s; staged (%s beside %s, %d earlier pairs stopped racing first): fired after %.1f s, %s, heads turned to each other: %s" % [
			counts.alongside, " (duel karts keep their own lines through each other, so it seldom comes up)" if counts.alongside == 0 else "",
			staged.by, staged.to, stage_tries, staged.after, "no gesture" if staged.gesture < 0 else Gestures.G.find_key(staged.gesture), staged_looks])
	if bump_staged != null:
		print("fist bumps: %d in the race itself; staged (%s %.2f m beside %s; earlier pairs: %d left the grid first, %d could not reach each other): bumped after %.2f s" % [
			counts.fist_bump - 1, bump_staged.b, bump_staged.lat, bump_staged.a, bump_tries, bump_skip.size(), bump_staged.after])
	if not bad.is_empty():
		push_error("race_reactions_check: " + "; ".join(bad))
	# The game goes first, and the audio thread drops its stopped music and engines on its next mix:
	# quitting at once leaks their streams.
	main.free()
	await create_timer(0.3).timeout
	quit(0 if bad.is_empty() else 1)

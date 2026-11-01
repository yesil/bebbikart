extends SceneTree
## Headless check of the race-wide reactions (race_reactions.gd) in the real mock race with kit
## racers. The game races duels (main.gd sets sim.solo): one racer per half, two at most on the
## track, passing through each other. Counts every reaction event and fails if the start grid
## (lean in, a fist bump, whoop on green), overtakes or two racers finishing together never
## happened (MUST: seed 4 has them all), if a finisher misses its finish (its signature cheer, a
## wave, a look into the camera), if no half ever showed its racer from the front on the grid and
## after its lap (main.gd turns the racer's head to that camera; what took the head before such a
## look ended is reported), if a racer coasting after its finish leaves the road, if two finishers
## stand inside each other (after SETTLE_S), if a rival moment fires while a group leaves the grid
## or a finisher cheers together twice. Crashes and failed runs are rare, so flinches and slumps
## are only counted.
## Alongside (a wave or taunt at a rival side by side at the same speed for SIDE_S) needs two
## karts in different lines: duel karts keep their own lines through each other and it never came
## up (0 in 1080 s of duels over five seeds; two racers seldom even hold the same speed for a
## second). The check stages it: once two racers are well clear of the grid, a Stager holds one
## beside the other at the other's speed as race_reactions.gd reads them, and the check fails
## unless the reaction fires for that pair and the two look at each other. The sim never sees it:
## main.gd's next sync puts the racer back on its line, and its speed is put back before the sim's
## next tick (the reaction keeps its own cooldown and rivalry memory). Alongside in the race
## itself is counted and reported.
## main.gd reads the same user args (pass --kit).
##
## High fives must bring the two hands together (HF_TOUCH); every pair of a high five is listed.
##   godot --headless --path apps/game --script res://racer_kit/tools/race_reactions_check.gd \
##     -- --kit --racers=16 --seed=4 --speed=2 [--limit=120] [--verbose]

const KitRacerView = preload("res://racer_kit/kit_racer_view.gd")
const RaceReactions = preload("res://racer_kit/race_reactions.gd")
const Gestures = preload("res://racer_kit/racer_gestures.gd")
const MUST := ["go", "overtake", "finish_together", "fist_bump"]
const SETTLE_S := 0.5
const MAX_PAIR_FRAMES := 15
const HF_TOUCH := 0.2        # m: the two slapping hands (centres) must come this close
const STAGE_LAT := 2.0       # m: the staged racer drives this far beside the other (in RaceReactions.SIDE_LANE, past BRACE_DIST)
const STAGE_MAX_S := 3.0     # s: the staged pair must react within this


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
var front_was := {}    # side -> main.gd showed that half's racer from the front last frame
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


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--limit="):
			limit = float(a.trim_prefix("--limit="))
	if not "--kit" in OS.get_cmdline_user_args():
		push_error("race_reactions_check: pass --kit (placeholder racers have no drivers)")
		quit(1)
		return
	main = (load("res://main.tscn") as PackedScene).instantiate()
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


func _racing(v) -> bool:
	return is_instance_valid(v) and v.get("toy") != null and v.racer != null and v.racer.state == "racing" \
		and not v.parked and v.leaving == ""


## main.gd turns a racer's head to its half's camera as that camera comes round to the front (on
## the grid, after the lap; main.gd _update_duel): follows each such look until it ends and notes
## whether something else took the head first.
func _front_looks() -> void:
	var fw: Dictionary = main._front_was
	for side in fw:
		if fw[side] and not front_was.get(side, false):
			var v = _front_view(side)
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


## The racer view main.gd turned to the half's front camera (as _update_duel picks it: the
## newest run of the side; full screen shows the one racer whatever its side).
func _front_view(side: String):
	var on_side := {}
	for rid in main.duel_sides:
		var v = main._view_of(rid)
		if v != null:
			on_side[main.duel_sides[rid]] = v
	if not main.duel_screen.split:
		return on_side.get("left", on_side.get("right", null))
	return on_side.get(side, null)


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
	var stay: float = v.FINISH_STAY if v.leaving == "finished" else v.FAIL_STAY
	return stay - v._leave_t > SETTLE_S and v._leave_t > v.POP


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
	for pair in fb_pairs:
		if float(fb_pairs[pair][1]) > HF_TOUCH + 0.04:  # two round fists
			fb_missed += 1
	if fb_missed > 0:
		bad.append("%d of %d fist bumps where the fists did not meet" % [fb_missed, fb_pairs.size()])
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
	if staged == null:
		bad.append("staged alongside never fired (%s)" % ("held side by side %.0f s without a reaction" % STAGE_MAX_S if staged_late
			else "no two racers on the track to stage it with, %d pairs stopped racing first" % stage_tries))
	elif not staged_looks:
		bad.append("staged alongside fired but the two did not look at each other")
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
	if not bad.is_empty():
		push_error("race_reactions_check: " + "; ".join(bad))
	# The game goes first, and the audio thread drops its stopped music and engines on its next mix:
	# quitting at once leaks their streams.
	main.free()
	await create_timer(0.3).timeout
	quit(0 if bad.is_empty() else 1)

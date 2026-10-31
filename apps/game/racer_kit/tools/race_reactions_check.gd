extends SceneTree
## Headless check of the race-wide reactions (race_reactions.gd) in the real mock race with kit
## racers: counts every reaction event and fails if the start grid (lean in, whoop on green),
## overtakes, a rival alongside or two racers finishing together never happened, if a racer
## coasting after its finish leaves the road, if two finishers stand inside each other (after
## SETTLE_S), if a rival moment fires while a group leaves the grid or a finisher cheers together
## twice. Crashes are rare, so flinches are only counted.
## main.gd reads the same user args (pass --kit).
##
## High fives must bring the two hands together (HF_TOUCH); every pair of a high five is listed.
##   godot --headless --path apps/game --script res://racer_kit/tools/race_reactions_check.gd \
##     -- --kit --racers=16 --seed=4 --speed=2 [--limit=120] [--verbose]

const KitRacerView = preload("res://racer_kit/kit_racer_view.gd")
const MUST := ["go", "overtake", "alongside", "finish_together", "fist_bump"]
const SETTLE_S := 0.5
const MAX_PAIR_FRAMES := 15
const HF_TOUCH := 0.2        # m: the two slapping hands (centres) must come this close

var main: Node
var limit := 120.0
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
	t += delta
	var rr = main.get_node_or_null("RaceReactions")
	if rr != null:
		for e in rr.events:
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
	for k in main.views:
		var v = main.views[k]
		if v.get_script() == KitRacerView and v.grid_ready:
			ready_seen[v] = true
	var lv: Array = []
	for id in main.leaving:
		var v = main.leaving[id]
		if is_instance_valid(v) and v.leaving != "":
			lv.append(v)
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
		_report()
	return false


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
	print("race reactions in %.0f s: %s, leaning in on the grid: %d racers, coasting finishers on the road: %d frames, finishers inside each other: %d frames (%d pairs)%s" % [
		limit, JSON.stringify(counts), ready_seen.size(), coast_frames, overlaps, pair_frames.size(),
		"" if counts.flinch > 0 else " (no crash near a racer this run)"])
	if not bad.is_empty():
		push_error("race_reactions_check: " + "; ".join(bad))
	quit(0 if bad.is_empty() else 1)

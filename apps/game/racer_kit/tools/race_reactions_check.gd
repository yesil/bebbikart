extends SceneTree
## Headless check of the race-wide reactions (race_reactions.gd) in the real mock race with kit
## racers: counts every reaction event and fails if the start grid (lean in, whoop on green),
## overtakes, a rival alongside or two racers finishing together never happened, or if a racer
## coasting after its finish leaves the road. Crashes are rare, so flinches are only counted.
## main.gd reads the same user args (pass --kit).
##
##   godot --headless --path apps/game --script res://racer_kit/tools/race_reactions_check.gd \
##     -- --kit --racers=16 --seed=4 --speed=2 [--limit=120]

const KitRacerView = preload("res://racer_kit/kit_racer_view.gd")
const MUST := ["go", "overtake", "alongside", "finish_together"]

var main: Node
var limit := 120.0
var t := 0.0
var counts := {"go": 0, "overtake": 0, "alongside": 0, "flinch": 0, "finish_together": 0}
var ready_seen := {}   # views seen leaning in on the grid
var off_road := 0      # frames a coasting finisher was off its road
var coast_frames := 0
var early_rivals := 0  # rival moments right after the grid (a group leaving together)
var together := {}     # finisher -> joint cheers


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
			if e.type == "finish_together":
				for v in e.views:
					together[v] = int(together.get(v, 0)) + 1
	for k in main.views:
		var v = main.views[k]
		if v.get_script() == KitRacerView and v.grid_ready:
			ready_seen[v] = true
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


func _report() -> void:
	var bad := PackedStringArray()
	for k in MUST:
		if int(counts.get(k, 0)) == 0:
			bad.append("no %s" % k)
	if ready_seen.is_empty():
		bad.append("nobody leaned in on the grid")
	if early_rivals > 0:
		bad.append("%d rival moments while a group was still leaving the grid" % early_rivals)
	var twice := together.values().filter(func(n): return n > 1).size()
	if twice > 0:
		bad.append("%d finishers cheered together more than once" % twice)
	if off_road > 0:
		bad.append("coasting finishers off the road for %d of %d frames" % [off_road, coast_frames])
	print("race reactions in %.0f s: %s, leaning in on the grid: %d racers, coasting finishers on the road: %d frames%s" % [
		limit, JSON.stringify(counts), ready_seen.size(), coast_frames,
		"" if counts.flinch > 0 else " (no crash near a racer this run)"])
	if not bad.is_empty():
		push_error("race_reactions_check: " + "; ".join(bad))
	quit(0 if bad.is_empty() else 1)
